import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

// -----------------------------------------------------------------------------
// Fixtures: models built directly, serialized with SessionSerializer, and
// served to the CLI through an injected map-based loader. No filesystem,
// no clock, no process spawning — fully deterministic.
// -----------------------------------------------------------------------------

final DateTime _start = DateTime.utc(2026, 2, 1, 9, 0, 0);

PerformanceSession _session(String id, String name) {
  final session = PerformanceSession(
    id: id,
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
  )..endedAt = _start.add(const Duration(minutes: 2));
  return session;
}

SessionStatistics _stats({int totalFrames = 1000}) {
  return SessionStatistics(
    totalFrames: totalFrames,
    normalFrames: totalFrames - 18,
    warningFrames: 10,
    slowFrames: 6,
    severeFrames: 2,
    slowFrameRate: 0.008,
    averageBuildMs: 7.455,
    averageRasterMs: 8.909,
    averageTotalMs: 16.364,
    p50Ms: 8.0,
    p90Ms: 16.0,
    p95Ms: 28.0,
    p99Ms: 40.0,
    worstFrameMs: 80.0,
  );
}

ScreenPerformanceSummary _screen(String name, int anomalyCount) =>
    ScreenPerformanceSummary(
      name: name,
      totalFrames: 500,
      slowFrames: 10,
      severeFrames: 2,
      anomalyCount: anomalyCount,
      slowFrameRate: 0.02,
      p95Ms: 20.0,
      worstMs: 40.0,
      probableBottleneck: FrameBottleneck.ui,
    );

PerformanceReport _report({
  required String id,
  required String name,
  List<ScreenPerformanceSummary> screens = const [],
}) {
  return PerformanceReport(
    session: _session(id, name),
    statistics: _stats(),
    screens: screens,
    interactions: const [],
    traces: const [],
    anomalies: const [],
    worstAnomalies: const [],
  );
}

/// Serialized session documents keyed by fake path.
Map<String, String> _files({
  int beforeFrames = 1000,
  List<ScreenPerformanceSummary> beforeScreens = const [],
  List<ScreenPerformanceSummary> afterScreens = const [],
}) {
  return {
    '/session.json': const SessionSerializer()
        .serializeToString(_report(id: 'ses_main', name: 'main')),
    '/screens.json': const SessionSerializer().serializeToString(
      _report(
        id: 'ses_screens',
        name: 'screens',
        screens: [
          _screen('Home', 4),
          _screen('Settings', 2),
          _screen('Profile', 1),
        ],
      ),
    ),
    '/before.json': const SessionSerializer().serializeToString(
      PerformanceReport(
        session: _session('ses_before', 'before'),
        statistics: _stats(totalFrames: beforeFrames),
        screens: beforeScreens,
        interactions: const [],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      ),
    ),
    '/after.json': const SessionSerializer().serializeToString(
      PerformanceReport(
        session: _session('ses_after', 'after'),
        statistics: _stats(totalFrames: 1000),
        screens: afterScreens,
        interactions: const [],
        traces: const [],
        anomalies: const [],
        worstAnomalies: const [],
      ),
    ),
  };
}

CommandRunnerDependencies _deps(Map<String, String> files) {
  return CommandRunnerDependencies(
    loadFile: (path) {
      final content = files[path];
      if (content == null) {
        throw StateError('No such file: $path');
      }
      return content;
    },
    probe: const NullSystemProbe(),
  );
}

