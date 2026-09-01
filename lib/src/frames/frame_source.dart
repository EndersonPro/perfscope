import 'frame_sample.dart';

/// Contract for anything that can observe frames and turn them into
/// [FrameSample] values on a stream.
///
/// Implementations decide where frame timings come from (the Flutter engine,
/// a fake in tests, or another platform surface) while the rest of PerfScope
/// only consumes the resulting stream.
abstract interface class FrameSource {
  /// Stream of converted samples. Must be subscribed before [start] so no
  /// early samples are dropped by broadcast semantics.
  Stream<FrameSample> get frames;

  /// Begins observing the underlying source of frame timings.
  ///
  /// May throw [StateError] if already started; see implementations.
  Future<void> start();

  /// Stops observing. Implementations must tolerate being called when not
  /// running (idempotent).
  Future<void> stop();
}
