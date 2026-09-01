part of 'performance_anomaly.dart';

/// Raised when a manually traced operation exceeds
/// `PerfScopeConfig.longTraceThreshold`.
///
/// Severity mapping (documented contract, threshold = the configured
/// long-trace threshold):
/// * duration >= 5x threshold → [AnomalySeverity.critical];
/// * duration >= 2x threshold → [AnomalySeverity.high];
/// * otherwise                → [AnomalySeverity.medium].
///
/// Comparisons use greater-than-or-equal on the multipliers: a trace
/// landing exactly on 2x or 5x falls in the higher tier. The anomaly only
/// asserts the trace was slow while [screen]/[interactionId] were current;
/// it never claims causality over any frame.
final class LongTraceAnomaly extends PerformanceAnomaly {
  /// Creates a long-trace anomaly.
  const LongTraceAnomaly({
    required super.id,
    required super.timestamp,
    required super.severity,
    required this.traceId,
    required this.name,
    required this.duration,
    super.screen,
    super.interactionId,
    super.metadata,
  });

  /// Maps a trace [duration] against [threshold] to its anomaly severity,
  /// following the multiplier tiers documented on this class.
  static AnomalySeverity severityFor(Duration duration, Duration threshold) {
    if (duration >= threshold * 5) {
      return AnomalySeverity.critical;
    }
    if (duration >= threshold * 2) {
      return AnomalySeverity.high;
    }
    return AnomalySeverity.medium;
  }

  /// Correlation id of the completed trace that triggered this anomaly.
  final String traceId;

  /// Caller-provided label of the traced operation.
  final String name;

  /// How long the traced operation took.
  final Duration duration;
}
