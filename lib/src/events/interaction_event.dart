part of 'performance_event.dart';

/// Kind of interaction lifecycle reported by an [InteractionEvent].
enum InteractionEventKind {
  /// An interaction span started.
  start,

  /// An interaction span ended; [InteractionEvent.duration] is non-null.
  end,

  /// A one-shot quick marker was recorded for the next observed frame.
  marker,
}

/// Emitted for interaction lifecycle transitions: span starts, span ends,
/// and quick markers.
///
/// [duration] is non-null only for [InteractionEventKind.end].
final class InteractionEvent extends PerformanceEvent {
  /// Creates an interaction event.
  const InteractionEvent({
    required super.id,
    required super.timestamp,
    required this.interactionId,
    required this.name,
    required this.kind,
    this.parentInteractionId,
    this.duration,
  });

  /// Correlation id of the affected span (or marker).
  final String interactionId;

  /// Caller-provided label of the interaction.
  final String name;

  /// Which lifecycle transition this event describes.
  final InteractionEventKind kind;

  /// Id of the enclosing span for nested interactions, null at the root.
  final String? parentInteractionId;

  /// Wall-clock time the span took, set only when [kind] is
  /// [InteractionEventKind.end].
  final Duration? duration;
}
