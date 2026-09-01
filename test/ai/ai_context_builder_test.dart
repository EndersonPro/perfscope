import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

// -----------------------------------------------------------------------------
// Hand-built fixture: models constructed directly, no engine involved.
// -----------------------------------------------------------------------------

final DateTime _start = DateTime.utc(2026, 1, 15, 10, 0, 0);
final DateTime _end = _start.add(const Duration(minutes: 4, seconds: 32));

const _stats = SessionStatistics(
  totalFrames: 18421,
  normalFrames: 18384,
  warningFrames: 0,
  slowFrames: 30,
  severeFrames: 7,
  slowFrameRate: 37 / 18421,
  averageBuildMs: 6.2,
  averageRasterMs: 4.1,
  averageTotalMs: 10.3,
  p50Ms: 7.1,
  p90Ms: 12.9,
  p95Ms: 14.4,
  p99Ms: 28.7,
  worstFrameMs: 71.3,
);

PerformanceSession _session({String? name, bool ended = true}) {
  final session = PerformanceSession(
    id: 'ses_test',
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
  if (ended) {
    session.endedAt = _end;
  }
  return session;
}

ScreenPerformanceSummary _screen(
  String name, {
  int anomalyCount = 1,
  double rate = 0.02,
  double p95 = 20.0,
  double worst = 30.0,
  FrameBottleneck bottleneck = FrameBottleneck.ui,
}) {
  return ScreenPerformanceSummary(
    name: name,
    totalFrames: 1000,
    slowFrames: 12,
    severeFrames: 8,
    anomalyCount: anomalyCount,
    slowFrameRate: rate,
    p95Ms: p95,
    worstMs: worst,
    probableBottleneck: bottleneck,
  );
}

InteractionPerformanceSummary _interaction(
  String name, {
  int anomalyCount = 3,
}) {
  return InteractionPerformanceSummary(
    name: name,
    mostRecentInteractionId: 'itx_1',
    spanCount: 4,
    frameCount: 200,
    anomalyCount: anomalyCount,
    totalSpanDuration: const Duration(milliseconds: 250),
    p95Ms: 22.5,
    worstMs: 33.5,
    probableBottleneck: FrameBottleneck.mixed,
  );
}

CompletedTrace _trace(String name) => CompletedTrace(
      id: 'trc_1',
      name: name,
      startedAt: _start,
      duration: const Duration(milliseconds: 120),
      screen: 'ProductList',
      didThrow: false,
    );

/// Full report: two ranked screens, top interaction named like screen 1.
PerformanceReport _fullReport() {
  return PerformanceReport(
    session: _session(name: 'checkout-performance'),
    statistics: _stats,
    screens: [
      // Ranked as-is; the builder never reorders.
      _screen('ProductList', anomalyCount: 12, p95: 29.4, worst: 46.2),
      _screen('ProductDetails',
          anomalyCount: 8,
          p95: 21.0,
          worst: 38.5,
          bottleneck: FrameBottleneck.raster),
    ],
    interactions: [_interaction('ProductList')],
    traces: [_trace('load_catalog')],
    anomalies: const [],
    worstAnomalies: const [],
  );
}

/// Finds the index of [line] as an exact full line of [text].
int _lineIndex(String text, String line) {
  final lines = text.split('\n');
  return lines.indexOf(line);
}

void main() {
  group('buildAiContextText', () {
    test('header is first line and key lines appear in order', () {
      final text = buildAiContextText(_fullReport());
      final lines = text.split('\n');

      expect(lines.first, 'PERFSCOPE_SESSION');

      final nameIdx = _lineIndex(text, 'name: checkout-performance');
      final durationIdx = _lineIndex(text, 'duration: 4m 32s');
      final framesIdx = _lineIndex(text, 'frames: 18421');
      final slowIdx = _lineIndex(text, 'slow_frames: 37');
      final rateIdx = _lineIndex(text, 'slow_frame_rate: 0.20%');
      final p50Idx = _lineIndex(text, 'p50_ms: 7.1');
      final p95Idx = _lineIndex(text, 'p95_ms: 14.4');
      final p99Idx = _lineIndex(text, 'p99_ms: 28.7');
      final worstIdx = _lineIndex(text, 'worst_frame_ms: 71.3');

      expect(nameIdx, greaterThan(0));
      expect(durationIdx, greaterThan(nameIdx));
      expect(framesIdx, greaterThan(durationIdx));
      expect(slowIdx, greaterThan(framesIdx));
      expect(rateIdx, greaterThan(slowIdx));
      expect(p50Idx, greaterThan(rateIdx));
      expect(p95Idx, greaterThan(p50Idx));
      expect(p99Idx, greaterThan(p95Idx));
      expect(worstIdx, greaterThan(p99Idx));

      final issuesIdx = lines.indexOf('TOP_ISSUES:');
      expect(issuesIdx, greaterThan(worstIdx));
    });

    test('issues are numbered with screen data and uppercase bottlenecks', () {
      final text = buildAiContextText(_fullReport());

      final oneIdx = _lineIndex(text, '1:');
      final listIdx = _lineIndex(text, 'screen: ProductList');
      final anomaliesIdx = _lineIndex(text, 'anomalies: 12');
      final issueWorstIdx = _lineIndex(text, 'worst_frame_ms: 46.2');
      final issueP95Idx = _lineIndex(text, 'p95_ms: 29.4');
      final bottleneckIdx = _lineIndex(text, 'probable_bottleneck: UI');

      expect(oneIdx, greaterThan(_lineIndex(text, 'TOP_ISSUES:')));
      expect(listIdx, greaterThan(oneIdx));
      expect(anomaliesIdx, greaterThan(listIdx));
      expect(issueWorstIdx, greaterThan(anomaliesIdx));
      expect(issueP95Idx, greaterThan(issueWorstIdx));
      expect(bottleneckIdx, greaterThan(issueP95Idx));
      expect(
        text.contains('probable_bottleneck: RASTER'),
        isTrue,
        reason: 'second issue carries its own bottleneck label',
      );
      // No lowercase enum names leak into the text format.
      expect(text.contains(': ui\n'), isFalse);
    });

    test('interaction line merges only on exact top-interaction name match',
        () {
      final text = buildAiContextText(_fullReport());
      // Top interaction 'ProductList' matches issue 1's screen only.
      final interactionLineIdx = _lineIndex(text, 'interaction: ProductList');
      expect(interactionLineIdx, greaterThan(0));
      expect(
        interactionLineIdx > _lineIndex(text, 'screen: ProductList'),
        isTrue,
      );
      expect(
        interactionLineIdx < _lineIndex(text, 'anomalies: 12'),
        isTrue,
      );
      // Issue 2 has no interaction line at all.
      final allLines = text.split('\n');
      final secondIssueStart = allLines.indexOf('2:');
      final secondBlock = allLines.sublist(secondIssueStart).join('\n');
      expect(secondBlock.contains('interaction:'), isFalse);
    });

    test('unnamed session renders placeholder', () {
      final report = PerformanceReport(
        session: _session(),
        statistics: _stats,
        screens: const [],
        interactions: const [],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      );
      expect(buildAiContextText(report), contains('name: (unnamed)'));
    });

    test('active session omits duration line', () {
      final report = PerformanceReport(
        session: _session(ended: false),
        statistics: _stats,
        screens: const [],
        interactions: const [],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      );
      final text = buildAiContextText(report);
      expect(text.contains('duration:'), isFalse);
    });

    test('no screens yield empty TOP_ISSUES section', () {
      final report = PerformanceReport(
        session: _session(name: 'empty'),
        statistics: _stats,
        screens: const [],
        interactions: const [],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      );
      final text = buildAiContextText(report);
      expect(text, endsWith('TOP_ISSUES:'));
      expect(text.contains('\n1:'), isFalse);
    });

    test('unknown bottleneck renders as UNKNOWN', () {
      final report = PerformanceReport(
        session: _session(name: 's'),
        statistics: _stats,
        screens: [
          _screen('MysteryScreen', bottleneck: FrameBottleneck.unknown),
        ],
        interactions: const [],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      );
      expect(
        buildAiContextText(report),
        contains('probable_bottleneck: UNKNOWN'),
      );
    });

    test('whole-number ms values drop trailing .0', () {
      final report = PerformanceReport(
        session: _session(name: 's'),
        statistics: _stats,
        screens: [
          _screen('RoundScreen', p95: 29.0, worst: 46.0),
        ],
        interactions: const [],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      );
      final text = buildAiContextText(report);
      expect(text, contains('worst_frame_ms: 46\n'));
      expect(text, contains('p95_ms: 29\n'));
    });

    test('maxTopIssues caps numbered issues', () {
      final text = buildAiContextText(
        _fullReport(),
        config: const AiContextConfig(maxTopIssues: 1),
      );
      expect(text.contains('\n1:'), isTrue);
      expect(text.contains('\n2:'), isFalse);
      expect(text, contains('screen: ProductList'));
      expect(text.contains('screen: ProductDetails'), isFalse);
    });

    test('maxChars hard cap appends truncation marker', () {
      final text = buildAiContextText(
        _fullReport(),
        config: const AiContextConfig(maxChars: 60),
      );
      expect(text.length, lessThanOrEqualTo(60));
      expect(text, endsWith('...[truncated]'));
    });

    test('text hygiene: no tabs, no trailing whitespace on any line', () {
      final text = buildAiContextText(_fullReport());
      expect(text.contains('\t'), isFalse);
      for (final line in text.split('\n')) {
        expect(line, line.trimRight(),
            reason: 'trailing whitespace in "$line"');
      }
    });
  });

  group('buildAiContextJson', () {
    test('top-level structure and fixed values', () {
      final json = buildAiContextJson(
        _fullReport(),
        now: () => DateTime.utc(2026, 1, 15, 11, 0, 0),
      );

      expect(
          json.keys,
          containsAll(<String>[
            'schema_version',
            'kind',
            'session',
            'summary',
            'top_issues',
            'traces',
            'generated_at',
          ]));
      expect(json['schema_version'], aiContextSchemaVersion);
      expect(json['schema_version'], 1);
      expect(json['kind'], 'ai_context');
      expect(json['generated_at'], '2026-01-15T11:00:00.000Z');
    });

    test('generated_at clock is injectable and deterministic', () {
      final jsonA = buildAiContextJson(
        _fullReport(),
        now: () => DateTime.utc(2026, 3, 1, 8, 30, 15, 250),
      );
      final jsonB = buildAiContextJson(
        _fullReport(),
        now: () => DateTime.utc(2026, 3, 1, 8, 30, 15, 250),
      );
      expect(jsonA['generated_at'], jsonB['generated_at']);
      expect(jsonA['generated_at'], '2026-03-01T08:30:15.250Z');
    });

    test('session block carries identity and derived duration', () {
      final json = buildAiContextJson(
        _fullReport(),
        now: () => _start,
      );
      final session = json['session'] as Map<String, Object?>;
      expect(session['id'], 'ses_test');
      expect(session['name'], 'checkout-performance');
      expect(session['started_at'], '2026-01-15T10:00:00.000Z');
      expect(session['ended_at'], '2026-01-15T10:04:32.000Z');
      expect(session['duration_ms'], 272000);
    });

    test('unnamed sessions omit the name key instead of emitting null', () {
      final json = buildAiContextJson(
        PerformanceReport(
          session: _session(),
          statistics: _stats,
          screens: const [],
          interactions: const [],
          traces: const [],
          anomalies: const [],
          worstAnomalies: const [],
        ),
        now: () => _start,
      );
      final session = json['session'] as Map<String, Object?>;
      expect(session.containsKey('name'), isFalse);
    });

    test('summary mirrors session statistics', () {
      final json = buildAiContextJson(
        _fullReport(),
        now: () => _start,
      );
      final summary = json['summary'] as Map<String, Object?>;
      expect(summary['total_frames'], 18421);
      expect(summary['slow_frames'], 30);
      expect(summary['severe_frames'], 7);
      expect(summary['slow_frame_rate'], closeTo(37 / 18421, 1e-9));
      expect(summary['p95_ms'], 14.4);
      expect(summary['worst_frame_ms'], 71.3);
    });

    test('top_issues respect maxTopIssues and carry structured fields', () {
      final json = buildAiContextJson(
        _fullReport(),
        config: const AiContextConfig(maxTopIssues: 1),
        now: () => _start,
      );
      final issues = json['top_issues'] as List<Object?>;
      expect(issues.length, 1);
      final first = issues.first as Map<String, Object?>;
      expect(first['screen'], 'ProductList');
      expect(first['interaction'], 'ProductList');
      expect(first['anomaly_count'], 12);
      expect(first['probable_bottleneck'], 'ui');
      expect(first['worst_ms'], 46.2);
    });

    test('traces honor includeTraces and maxAnomaliesListed cap', () {
      final report = PerformanceReport(
        session: _session(name: 's'),
        statistics: _stats,
        screens: const [],
        interactions: const [],
        traces: [
          _trace('t1'),
          _trace('t2'),
          _trace('t3'),
        ],
        anomalies: const [],
        worstAnomalies: const [],
      );

      final capped = buildAiContextJson(
        report,
        config: const AiContextConfig(maxAnomaliesListed: 2),
        now: () => _start,
      );
      final traces = capped['traces'] as List<Object?>;
      expect(traces.length, 2);
      expect((traces.first as Map<String, Object?>)['name'], 't1');
      final traceMap = traces.first as Map<String, Object?>;
      expect(traceMap.containsKey('duration_ms'), isTrue);
      expect(traceMap.containsKey('screen'), isTrue);
      expect(traceMap.containsKey('did_throw'), isTrue);

      final withoutTraces = buildAiContextJson(
        report,
        config: const AiContextConfig(includeTraces: false),
        now: () => _start,
      );
      expect(withoutTraces['traces'], isEmpty);
    });
  });

  group('ReportAiContext extension', () {
    test('toAiContext delegates to the text builder', () {
      final report = _fullReport();
      expect(
        report.toAiContext(),
        buildAiContextText(report),
      );
      expect(
        report.toAiContext(config: const AiContextConfig(maxTopIssues: 1)),
        buildAiContextText(
          report,
          config: const AiContextConfig(maxTopIssues: 1),
        ),
      );
    });

    test('toAiJson delegates to the JSON builder with injected clock', () {
      final report = _fullReport();
      expect(
        report.toAiJson(now: () => _start),
        buildAiContextJson(report, now: () => _start),
      );
    });
  });

  group('AiContextConfig', () {
    test('defaults match the documented values', () {
      const config = AiContextConfig();
      expect(config.maxTopIssues, 10);
      expect(config.maxAnomaliesListed, 20);
      expect(config.includeTraces, isTrue);
      expect(config.includeScreens, isTrue);
      expect(config.includeInteractions, isTrue);
      expect(config.maxChars, 12000);
    });

    test('copyWith replaces only given fields', () {
      const config = AiContextConfig();
      final copied = config.copyWith(maxChars: 100, includeScreens: false);
      expect(copied.maxChars, 100);
      expect(copied.includeScreens, isFalse);
      expect(copied.maxTopIssues, 10);
      expect(copied.maxAnomaliesListed, 20);
      expect(copied.includeTraces, isTrue);
      expect(copied.includeInteractions, isTrue);
    });
  });
}
