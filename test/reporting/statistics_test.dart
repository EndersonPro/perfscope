import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

/// Deterministic fixed timestamp — no real clock involved.
final _capturedAt = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

FrameSample _sample({
  required Duration build,
  required Duration raster,
  required Duration total,
}) {
  return FrameSample(
    id: total.inMicroseconds,
    frameNumber: null,
    capturedAt: _capturedAt,
    buildDuration: build,
    rasterDuration: raster,
    totalDuration: total,
    vsyncOverhead: Duration.zero,
    frameBudget: const Duration(microseconds: 16667),
    screen: null,
    interactionId: null,
  );
}

void main() {
  group('nearestRankPercentileMicros', () {
    test('p50 of 4 samples picks the 2nd smallest (ceil(0.5*4)=2)', () {
      // rank = ceil(50/100*4) = ceil(2.0) = 2 → index 1.
      expect(nearestRankPercentileMicros([10, 20, 30, 40], 50), 20);
    });

    test('p50 of 5 samples picks the middle (ceil(0.5*5)=ceil(2.5)=3)', () {
      // rank = 3 → index 2.
      expect(nearestRankPercentileMicros([10, 20, 30, 40, 50], 50), 30);
    });

    test('p95 rounds up inside the list (ceil(0.95*4)=ceil(3.8)=4)', () {
      expect(nearestRankPercentileMicros([10, 20, 30, 40], 95), 40);
    });

    test('p100 clamps to the maximum and p0 clamps to the minimum', () {
      expect(nearestRankPercentileMicros([10, 20, 30, 40], 100), 40);
      expect(nearestRankPercentileMicros([10, 20, 30, 40], 0), 10);
    });

    test('empty input yields 0', () {
      expect(nearestRankPercentileMicros([], 50), 0);
    });
  });

  group('microsToMsRounded', () {
    test('integer microseconds convert exactly to 3-decimal ms', () {
      expect(microsToMsRounded(16667), 16.667);
      expect(microsToMsRounded(1000), 1.0);
      expect(microsToMsRounded(1), 0.001);
      expect(microsToMsRounded(1234567), 1234.567);
      expect(microsToMsRounded(0), 0.0);
    });
  });

  group('StatisticsCalculator', () {
    test('empty snapshot is all zeros with a 0 slow-frame rate', () {
      expect(StatisticsCalculator().snapshot(), SessionStatistics.zero);
    });

    test('single element: every percentile equals it', () {
      final calc = StatisticsCalculator();
      calc.addFrame(
        _sample(
            build: const Duration(milliseconds: 10),
            raster: Duration.zero,
            total: const Duration(milliseconds: 25)),
        FrameSeverity.normal,
      );
      final stats = calc.snapshot();
      expect(stats.totalFrames, 1);
      expect(stats.normalFrames, 1);
      expect(stats.slowFrameRate, 0);
      expect(stats.averageBuildMs, 10.0);
      expect(stats.averageRasterMs, 0.0);
      expect(stats.averageTotalMs, 25.0);
      expect(stats.p50Ms, 25.0);
      expect(stats.p90Ms, 25.0);
      expect(stats.p95Ms, 25.0);
      expect(stats.p99Ms, 25.0);
      expect(stats.worstFrameMs, 25.0);
    });

    test('out-of-order additions are sorted internally before ranking', () {
      final calc = StatisticsCalculator();
      void add(int totalMs) => calc.addFrame(
            _sample(
              build: Duration.zero,
              raster: Duration.zero,
              total: Duration(milliseconds: totalMs),
            ),
            FrameSeverity.normal,
          );
      add(30);
      add(10);
      add(20);
      // Sorted window [10, 20, 30]: rank = ceil(0.5*3) = ceil(1.5) = 2.
      expect(calc.snapshot().p50Ms, 20.0);
    });

    test('rolling eviction changes percentiles (capacity 4, push 1..5)', () {
      final calc = StatisticsCalculator(windowCapacity: 4);
      for (var ms = 1; ms <= 5; ms++) {
        calc.addFrame(
          _sample(
            build: Duration.zero,
            raster: Duration.zero,
            total: Duration(milliseconds: ms),
          ),
          FrameSeverity.normal,
        );
      }
      // Window evicted the 1ms sample: [2, 3, 4, 5].
      // p50: rank = ceil(0.5*4) = 2 → index 1 → 3ms (lower-middle).
      expect(calc.snapshot().p50Ms, 3.0);
      // p95: rank = ceil(0.95*4) = ceil(3.8) = 4 → index 3 → 5ms.
      expect(calc.snapshot().p95Ms, 5.0);
      // Worst is tracked exactly across evictions.
      expect(calc.snapshot().worstFrameMs, 5.0);
    });

    test('averages, worst, and rates are exact across severities', () {
      final calc = StatisticsCalculator();
      void add(Duration build, Duration raster, Duration total,
          FrameSeverity severity) {
        calc.addFrame(
            _sample(build: build, raster: raster, total: total), severity);
      }

      add(const Duration(milliseconds: 3), const Duration(milliseconds: 5),
          const Duration(milliseconds: 8), FrameSeverity.normal);
      add(Duration.zero, Duration.zero, const Duration(milliseconds: 20),
          FrameSeverity.warning);
      add(const Duration(milliseconds: 30), Duration.zero,
          const Duration(milliseconds: 30), FrameSeverity.slow);
      add(const Duration(milliseconds: 10), const Duration(milliseconds: 40),
          const Duration(milliseconds: 60), FrameSeverity.severe);

      final stats = calc.snapshot();
      // Sums: build 3+0+30+10=43; raster 5+0+0+40=45; total 8+20+30+60=118.
      expect(stats.totalFrames, 4);
      expect(stats.normalFrames, 1);
      expect(stats.warningFrames, 1);
      expect(stats.slowFrames, 1);
      expect(stats.severeFrames, 1);
      expect(stats.slowFrameRate, 0.5);
      expect(stats.averageBuildMs, 10.75);
      expect(stats.averageRasterMs, 11.25);
      expect(stats.averageTotalMs, 29.5);
      // Sorted totals [8, 20, 30, 60]: p50 rank=ceil(2)=2 → 20;
      // p90/p95/p99 ranks ceil(3.6)/ceil(3.8)/ceil(3.96) all = 4 → 60.
      expect(stats.p50Ms, 20.0);
      expect(stats.p90Ms, 60.0);
      expect(stats.p95Ms, 60.0);
      expect(stats.p99Ms, 60.0);
      expect(stats.worstFrameMs, 60.0);
    });

    test('averages round half away from zero to 3 decimals', () {
      final calc = StatisticsCalculator();
      void addUs(int us) => calc.addFrame(
            _sample(
                build: Duration.zero,
                raster: Duration.zero,
                total: Duration(microseconds: us)),
            FrameSeverity.normal,
          );
      addUs(1111);
      addUs(1112);
      // Mean = 1111.5 µs = 1.1115 ms → rounds to 1.112 ms.
      expect(calc.snapshot().averageTotalMs, 1.112);
    });

    test('reset restores the zero state including the window', () {
      final calc = StatisticsCalculator();
      calc.addFrame(
        _sample(
            build: const Duration(milliseconds: 5),
            raster: Duration.zero,
            total: const Duration(milliseconds: 40)),
        FrameSeverity.severe,
      );
      calc.reset();
      expect(calc.snapshot(), SessionStatistics.zero);
    });
  });

  group('SessionStatistics value semantics', () {
    // Runtime-built fixture: calling it twice yields two DISTINCT
    // instances with identical field values. Two `const` literals would be
    // canonicalized into one instance by Dart, making an identity check
    // meaningless — hence the runtime-computed p95 argument.
    SessionStatistics statsFixture() {
      final p95Ms = 2.0 + 2.0;
      return SessionStatistics(
        totalFrames: 2,
        normalFrames: 1,
        warningFrames: 0,
        slowFrames: 1,
        severeFrames: 0,
        slowFrameRate: 0.5,
        averageBuildMs: 1.5,
        averageRasterMs: 2.5,
        averageTotalMs: 4.0,
        p50Ms: 3.0,
        p90Ms: 4.0,
        p95Ms: p95Ms,
        p99Ms: 4.0,
        worstFrameMs: 5.0,
      );
    }

    test('equal instances compare equal and hash identically', () {
      final a = statsFixture();
      final b = statsFixture();

      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('a differing field breaks equality', () {
      final base = statsFixture();
      final changed = SessionStatistics(
        totalFrames: 2,
        normalFrames: 1,
        warningFrames: 0,
        slowFrames: 1,
        severeFrames: 0,
        slowFrameRate: 0.5,
        averageBuildMs: 1.5,
        averageRasterMs: 2.5,
        averageTotalMs: 4.0,
        p50Ms: 3.0,
        p90Ms: 4.0,
        p95Ms: 99.0, // differs
        p99Ms: 4.0,
        worstFrameMs: 5.0,
      );
      expect(base == changed, isFalse);
    });
  });
}
