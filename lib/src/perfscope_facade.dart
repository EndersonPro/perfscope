import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

import 'anomalies/frame_context_window.dart';
import 'anomalies/performance_anomaly.dart';
import 'core/clock.dart';
import 'core/perfscope_config.dart';
import 'core/perfscope_engine.dart';
import 'context/interaction_tracker.dart' show InteractionHandle;
import 'context/screen_tracker.dart' show unknownScreenName;
import 'events/performance_event.dart';
import 'exporters/performance_exporter.dart'
    show PerformanceExporter, reportForExport;
import 'logging/log_writer.dart';
import 'reporting/performance_report.dart';
import 'reporting/session_comparison.dart';
import 'serialization/session_serializer.dart';
import 'sessions/performance_session.dart';
import 'sinks/performance_event_sink.dart';
import 'traces/trace_tracker.dart';

/// Warning emitted once per process when PerfScope runs in debug builds.
///
/// Debug-mode frame timings carry assertions and JIT overhead; they are not
/// representative of what users experience in release builds.
const String _debugModeWarning = '[PerfScope] Running in DEBUG mode: '
    'performance measurements are NOT representative of real-world '
    'behavior. Use `flutter run --profile` for trustworthy numbers.';

/// Static facade for initializing PerfScope in a host application.
///
/// Typical usage, once during app startup:
///
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   PerfScope.initialize();
///   runApp(const MyApp());
/// }
/// ```
abstract final class PerfScope {
  static PerfScopeEngine? _engine;
  static LogWriter? _logWriter;
  static bool _debugWarningWritten = false;

  /// Whether an initialized engine is currently active.
  static bool get isEnabled => _engine != null;

  /// Broadcast stream of events from the active engine.
  ///
  /// Returns an empty stream while PerfScope is not initialized, so
  /// subscribing before [initialize] is safe.
  static Stream<PerformanceEvent> get events =>
      _engine?.events ?? const Stream.empty();

  /// The active engine, or null before initialization / after dispose.
  ///
  /// Exposed exclusively for tests and advanced embedding scenarios that
  /// need direct access to internals; regular applications should rely on
  /// the [events] stream only.
  static PerfScopeEngine? get debugEngine => _engine;

  /// Internal locator used by framework adapters (e.g. the navigator
  /// observer) to resolve the live engine without importing singleton
  /// state directly. Returns null while PerfScope is not initialized.
  static PerfScopeEngine? get maybeEngine => _engine;

  /// Creates and starts the engine with the given (or default) [config].
  ///
  /// Idempotent: calling it again while enabled logs one `[PerfScope]` line
  /// through the active writer and returns the existing engine untouched.
  ///
  /// In debug builds ([kDebugMode]) a warning about unrepresentable
  /// measurements is written exactly once per process, regardless of how
  /// many times PerfScope is disposed and re-initialized.
  ///
  /// Engine start is fire-and-forget on purpose: application startup must
  /// never wait on observability plumbing. Startup failures surface in the
  /// log writer instead of blocking `main`.
  ///
  /// [logWriter] overrides the default console sink — mainly useful for
  /// tests and apps that already own a logging pipeline.
  ///
  /// [sinks] receive every RAW event alongside the public stream (see
  /// [PerformanceEventSink]). They deliberately live OUTSIDE
  /// [PerfScopeConfig]: the config is a const, immutable value object
  /// describing WHAT PerfScope measures and prints, while sinks are
  /// stateful runtime collaborators whose identity and lifecycle belong to
  /// the embedding app — merging them into config would break const
  /// construction and equality.
  static void initialize({
    PerfScopeConfig? config,
    LogWriter? logWriter,
    List<PerformanceEventSink>? sinks,
  }) {
    if (_engine != null) {
      _safeLog('[PerfScope] PerfScope.initialize() ignored: '
          'already initialized');
      return;
    }
    _logWriter = logWriter ?? const ConsoleLogWriter();
    if (kDebugMode && !_debugWarningWritten) {
      _debugWarningWritten = true;
      _safeLog(_debugModeWarning);
    }
    final engine = PerfScopeEngine(
      config: config,
      clock: const SystemClock(),
      logWriter: _logWriter,
      sinks: sinks ?? const <PerformanceEventSink>[],
    );
    _engine = engine;
    // Intentionally not awaited: see doc comment above.
    unawaited(engine.start());
  }

