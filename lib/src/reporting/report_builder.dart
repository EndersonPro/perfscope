/// Pure assembly of [PerformanceReport] values from accumulated records.
///
/// Deterministic by contract: identical inputs always produce identically
/// ordered outputs. Ranking rules:
/// * Screens and interactions: `anomalyCount` DESC → `p95Ms` DESC →
///   name ASC.
/// * Worst anomalies: severity DESC → duration DESC (long-trace anomalies
///   use their trace duration, frame anomalies their frame's total) → id
///   ASC as the final tiebreaker.
library;

import '../anomalies/performance_anomaly.dart';
import '../sessions/performance_session.dart';
import '../traces/trace_tracker.dart';
import 'interaction_summary.dart';
import 'performance_report.dart';
import 'screen_summary.dart';
import 'statistics.dart';

/// Builds a [PerformanceReport] from one session's frozen records.
///
/// The screens/interactions iterables may contain accumulators with zero
/// records — every screen/interaction seen is included in the report.
PerformanceReport buildPerformanceReport({
  required PerformanceSession session,
  required SessionStatistics statistics,
  required Iterable<ScreenPerformanceAccumulator> screenAccumulators,
  required Iterable<InteractionPerformanceAccumulator> interactionAccumulators,
  required List<CompletedTrace> traces,
  required List<PerformanceAnomaly> anomalies,
}) {
  final screens = screenAccumulators.map((a) => a.build()).toList()
    ..sort(_compareSummaries);
  final interactions = interactionAccumulators.map((a) => a.build()).toList()
    ..sort(_compareInteractions);
  final worst = anomalies.toList()..sort(_compareWorstAnomalies);
  return PerformanceReport(
    session: session,
    statistics: statistics,
    screens: screens,
    interactions: interactions,
    traces: traces,
    anomalies: anomalies,
    worstAnomalies: worst.take(10).toList(),
  );
}

int _compareSummaries(ScreenPerformanceSummary a, ScreenPerformanceSummary b) {
  final byAnomalies = b.anomalyCount.compareTo(a.anomalyCount);
  if (byAnomalies != 0) return byAnomalies;
  final byP95 = b.p95Ms.compareTo(a.p95Ms);
  if (byP95 != 0) return byP95;
  return a.name.compareTo(b.name);
}

int _compareInteractions(
  InteractionPerformanceSummary a,
  InteractionPerformanceSummary b,
) {
  final byAnomalies = b.anomalyCount.compareTo(a.anomalyCount);
  if (byAnomalies != 0) return byAnomalies;
  final byP95 = b.p95Ms.compareTo(a.p95Ms);
  if (byP95 != 0) return byP95;
  return a.name.compareTo(b.name);
}

/// Duration used for worst-anomaly ordering; 0 when none applies.
Duration _anomalyDuration(PerformanceAnomaly anomaly) => switch (anomaly) {
      LongTraceAnomaly(:final duration) => duration,
      FrameAnomaly(:final sample) => sample.totalDuration,
    };

int _compareWorstAnomalies(PerformanceAnomaly a, PerformanceAnomaly b) {
  final bySeverity = b.severity.index.compareTo(a.severity.index);
  if (bySeverity != 0) return bySeverity;
  final byDuration = _anomalyDuration(b).compareTo(_anomalyDuration(a));
  if (byDuration != 0) return byDuration;
  return a.id.compareTo(b.id);
}
