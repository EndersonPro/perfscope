import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

void main() {
  group('FixedFrameBudget.fromFps', () {
    test('60Hz yields 16667 microseconds', () {
      expect(
        FixedFrameBudget.fromFps(60).currentBudget,
        const Duration(microseconds: 16667),
      );
    });

    test('90Hz yields 11111 microseconds', () {
      expect(
        FixedFrameBudget.fromFps(90).currentBudget,
        const Duration(microseconds: 11111),
      );
    });

    test('120Hz yields 8333 microseconds', () {
      expect(
        FixedFrameBudget.fromFps(120).currentBudget,
        const Duration(microseconds: 8333),
      );
    });

    test('144Hz yields 6944 microseconds', () {
      expect(
        FixedFrameBudget.fromFps(144).currentBudget,
        const Duration(microseconds: 6944),
      );
    });

    test('fractional fps works', () {
      expect(
        FixedFrameBudget.fromFps(59.94).currentBudget,
        Duration(microseconds: (1000000 / 59.94).round()),
      );
      expect(
          FixedFrameBudget.fromFps(59.94).currentBudget.inMicroseconds, 16683);
    });

    test('source is configured', () {
      expect(
        FixedFrameBudget.fromFps(60).source,
        FrameBudgetSource.configured,
      );
    });
  });

  group('fallback budget', () {
    test('equals the 60Hz interval', () {
      expect(
          FixedFrameBudget.fallbackBudget, const Duration(microseconds: 16667));
    });
  });
}
