import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

/// Deterministic fixed timestamp — no real clock involved.
final _capturedAt = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

const _budget60 = Duration(microseconds: 16667);

FrameSample _sample({
  int id = 1,
  Duration build = Duration.zero,
  Duration raster = Duration.zero,
  Duration? total,
  Duration frameBudget = _budget60,
}) {
  return FrameSample(
    id: id,
    frameNumber: id,
    capturedAt: _capturedAt,
    buildDuration: build,
    rasterDuration: raster,
    totalDuration: total ?? build + raster,
    vsyncOverhead: Duration.zero,
    frameBudget: frameBudget,
    screen: null,
    interactionId: null,
  );
}

void main() {
  group('severity boundaries (60fps budget = 16667us)', () {
    // Thresholds from strictly-greater comparisons:
    // warning > 16667.0, slow > 25000.5, severe > 50001.0.
    final classifier = const FrameClassifier();

    test('total exactly at budget stays normal', () {
      final c = classifier.classify(_sample(total: _micro(16667)));
      expect(c.severity, FrameSeverity.normal);
      expect(c.bottleneck, FrameBottleneck.unknown);
    });

    test('one microsecond over budget becomes warning', () {
      expect(
        classifier.classify(_sample(total: _micro(16668))).severity,
        FrameSeverity.warning,
      );
    });

    test('25000us is warning, 25001us is slow', () {
      expect(
        classifier.classify(_sample(total: _micro(25000))).severity,
        FrameSeverity.warning,
      );
      expect(
        classifier.classify(_sample(total: _micro(25001))).severity,
        FrameSeverity.slow,
      );
    });

    test('50000us and 50001us are slow; 50002us is severe', () {
      // 3.0 x 16667 == 50001 exactly, so at-threshold (50001) counts as
      // lower tier per the strictly-greater rule.
      expect(
        classifier.classify(_sample(total: _micro(50000))).severity,
        FrameSeverity.slow,
      );
      expect(
        classifier.classify(_sample(total: _micro(50001))).severity,
        FrameSeverity.slow,
      );
      expect(
        classifier.classify(_sample(total: _micro(50002))).severity,
        FrameSeverity.severe,
      );
    });

    test('same duration flips severity across budgets', () {
      final total = _micro(20000);
      // 60fps budget 16667us: slow threshold 25000.5 -> warning.
      expect(
        classifier.classify(_sample(total: total)).severity,
        FrameSeverity.warning,
      );
      // 90fps budget 11111us: slow threshold 16666.5 -> slow.
      expect(
        classifier
            .classify(_sample(total: total, frameBudget: _micro(11111)))
            .severity,
        FrameSeverity.slow,
      );
      // Custom tight budget 5000us: severe threshold 15000 -> severe.
      expect(
        classifier
            .classify(_sample(total: total, frameBudget: _micro(5000)))
            .severity,
        FrameSeverity.severe,
      );
    });

    test('relaxed thresholds upgrade classification', () {
      final relaxed = const FrameClassifier(
        thresholds: PerformanceThresholds(
          warningMultiplier: 0.9,
          slowMultiplier: 0.95,
          severeMultiplier: 0.98,
        ),
      );
      // 16000us against 16667us: within budget under defaults,
      // but above 0.95x (15833.65) under relaxed thresholds -> slow.
      final sample = _sample(total: _micro(16000));
      expect(classifier.classify(sample).severity, FrameSeverity.normal);
      expect(relaxed.classify(sample).severity, FrameSeverity.slow);
    });
  });

  group('bottleneck heuristic', () {
    final classifier = const FrameClassifier();

    test('build-dominant frame reports ui', () {
      final sample = _sample(build: _ms(28), raster: _ms(4));
      final classification = classifier.classify(sample);

      expect(classification.severity, FrameSeverity.slow);
      expect(classification.bottleneck, FrameBottleneck.ui);
    });

    test('raster-dominant frame reports raster', () {
      final sample = _sample(build: _ms(4), raster: _ms(28));
      final classification = classifier.classify(sample);

      expect(classification.severity, FrameSeverity.slow);
      expect(classification.bottleneck, FrameBottleneck.raster);
    });

    test('comparable split reports mixed (severe tier)', () {
      final sample = _sample(build: _ms(28), raster: _ms(24));
      final classification = classifier.classify(sample);

      // 52ms total exceeds the severe threshold (50.001ms).
      expect(classification.severity, FrameSeverity.severe);
      expect(classification.bottleneck, FrameBottleneck.mixed);
    });

    test('severe frame with equal-ish split reports mixed', () {
      final sample = _sample(build: _ms(26), raster: _ms(26));
      final classification = classifier.classify(sample);

      expect(classification.severity, FrameSeverity.severe);
      expect(classification.bottleneck, FrameBottleneck.mixed);
    });

    test('zero raster with positive build reports ui', () {
      final sample = _sample(build: _ms(28), raster: Duration.zero);
      final classification = classifier.classify(sample);

      expect(classification.severity, FrameSeverity.slow);
      expect(classification.bottleneck, FrameBottleneck.ui);
    });

    test('zero build with positive raster reports raster', () {
      final sample = _sample(build: Duration.zero, raster: _ms(28));
      final classification = classifier.classify(sample);

      expect(classification.severity, FrameSeverity.slow);
      expect(classification.bottleneck, FrameBottleneck.raster);
    });

    test('normal frame always reports unknown bottleneck', () {
      final sample = _sample(build: _ms(10), raster: _ms(5));
      final classification = classifier.classify(sample);

      expect(classification.severity, FrameSeverity.normal);
      expect(classification.bottleneck, FrameBottleneck.unknown);
    });
  });

  group('classification equality', () {
    test('equal severities and bottlenecks compare equal', () {
      expect(
        const FrameClassification(FrameSeverity.slow, FrameBottleneck.ui),
        equals(
            const FrameClassification(FrameSeverity.slow, FrameBottleneck.ui)),
      );
      expect(
        const FrameClassification(FrameSeverity.slow, FrameBottleneck.ui)
            .hashCode,
        const FrameClassification(FrameSeverity.slow, FrameBottleneck.ui)
            .hashCode,
      );
    });
  });
}

Duration _micro(int us) => Duration(microseconds: us);
Duration _ms(int ms) => Duration(milliseconds: ms);
