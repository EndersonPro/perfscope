/// Serialization benchmark for [SessionSerializer.serializeToString].
///
/// Builds ONE synthetic mid-size report directly from the reporting models
/// (3 screens, 2 interactions, 10 traces, 30 anomalies over ~6,000 frames),
/// attaches it to a finished session exactly as `SessionManager.stop()`
/// would, then times repeated JSON serializations of the same report.
///
/// ```
/// dart run benchmark/serialization_benchmark.dart
/// ```
///
/// Numbers are machine-specific and vary by device; treat them as
/// order-of-magnitude guidance only.
library;

// Benchmark scripts print their report to stdout by design.
// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:perfscope/src/anomalies/performance_anomaly.dart';
import 'package:perfscope/src/frames/frame_classifier.dart';
import 'package:perfscope/src/frames/frame_budget.dart';
import 'package:perfscope/src/frames/frame_sample.dart';
import 'package:perfscope/src/reporting/interaction_summary.dart';
import 'package:perfscope/src/reporting/report_builder.dart';
import 'package:perfscope/src/reporting/screen_summary.dart';
import 'package:perfscope/src/reporting/statistics.dart';
import 'package:perfscope/src/serialization/session_serializer.dart';
import 'package:perfscope/src/sessions/performance_session.dart';
import 'package:perfscope/src/traces/trace_tracker.dart';

const int _frameCount = 6000;
const int _anomalyCount = 30;
const int _traceCount = 10;
const int _warmupBatches = 3;
const int _timedBatches = 15;
const int _opsPerBatch = 100;
final Duration _budget = const Duration(microseconds: 16667); // 60 Hz

/// Deterministic LCG so every run builds an identical report.
class _Lcg {
  _Lcg(this._state);

  static const int _multiplier = 1103515245;
  static const int _increment = 12345;
  static const int _modulus = 1 << 31;

  int _state;

  int next() => _state = (_multiplier * _state + _increment) % _modulus;
}

