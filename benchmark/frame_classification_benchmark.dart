/// Throughput benchmark for [FrameClassifier.classify].
///
/// Measures how fast a single shared classifier tiers frame samples across
/// the full severity/bottleneck matrix. Pure Dart — run it directly:
///
/// ```
/// dart run benchmark/frame_classification_benchmark.dart
/// ```
///
/// Numbers are machine-specific and vary by device; treat them as
/// order-of-magnitude guidance only.
library;

// Benchmark scripts print their report to stdout by design.
// ignore_for_file: avoid_print

import 'package:perfscope/src/frames/frame_classifier.dart';
import 'package:perfscope/src/frames/frame_sample.dart';

/// Deterministic LCG so every run feeds identical data to the classifier.
class _Lcg {
  _Lcg(this._state);

  static const int _multiplier = 1103515245;
  static const int _increment = 12345;
  static const int _modulus = 1 << 31;

  int _state;

  int next() => _state = (_multiplier * _state + _increment) % _modulus;
}

const int _sampleCount = 2000;
const int _warmupBatches = 5;
const int _timedBatches = 20;
const int _opsPerBatch = 20000;

void main() {
  final rng = _Lcg(42);
  final budget = const Duration(microseconds: 16667); // 60 Hz

  // Spread samples across severity tiers and bottleneck shapes so both
  // branches of classify() stay hot.
  final samples = List<FrameSample>.generate(_sampleCount, (i) {
    // Cycle build/raster mixes through ui-heavy, raster-heavy, balanced,
    // and one-sided shapes; totals sweep normal → severe territory.
    final shape = i % 4;
    final scaleUs = 4000 + rng.next() % 50000; // 4ms .. ~54ms totals
    final buildUs = switch (shape) {
      0 => scaleUs * 9 ~/ 10,
      1 => scaleUs * 1 ~/ 10,
      2 => scaleUs * 5 ~/ 10,
      _ => scaleUs,
    };
    final rasterUs = switch (shape) {
      0 => scaleUs * 1 ~/ 10,
      1 => scaleUs * 9 ~/ 10,
      2 => scaleUs * 5 ~/ 10,
      _ => 0,
    };
    return FrameSample(
      id: i + 1,
      frameNumber: i + 1,
      capturedAt: DateTime.fromMicrosecondsSinceEpoch(1700000000000000 + i),
      buildDuration: Duration(microseconds: buildUs),
      rasterDuration: Duration(microseconds: rasterUs),
      totalDuration: Duration(microseconds: buildUs + rasterUs),
      vsyncOverhead: const Duration(microseconds: 300),
      frameBudget: budget,
      screen: 'BenchmarkScreen',
      interactionId: i.isOdd ? 'int_${i ~/ 100}' : null,
    );
  });

  const classifier = FrameClassifier();
  var sink = 0;

  void runBatch() {
    for (var op = 0; op < _opsPerBatch; op++) {
      final classification = classifier.classify(samples[op % _sampleCount]);
      // Consume the result so JIT cannot eliminate the work.
      sink += classification.severity.index + classification.bottleneck.index;
    }
  }

  for (var i = 0; i < _warmupBatches; i++) {
    runBatch();
  }

  final nsPerOp = <double>[];
  for (var b = 0; b < _timedBatches; b++) {
    final watch = Stopwatch()..start();
    runBatch();
    watch.stop();
    nsPerOp.add(watch.elapsedMicroseconds * 1000 / _opsPerBatch);
  }
  nsPerOp.sort();

  final medianNs = nsPerOp[nsPerOp.length ~/ 2];
  print('frame_classification_benchmark');
  print('  batches: $_timedBatches x $_opsPerBatch ops '
      '($_sampleCount distinct samples)');
  print('  median: ${medianNs.toStringAsFixed(1)} ns/op');
  print('  throughput: ${(1e9 / medianNs).toStringAsFixed(0)} ops/sec');
  if (sink == -1) print('  (unreachable sink: $sink)');
}
