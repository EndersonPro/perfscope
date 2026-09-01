part of 'performance_event.dart';

/// Emitted once per observed frame, right after classification.
///
/// Carries the immutable [FrameSample] so consumers can apply their own
/// thresholds or statistics without re-deriving anything.
final class FrameEvent extends PerformanceEvent {
  /// Creates a frame event.
  const FrameEvent({
    required super.id,
    required super.timestamp,
    required this.sample,
  });

  /// The measured frame that triggered this event.
  final FrameSample sample;
}
