/// Throughput benchmark for [RingBuffer.add] at capacity 500.
///
/// Fills the buffer once, then times the steady-state OVERWRITE path
/// (every add replaces the oldest slot and advances the head), which is
/// the path PerfScope hits during long frame-monitoring sessions.
///
/// ```
/// dart run benchmark/ring_buffer_benchmark.dart
/// ```
///
/// Numbers are machine-specific and vary by device; treat them as
/// order-of-magnitude guidance only.
library;

// Benchmark scripts print their report to stdout by design.
// ignore_for_file: avoid_print

import 'package:perfscope/src/buffers/ring_buffer.dart';

const int capacity = 500;
const int _warmupBatches = 5;
const int _timedBatches = 10;
const int _opsPerBatch = 200000;

void main() {
  final buffer = RingBuffer<int>(capacity);

  // Pre-fill so timed batches exercise only the overwrite branch.
  for (var i = 0; i < capacity; i++) {
    buffer.add(i);
  }

  var next = 0;
  var sink = 0;

  void runBatch() {
    for (var op = 0; op < _opsPerBatch; op++) {
      buffer.add(next++);
    }
    // Consume the tail so the JIT cannot dead-code the adds.
    sink += buffer.last!;
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
  print('ring_buffer_benchmark');
  print('  capacity: $capacity, batches: $_timedBatches x $_opsPerBatch ops '
      '(steady-state overwrite)');
  print('  median: ${medianNs.toStringAsFixed(1)} ns/op');
  print('  throughput: ${(1e9 / medianNs).toStringAsFixed(0)} ops/sec');
  if (sink == -1) print('  (unreachable sink: $sink)');
}