void main() {
  final rng = _Lcg(99);
  const classifier = FrameClassifier();

  final calculator = StatisticsCalculator();
  final screens = <ScreenPerformanceAccumulator>[
    ScreenPerformanceAccumulator('ProductList'),
    ScreenPerformanceAccumulator('Checkout'),
    ScreenPerformanceAccumulator('Home'),
  ];
  final interactions = <InteractionPerformanceAccumulator>[
    InteractionPerformanceAccumulator('scroll_feed'),
    InteractionPerformanceAccumulator('tap_pay'),
  ];
  final anomalies = <PerformanceAnomaly>[];
  final traceList = <CompletedTrace>[];

  var anomalyCursor = 0;
  for (var i = 0; i < _frameCount; i++) {
    final buildUs = 2000 + rng.next() % 40000;
    final rasterUs = 1000 + rng.next() % 20000;
    final sample = FrameSample(
      id: i + 1,
      frameNumber: i + 1,
      capturedAt:
          DateTime.fromMicrosecondsSinceEpoch(1700000000000000 + i * 16667),
      buildDuration: Duration(microseconds: buildUs),
      rasterDuration: Duration(microseconds: rasterUs),
      totalDuration: Duration(microseconds: buildUs + rasterUs),
      vsyncOverhead: const Duration(microseconds: 300),
      frameBudget: _budget,
      screen: screens[i % screens.length].name,
      interactionId: i % 7 == 0 ? 'int_${i ~/ 70}' : null,
    );
    final severity = classifier.classify(sample).severity;
    calculator.addFrame(sample, severity);
    screens[i % screens.length].addFrame(sample, severity);
    if (i % 7 == 0) {
      interactions[0].noteSpan('int_${i ~/ 70}');
      interactions[0].addFrame(sample, severity);
    }

    // Promote a deterministic slice of slow frames into frame anomalies.
    if (severity == FrameSeverity.slow && anomalyCursor < _anomalyCount) {
      final classification = classifier.classify(sample);
      final bottleneck =
          FrameBottleneck.values[anomalyCursor % 4]; // unknown/ui/raster/mixed
      final rebuilt = FrameClassification(FrameSeverity.slow, bottleneck);
      anomalies.add(createFrameAnomaly(
        id: 'anm_${anomalyCursor + 1}',
        timestamp: sample.capturedAt,
        sample: sample,
        classification: rebuilt == classification ? classification : rebuilt,
      ));
      screens[i % screens.length].addAnomaly(anomalies.last);
      if (i % 7 == 0) interactions[0].addAnomaly(anomalies.last);
      anomalyCursor++;
    }
  }

  for (var t = 0; t < _traceCount; t++) {
    final trace = CompletedTrace(
      id: 'trc_${t + 1}',
      name: 'load_catalog_$t',
      startedAt: DateTime.fromMicrosecondsSinceEpoch(1700000000000000 + t),
      duration: Duration(milliseconds: 40 + t * 15),
      screen: screens[t % screens.length].name,
      didThrow: t == 4,
      metadata: {'index': t},
    );
    traceList.add(trace);
    interactions[1]
      ..noteSpan(trace.id)
      ..addSpanDuration(trace.duration);
  }
  // Give the second interaction some frame attribution too.
  for (var i = 0; i < _frameCount ~/ 2; i += 9) {
    final sample = FrameSample(
      id: 100000 + i,
      frameNumber: 100000 + i,
      capturedAt:
          DateTime.fromMicrosecondsSinceEpoch(1700000001000000 + i * 16667),
      buildDuration: const Duration(microseconds: 9000),
      rasterDuration: const Duration(microseconds: 5000),
      totalDuration: const Duration(microseconds: 14300),
      vsyncOverhead: const Duration(microseconds: 300),
      frameBudget: _budget,
      screen: 'Checkout',
      interactionId: 'trc_1',
    );
    const severity = FrameSeverity.normal;
    interactions[1].addFrame(sample, severity);
  }
  interactions[1].addAnomaly(anomalies.first);

  final session = PerformanceSession(
    id: 'ses_bench',
    name: 'benchmark-session',
    startedAt: DateTime.fromMicrosecondsSinceEpoch(1700000000000000),
    environment: buildPerformanceEnvironment(
      frameBudget: FixedFrameBudget.fallbackBudget,
      source: FrameBudgetSource.fallback,
    ),
    metadata: {'build': 'bench', 'variant': 'mid'},
    calculator: StatisticsCalculator(),
    anomalies: <PerformanceAnomaly>[],
  )
    // Mark the session finished so the serialized document carries an
    // ended_at timestamp and a duration, like any stopped session.
    ..endedAt = DateTime.fromMicrosecondsSinceEpoch(1700000060000000);
  final report = buildPerformanceReport(
    session: session,
    statistics: calculator.snapshot(),
    screenAccumulators: screens,
    interactionAccumulators: interactions,
    traces: traceList,
    anomalies: anomalies,
  );
  // Mirror the SessionManager.stop() contract so the serializer takes the
  // attached-report path.
  session.attachReport(report);

  const serializer = SessionSerializer();
  final jsonOnce = serializer.serializeToString(report);
  print('serialization_benchmark');
  print('  report: $_frameCount frames, ${screens.length} screens, '
      '${interactions.length} interactions, $_anomalyCount frame anomalies, '
      '$_traceCount traces');
  print('  serialized size: ${utf8.encode(jsonOnce).length} bytes');

  var sink = 0;
  void runBatch() {
    for (var op = 0; op < _opsPerBatch; op++) {
      final out = serializer.serializeToString(report);
      sink += out.length;
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
  print('  serializeToString median: ${(medianNs / 1e6).toStringAsFixed(3)} '
      'ms/op (${(1e9 / medianNs).toStringAsFixed(1)} ops/sec)');
  if (sink == -1) print('  (unreachable sink: $sink)');
}
