import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/src/core/ids.dart';

import '../helpers/fake_clock.dart';

/// Deterministic fixed timestamp — no real clock involved.
final _capturedAt = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

const _budget60 = Duration(microseconds: 16667);

FrameSample _sample({
  int id = 1,
  Duration build = Duration.zero,
  Duration raster = Duration.zero,
  Duration? total,
  String? screen,
  String? interactionId,
}) {
  return FrameSample(
    id: id,
    frameNumber: id,
    capturedAt: _capturedAt,
    buildDuration: build,
    rasterDuration: raster,
    totalDuration: total ?? build + raster,
    vsyncOverhead: Duration.zero,
    frameBudget: _budget60,
    screen: screen,
    interactionId: interactionId,
  );
}

/// Shared fixture: one generator, one manual clock.
(AnomalyDetector, FakeClock) _detector() {
  final clock = FakeClock();
  return (
    AnomalyDetector(anomalyIds: IdGenerator('anm'), clock: clock),
    clock,
  );
}

void main() {
  group('AnomalyDetector', () {
    test('normal frames produce no anomaly', () {
      final (detector, _) = _detector();
      final sample =
          _sample(build: const Duration(milliseconds: 3), raster: _ms(5));

      expect(detector.detect(sample, const FrameClassifier().classify(sample)),
          isNull);
    });

    test('warning-tier frames produce no anomaly', () {
      final (detector, _) = _detector();
      // 20ms over a 16667us budget: above warning, below slow (25000.5us).
      final sample = _sample(total: _ms(20));

      expect(detector.detect(sample, const FrameClassifier().classify(sample)),
          isNull);
    });

    test('slow frame with unknown bottleneck yields SlowFrameAnomaly', () {
      final (detector, _) = _detector();
      // No phase durations but a long total: slow tier, unknown blame.
      final sample = _sample(total: _ms(30));
      final classification = const FrameClassifier().classify(sample);

      final anomaly =
          detector.detect(sample, classification) as SlowFrameAnomaly;

      expect(anomaly.bottleneck, FrameBottleneck.unknown);
      expect(anomaly.severity, AnomalySeverity.high);
    });

    test('ui/raster/mixed bottlenecks pick the matching subclass', () {
      final (detector, _) = _detector();

      final uiSample = _sample(build: _ms(28), raster: _ms(4), total: _ms(32));
      expect(
        detector.detect(uiSample, const FrameClassifier().classify(uiSample)),
        isA<UiBoundFrameAnomaly>(),
      );

      final rasterSample =
          _sample(build: _ms(4), raster: _ms(28), total: _ms(32));
      expect(
        detector.detect(
            rasterSample, const FrameClassifier().classify(rasterSample)),
        isA<RasterBoundFrameAnomaly>(),
      );

      final mixedSample =
          _sample(build: _ms(14), raster: _ms(12), total: _ms(26));
      expect(
        detector.detect(
            mixedSample, const FrameClassifier().classify(mixedSample)),
        isA<MixedFrameAnomaly>(),
      );
    });

    test('severe frame maps to critical, slow stays high', () {
      final (detector, _) = _detector();
      final severe = _sample(build: _ms(26), raster: _ms(26), total: _ms(52));
      expect(
        detector
            .detect(severe, const FrameClassifier().classify(severe))!
            .severity,
        AnomalySeverity.critical,
      );

      final slow = _sample(total: _ms(30));
      expect(
        detector.detect(slow, const FrameClassifier().classify(slow))!.severity,
        AnomalySeverity.high,
      );
    });

    test('screen and interactionId come off the enriched sample', () {
      final (detector, _) = _detector();
      final sample = _sample(
        total: _ms(30),
        screen: 'checkout',
        interactionId: 'int_9',
      );

      final anomaly =
          detector.detect(sample, const FrameClassifier().classify(sample))!;

      expect(anomaly.screen, 'checkout');
      expect(anomaly.interactionId, 'int_9');
    });

    test('ids are sequential through the injected generator', () {
      final (detector, _) = _detector();
      final sample = _sample(total: _ms(30));

      final first = detector.detect(sample, _classificationSlow)!;
      final second = detector.detect(sample, _classificationSlow)!;

      expect(first.id, 'anm_1');
      expect(second.id, 'anm_2');
    });

    test('timestamps follow the injected clock', () {
      final (detector, clock) = _detector();
      final sample = _sample(total: _ms(30));

      final first = detector.detect(sample, _classificationSlow)!;
      clock.advance(const Duration(milliseconds: 5));
      final second = detector.detect(sample, _classificationSlow)!;

      expect(second.timestamp.difference(first.timestamp),
          const Duration(milliseconds: 5));
    });

    test('metadata defaults to an empty map', () {
      final (detector, _) = _detector();
      final sample = _sample(total: _ms(30));

      final anomaly =
          detector.detect(sample, _classificationSlow) as FrameAnomaly;

      expect(anomaly.metadata, isEmpty);
      expect(anomaly.sample.id, sample.id);
      expect(anomaly.classification.bottleneck, FrameBottleneck.unknown);
      expect(anomaly.frameBudget, _budget60);
    });
  });
}

const FrameClassification _classificationSlow =
    FrameClassification(FrameSeverity.slow, FrameBottleneck.unknown);

Duration _ms(int ms) => Duration(milliseconds: ms);
