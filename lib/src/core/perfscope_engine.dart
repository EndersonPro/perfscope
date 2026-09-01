import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../anomalies/anomaly_detector.dart';
import '../anomalies/frame_context_window.dart';
import '../anomalies/performance_anomaly.dart';
import '../buffers/ring_buffer.dart';
import '../context/interaction_tracker.dart';
import '../context/metadata_store.dart';
import '../context/metadata_validator.dart';
import '../context/screen_tracker.dart';
import '../events/performance_event.dart';
import '../frames/frame_budget.dart';
import '../frames/frame_classifier.dart';
import '../frames/frame_sample.dart';
import '../frames/flutter_frame_source.dart';
import '../frames/frame_source.dart';
import '../logging/log_writer.dart';
import '../logging/performance_logger.dart';
import '../navigation/screen_context_port.dart';
import '../reporting/performance_report.dart';
import '../sessions/performance_session.dart';
import '../sessions/session_manager.dart';
import '../sinks/performance_event_sink.dart';
import '../traces/timeline_adapter.dart';
import '../traces/trace_tracker.dart';
import 'clock.dart';
import 'frame_budget_resolver.dart';
import 'ids.dart';
import 'perfscope_config.dart';

/// Maximum number of detected anomalies kept in memory.
///
/// Deliberately config-independent: the anomaly window is a bounded
/// diagnostic buffer (oldest entries dropped), not a tunable history.
const int maxStoredAnomalies = 1000;

/// Core runtime that wires a [FrameSource] to classification, the public
/// event stream, and the bounded recent-frames buffer.
///
/// The engine performs per-frame work only: adapt, classify, enqueue.
/// Anything expensive (rendering, anomaly detection, persistence) belongs to
/// later phases or external subscribers of [events].
///
/// Failure containment: exceptions raised while processing internal events
/// are caught and routed to the [LogWriter] with a `[PerfScope]` prefix —
/// they must never propagate into the host application.
final class PerfScopeEngine implements ScreenContextPort {
  /// Creates an engine from optional collaborators.
  ///
  /// Defaults: config falls back to `const PerfScopeConfig()`, the frame
  /// source becomes a [FlutterFrameSource] fed by the resolved budget, and
  /// output goes to the console.
  PerfScopeEngine({
    PerfScopeConfig? config,
    FrameSource? frameSource,
    FrameBudgetProvider? frameBudgetProvider,
    Clock clock = const SystemClock(),
    LogWriter? logWriter,
    TraceTimelineAdapter? timelineAdapter,
    SessionManager? sessionManager,
    List<PerformanceEventSink> sinks = const <PerformanceEventSink>[],
  })  : config = config ?? const PerfScopeConfig(),
        _clock = clock,
        _logWriter = logWriter ?? ConsoleLogWriter(),
        _sinks = List<PerformanceEventSink>.unmodifiable(sinks),
        _eventIds = IdGenerator('evt'),
        _traceIds = IdGenerator('trc'),
        _anomalyIds = IdGenerator('anm'),
        _recentFrames = RingBuffer<FrameSample>(
          (config ?? const PerfScopeConfig()).frameBufferSize,
        ),
        _anomalies = RingBuffer<PerformanceAnomaly>(maxStoredAnomalies),
        _classifier = FrameClassifier(
          thresholds: (config ?? const PerfScopeConfig()).thresholds,
        ),
        _frameBudgetProvider = frameBudgetProvider ??
            FrameBudgetResolver(config: config ?? const PerfScopeConfig())
                .resolve(),
        _screenTracker = ScreenTracker(),
        _metadataStore = MetadataStore(),
        _timelineAdapterOverride = timelineAdapter,
        _interactionTracker = InteractionTracker(
          onWarning: (message) =>
              (logWriter ?? const ConsoleLogWriter()).write(message),
        ) {
    // Session ownership comes first: the default manager reuses THIS
    // engine's trace tracker (no duplicate storage) and reads its
    // environment inputs from already-initialized collaborators.
    _sessionManager = sessionManager ??
        SessionManager(
          traceTracker: _traceTracker,
          clock: _clock,
          frameBudgetProvider: _frameBudgetProvider,
          statisticWindowCapacity:
              (config ?? const PerfScopeConfig()).maxStatisticSamples,
          metadataSnapshot: () => _metadataStore.snapshot(),
        );
    _frameSource = frameSource ??
        FlutterFrameSource(
          frameBudgetProvider: _frameBudgetProvider,
          clock: _clock,
        );
    // Structured logging rides on the same writer as internal diagnostics
    // but honors the configured style/verbosity policy. The session id
    // resolver lets JSON envelopes correlate with the open session; read
    // lazily so it always reflects the CURRENT session.
    _logger = PerformanceLogger(
      style: (config ?? const PerfScopeConfig()).logStyle,
      writer: _logWriter,
      printNormalFrames: (config ?? const PerfScopeConfig()).printNormalFrames,
      printWarnings: (config ?? const PerfScopeConfig()).printWarnings,
      printAnomalies: (config ?? const PerfScopeConfig()).printAnomalies,
      verbose: (config ?? const PerfScopeConfig()).verbose,
      sessionIdResolver: () => _sessionManager.activeSession?.id,
    );
    // Route span endings into the event stream; assigned here because the
    // handler needs instance state that does not exist during the
    // initializer list.
    _interactionTracker.onSpanEnded = _onInteractionSpanEnded;
  }

