/// A recorded PerfScope session: its identity, environment, metadata
/// snapshot, and the live aggregates backing [statistics] / [anomalies].
///
/// A session is created exclusively by [SessionManager.start]. While the
/// session is active its aggregates keep growing; after `endedAt` is set
/// (by an explicit stop or by starting a replacement session) the same
/// getters return frozen values, because the manager stops writing into
/// the retired accumulators and opens fresh ones for the next session.
library;

import '../anomalies/performance_anomaly.dart';
import '../frames/frame_budget.dart';
import '../reporting/performance_report.dart';
import '../reporting/statistics.dart';
import 'is_web.dart';
import 'platform_name.dart';

/// Immutable description of the environment a session ran in.
final class PerformanceEnvironment {
  /// Creates an immutable environment description.
  const PerformanceEnvironment({
    required this.frameBudgetFps,
    required this.frameBudgetMs,
    required this.frameBudgetSource,
    required this.platform,
  });

  /// Effective frame budget expressed as frames per second, rounded to
  /// two decimals (e.g. `60.0` for a 16.667 ms budget).
  final double frameBudgetFps;

  /// Effective per-frame budget in milliseconds, rounded to three decimals.
  final double frameBudgetMs;

  /// Where the budget came from (detected/configured/fallback).
  final FrameBudgetSource frameBudgetSource;

  /// Host platform name (`web`, or the OS name; `'unknown'` when the
  /// runtime refuses to answer).
  final String platform;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerformanceEnvironment &&
          runtimeType == other.runtimeType &&
          frameBudgetFps == other.frameBudgetFps &&
          frameBudgetMs == other.frameBudgetMs &&
          frameBudgetSource == other.frameBudgetSource &&
          platform == other.platform;

  @override
  int get hashCode =>
      Object.hash(frameBudgetFps, frameBudgetMs, frameBudgetSource, platform);
}

/// Builds the [PerformanceEnvironment] for a session from the effective
/// frame budget. Pure: fps = 1e6 / budget µs rounded to two decimals.
PerformanceEnvironment buildPerformanceEnvironment({
  required Duration frameBudget,
  required FrameBudgetSource source,
}) {
  final micros = frameBudget.inMicroseconds;
  final fps = micros <= 0 ? 0.0 : Duration.microsecondsPerSecond / micros;
  return PerformanceEnvironment(
    frameBudgetFps: (fps * 100).roundToDouble() / 100,
    // Integer µs ÷ 1000 IS the correctly-rounded 3-decimal ms value.
    frameBudgetMs: microsToMsRounded(micros),
    frameBudgetSource: source,
    platform: kRunsOnWeb ? 'web' : resolvePlatformName(),
  );
}

/// One recorded observation window over app performance.
///
/// Instances are mutable in exactly one field ([endedAt]); everything else
/// is fixed at creation. The anomaly list and statistics are backed by the
/// manager's live accumulators while active, then freeze on stop.
final class PerformanceSession {
  /// Creates a session. Called by [SessionManager]; [metadata] is copied
  /// defensively so later caller-side mutations never leak in either
  /// direction (the store snapshot itself is already deep-copied).
  PerformanceSession({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.environment,
    Map<String, Object?>? metadata,
    required StatisticsCalculator calculator,
    required List<PerformanceAnomaly> anomalies,
  })  : metadata =
            Map<String, Object?>.of(metadata ?? const <String, Object?>{}),
        _calculator = calculator,
        _anomalies = anomalies;

  /// Local correlation identifier unique within this PerfScope process
  /// (prefix `ses`).
  final String id;

  /// Optional caller-provided label (e.g. `'release-check'`).
  final String? name;

  /// Wall-clock time at which the session opened.
  final DateTime startedAt;

  /// Wall-clock time at which the session closed, null while active.
  DateTime? endedAt;

  /// Environment the session runs against.
  final PerformanceEnvironment environment;

  /// Defensive snapshot of the metadata store taken at START: later store
  /// mutations do not retroactively change the session record.
  final Map<String, Object?> metadata;

  final StatisticsCalculator _calculator;
  final List<PerformanceAnomaly> _anomalies;

  /// Report attached when the session was stopped, auto-finalized, or
  /// rebuilt by the deserializer. Null while the session is live.
  PerformanceReport? _attachedReport;

  /// Frozen statistics injected by [freezeStatistics]; takes precedence
  /// over [_calculator] once set.
  SessionStatistics? _frozenStatistics;

  /// Whether the session is still open (no [endedAt] set).
  bool get isActive => endedAt == null;

  /// Current statistics — frozen once the session has ended.
  ///
  /// Returns the value installed by [freezeStatistics] when present (the
  /// deserialization path), otherwise a snapshot of the live accumulators
  /// (the normal recording path).
  SessionStatistics statistics() => _frozenStatistics ?? _calculator.snapshot();

  /// Unmodifiable view of the anomalies attributed to this session.
  List<PerformanceAnomaly> get anomalies => List.unmodifiable(_anomalies);

  /// The report produced for this session by `SessionManager.stop()`, the
  /// auto-finalize path, or deserialization; null before that point.
  ///
  /// Exporters read this instead of rebuilding aggregates so an export
  /// always reflects exactly what was reported.
  PerformanceReport? get attachedReport => _attachedReport;

  /// Stores [report] as this session's [attachedReport].
  ///
  /// Called by the session manager on stop/auto-finalize and public so the
  /// parser can re-attach a reconstructed report to a parsed session.
  void attachReport(PerformanceReport report) {
    _attachedReport = report;
  }

  /// Installs [statistics] as the frozen result of [statistics].
  ///
  /// For DESERIALIZATION only: parsed sessions have no recording history,
  /// so their empty accumulators would recompute zeros. The parser calls
  /// this with the statistics decoded from the summary block.
  void freezeStatistics(SessionStatistics statistics) {
    _frozenStatistics = statistics;
  }
}
