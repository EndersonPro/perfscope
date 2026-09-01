import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

// -----------------------------------------------------------------------------
// Hand-built fixtures: models constructed directly, no engine involved.
// -----------------------------------------------------------------------------

final DateTime _start = DateTime.utc(2026, 2, 1, 9, 0, 0);

SessionStatistics _stats({
  int totalFrames = 1000,
  double slowFrameRate = 0.10,
  double p95Ms = 20.0,
  double p99Ms = 40.0,
  double worstFrameMs = 80.0,
  double averageBuildMs = 7.455,
  double averageRasterMs = 8.909,
}) {
  return SessionStatistics(
    totalFrames: totalFrames,
    normalFrames: totalFrames - 100,
    warningFrames: 0,
    slowFrames: 80,
    severeFrames: 20,
    slowFrameRate: slowFrameRate,
    averageBuildMs: averageBuildMs,
    averageRasterMs: averageRasterMs,
    averageTotalMs: averageBuildMs + averageRasterMs,
    p50Ms: 8.0,
    p90Ms: 16.0,
    p95Ms: p95Ms,
    p99Ms: p99Ms,
    worstFrameMs: worstFrameMs,
  );
}

PerformanceSession _session(String name) {
  final session = PerformanceSession(
    id: 'ses_$name',
    name: name,
    startedAt: _start,
    environment: const PerformanceEnvironment(
      frameBudgetFps: 60.0,
      frameBudgetMs: 16.667,
      frameBudgetSource: FrameBudgetSource.detected,
      platform: 'test',
    ),
    calculator: StatisticsCalculator(),
    anomalies: const [],
  );
  session.endedAt = _start.add(const Duration(minutes: 2));
  return session;
}

ScreenPerformanceSummary _screen(
  String name, {
  double rate = 0.05,
  double p95 = 20.0,
  double worst = 40.0,
}) {
  return ScreenPerformanceSummary(
    name: name,
    totalFrames: 500,
    slowFrames: 20,
    severeFrames: 5,
    anomalyCount: 4,
    slowFrameRate: rate,
    p95Ms: p95,
    worstMs: worst,
    probableBottleneck: FrameBottleneck.ui,
  );
}

InteractionPerformanceSummary _interaction(
  String name, {
  double p95 = 15.0,
  double worst = 30.0,
}) {
  return InteractionPerformanceSummary(
    name: name,
    mostRecentInteractionId: 'itx_1',
    spanCount: 2,
    frameCount: 100,
    anomalyCount: 1,
    totalSpanDuration: const Duration(milliseconds: 80),
    p95Ms: p95,
    worstMs: worst,
    probableBottleneck: FrameBottleneck.raster,
  );
}

PerformanceReport _report({
  required String name,
  required SessionStatistics statistics,
  List<ScreenPerformanceSummary> screens = const [],
  List<InteractionPerformanceSummary> interactions = const [],
}) {
  return PerformanceReport(
    session: _session(name),
    statistics: statistics,
    screens: screens,
    interactions: interactions,
    traces: const [],
    anomalies: const [],
    worstAnomalies: const [],
  );
}

MetricComparison _metric(SessionComparison comparison, String label) =>
    comparison.overall.firstWhere((m) => m.label == label);

