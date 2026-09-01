/// Immutable record describing a single measured frame.
///
/// Instances are plain value objects: equality covers every field.
/// [capturedAt] is a real timestamp so a const constructor is not possible;
/// use normal construction and treat instances as immutable afterwards.
class FrameSample {
  /// Creates a frame sample.
  FrameSample({
    required this.id,
    required this.frameNumber,
    required this.capturedAt,
    required this.buildDuration,
    required this.rasterDuration,
    required this.totalDuration,
    required this.vsyncOverhead,
    required this.frameBudget,
    required this.screen,
    required this.interactionId,
  });

  /// Local correlation identifier unique within this PerfScope session.
  final int id;

  /// Monotonic frame number reported by the engine, when available.
  final int? frameNumber;

  /// Wall-clock time at which the frame was captured.
  final DateTime capturedAt;

  /// Time spent executing UI (build/layout/paint) phase work.
  final Duration buildDuration;

  /// Time spent in the rasterization thread for this frame.
  final Duration rasterDuration;

  /// Total wall time from vsync start to frame completion.
  final Duration totalDuration;

  /// Overhead attributed to scheduling relative to the vsync signal.
  final Duration vsyncOverhead;

  /// Budget this frame was expected to meet (e.g. 16.667ms at 60Hz).
  final Duration frameBudget;

  /// Name of the screen visible while the frame was rendered, if known.
  final String? screen;

  /// Identifier of the interaction that triggered this frame, if any.
  final String? interactionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrameSample &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          frameNumber == other.frameNumber &&
          capturedAt == other.capturedAt &&
          buildDuration == other.buildDuration &&
          rasterDuration == other.rasterDuration &&
          totalDuration == other.totalDuration &&
          vsyncOverhead == other.vsyncOverhead &&
          frameBudget == other.frameBudget &&
          screen == other.screen &&
          interactionId == other.interactionId;

  @override
  int get hashCode => Object.hash(
        id,
        frameNumber,
        capturedAt,
        buildDuration,
        rasterDuration,
        totalDuration,
        vsyncOverhead,
        frameBudget,
        screen,
        interactionId,
      );

  String _ms(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(1)}ms';

  @override
  String toString() => 'FrameSample(#${frameNumber ?? id} '
      'total=${_ms(totalDuration)} '
      'build=${_ms(buildDuration)} '
      'raster=${_ms(rasterDuration)})';
}
