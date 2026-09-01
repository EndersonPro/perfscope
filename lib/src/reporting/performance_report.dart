/// Immutable end-of-session report: session identity, aggregate
/// statistics, per-screen and per-interaction summaries, completed traces,
/// and the anomalies ranked worst-first.
///
/// Reports are pure computation over records already held in memory — no
/// IO, no formatting. Text rendering (Phase 7) and serialization (Phase 8)
/// build on top of these values.
library;

import '../anomalies/performance_anomaly.dart';
import '../sessions/performance_session.dart';
import '../traces/trace_tracker.dart';
import 'interaction_summary.dart';
import 'screen_summary.dart';
import 'statistics.dart';

/// The full report for one finished [PerformanceSession].
final class PerformanceReport {
  /// Creates a report. The given lists are copied; later mutations of the
  /// caller's collections never leak into the report.
  PerformanceReport({
    required this.session,
    required this.statistics,
    required List<ScreenPerformanceSummary> screens,
    required List<InteractionPerformanceSummary> interactions,
    required List<CompletedTrace> traces,
    required List<PerformanceAnomaly> anomalies,
    required this.worstAnomalies,
  })  : screens = List.unmodifiable(screens),
        interactions = List.unmodifiable(interactions),
        traces = List.unmodifiable(traces),
        anomalies = List.unmodifiable(anomalies);

  /// The session this report closes.
  final PerformanceSession session;

  /// Session-wide frame statistics.
  final SessionStatistics statistics;

  /// Every screen seen during the session, ranked by the builder's rule,
  /// including screens with zero anomalies.
  final List<ScreenPerformanceSummary> screens;

  /// Every interaction name seen during the session, ranked like
  /// [screens], including interactions with zero anomalies.
  final List<InteractionPerformanceSummary> interactions;

  /// Completed traces recorded while the engine ran (bounded window).
  final List<CompletedTrace> traces;

  /// All anomalies attributed to the session, in detection order.
  final List<PerformanceAnomaly> anomalies;

  /// Top 10 most serious anomalies: severity descending, then duration
  /// descending where the anomaly carries one.
  final List<PerformanceAnomaly> worstAnomalies;
}
