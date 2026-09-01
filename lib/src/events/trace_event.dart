part of 'performance_event.dart';

/// Emitted exactly once per completed manual trace, whether its body
/// succeeded or threw.
///
/// Correlates with a stored [CompletedTrace] via [traceId]; when the trace
/// exceeded the configured long-trace threshold, an [AnomalyEvent] carrying
/// a `LongTraceAnomaly` follows immediately after this one.
final class TraceEvent extends PerformanceEvent {
  /// Creates a trace event.
  const TraceEvent({
    required super.id,
    required super.timestamp,
    required this.traceId,
    required this.name,
    required this.duration,
    required this.didThrow,
    required this.screen,
    required this.metadata,
    this.interactionId,
  });

  /// Correlation id of the completed trace (prefix `trc`).
  final String traceId;

  /// Caller-provided label of the traced operation.
  final String name;

  /// How long the traced operation took, including the failure path.
  final Duration duration;

  /// Whether the traced body threw before completing.
  final bool didThrow;

  /// Screen name captured when the trace *started* (not live values).
  final String screen;

  /// Id of the interaction span active when the trace started, if any.
  ///
  /// Temporal correlation only: co-occurrence is not causation.
  final String? interactionId;

  /// Validated, defensively copied caller-supplied context.
  final Map<String, Object?> metadata;
}
