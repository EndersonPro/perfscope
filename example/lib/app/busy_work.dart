import 'dart:math';

/// Calibrates the device speed, then spins the CPU for roughly [target] of
/// wall-clock time and returns the actually elapsed duration.
///
/// NEVER hardcode iteration counts: iteration cost varies by orders of
/// magnitude across devices and build modes. A fixed probe batch
/// (20000 trivial iterations) is timed first, an iterations-per-millisecond
/// rate is derived from it, and the spin length is scaled to the measured
/// rate.
///
/// Shared by several scenarios (UI-thread jank, sync tracing, before/after
/// comparison) so every screen janks by the same, device-adaptive recipe.
Duration busyWork(Duration target) {
  const int probeIterations = 20000;
  final Stopwatch watch = Stopwatch()..start();
  double sink = 0;
  for (int i = 0; i < probeIterations; i++) {
    sink += sqrt(i);
  }
  watch.stop();
  if (sink.isNaN || watch.elapsedMicroseconds == 0) {
    // Degenerate probe (should not happen); do nothing measurable.
    return Duration.zero;
  }
  final double iterationsPerMs =
      probeIterations / (watch.elapsedMicroseconds / 1000);
  final int spinIterations = (iterationsPerMs * target.inMilliseconds)
      .round()
      .clamp(1, 1 << 40);

  final Stopwatch busy = Stopwatch()..start();
  double checksum = 0;
  for (int i = 0; i < spinIterations; i++) {
    checksum += sqrt(i);
  }
  busy.stop();
  assert(checksum.isFinite);
  return busy.elapsed;
}