  /// Configuration in effect for this engine instance.
  final PerfScopeConfig config;

  final Clock _clock;
  final LogWriter _logWriter;
  final List<PerformanceEventSink> _sinks;
  final IdGenerator _eventIds;
  final IdGenerator _traceIds;
  final IdGenerator _anomalyIds;
  final RingBuffer<FrameSample> _recentFrames;
  final RingBuffer<PerformanceAnomaly> _anomalies;
  final FrameClassifier _classifier;

  /// Context-window collector owned by the engine: the detector decides IF
  /// a frame is anomalous, this captures the frames AROUND the decision.
  final FrameContextWindowCollector _contextWindows =
      FrameContextWindowCollector();

  /// Pure frame-anomaly decision point; lazily wired to the `anm` id
  /// generator and the injected clock.
  late final AnomalyDetector _frameAnomalyDetector = AnomalyDetector(
    clock: _clock,
    anomalyIds: _anomalyIds,
  );
  final FrameBudgetProvider _frameBudgetProvider;
  final ScreenTracker _screenTracker;
  final MetadataStore _metadataStore;
  final InteractionTracker _interactionTracker;

  /// Timeline adapter override injected for tests/embeddings; null means
  /// "use the real adapter matching the trace flavor".
  final TraceTimelineAdapter? _timelineAdapterOverride;

  /// Sync-flavor Timeline adapter: the injected override when present,
  /// otherwise the real `Timeline.startSync`-backed one.
  late final TraceTimelineAdapter _syncTimeline =
      _timelineAdapterOverride ?? const RealSyncTimelineAdapter();

  /// Async-flavor Timeline adapter: the injected override when present,
  /// otherwise the real [TimelineTask]-backed one.
  late final TraceTimelineAdapter _asyncTimeline =
      _timelineAdapterOverride ?? RealAsyncTimelineAdapter();

  final TraceTracker _traceTracker = TraceTracker();

  /// Session lifecycle + aggregation owner; assigned in the constructor
  /// body because the default instance needs other initialized fields.
  late final SessionManager _sessionManager;

  late final FrameSource _frameSource;

  /// Styled-output gate over [_logWriter]; assigned in the constructor
  /// body because it needs the session manager for session-id resolution.
  late final PerformanceLogger _logger;

  final StreamController<PerformanceEvent> _events =
      StreamController<PerformanceEvent>.broadcast(sync: false);

  StreamSubscription<FrameSample>? _framesSubscription;