  /// Tears down the active engine and fully resets singleton state so a
  /// subsequent [initialize] starts fresh (hot-restart friendly).
  static Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }

  /// Resets all static state, including once-per-process flags.
  @visibleForTesting
  static void resetForTest() {
    _engine = null;
    _logWriter = null;
    _debugWarningWritten = false;
  }

  /// Manually overrides the current screen (for apps without a Navigator)
  /// and optionally merges [metadata] entries into the metadata store.
  ///
  /// No-op-safe when PerfScope is disabled; invalid [metadata] values
  /// still throw [ArgumentError] while enabled (fail fast in development).
  static void screen(String name, {Map<String, Object?>? metadata}) =>
      _engine?.overrideScreen(name, metadata: metadata);

  /// Starts an interaction span, returning a handle to end it with.
  ///
  /// No-op-safe: returns an inert, already-ended handle when disabled or
  /// when the interaction depth guard is active.
  static InteractionHandle startInteraction(String name) =>
      _engine?.startInteraction(name) ?? InteractionHandle.inert(name);

  /// Records a one-shot quick marker attributed to the next observed
  /// frame. No-op-safe when disabled.
  static void interaction(String name) => _engine?.markInteraction(name);

  /// Stores contextual metadata. Throws [ArgumentError] for values outside
  /// the allowed types/limits; no-op-safe when disabled.
  static void setMetadata(String key, Object? value) =>
      _engine?.setMetadata(key, value);

  /// Removes one metadata entry. No-op-safe when disabled.
  static void removeMetadata(String key) => _engine?.removeMetadata(key);

  /// Removes every metadata entry. No-op-safe when disabled.
  static void clearMetadata() => _engine?.clearMetadata();

  /// Current screen name, or `'unknown'` when disabled.
  static String get currentScreen =>
      _engine?.currentScreen ?? unknownScreenName;

  /// Times a synchronous [body] under [name] and returns its result.
  ///
  /// Disabled-safe by contract: when PerfScope is not initialized the body
  /// still runs exactly once and its result is returned — just WITHOUT any
  /// tracing, events, or anomaly detection. When enabled, a completed trace
  /// is recorded, a [TraceEvent] is emitted, and long traces additionally
  /// produce an anomaly (see [PerfScopeEngine.trace] for full semantics,
  /// including untouched rethrow of body failures).
  ///
  /// Invalid [metadata] throws [ArgumentError] while enabled; it is never
  /// validated while disabled.
  static R trace<R>(String name, R Function() body,
      {Map<String, Object?>? metadata}) {
    final engine = _engine;
    if (engine == null) {
      // Not initialized: run the body without tracing, transparently.
      return body();
    }
    return engine.trace(name, body, metadata: metadata);
  }

  /// Async counterpart of [trace] for [Future]-returning bodies.
  ///
  /// Disabled-safe: without an engine the body runs untraced and its
  /// future result is returned unchanged. Failure semantics while enabled
  /// mirror [trace]: record first, then rethrow the ORIGINAL error and
  /// stack trace untouched.
  static Future<R> traceAsync<R>(String name, Future<R> Function() body,
      {Map<String, Object?>? metadata}) async {
    final engine = _engine;
    if (engine == null) {
      return body();
    }
    return engine.traceAsync(name, body, metadata: metadata);
  }

  /// Chronological snapshot of recently detected anomalies, or an empty
  /// list when disabled. Bounded window — see [maxStoredAnomalies].
  static List<PerformanceAnomaly> get anomalies =>
      _engine?.anomalies ?? const <PerformanceAnomaly>[];

  /// Chronological snapshot of recent completed traces, or an empty list
  /// when disabled. Bounded window — see [maxStoredTraces].
  static List<CompletedTrace> get recentTraces =>
      _engine?.recentTraces ?? const <CompletedTrace>[];

  /// Context window (preceding + following frames) around the frame
  /// anomaly with [anomalyId], or null when PerfScope is disabled, the id
  /// is unknown, or the window was evicted from its bounded store.
  static FrameContextWindow? contextWindowFor(String anomalyId) =>
      _engine?.contextWindowFor(anomalyId);

  /// Opens a new performance session, auto-finalizing an already-active
  /// one first (its report-time state stays reachable through the engine).
  ///
  /// Throws [StateError] when PerfScope is not initialized: a caller that
  /// explicitly manages sessions should know immediately that no engine
  /// exists, instead of silently recording nothing.
  static PerformanceSession startSession([String? name]) {
    final engine = _engine;
    if (engine == null) {
      throw StateError('PerfScope.startSession() called before '
          'PerfScope.initialize().');
    }
    return engine.startSession(name);
  }

  /// Stops the active session and returns its [PerformanceReport].
  ///
  /// Async signature for future-proofing (report flushing may become
  /// async); today the body completes synchronously. Throws [StateError]
  /// when PerfScope is disabled or no session is active.
  static Future<PerformanceReport> stopSession() async {
    final engine = _engine;
    if (engine == null) {
      throw StateError('PerfScope.stopSession() called without an '
          'initialized PerfScope.');
    }
    return engine.stopSession();
  }

  /// The currently open session, or null when PerfScope is disabled or no
  /// session is active. Never throws.
  static PerformanceSession? get currentSession => _engine?.currentSession;

  /// The most recent finished-session report, or null when PerfScope is
  /// disabled or no session has been stopped yet. Never throws.
  static PerformanceReport? get lastReport => _engine?.lastReport;

  /// Pure before/after comparison of two finished-session reports.
  ///
  /// Delegates to [SessionComparator.compare]; no engine or
  /// initialization is involved — pass any two [PerformanceReport]s
  /// regardless of where they came from.
  static SessionComparison compareSessions(
    PerformanceReport before,
    PerformanceReport after,
  ) =>
      SessionComparator.compare(before, after);

  /// Serializes a session to the PerfScope JSON schema, or returns null
  /// when PerfScope is disabled or no session was ever opened.
  ///
  /// Export target, in priority order:
  /// 1. The CURRENTLY OPEN session — mid-session exports use a minimal
  ///    snapshot (session statistics plus attributed anomalies) because no
  ///    full report exists yet.
  /// 2. After [stopSession] there is no open session, so the LAST FINISHED
  ///    session is exported instead through its attached stop-time report
  ///    ([lastReport]-grade data).
  ///
  /// With [includeContextWindows] enabled, complete context windows are
  /// resolved through the engine and embedded per frame anomaly.
  static String? exportCurrentSessionAsJson(
      {bool includeContextWindows = true}) {
    final engine = _engine;
    if (engine == null) {
      return null;
    }
    // reportForExport prefers the attached stop-time report and falls back
    // to a minimal live snapshot, so both branches share one code path.
    final session = engine.currentSession ?? engine.lastFinishedSession;
    if (session == null) {
      return null;
    }
    return const SessionSerializer().serializeToString(
      reportForExport(session),
      resolveContextWindow:
          includeContextWindows ? engine.contextWindowFor : null,
    );
  }

  /// Exports the currently open session through [exporter].
  ///
  /// Throws [StateError] when PerfScope is disabled or no session is open:
  /// an explicit export request failing silently would be indistinguishable
  /// from an exporter receiving nothing. Context windows are resolved
  /// through the engine when [includeContextWindows] is set.
  static Future<void> export({
    required PerformanceExporter exporter,
    bool includeContextWindows = true,
  }) async {
    final engine = _engine;
    final session = engine?.currentSession;
    if (engine == null || session == null) {
      throw StateError('No performance session available to export.');
    }
    await exporter.export(
      session,
      resolveContextWindow:
          includeContextWindows ? engine.contextWindowFor : null,
    );
  }

  static void _safeLog(String value) {
    try {
      (_logWriter ?? const ConsoleLogWriter()).write(value);
    } catch (_) {
      // Never let logging failures escape initialization.
    }
  }
}
