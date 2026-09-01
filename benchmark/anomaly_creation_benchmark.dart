/// Creation-cost benchmark for [createFrameAnomaly].
///
/// Each timed operation covers the full engine-side anomaly path:
/// [IdGenerator.next] for the correlation id, [SystemClock.now] for the
/// timestamp, and the factory dispatch to the concrete subclass matching
/// the probable bottleneck.
///
/// ```
/// dart run benchmark/anomaly_creation_benchmark.dart
/// ```
///
/// Numbers are machine-specific and vary by device; treat them as
/// order-of-magnitude guidance only.
library;

// Benchmark scripts print their report to stdout by design.
// ignore_for_file: avoid_print

import 'package:perfscope/src/anomalies/performance_anomaly.dart';
import 'package:perfscope/src/core/clock.dart';
import 'package:perfscope/src/core/ids.dart';
import 'package:perfscope/src/frames/frame_classifier.dart';
import 'package:perfscope/src/frames/frame_sample.dart';

const int _warmupBatches = 5;
const int _timedBatches = 15;
const int _opsPerBatch = 20000;
final Duration _budget = const Duration(microseconds: 16667); // 60 Hz

void main() {
  // One representative slow, UI-bound sample; classification is hoisted so
  // the measured loop isolates id + clock + factory construction cost.
  final sample = FrameSample(
    id: 1,
    frameNumber: 1,
    capturedAt: DateTime.fromMicrosecondsSinceEpoch(1700000000000000),
    buildDuration: const Duration(microseconds: 27400),
    rasterDuration: const Duration(microseconds: 4800),
    totalDuration: const Duration(microseconds: 33100),
    vsyncOverhead: const Duration(microseconds: 300),
    frameBudget: _budget,
    screen: 'ProductList',
    interactionId: 'int_1',
  );
  const classifier = FrameClassifier();
  final classification =
      classifier.classify(sample); // slow + ui under these numbers
  if (classification.bottleneck != FrameBottleneck.ui) {
    print('FATAL: fixture no longer classifies as UI-bound; fix the sample.');
    return;
  }

  final ids = IdGenerator('anm');
  const clock = SystemClock();
  PerformanceAnomaly? sink;

  void runBatch() {
    for (var op = 0; op < _opsPerBatch; op++) {
      sink = createFrameAnomaly(
        id: ids.next(),
        timestamp: clock.now(),
        sample: sample,
        classification: classification,
      );
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
  print('anomaly_creation_benchmark');
  print('  batches: $_timedBatches x $_opsPerBatch ops '
      '(IdGenerator.next + SystemClock.now + factory dispatch)');
  print('  median: ${medianNs.toStringAsFixed(1)} ns/op');
  print('  throughput: ${(1e9 / medianNs).toStringAsFixed(0)} ops/sec');
  print('  last created: ${sink.runtimeType}');
}