  bool _started = false;
  bool _disposed = false;

  AppLifecycleState? _lastLifecycleState;

  /// Most recent lifecycle state reported via [handleLifecycle], if any.
  AppLifecycleState? get lastLifecycleState => _lastLifecycleState;

  /// Broadcast stream of all events produced by this engine.
  Stream<PerformanceEvent> get events => _events.stream;

  /// Single emission point for every event: adds to the broadcast stream
  /// AND fans the raw event out to each configured sink, guarded per sink
  /// so one failing sink can never break the stream or its siblings.
  void _dispatch(PerformanceEvent event) {
    _events.add(event);
    for (final sink in _sinks) {
      try {
        if (!sink.accepts(event)) {
          continue;
        }
        sink.add(event);
      } catch (error) {
        debugPrint('[PerfScope] sink error: $error');
      }
    }
  }

  /// Chronological snapshot of the most recent frames (bounded by
  /// [PerfScopeConfig.frameBufferSize]).
  List<FrameSample> get recentFrames => _recentFrames.toList();

  /// Chronological snapshot of the most recent completed manual traces
  /// (bounded by [maxStoredTraces], oldest dropped first).
  List<CompletedTrace> get recentTraces => _traceTracker.traces;

  /// Chronological snapshot of the most recent detected anomalies
  /// (bounded by [maxStoredAnomalies], oldest dropped first).
  List<PerformanceAnomaly> get anomalies => _anomalies.toList();

  /// The currently open session, or null before any [startSession].
  PerformanceSession? get currentSession => _sessionManager.activeSession;

  /// The most recently finished session — via [stopSession] or
  /// auto-finalization by a later [startSession] — or null.
  PerformanceSession? get lastFinishedSession =>
      _sessionManager.lastFinishedSession;

  /// The report produced by the most recent [stopSession], or null.
  PerformanceReport? get lastReport => _sessionManager.lastReport;

  /// Opens a new session, auto-finalizing an active one first.
  ///
  /// Exposed for the facade and advanced embeddings; regular applications
  /// should call the facade instead.
  PerformanceSession startSession([String? name]) =>
      _sessionManager.start(name: name);

  /// Stops the active session and synchronously builds its report.
  ///
  /// The [Future] wrapper is deliberate future-proofing so callers may
  /// `await` it today and stay compatible if flushing ever becomes async.
  /// Throws [StateError] when no session is active.
  ///
  /// After the report is built it is rendered through the engine's
  /// [PerformanceLogger] and written to the SAME [LogWriter] used for all
  /// PerfScope output — respecting the configured style (silent writes
  /// nothing). Rendering is failure-contained; a formatting bug can never
  /// hide the report from the caller.
  Future<PerformanceReport> stopSession() async {
    final report = _sessionManager.stop();
    _guard(() {
      final rendered = _logger.renderReport(report);
      if (rendered.isNotEmpty) {
        _logWriter.write('$rendered\n');
      }
    });
    return report;
  }

  /// Context window (preceding + following frames) captured around the
  /// frame anomaly with [anomalyId], or null when the id is unknown, names
  /// a non-frame anomaly ([LongTraceAnomaly]), or the window was already
  /// evicted from its bounded store.
  FrameContextWindow? contextWindowFor(String anomalyId) =>
      _contextWindows.windowFor(anomalyId);

  /// Screen-context tracker: navigation name stack feeding [ScreenEvent]s.
  ///
  /// Exposed for tests and advanced embeddings; applications should use
  /// the facade or attach a [PerfScopeNavigatorObserver] instead.
  ScreenTracker get screenTracker => _screenTracker;

  /// Interaction tracker backing [startInteraction] / [markInteraction].
  InteractionTracker get interactionTracker => _interactionTracker;

  /// Key/value metadata store attached to subsequent records.
  MetadataStore get metadataStore => _metadataStore;

  /// Name of the screen currently considered visible (never null;
  /// unnamed routes report `'unknown'`).
  String get currentScreen => _screenTracker.current;

