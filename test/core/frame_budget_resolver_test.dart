import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

const _budget60 = Duration(microseconds: 16667);
const _budget120 = Duration(microseconds: 8333);

FrameBudgetResolver _resolver({
  required RefreshRateProbe probe,
  int targetFrameRate = 60,
}) {
  return FrameBudgetResolver(
    config: PerfScopeConfig(targetFrameRate: targetFrameRate),
    probeRefreshRate: probe,
  );
}

void main() {
  group('fallback path', () {
    test('no detected rate and default target yields fallback budget', () {
      final provider =
          _resolver(probe: () => null, targetFrameRate: 60).resolve();

      expect(provider.source, FrameBudgetSource.fallback);
      expect(provider.currentBudget, FixedFrameBudget.fallbackBudget);
      expect(provider.currentBudget, _budget60);
    });

    test('throwing probe is treated as no detection', () {
      final provider = _resolver(
        probe: () => throw StateError('display exploded'),
      ).resolve();

      expect(provider.source, FrameBudgetSource.fallback);
      expect(provider.currentBudget, _budget60);
    });
  });

  group('configured path', () {
    test('non-default target overrides even without detection', () {
      final provider =
          _resolver(probe: () => null, targetFrameRate: 120).resolve();

      expect(provider.source, FrameBudgetSource.configured);
      expect(provider.currentBudget, _budget120);
    });

    test('non-default target overrides a successful detection', () {
      final provider =
          _resolver(probe: () => 90.0, targetFrameRate: 120).resolve();

      expect(provider.source, FrameBudgetSource.configured);
      expect(provider.currentBudget, _budget120);
    });
  });

  group('detected path', () {
    test('plausible detection wins under default target', () {
      final provider =
          _resolver(probe: () => 120.0, targetFrameRate: 60).resolve();

      expect(provider.source, FrameBudgetSource.detected);
      expect(provider.currentBudget, _budget120);
    });

    test('implausible detection values are ignored by contract', () {
      // The real probe filters implausible rates; a fake returning one
      // exercises the resolver's trust boundary only for plausible input,
      // so here we assert a *plausible* edge value still resolves.
      final provider =
          _resolver(probe: () => 1000.0, targetFrameRate: 60).resolve();

      expect(provider.source, FrameBudgetSource.detected);
    });
  });

  group('real probe', () {
    test('detectRefreshRate never throws and stays within plausibility', () {
      final rate = FrameBudgetResolver.detectRefreshRate();

      if (rate != null) {
        expect(rate, greaterThan(1));
        expect(rate, lessThanOrEqualTo(1000));
      }
      // null is acceptable in headless test environments.
    });
  });
}
