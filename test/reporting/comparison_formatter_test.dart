import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

// -----------------------------------------------------------------------------
// Hand-built fixtures: models constructed directly, no engine involved.
// -----------------------------------------------------------------------------

SessionStatistics _stats({
  int totalFrames = 1000,
  double slowFrameRate = 0.018,
  double p95Ms = 28.0,
  double p99Ms = 40.0,
  double worstFrameMs = 80.0,
  double averageBuildMs = 7.455,
  double averageRasterMs = 8.909,
}) {
  return SessionStatistics(
    totalFrames: totalFrames,
    normalFrames: totalFrames - 18,
    warningFrames: 10,
    slowFrames: 6,
    severeFrames: 2,
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

PerformanceReport _report(SessionStatistics statistics) {
  final session = PerformanceSession(
    id: 'ses_cmp',
    name: 'cmp',
    startedAt: DateTime.utc(2026, 2, 1, 9, 0, 0),
    environment: const PerformanceEnvironment(
      frameBudgetFps: 60.0,
      frameBudgetMs: 16.667,
      frameBudgetSource: FrameBudgetSource.detected,
      platform: 'test',
    ),
    calculator: StatisticsCalculator(),
    anomalies: const [],
  )..endedAt = DateTime.utc(2026, 2, 1, 9, 2, 0);
  return PerformanceReport(
    session: session,
    statistics: statistics,
    screens: const [],
    interactions: const [],
    traces: const [],
    anomalies: const [],
    worstAnomalies: const [],
  );
}

/// Fixed column geometry produced by the formatter for these fixtures:
/// label column 15 wide, numeric columns 8-wide content + 2-space gaps.
String _line(String label, String before, String after, String delta) =>
    '${label.padRight(15)}'
    '${before.padLeft(10)}'
    '${after.padLeft(10)}'
    '${delta.padLeft(10)}';

/// Column geometry when the widest label is 'Worst frame' (11 chars),
/// as in per-interaction tables.
String _interactionLine(
        String label, String before, String after, String delta) =>
    '${label.padRight(11)}'
    '${before.padLeft(10)}'
    '${after.padLeft(10)}'
    '${delta.padLeft(10)}';

void main() {
  group('formatSessionComparison', () {
    test('overall table: exact column alignment with negative deltas', () {
      final comparison = SessionComparator.compare(
        _report(_stats()),
        _report(_stats(
          slowFrameRate: 0.004,
          p95Ms: 14.0,
          p99Ms: 20.0,
          worstFrameMs: 40.0,
          averageBuildMs: 3.2,
          averageRasterMs: 4.6,
        )),
      );

      // Hand-computed expectations pinning the documented geometry:
      // 15-wide left-aligned labels, 10-wide right-aligned fields.
      expect(formatSessionComparison(comparison).split('\n'), [
        '                   BEFORE     AFTER     DELTA',
        _line('Slow frame rate', '1.8%', '0.4%', '-77.8%'),
        _line('p95', '28ms', '14ms', '-50.0%'),
        _line('p99', '40ms', '20ms', '-50.0%'),
        _line('Worst frame', '80ms', '40ms', '-50.0%'),
        _line('Avg build', '7ms', '3ms', '-57.1%'),
        _line('Avg raster', '9ms', '5ms', '-48.4%'),
        '',
      ]);
    });

    test('positive deltas carry an explicit plus sign', () {
      final comparison = SessionComparator.compare(
        _report(_stats(p95Ms: 20.0)),
        _report(_stats(p95Ms: 25.0)),
      );

      final output = formatSessionComparison(comparison);
      final p95Row =
          output.split('\n').firstWhere((line) => line.startsWith('p95'));
      expect(p95Row, _line('p95', '20ms', '25ms', '+25.0%'));
    });

    test('n/a when either side is missing or baseline is zero', () {
      final zeroBaseline = SessionComparator.compare(
        _report(_stats(p95Ms: 0)),
        _report(_stats(p95Ms: 10)),
      );
      final p95Row = zeroBaseline.outputP95Row();
      expect(p95Row.endsWith('n/a'), isTrue);
    });

    test('screens section renders one table per compared screen', () {
      ScreenPerformanceSummary screen(String name, double rate) =>
          ScreenPerformanceSummary(
            name: name,
            totalFrames: 500,
            slowFrames: 10,
            severeFrames: 2,
            anomalyCount: 3,
            slowFrameRate: rate,
            p95Ms: 20.0,
            worstMs: 40.0,
            probableBottleneck: FrameBottleneck.ui,
          );
      final beforeReport = PerformanceReport(
        session: _report(_stats()).session,
        statistics: _stats(),
        screens: [screen('Home', 0.02)],
        interactions: const [],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      );
      final afterReport = PerformanceReport(
        session: _report(_stats()).session,
        statistics: _stats(),
        screens: [screen('Home', 0.01)],
        interactions: const [],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      );

      final output = formatSessionComparison(
        SessionComparator.compare(beforeReport, afterReport),
      );

      expect(output, contains('By screen:'));
      expect(output, contains('\nHome\n'));
      // Screen tables reuse the same metric rendering as the overall
      // block (rate in percent points, durations rounded to whole ms).
      expect(
          output, contains(_line('Slow frame rate', '2.0%', '1.0%', '-50.0%')));
      expect(output, contains(_line('Worst frame', '40ms', '40ms', '0.0%')));
    });

    test('single-sided screen shows n/a columns and n/a delta', () {
      ScreenPerformanceSummary screen(String name) => ScreenPerformanceSummary(
            name: name,
            totalFrames: 500,
            slowFrames: 10,
            severeFrames: 2,
            anomalyCount: 3,
            slowFrameRate: 0.02,
            p95Ms: 20.0,
            worstMs: 40.0,
            probableBottleneck: FrameBottleneck.ui,
          );
      final beforeOnly = PerformanceReport(
        session: _report(_stats()).session,
        statistics: _stats(),
        screens: [screen('OnlyBefore')],
        interactions: const [],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      );
      final plain = _report(_stats());

      final output = formatSessionComparison(
        SessionComparator.compare(beforeOnly, plain),
      );

      expect(output, contains('By screen:'));
      expect(output, contains('OnlyBefore'));
      expect(output, contains(_line('p95', '20ms', 'n/a', 'n/a')));
    });

    test('interactions section renders p95 and worst_frame only', () {
      InteractionPerformanceSummary interaction(double p95) =>
          InteractionPerformanceSummary(
            name: 'tap',
            mostRecentInteractionId: 'itx_1',
            spanCount: 2,
            frameCount: 100,
            anomalyCount: 1,
            totalSpanDuration: const Duration(milliseconds: 80),
            p95Ms: p95,
            worstMs: 30.0,
            probableBottleneck: FrameBottleneck.raster,
          );
      final beforeReport = PerformanceReport(
        session: _report(_stats()).session,
        statistics: _stats(),
        screens: const [],
        interactions: [interaction(15.0)],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      );
      final afterReport = PerformanceReport(
        session: _report(_stats()).session,
        statistics: _stats(),
        screens: const [],
        interactions: [interaction(10.0)],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      );

      final output = formatSessionComparison(
        SessionComparator.compare(beforeReport, afterReport),
      );

      expect(output, contains('By interaction:'));
      expect(output, contains('\ntap\n'));
      // Interaction tables compute their own label width (11 here).
      expect(
        output,
        contains(_interactionLine('p95', '15ms', '10ms', '-33.3%')),
      );
      expect(
        output,
        contains(_interactionLine('Worst frame', '30ms', '30ms', '0.0%')),
      );
    });

    test('warnings section omitted when empty, rendered when present', () {
      final identical = SessionComparator.compare(
        _report(_stats()),
        _report(_stats()),
      );
      final output = formatSessionComparison(identical);
      // Same frame counts, no screens on either side: nothing to warn.
      expect(output, isNot(contains('Warnings:')));

      final lowSample = SessionComparator.compare(
        _report(_stats(totalFrames: 50)),
        _report(_stats()),
      );
      final noisyOutput = formatSessionComparison(lowSample);
      expect(noisyOutput, contains('Warnings:'));
      expect(
        noisyOutput,
        contains("  - Low sample: the 'before' session recorded "
            '50 frames'),
      );
    });
  });
}

extension on SessionComparison {
  /// The p95 row of the overall table.
  String outputP95Row() => formatSessionComparison(this)
      .split('\n')
      .firstWhere((line) => line.startsWith('p95'));
}
