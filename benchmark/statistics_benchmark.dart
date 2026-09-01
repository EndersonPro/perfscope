/// Throughput benchmark for [StatisticsCalculator].
///
/// Two measurements over the default 10,000-sample window
/// (`maxStatisticSamples`):
/// 1. [StatisticsCalculator.addFrame] steady-state throughput once the
///    percentile window is full (includes ring-buffer eviction).
/// 2. [StatisticsCalculator.snapshot] cost — the nearest-rank percentile
///    pass sorts the whole 10k window on every call.
///
/// ```
/// dart run benchmark/statistics_benchmark.dart
/// ```
///
/// Numbers are machine-specific and vary by device; treat them as
/// order-of-magnitude guidance only.
library;

// Benchmark scripts print their report to stdout by design.
// ignore_for_file: avoid_print

import 'package:perfscope/src/frames/frame_classifier.dart';
import 'package:perfscope/src/frames/frame_sample.dart';
import 'package:perfscope/src/reporting/statistics.dart';

const int _windowCapacity = 10000;
const int _warmupBatches = 3;
const int _timedBatches = 10;
const int _addOpsPerBatch = 100000;
const int _snapshotOpsPerBatch = 20;
final Duration _budget = const Duration(microseconds: 16667); // 60 Hz

/// Deterministic LCG so every run feeds identical data.
class _Lcg {
  _Lcg(this._state);

  static const int _multiplier = 1103515245;
  static const int _increment = 12345;
  static const int _modulus = 1 << 31;

  int _state;

  int next() => _state = (_multiplier * _state + _increment) % _modulus;
}

FrameSample _sample(int i, int buildUs, int rasterUs) => FrameSample(
      id: i + 1,
      frameNumber: i + 1,
      capturedAt: DateTime.fromMicrosecondsSinceEpoch(1700000000000000 + i),
      buildDuration: Duration(microseconds: buildUs),
      rasterDuration: Duration(microseconds: rasterUs),
      totalDuration: Duration(microseconds: buildUs + rasterUs),
      vsyncOverhead: const Duration(microseconds: 300),
      frameBudget: _budget,
      screen: 'BenchmarkScreen',
      interactionId: null,
    );

void main() {
  final rng = _Lcg(7);
  final samples = List<FrameSample>.generate(2000, (i) {
    final buildUs = 2000 + rng.next() % 40000;
    final rasterUs = 1000 + rng.next() % 20000;
    return _sample(i, buildUs, rasterUs);
  });
  final severities = <FrameSeverity>[];
  const classifier = FrameClassifier();
  for (final sample in samples) {
    severities.add(classifier.classify(sample).severity);
  }

  var cursor = 0;
  final calculator = StatisticsCalculator(windowCapacity: _windowCapacity);

  // Pre-fill the window so timed addFrames include eviction cost.
  for (var i = 0; i < _windowCapacity; i++) {
    final idx = i % samples.length;
    calculator.addFrame(samples[idx], severities[idx]);
  }

  void runAddBatch() {
    for (var op = 0; op < _addOpsPerBatch; op++) {
      calculator.addFrame(samples[cursor], severities[cursor]);
      cursor = (cursor + 1) % samples.length;
    }
  }

  for (var i = 0; i < _warmupBatches; i++) {
    runAddBatch();
  }

  final addNsPerOp = <double>[];
  for (var b = 0; b < _timedBatches; b++) {
    final watch = Stopwatch()..start();
    runAddBatch();
    watch.stop();
    addNsPerOp.add(watch.elapsedMicroseconds * 1000 / _addOpsPerBatch);
  }
  addNsPerOp.sort();

  void runSnapshotBatch() {
    var last = calculator.snapshot();
    for (var op = 0; op < _snapshotOpsPerBatch - 1; op++) {
      last = calculator.snapshot();
    }
    // Keep the result observable.
    if (last.totalFrames <= _windowCapacity) {
      print('unexpectedly small statistics window');
    }
  }

  for (var i = 0; i < _warmupBatches; i++) {
    runSnapshotBatch();
  }

  final snapshotNsPerOp = <double>[];
  for (var b = 0; b < _timedBatches; b++) {
    final watch = Stopwatch()..start();
    runSnapshotBatch();
    watch.stop();
    snapshotNsPerOp
        .add(watch.elapsedMicroseconds * 1000 / _snapshotOpsPerBatch);
  }
  snapshotNsPerOp.sort();

  final medianAddNs = addNsPerOp[addNsPerOp.length ~/ 2];
  final medianSnapshotNs = snapshotNsPerOp[snapshotNsPerOp.length ~/ 2];
  print('statistics_benchmark');
  print('  window: $_windowCapacity samples');
  print('  addFrame   median: ${medianAddNs.toStringAsFixed(1)} ns/op '
      '(${(1e9 / medianAddNs).toStringAsFixed(0)} ops/sec)');
  print('  snapshot() median: ${(medianSnapshotNs / 1e6).toStringAsFixed(3)} '
      'ms/op (${(1e9 / medianSnapshotNs).toStringAsFixed(1)} ops/sec) '
      '— sorts the full window per call');
}