void main() {
  group('analyze', () {
    test('happy path prints compact summary and exits 0', () async {
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runPerfScopeCli(
        ['analyze', '/session.json'],
        out: out,
        err: err,
        deps: _deps(_files()),
      );

      expect(code, 0);
      expect(err.toString(), isEmpty);
      expect(out.toString(), contains('Session: ses_main'));
      expect(out.toString(), contains('Name: main'));
      expect(out.toString(), contains('Duration:'));
      expect(out.toString(), contains('Frames: 1000'));
      expect(out.toString(), contains('Slow-frame rate: 0.8%'));
      expect(out.toString(), contains('p95: 28ms'));
      expect(out.toString(), contains('p99: 40ms'));
      expect(out.toString(), contains('Worst frame: 80ms'));
      expect(out.toString(), contains('Anomalies: 0'));
    });

    test('top screens ranked by anomalies, capped at three', () async {
      final out = StringBuffer();
      final code = await runPerfScopeCli(
        ['analyze', '/screens.json'],
        out: out,
        err: StringBuffer(),
        deps: _deps(_files()),
      );

      expect(code, 0);
      expect(out.toString(), contains('Top screens by anomalies:'));
      expect(out.toString(), contains('1. Home - 4'));
      expect(out.toString(), contains('2. Settings - 2'));
      expect(out.toString(), contains('3. Profile - 1'));
    });

    test('missing file exits 2 with message on stderr', () async {
      final err = StringBuffer();
      final code = await runPerfScopeCli(
        ['analyze', '/nope.json'],
        out: StringBuffer(),
        err: err,
        deps: _deps(_files()),
      );

      expect(code, 2);
      expect(err.toString(), contains('Cannot read file: /nope.json'));
    });

    test('malformed JSON exits 3', () async {
      final err = StringBuffer();
      final code = await runPerfScopeCli(
        ['analyze', '/broken.json'],
        out: StringBuffer(),
        err: err,
        deps: _deps({'/broken.json': '{not json'}),
      );

      expect(code, 3);
      expect(err.toString(), contains('malformed JSON'));
    });

    test('unsupported schema version exits 3 with exact parser message',
        () async {
      final doc = _files()['/session.json']!;
      final tampered = doc.replaceFirst(
        '"$kKeySchemaVersion":$kSchemaVersion',
        '"$kKeySchemaVersion":99',
      );
      expect(tampered, isNot(doc));

      final err = StringBuffer();
      final code = await runPerfScopeCli(
        ['analyze', '/tampered.json'],
        out: StringBuffer(),
        err: err,
        deps: _deps({'/tampered.json': tampered}),
      );

      expect(code, 3);
      expect(
        err.toString(),
        contains('Unsupported PerfScope schema version: 99. '
            'Supported versions: $kSchemaVersion.'),
      );
    });
  });

  group('report', () {
    test('prints the full formatted report box', () async {
      final out = StringBuffer();
      final code = await runPerfScopeCli(
        ['report', '/session.json'],
        out: out,
        err: StringBuffer(),
        deps: _deps(_files()),
      );

      expect(code, 0);
      expect(out.toString(), contains('PerfScope — Session Summary'));
      expect(out.toString(), contains('ses_main'));
    });
  });

  group('compare', () {
    test('happy path prints DELTA table and warnings section', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      // 50 frames trips the low-sample warning on the before side.
      final code = await runPerfScopeCli(
        ['compare', '/before.json', '/after.json'],
        out: out,
        err: err,
        deps: _deps(_files(beforeFrames: 50)),
      );

      expect(code, 0);
      expect(err.toString(), isEmpty);
      expect(out.toString(), contains('BEFORE'));
      expect(out.toString(), contains('AFTER'));
      expect(out.toString(), contains('DELTA'));
      expect(out.toString(), contains('Warnings:'));
      expect(out.toString(), contains('Low sample'));
    });
  });

  group('ai-context', () {
    test('output starts with the PERFSCOPE_SESSION marker', () async {
      final out = StringBuffer();
      final code = await runPerfScopeCli(
        ['ai-context', '/session.json'],
        out: out,
        err: StringBuffer(),
        deps: _deps(_files()),
      );

      expect(code, 0);
      expect(out.toString(), startsWith('PERFSCOPE_SESSION'));
    });
  });

  group('usage', () {
    test('--help lists all five commands and exits 0', () async {
      final out = StringBuffer();
      final code =
          await runPerfScopeCli(['--help'], out: out, err: StringBuffer());

      expect(code, 0);
      for (final command in [
        'analyze',
        'report',
        'compare',
        'ai-context',
        'doctor',
      ]) {
        expect(out.toString(), contains(command));
      }
    });

    test('-h behaves like --help', () async {
      final out = StringBuffer();
      final code = await runPerfScopeCli(['-h'], out: out, err: StringBuffer());

      expect(code, 0);
      expect(out.toString(), contains('analyze'));
    });

    test('unknown command exits 1 with hint on stderr', () async {
      final err = StringBuffer();
      final code = await runPerfScopeCli(
        ['frobnicate'],
        out: StringBuffer(),
        err: err,
      );

      expect(code, 1);
      expect(err.toString(), contains("Unknown command: 'frobnicate'"));
      expect(err.toString(), contains('--help'));
    });
  });
}
