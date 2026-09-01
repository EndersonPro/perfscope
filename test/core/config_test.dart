import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

void main() {
  group('PerfScopeConfig defaults', () {
    test('match documented values', () {
      const config = PerfScopeConfig();
      expect(config.enabled, isTrue);
      expect(config.targetFrameRate, 60);
      expect(config.frameBufferSize, 500);
      expect(config.contextFramesBefore, 5);
      expect(config.contextFramesAfter, 5);
      expect(config.logStyle, PerfScopeLogStyle.pretty);
      expect(config.printNormalFrames, isFalse);
      expect(config.printWarnings, isFalse);
      expect(config.printAnomalies, isTrue);
      expect(config.autoStartSession, isTrue);
      expect(config.verbose, isFalse);
      expect(config.longTraceThreshold, const Duration(milliseconds: 50));
      expect(config.maxStatisticSamples, 10000);
      expect(config.thresholds, PerformanceThresholds.defaults);
    });

    test('thresholds defaults are 1.0 / 1.5 / 3.0', () {
      const t = PerformanceThresholds.defaults;
      expect(t.warningMultiplier, 1.0);
      expect(t.slowMultiplier, 1.5);
      expect(t.severeMultiplier, 3.0);
    });
  });

  group('PerfScopeConfig copyWith', () {
    test('changes only targeted fields', () {
      const base = PerfScopeConfig();
      final modified = base.copyWith(
        enabled: false,
        targetFrameRate: 120,
        frameBufferSize: 64,
        contextFramesBefore: 2,
        contextFramesAfter: 3,
        logStyle: PerfScopeLogStyle.json,
        printNormalFrames: true,
        printWarnings: true,
        printAnomalies: false,
        autoStartSession: false,
        verbose: true,
        longTraceThreshold: const Duration(milliseconds: 10),
        maxStatisticSamples: 500,
        thresholds: const PerformanceThresholds(
          warningMultiplier: 1.1,
          slowMultiplier: 1.6,
          severeMultiplier: 2.5,
        ),
      );

      expect(modified.enabled, isFalse);
      expect(modified.targetFrameRate, 120);
      expect(modified.frameBufferSize, 64);
      expect(modified.contextFramesBefore, 2);
      expect(modified.contextFramesAfter, 3);
      expect(modified.logStyle, PerfScopeLogStyle.json);
      expect(modified.printNormalFrames, isTrue);
      expect(modified.printWarnings, isTrue);
      expect(modified.printAnomalies, isFalse);
      expect(modified.autoStartSession, isFalse);
      expect(modified.verbose, isTrue);
      expect(modified.longTraceThreshold, const Duration(milliseconds: 10));
      expect(modified.maxStatisticSamples, 500);
      expect(
        modified.thresholds,
        const PerformanceThresholds(
          warningMultiplier: 1.1,
          slowMultiplier: 1.6,
          severeMultiplier: 2.5,
        ),
      );
    });

    test('empty copyWith returns an equal config', () {
      const base = PerfScopeConfig();
      expect(base.copyWith(), equals(base));
    });
  });

  group('PerfScopeConfig equality', () {
    test('const instances with same args are equal', () {
      const a = PerfScopeConfig();
      const b = PerfScopeConfig();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different configs are not equal', () {
      const a = PerfScopeConfig();
      final b = a.copyWith(verbose: true);
      expect(a, isNot(equals(b)));
    });
  });

  group('PerfScopeConfig validation', () {
    test('targetFrameRate of 0 throws AssertionError', () {
      expect(
        () => PerfScopeConfig(targetFrameRate: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('targetFrameRate above 1000 throws AssertionError', () {
      expect(
        () => PerfScopeConfig(targetFrameRate: 1001),
        throwsA(isA<AssertionError>()),
      );
    });

    test('frameBufferSize of 0 throws AssertionError', () {
      expect(
        () => PerfScopeConfig(frameBufferSize: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('negative contextFramesBefore throws AssertionError', () {
      expect(
        () => PerfScopeConfig(contextFramesBefore: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('negative contextFramesAfter throws AssertionError', () {
      expect(
        () => PerfScopeConfig(contextFramesAfter: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('maxStatisticSamples below 100 throws AssertionError', () {
      expect(
        () => PerfScopeConfig(maxStatisticSamples: 50),
        throwsA(isA<AssertionError>()),
      );
    });

    test('slow <= warning multiplier ordering violation throws', () {
      expect(
        // Not const: the assertion must fire at runtime to be observable.
        () => PerformanceThresholds(slowMultiplier: 1.0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => PerformanceThresholds(
          warningMultiplier: 1.5,
          slowMultiplier: 1.5,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('severe <= slow ordering violation throws', () {
      expect(
        () => PerformanceThresholds(severeMultiplier: 1.5),
        throwsA(isA<AssertionError>()),
      );
    });

    test('non-positive warningMultiplier throws', () {
      expect(
        () => PerformanceThresholds(warningMultiplier: 0.0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('PerformanceThresholds equality', () {
    test('same values are equal with matching hashCode', () {
      const a = PerformanceThresholds();
      const b = PerformanceThresholds.defaults;
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different values are not equal', () {
      expect(
        const PerformanceThresholds(warningMultiplier: 0.5),
        isNot(equals(const PerformanceThresholds())),
      );
    });
  });
}