  /// Manually overrides the current screen (custom routing without a
  /// Navigator) and optionally merges [metadata] into the store first.
  ///
  /// Emits a [ScreenEvent] with [ScreenChangeReason.manual] when the
  /// visible screen actually changes.
  void overrideScreen(String name, {Map<String, Object?>? metadata}) {
    if (_disposed) {
      return;
    }
    if (metadata != null) {
      metadata.forEach(_metadataStore.set);
    }
    _guard(() {
      final change = _screenTracker.override(name);
      if (change.changed) {
        _emitScreenChange(change, ScreenChangeReason.manual);
      }
    });
  }

  /// Starts an interaction span and emits an [InteractionEvent] of kind
  /// [InteractionEventKind.start]. Call [InteractionHandle.end] on the
  /// returned handle exactly once; out-of-order endings are supported.
  ///
  /// When the depth guard is active the returned handle is inert (empty
  /// id, already ended) and only a one-time warning is logged.
  InteractionHandle startInteraction(String name) {
    final handle = _interactionTracker.start(name, _clock.now());
    if (handle.id.isEmpty || _disposed) {
      // Depth guard fired (tracker already warned once).
      return handle;
    }
    _guard(() => _sessionManager.noteInteraction(handle.id, handle.name));
    _guard(() {
      _dispatch(InteractionEvent(
        id: _eventIds.next(),
        timestamp: _clock.now(),
        interactionId: handle.id,
        name: handle.name,
        kind: InteractionEventKind.start,
        parentInteractionId: handle.parentInteractionId,
      ));
    });
    return handle;
  }

  /// Records a one-shot quick marker attributed to the very next observed
  /// frame, emitting an [InteractionEvent] of kind
  /// [InteractionEventKind.marker].
  void markInteraction(String name) {
    final markerId = _interactionTracker.markOnce(name, _clock.now());
    if (_disposed) {
      return;
    }
    // Quick markers count as interaction spans for session summaries.
    _guard(() => _sessionManager.noteInteraction(markerId, name));
    _guard(() {
      _dispatch(InteractionEvent(
        id: _eventIds.next(),
        timestamp: _clock.now(),
        interactionId: markerId,
        name: name,
        kind: InteractionEventKind.marker,
      ));
    });
  }

  /// Stores contextual metadata. Throws [ArgumentError] for values outside
  /// the allowed types/limits; see [MetadataStore].
  void setMetadata(String key, Object? value) => _metadataStore.set(key, value);

  /// Times a synchronous [body] under [name], recording a
  /// [CompletedTrace], emitting a [TraceEvent], and — when the resulting
  /// duration exceeds `config.longTraceThreshold` — storing a
  /// [LongTraceAnomaly] and emitting an [AnomalyEvent].
  ///
  /// Screen and interaction attribution is captured at *start* into the
  /// record; mid-trace context changes never retroactively re-attribute it.
  /// Correlation is temporal only: PerfScope never claims a trace caused
  /// any specific frame.
  ///
  /// The body is instrumented through dart:developer Timeline spans via
  /// the engine's [TraceTimelineAdapter]; Timeline failures can never break
  /// application flow.
  ///
  /// If [body] throws, the failure is still fully recorded (with the true
  /// duration and `didThrow: true`) and then the ORIGINAL error object and
  /// its original stack trace are rethrown untouched. Invalid [metadata]
  /// throws [ArgumentError] before [body] runs (fail fast, nothing timed).
  R trace<R>(String name, R Function() body, {Map<String, Object?>? metadata}) {
    final start = _startTrace(name, metadata);
    _syncTimeline.start(name, start.arguments);
    try {
      final result = body();
      _syncTimeline.finish();
      _endTrace(start, didThrow: false);
      return result;
    } catch (_) {
      _syncTimeline.finish();
      _endTrace(start, didThrow: true);
      // Plain rethrow: preserves both the original error object and its
      // original stack trace exactly.
      rethrow;
    }
  }

