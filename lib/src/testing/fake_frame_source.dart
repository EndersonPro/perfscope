import 'dart:async';

import '../frames/frame_sample.dart';
import '../frames/frame_source.dart';

/// Deterministic [FrameSource] for tests.
///
/// Lets test code push synthetic [FrameSample] batches directly via [emit]
/// / [emitAll]; start/stop merely track state through [started]/[stopped].
/// No timers are involved, so tests stay fully synchronous in their
/// arrangement and only await stream delivery.
final class FakeFrameSource implements FrameSource {
  final StreamController<FrameSample> _controller =
      StreamController<FrameSample>.broadcast(sync: false);

  bool _started = false;
  bool _stopped = false;

  /// Whether [start] has been called.
  bool get started => _started;

  /// Whether [stop] has been called.
  bool get stopped => _stopped;

  @override
  Stream<FrameSample> get frames => _controller.stream;

  @override
  Future<void> start() async {
    _started = true;
  }

  @override
  Future<void> stop() async {
    _stopped = true;
  }

  /// Pushes one synthetic sample to every current listener.
  void emit(FrameSample sample) => _controller.add(sample);

  /// Pushes each of [samples] in iteration order.
  void emitAll(Iterable<FrameSample> samples) {
    for (final sample in samples) {
      emit(sample);
    }
  }
}
