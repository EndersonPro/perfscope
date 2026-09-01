/// Owns the ACTIVE PerfScope session and everything it aggregates:
/// frame statistics, per-screen and per-interaction accumulators, and the
/// attributed anomaly list.
///
/// Trace storage is NOT duplicated here — the engine's existing
/// [TraceTracker] instance is injected and reused as the single source of
/// truth; reports read their trace list from it.
///
/// All recording APIs are no-ops when no session is active, so callers
/// never need to guard their calls.
library;

import '../anomalies/performance_anomaly.dart';
import '../core/clock.dart';
import '../core/ids.dart';
import '../context/screen_tracker.dart' show unknownScreenName;
import '../frames/frame_budget.dart';
import '../frames/frame_classifier.dart';
import '../frames/frame_sample.dart';
import '../reporting/interaction_summary.dart';
import '../reporting/performance_report.dart';
import '../reporting/report_builder.dart';
import '../reporting/screen_summary.dart';
import '../reporting/statistics.dart';
import '../traces/trace_tracker.dart';
import 'performance_session.dart';

/// Maximum entries in the interaction id→name lookup used to attribute
/// span endings and anomalies back to their named flow. Oldest-inserted
/// ids are evicted first so memory stays bounded.
const int defaultInteractionNameCacheCapacity = 512;

/// Creates, finalizes, and aggregates [PerformanceSession]s.
final class SessionManager {
  /// Creates a manager reusing [traceTracker] as its completed-trace
  /// store. [frameBudgetProvider] and [metadataSnapshot] feed each new
  /// session's environment/metadata record; when omitted the environment
  /// falls back to the canonical 60 Hz budget.
  SessionManager({
    required TraceTracker traceTracker,
    Clock clock = const SystemClock(),
    FrameBudgetProvider? frameBudgetProvider,
    Map<String, Object?> Function()? metadataSnapshot,
    int statisticWindowCapacity = defaultStatisticWindowCapacity,
    int interactionNameCacheCapacity = defaultInteractionNameCacheCapacity,
  })  : _traceTracker = traceTracker,
        _clock = clock,
        _frameBudgetProvider = frameBudgetProvider,
        _metadataSnapshot = metadataSnapshot,
        _statisticWindowCapacity = statisticWindowCapacity,
        _interactionNameCacheCapacity = interactionNameCacheCapacity,
        assert(statisticWindowCapacity > 0),
        assert(interactionNameCacheCapacity > 0);

  final TraceTracker _traceTracker;
  final Clock _clock;
  final FrameBudgetProvider? _frameBudgetProvider;
  final Map<String, Object?> Function()? _metadataSnapshot;
  final int _statisticWindowCapacity;
  final int _interactionNameCacheCapacity;

  final IdGenerator _sessionIds = IdGenerator('ses');

  StatisticsCalculator? _calculator;
  Map<String, ScreenPerformanceAccumulator>? _screens;
  Map<String, InteractionPerformanceAccumulator>? _interactions;

  /// Insertion-ordered id→name map with oldest-entry eviction.
  final Map<String, String> _interactionNames = <String, String>{};
  final Set<String> _notedInteractionIds = <String>{};
  List<PerformanceAnomaly> _activeAnomalies = <PerformanceAnomaly>[];
  PerformanceSession? _activeSession;
  PerformanceSession? _lastFinishedSession;
  PerformanceReport? _lastReport;

  /// The currently open session, or null.
  PerformanceSession? get activeSession => _activeSession;

  /// The most recently finished session (explicit stop OR auto-finalize
  /// by a subsequent start), or null.
  PerformanceSession? get lastFinishedSession => _lastFinishedSession;

  /// The most recently produced report, or null before any stop.
  PerformanceReport? get lastReport => _lastReport;

  /// Whether a session is currently open.
  bool get hasActiveSession => _activeSession != null;