  /// Async counterpart of [trace] for [Future]-returning bodies, using
  /// async-flavor Timeline spans ([TimelineTask] start/finish).
  ///
  /// Failure semantics match [trace]: record first, then rethrow the
  /// ORIGINAL error and stack trace untouched (`await` surfaces exactly
  /// the error/stack the failed future carried).
  Future<R> traceAsync<R>(String name, Future<R> Function() body,
      {Map<String, Object?>? metadata}) async {
    final start = _startTrace(name, metadata);
    _asyncTimeline.start(name, start.arguments);
    R result;
    try {
      result = await body();
    } catch (_) {
      _asyncTimeline.finish();
      _endTrace(start, didThrow: true);
      // Preserves the error object and the stack trace attached to the
      // failed future — exactly what an uninstrumented await would throw.
      rethrow;
    }
    _asyncTimeline.finish();
    _endTrace(start, didThrow: false);
    return result;
  }

  _TraceStartContext _startTrace(String name, Map<String, Object?>? metadata) {
    return _TraceStartContext(
      id: _traceIds.next(),
      name: name,
      startedAt: _clock.now(),
      screen: currentScreen,
      interactionId: () {
        final active = _interactionTracker.activeInteractionId;
        return active == noActiveInteractionId ? null : active;
      }(),
      arguments:
          metadata == null ? null : MetadataValidator.validatedCopy(metadata),
    );
  }

  void _endTrace(_TraceStartContext start, {required bool didThrow}) {
    if (_disposed) {
      // Body must still have run to completion; only bookkeeping stops.
      return;
    }
    final endedAt = _clock.now();
    final duration = endedAt.difference(start.startedAt);
    final completed = CompletedTrace(
      id: start.id,
      name: start.name,
      startedAt: start.startedAt,
      duration: duration,
      screen: start.screen,
      didThrow: didThrow,
      metadata: start.arguments ?? const <String, Object?>{},
    );
    _guard(() {
      // Single trace storage point: the manager forwards into the shared
      // tracker. Runs even without an active session so the bounded
      // recent-trace window survives across sessions.
      _sessionManager.recordTrace(completed);
      _dispatch(TraceEvent(
        id: _eventIds.next(),
        timestamp: endedAt,
        traceId: completed.id,
        name: completed.name,
        duration: duration,
        didThrow: didThrow,
        screen: completed.screen,
        interactionId: start.interactionId,
        metadata: completed.metadata,
      ));
      _evaluateLongTrace(completed, start.interactionId, endedAt);
    });
  }

  /// Emits a [LongTraceAnomaly] when [trace] exceeded the configured long
  /// trace threshold. Correlation with screen/interaction is temporal
  /// only — this NEVER claims the trace caused any specific frame.
  void _evaluateLongTrace(
    CompletedTrace trace,
    String? interactionId,
    DateTime detectedAt,
  ) {
    final threshold = config.longTraceThreshold;
    if (trace.duration <= threshold) {
      return;
    }
    final anomaly = LongTraceAnomaly(
      id: _anomalyIds.next(),
      timestamp: detectedAt,
      severity: LongTraceAnomaly.severityFor(trace.duration, threshold),
      traceId: trace.id,
      name: trace.name,
      duration: trace.duration,
      screen: trace.screen,
      interactionId: interactionId,
      metadata: trace.metadata,
    );
    _anomalies.add(anomaly);
    // Route the long trace into the active session's aggregates too
    // (no-op when no session is open) — same contract as frame anomalies.
    _guard(() => _sessionManager.recordAnomaly(anomaly));
    _dispatch(AnomalyEvent(
      id: _eventIds.next(),
      timestamp: detectedAt,
      anomaly: anomaly,
    ));
  }

  /// Removes one metadata entry, returning its previous value.
  Object? removeMetadata(String key) => _metadataStore.remove(key);

  /// Removes every metadata entry.
  void clearMetadata() => _metadataStore.clear();

