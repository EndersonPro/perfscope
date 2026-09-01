part of 'performance_event.dart';

/// Emitted when the engine detects a [PerformanceAnomaly], right after
/// storing it in the bounded anomaly window.
final class AnomalyEvent extends PerformanceEvent {
  /// Creates an anomaly event.
  const AnomalyEvent({
    required super.id,
    required super.timestamp,
    required this.anomaly,
  });

  /// The detected anomaly.
  final PerformanceAnomaly anomaly;
}
