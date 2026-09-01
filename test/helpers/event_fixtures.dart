import 'package:perfscope/perfscope.dart';

/// Shared deterministic fixtures for logging/renderer/sink tests.
///
/// All timestamps are pinned so snapshots stay byte-stable across runs.

/// 60Hz frame budget: 16.667 ms.
const Duration budget60 = Duration(microseconds: 16667);

/// Pinned capture instant used by every fixture.
final DateTime fixedTime = DateTime.fromMicrosecondsSinceEpoch(
  1700000000000000,
);

/// Builds a frame sample with the given phase durations.
///
/// Defaults reproduce the canonical pretty-card example:
/// build 27.400 ms / raster 4.800 ms / total 33.100 ms on a 16.667 ms
/// budget, attributed to `ProductList` during `product_list_scroll`.
FrameSample frameSample({
  int id = 1,
  Duration build = const Duration(microseconds: 27400),
  Duration raster = const Duration(microseconds: 4800),
  Duration total = const Duration(microseconds: 33100),
  Duration budget = budget60,
  String? screen = 'ProductList',
  String? interactionId = 'product_list_scroll',
}) {
  return FrameSample(
    id: id,
    frameNumber: id,
    capturedAt: fixedTime,
    buildDuration: build,
    rasterDuration: raster,
    totalDuration: total,
    vsyncOverhead: Duration.zero,
    frameBudget: budget,
    screen: screen,
    interactionId: interactionId,
  );
}

/// UI-bound slow frame anomaly matching the canonical pretty-card example.
UiBoundFrameAnomaly uiBoundAnomaly({
  String id = 'anm_1',
  AnomalySeverity severity = AnomalySeverity.high,
  FrameSample? sample,
}) {
  final effectiveSample = sample ?? frameSample();
  return UiBoundFrameAnomaly(
    id: id,
    timestamp: fixedTime,
    severity: severity,
    sample: effectiveSample,
    classification: const FrameClassification(
      FrameSeverity.slow,
      FrameBottleneck.ui,
    ),
    frameBudget: effectiveSample.frameBudget,
    screen: effectiveSample.screen,
    interactionId: effectiveSample.interactionId,
  );
}

/// Long-trace anomaly for the compact/pretty trace variants.
LongTraceAnomaly longTraceAnomaly({
  String id = 'anm_2',
  String name = 'calculate_prices',
  Duration duration = const Duration(milliseconds: 127),
  AnomalySeverity severity = AnomalySeverity.high,
  String? screen = 'Checkout',
  String? interactionId,
}) {
  return LongTraceAnomaly(
    id: id,
    timestamp: fixedTime,
    severity: severity,
    traceId: 'trc_1',
    name: name,
    duration: duration,
    screen: screen,
    interactionId: interactionId,
  );
}

/// Wraps [event] in an anomaly event with a pinned id/timestamp.
AnomalyEvent anomalyEvent(PerformanceAnomaly anomaly, {String id = 'evt_1'}) {
  return AnomalyEvent(id: id, timestamp: fixedTime, anomaly: anomaly);
}

/// Wraps [sample] in a frame event with a pinned id/timestamp.
FrameEvent frameEvent(FrameSample sample, {String id = 'evt_f1'}) {
  return FrameEvent(id: id, timestamp: fixedTime, sample: sample);
}