  /// Starts observing frames. Idempotent: repeated calls are no-ops.
  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    // Subscribe before starting so broadcast samples cannot be dropped
    // between registration and first delivery.
    _framesSubscription =
        _frameSource.frames.listen(_onFrame, onError: _logError);
    await _frameSource.start();
    _started = true;
    // Session auto-start honors the config at start() time. An injected
    // manager that already has a session open is left untouched.
    if (config.autoStartSession && !_sessionManager.hasActiveSession) {
      _guard(_sessionManager.start);
    }
  }

  /// Stops the engine and releases its resources. Idempotent.
  ///
  /// Recording into the active session stops with the engine: after
  /// dispose no frame, trace, interaction, or anomaly ever reaches the
  /// [SessionManager] (every pipeline stage checks [_disposed]). An open
  /// session is intentionally left OPEN — stop it explicitly through
  /// [stopSession] first if a final report is wanted; its aggregates stay
  /// readable afterwards either way.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _framesSubscription?.cancel();
    _framesSubscription = null;
    try {
      await _frameSource.stop();
    } catch (error, stackTrace) {
      _logError(error, stackTrace);
    }
    await _events.close();
  }

  /// Reports an application lifecycle transition, emitting a
  /// [LifecycleEvent]. Safe to call after dispose (no-op).
  void handleLifecycle(AppLifecycleState state) {
    if (_disposed) {
      return;
    }
    _lastLifecycleState = state;
    _guard(() {
      _dispatch(
        LifecycleEvent(
          id: _eventIds.next(),
          timestamp: _clock.now(),
          state: state,
        ),
      );
    });
  }

  @override
  void onRoutePushed(String? name) {
    if (_disposed) {
      return;
    }
    _guard(() {
      final change = _screenTracker.push(name);
      if (change.changed) {
        _emitScreenChange(change, ScreenChangeReason.push);
      }
    });
  }

  @override
  void onRoutePopped() {
    if (_disposed) {
      return;
    }
    _guard(() {
      final change = _screenTracker.pop();
      if (change.changed) {
        _emitScreenChange(change, ScreenChangeReason.pop);
      }
    });
  }

  @override
  void onRouteReplaced(String? newName) {
    if (_disposed) {
      return;
    }
    _guard(() {
      final change = _screenTracker.replace(newName);
      if (change.changed) {
        _emitScreenChange(change, ScreenChangeReason.replace);
      }
    });
  }

  @override
  void onRouteRemoved() {
    if (_disposed) {
      return;
    }
    _guard(() {
      final change = _screenTracker.remove();
      if (change.changed) {
        _emitScreenChange(change, ScreenChangeReason.remove);
      }
    });
  }

  void _emitScreenChange(ScreenStackChange change, ScreenChangeReason reason) {
    _dispatch(ScreenEvent(
      id: _eventIds.next(),
      timestamp: _clock.now(),
      name: change.current,
      previousName: change.previous,
      reason: reason,
    ));
  }

  void _onInteractionSpanEnded(InteractionHandle handle) {
    if (_disposed) {
      return;
    }
    _guard(() {
      final now = _clock.now();
      final duration = now.difference(handle.startedAt);
      // The span duration is known exactly here; feed it to the session
      // aggregates before (and independently of) the event emission.
      _sessionManager.endInteraction(handle.id, duration);
      _dispatch(InteractionEvent(
        id: _eventIds.next(),
        timestamp: now,
        interactionId: handle.id,
        name: handle.name,
        kind: InteractionEventKind.end,
        parentInteractionId: handle.parentInteractionId,
        duration: duration,
      ));
    });
  }

  void _onFrame(FrameSample rawSample) {
    try {
      // Attribute before anything downstream sees the sample.
      final sample = _enrichWith(rawSample);
      final classification = _classifier.classify(sample);
      // Session recording sits right after classify: severity is known
      // and enrichment has already stamped screen/interaction.
      _guard(
          () => _sessionManager.recordFrame(sample, classification.severity));
      _dispatch(
        FrameEvent(
          id: _eventIds.next(),
          timestamp: _clock.now(),
          sample: sample,
        ),
      );
      _recentFrames.add(sample);
      // Anomaly work is failure-contained on its own: a detector or
      // collector bug must never stop the frame pipeline below.
      _guard(() => _detectFrameAnomalies(sample, classification));
    } catch (error, stackTrace) {
      _logError(error, stackTrace);
    }
  }

  /// Frame-anomaly stage of the pipeline, run once per stored frame:
  /// detect → open context window → store → emit → feed windows.
  ///
  /// Order matters: by detection time the anomaly frame is ALREADY the
  /// newest entry in [_recentFrames], so its `before` frames are the last
  /// [PerfScopeConfig.contextFramesBefore] entries EXCLUDING itself.
  /// Offering the frame to the collector happens unconditionally at the
  /// end; the window ignores its own anomaly frame, so an after-window
  /// only ever contains strictly FOLLOWING frames.
  void _detectFrameAnomalies(
    FrameSample sample,
    FrameClassification classification,
  ) {
    final anomaly = _frameAnomalyDetector.detect(sample, classification);
    if (anomaly is FrameAnomaly) {
      final history = _recentFrames.toList();
      final beforeEnd = history.length - 1; // exclude the anomaly frame
      final beforeStart = beforeEnd > config.contextFramesBefore
          ? beforeEnd - config.contextFramesBefore
          : 0;
      _contextWindows.open(
        anomaly.id,
        sample,
        history.sublist(beforeStart, beforeEnd),
        config.contextFramesAfter,
      );
      _anomalies.add(anomaly);
      // Route the anomaly into the active session's aggregates (no-op
      // when no session is open).
      _sessionManager.recordAnomaly(anomaly);
      _dispatch(AnomalyEvent(
        id: _eventIds.next(),
        timestamp: _clock.now(),
        anomaly: anomaly,
      ));
    }
    _contextWindows.offer(sample);
  }

  /// Returns [sample] stamped with the current screen and interaction
  /// attribution (samples are immutable, so an enriched copy is built).
  ///
  /// Attribution precedence for [FrameSample.interactionId]: the innermost
  /// active span wins; otherwise a pending quick marker is consumed — by
  /// the first frame only; with neither present the field stays null.
  FrameSample _enrichWith(FrameSample sample) {
    var interactionId = _interactionTracker.activeInteractionId;
    if (interactionId.isEmpty) {
      interactionId = _interactionTracker.consumePendingMarker() ?? '';
    }
    return FrameSample(
      id: sample.id,
      frameNumber: sample.frameNumber,
      capturedAt: sample.capturedAt,
      buildDuration: sample.buildDuration,
      rasterDuration: sample.rasterDuration,
      totalDuration: sample.totalDuration,
      vsyncOverhead: sample.vsyncOverhead,
      frameBudget: sample.frameBudget,
      screen: _screenTracker.current,
      interactionId: interactionId.isEmpty ? null : interactionId,
    );
  }

  /// Runs [action], containing any synchronous failure inside PerfScope.
  void _guard(void Function() action) {
    try {
      action();
    } catch (error, stackTrace) {
      _logError(error, stackTrace);
    }
  }

  void _logError(Object error, StackTrace stackTrace) {
    try {
      _logWriter.write('[PerfScope] $error\n$stackTrace');
    } catch (_) {
      // A failing log sink must never take the host app down with it.
    }
  }
}

/// Immutable context captured when a manual trace starts, threaded through
/// to completion bookkeeping so attribution always reflects the START
/// moment (screen and interaction are not re-read live afterwards).
final class _TraceStartContext {
  const _TraceStartContext({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.screen,
    required this.interactionId,
    required this.arguments,
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final String screen;
  final String? interactionId;

  /// Validated, defensively copied caller metadata (null when none given).
  final Map<String, Object?>? arguments;
}