  /// Opens a new session. If one is already active it is auto-finalized
  /// FIRST (its [PerformanceSession.endedAt] is set and it becomes
  /// retrievable through [lastFinishedSession]) so exactly one session is
  /// ever open.
  PerformanceSession start({String? name}) {
    if (_activeSession != null) {
      _finalizeActive();
    }
    final now = _clock.now();
    final budgetProvider = _frameBudgetProvider;
    _calculator = StatisticsCalculator(
      windowCapacity: _statisticWindowCapacity,
    );
    _screens = <String, ScreenPerformanceAccumulator>{};
    _interactions = <String, InteractionPerformanceAccumulator>{};
    _activeAnomalies = <PerformanceAnomaly>[];
    _notedInteractionIds.clear();
    _interactionNames.clear();
    final session = PerformanceSession(
      id: _sessionIds.next(),
      name: name,
      startedAt: now,
      environment: buildPerformanceEnvironment(
        frameBudget:
            budgetProvider?.currentBudget ?? FixedFrameBudget.fallbackBudget,
        source: budgetProvider?.source ?? FrameBudgetSource.fallback,
      ),
      metadata: _metadataSnapshot?.call(),
      calculator: _calculator!,
      anomalies: _activeAnomalies,
    );
    _activeSession = session;
    return session;
  }

  /// Closes the active session and builds its [PerformanceReport].
  ///
  /// Throws [StateError] when nothing is active. After a successful stop
  /// every recording API becomes a no-op until the next [start].
  PerformanceReport stop() {
    final session = _activeSession;
    if (session == null) {
      throw StateError(
          'No active PerfScope session to stop: call start() first.');
    }
    session.endedAt = _clock.now();
    final statistics = _calculator?.snapshot() ?? SessionStatistics.zero;
    final report = buildPerformanceReport(
      session: session,
      statistics: statistics,
      screenAccumulators: _screens?.values ?? const [],
      interactionAccumulators: _interactions?.values ?? const [],
      traces: _traceTracker.traces,
      anomalies: List.of(_activeAnomalies),
    );
    _lastFinishedSession = session;
    _lastReport = report;
    session.attachReport(report);
    // Clear ACTIVE pointers only: the finished session keeps its own
    // references, so its statistics()/anomalies stay stable afterwards.
    _activeSession = null;
    _calculator = null;
    _screens = null;
    _interactions = null;
    _activeAnomalies = const <PerformanceAnomaly>[];
    _notedInteractionIds.clear();
    _interactionNames.clear();
    return report;
  }

  /// Records one classified frame into the session aggregates. No-op
  /// without an active session.
  void recordFrame(FrameSample sample, FrameSeverity severity) {
    final screens = _screens;
    final interactions = _interactions;
    if (_calculator == null || screens == null || interactions == null) {
      return;
    }
    _calculator!.addFrame(sample, severity);
    final screenAccumulator = screens[sample.screen ?? unknownScreenName] ??=
        ScreenPerformanceAccumulator(
      sample.screen ?? unknownScreenName,
      windowCapacity: _statisticWindowCapacity,
    );
    screenAccumulator.addFrame(sample, severity);
    final interactionId = sample.interactionId;
    if (interactionId == null) {
      return;
    }
    final name = _interactionNames[interactionId];
    if (name == null) {
      return;
    }
    final interactionAccumulator =
        interactions[name] ??= InteractionPerformanceAccumulator(
      name,
      windowCapacity: _statisticWindowCapacity,
    );
    interactionAccumulator.addFrame(sample, severity);
  }

  /// Notes that an interaction span (or quick marker — markers count as
  /// spans) with [id] started under [name]. No-op without an active
  /// session or for repeated ids.
  void noteInteraction(String id, String name) {
    final interactions = _interactions;
    if (interactions == null || _notedInteractionIds.contains(id)) {
      return;
    }
    _notedInteractionIds.add(id);
    _rememberInteractionName(id, name);
    final accumulator =
        interactions[name] ??= InteractionPerformanceAccumulator(
      name,
      windowCapacity: _statisticWindowCapacity,
    );
    accumulator.noteSpan(id);
  }

  /// Credits [duration] of completed span wall-clock time to the flow the
  /// [id] was noted under. Unknown/evicted ids are ignored.
  void endInteraction(String id, Duration duration) {
    final interactions = _interactions;
    if (interactions == null) {
      return;
    }
    final name = _interactionNames[id];
    if (name == null) {
      return;
    }
    final accumulator = interactions[name];
    if (accumulator == null) {
      return;
    }
    accumulator.addSpanDuration(duration);
  }