void main() {
  group('overall metrics', () {
    test('complete ordered set of six labels with units', () {
      final before = _report(name: 'b', statistics: _stats());
      final after = _report(name: 'a', statistics: _stats());
      final comparison = SessionComparator.compare(before, after);

      expect(comparison.overall.map((m) => m.label).toList(), [
        'slow_frame_rate',
        'p95',
        'p99',
        'worst_frame',
        'average_build',
        'average_raster',
      ]);
      expect(comparison.overall.every((m) => m.unit == 'ms'),
          isFalse); // rate uses '%'
      expect(_metric(comparison, 'slow_frame_rate').unit, '%');
      expect(_metric(comparison, 'p95').unit, 'ms');
    });

    test('improvement: lower rate yields negative deltaPercent', () {
      final before =
          _report(name: 'b', statistics: _stats(slowFrameRate: 0.10));
      final after = _report(name: 'a', statistics: _stats(slowFrameRate: 0.05));
      final comparison = SessionComparator.compare(before, after);

      final metric = _metric(comparison, 'slow_frame_rate');
      expect(metric.before, closeTo(10.0, 1e-9)); // percentage points
      expect(metric.after, closeTo(5.0, 1e-9));
      expect(metric.deltaPercent, -50.0);
      expect(metric.deltaPercent, isNegative);
    });

    test('regression: higher value yields positive deltaPercent', () {
      final before = _report(name: 'b', statistics: _stats(p95Ms: 20.0));
      final after = _report(name: 'a', statistics: _stats(p95Ms: 30.0));
      final comparison = SessionComparator.compare(before, after);

      final metric = _metric(comparison, 'p95');
      expect(metric.before, 20.0);
      expect(metric.after, 30.0);
      expect(metric.deltaPercent, 50.0);
      expect(metric.deltaPercent, isPositive);
    });

    test('zero baseline yields null deltaPercent', () {
      final before = _report(name: 'b', statistics: _stats(worstFrameMs: 0.0));
      final after = _report(name: 'a', statistics: _stats(worstFrameMs: 50));
      final comparison = SessionComparator.compare(before, after);

      final metric = _metric(comparison, 'worst_frame');
      expect(metric.before, 0.0);
      expect(metric.after, 50.0);
      expect(metric.deltaPercent, isNull);
    });

    test('deltaPercent rounds to exactly one decimal', () {
      // 10 / 90 * 100 = 11.111... -> 11.1
      final up = SessionComparator.compare(
        _report(name: 'b', statistics: _stats(p95Ms: 90)),
        _report(name: 'a', statistics: _stats(p95Ms: 100)),
      );
      expect(_metric(up, 'p95').deltaPercent, 11.1);

      // 7 / 30 * 100 = 23.333... -> 23.3
      final repeating = SessionComparator.compare(
        _report(name: 'b', statistics: _stats(p99Ms: 30)),
        _report(name: 'a', statistics: _stats(p99Ms: 37)),
      );
      expect(_metric(repeating, 'p99').deltaPercent, 23.3);

      // -66.5 keeps the half-away-from-zero tie at one decimal.
      final downHalf = SessionComparator.compare(
        _report(name: 'b', statistics: _stats(averageBuildMs: 100)),
        _report(name: 'a', statistics: _stats(averageBuildMs: 33.5)),
      );
      expect(_metric(downHalf, 'average_build').deltaPercent, -66.5);
    });
  });

  group('screen pairing', () {
    test('union of names sorted alphabetically with single-sided entries', () {
      final before = _report(
        name: 'b',
        statistics: _stats(),
        screens: [_screen('Beta'), _screen('Alpha')],
      );
      final after = _report(
        name: 'a',
        statistics: _stats(),
        screens: [_screen('Alpha'), _screen('Gamma')],
      );
      final comparison = SessionComparator.compare(before, after);

      expect(comparison.screens.map((s) => s.screen).toList(),
          ['Alpha', 'Beta', 'Gamma']);

      final alpha = comparison.screens[0];
      expect(alpha.before?.name, 'Alpha');
      expect(alpha.after?.name, 'Alpha');

      final beta = comparison.screens[1];
      expect(beta.before?.name, 'Beta');
      expect(beta.after, isNull);

      final gamma = comparison.screens[2];
      expect(gamma.before, isNull);
      expect(gamma.after?.name, 'Gamma');
    });

    test('single-sided entries keep full metric set, all deltas null', () {
      final before = _report(
        name: 'b',
        statistics: _stats(),
        screens: [_screen('OnlyHere', rate: 0.02, p95: 12, worst: 25)],
      );
      final after = _report(name: 'a', statistics: _stats());
      final comparison = SessionComparator.compare(before, after);

      final single =
          comparison.screens.singleWhere((s) => s.screen == 'OnlyHere');
      expect(single.metrics.map((m) => m.label).toList(), [
        'slow_frame_rate',
        'p95',
        'worst_frame',
      ]);
      for (final metric in single.metrics) {
        expect(metric.before, isNotNull);
        expect(metric.after, isNull);
        expect(metric.deltaPercent, isNull);
      }
    });

    test('paired screen deltas reflect summary changes', () {
      final before = _report(
        name: 'b',
        statistics: _stats(),
        screens: [_screen('Home', rate: 0.04)],
      );
      final after = _report(
        name: 'a',
        statistics: _stats(),
        screens: [_screen('Home', rate: 0.01)],
      );
      final comparison = SessionComparator.compare(before, after);

      final home = comparison.screens.single;
      final rate = home.metrics.firstWhere((m) => m.label == 'slow_frame_rate');
      expect(rate.deltaPercent, -75.0);
      expect(rate.unit, '%');
    });
  });

  group('interaction pairing', () {
    test('interactions carry only p95 and worst_frame metrics', () {
      final before = _report(
        name: 'b',
        statistics: _stats(),
        interactions: [
          _interaction('scroll', p95: 15.0),
          _interaction('checkout', p95: 40.0),
        ],
      );
      final after = _report(
        name: 'a',
        statistics: _stats(),
        interactions: [_interaction('scroll', p95: 18.0)],
      );
      final comparison = SessionComparator.compare(before, after);

      expect(comparison.interactions.map((i) => i.interaction).toList(),
          ['checkout', 'scroll']); // alphabetical union

      final scroll = comparison.interactions.last;
      expect(
          scroll.metrics.map((m) => m.label).toList(), ['p95', 'worst_frame']);
      expect(scroll.metrics.firstWhere((m) => m.label == 'p95').deltaPercent,
          20.0);

      final checkout = comparison.interactions.first;
      expect(checkout.before, isNotNull);
      expect(checkout.after, isNull);
      expect(
        checkout.metrics.every((m) =>
            m.deltaPercent == null && m.before != null && m.after == null),
        isTrue,
      );
    });
  });

  group('warnings', () {
    test('healthy comparable pair produces none', () {
      final before = _report(
        name: 'baseline',
        statistics: _stats(totalFrames: 1000),
        screens: [_screen('Home'), _screen('List')],
      );
      final after = _report(
        name: 'candidate',
        statistics: _stats(totalFrames: 1200),
        screens: [_screen('Home'), _screen('List')],
      );
      expect(SessionComparator.compare(before, after).warnings, isEmpty);
    });

    test('disjoint screen sets warn about unpairable screens', () {
      final before = _report(
        name: 'b',
        statistics: _stats(totalFrames: 2000),
        screens: [_screen('Home')],
      );
      final after = _report(
        name: 'a',
        statistics: _stats(totalFrames: 2000),
        screens: [_screen('Settings')],
      );
      final warnings = SessionComparator.compare(before, after).warnings;
      expect(warnings.length, 1);
      expect(warnings.single, contains('No screens are shared'));
    });

    test('low sample warns per offending side without scale warning', () {
      final before = _report(
        name: 'b',
        statistics: _stats(totalFrames: 99), // below threshold, ratio 9.09x
        screens: [_screen('Home')],
      );
      final after = _report(
        name: 'a',
        statistics: _stats(totalFrames: 900),
        screens: [_screen('Home')],
      );
      final warnings = SessionComparator.compare(before, after).warnings;
      expect(warnings.length, 1);
      expect(warnings.single, contains("'before'"));
      expect(warnings.single, contains('99'));
    });

    test('both sides below threshold emit two low-sample warnings', () {
      final before = _report(
        name: 'b',
        statistics: _stats(totalFrames: 50),
        screens: [_screen('Home')],
      );
      final after = _report(
        name: 'a',
        statistics: _stats(totalFrames: 60),
        screens: [_screen('Home')],
      );
      final warnings = SessionComparator.compare(before, after).warnings;
      expect(warnings.length, 2);
      expect(warnings.any((w) => w.contains("'before'")), isTrue);
      expect(warnings.any((w) => w.contains("'after'")), isTrue);
    });

    test('frame-count gap beyond 10x warns once', () {
      final before = _report(
        name: 'b',
        statistics: _stats(totalFrames: 1000),
        screens: [_screen('Home')],
      );
      final after = _report(
        name: 'a',
        statistics: _stats(totalFrames: 12000), // 12x larger
        screens: [_screen('Home')],
      );
      final warnings = SessionComparator.compare(before, after).warnings;
      expect(warnings.length, 1);
      expect(warnings.single, contains('10x'));
      expect(warnings.single, contains('1000 vs 12000'));
    });

    test('exactly 10x does not warn', () {
      final before = _report(
        name: 'b',
        statistics: _stats(totalFrames: 1000),
        screens: [_screen('Home')],
      );
      final after = _report(
        name: 'a',
        statistics: _stats(totalFrames: 10000), // exactly 10x
        screens: [_screen('Home')],
      );
      expect(SessionComparator.compare(before, after).warnings, isEmpty);
    });
  });

  group('SessionComparison identity', () {
    test('keeps both source reports reachable', () {
      final before = _report(name: 'b', statistics: _stats());
      final after = _report(name: 'a', statistics: _stats());
      final comparison = SessionComparator.compare(before, after);
      expect(identical(comparison.before, before), isTrue);
      expect(identical(comparison.after, after), isTrue);
    });
  });
}