  /// Routes an anomaly into the matching screen/interaction aggregates.
  ///
  /// Sealed-type routing: [FrameAnomaly]s credit the screen and
  /// interaction captured on their sample AND count toward the
  /// probable-bottleneck mode; [LongTraceAnomaly]s credit only the
  /// anomaly counters of their correlated screen/interaction — they never
  /// touch frame statistics or bottleneck modes. No-op inactive.
  void recordAnomaly(PerformanceAnomaly anomaly) {
    if (_screens == null) {
      return;
    }
    // Every attributed anomaly joins the session record; the routing below
    // only decides which screen/interaction aggregates it ALSO credits.
    _activeAnomalies.add(anomaly);
    switch (anomaly) {
      case final FrameAnomaly frameAnomaly:
        _screenAccumulator(frameAnomaly.sample.screen)?.addAnomaly(
          frameAnomaly,
        );
        final frameInteractionId = frameAnomaly.sample.interactionId;
        if (frameInteractionId != null) {
          _interactionAccumulator(frameInteractionId)?.addAnomaly(frameAnomaly);
        }
      case final LongTraceAnomaly longTraceAnomaly:
        _screenAccumulator(longTraceAnomaly.screen)?.addAnomaly(
          longTraceAnomaly,
        );
        final traceInteractionId = longTraceAnomaly.interactionId;
        if (traceInteractionId != null) {
          _interactionAccumulator(traceInteractionId)
              ?.addAnomaly(longTraceAnomaly);
        }
    }
  }

  /// Forwards a completed trace into the shared [TraceTracker].
  ///
  /// Unlike the other recording APIs this one works WITHOUT an active
  /// session too: the recent-trace window survives across sessions by
  /// design, and reports snapshot whatever the tracker holds at stop time.
  void recordTrace(CompletedTrace trace) => _traceTracker.record(trace);

  void _rememberInteractionName(String id, String name) {
    // Re-inserting refreshes recency for repeated ids.
    _interactionNames.remove(id);
    _interactionNames[id] = name;
    while (_interactionNames.length > _interactionNameCacheCapacity) {
      _interactionNames.remove(_interactionNames.keys.first);
    }
  }

  ScreenPerformanceAccumulator? _screenAccumulator(String? screenName) {
    final screens = _screens;
    if (screens == null) {
      return null;
    }
    final key = screenName ?? unknownScreenName;
    return screens[key] ??= ScreenPerformanceAccumulator(
      key,
      windowCapacity: _statisticWindowCapacity,
    );
  }

  InteractionPerformanceAccumulator? _interactionAccumulator(String id) {
    final interactions = _interactions;
    if (interactions == null) {
      return null;
    }
    final name = _interactionNames[id];
    if (name == null) {
      return null;
    }
    return interactions[name] ??= InteractionPerformanceAccumulator(
      name,
      windowCapacity: _statisticWindowCapacity,
    );
  }

  void _finalizeActive() {
    final session = _activeSession;
    if (session == null) {
      return;
    }
    session.endedAt = _clock.now();
    // Build and attach a report BEFORE the accumulators are dropped so the
    // auto-finalized session stays fully exportable through
    // [PerformanceSession.attachedReport]. Unlike [stop], the report is NOT
    // published as [lastReport] — that getter keeps meaning "the last
    // explicitly stopped session".
    session.attachReport(buildPerformanceReport(
      session: session,
      statistics: _calculator?.snapshot() ?? SessionStatistics.zero,
      screenAccumulators: _screens?.values ?? const [],
      interactionAccumulators: _interactions?.values ?? const [],
      traces: _traceTracker.traces,
      anomalies: List.of(_activeAnomalies),
    ));
    _lastFinishedSession = session;
    _activeSession = null;
    _calculator = null;
    _screens = null;
    _interactions = null;
    _activeAnomalies = const <PerformanceAnomaly>[];
    _notedInteractionIds.clear();
    _interactionNames.clear();
  }
}
