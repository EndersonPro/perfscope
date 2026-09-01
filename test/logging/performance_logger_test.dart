import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

import '../helpers/event_fixtures.dart';

PerformanceSession _session({Duration elapsed = const Duration(seconds: 5)}) {
  final startedAt = fixedTime;
  final session = PerformanceSession(
    id: 'ses_1',
    name: null,
    startedAt: startedAt,
    environment: const PerformanceEnvironment(
      frameBudgetFps: 60,
      frameBudgetMs: 16.667,
      frameBudgetSource: FrameBudgetSource.configured,
      platform: 'test',
    ),
    calculator: StatisticsCalculator(),
    anomalies: <PerformanceAnomaly>[],
  );
  if (elapsed > Duration.zero) {
    session.endedAt = startedAt.add(elapsed);
  }
  return session;
}

PerformanceReport _report({SessionStatistics? statistics}) {
  return PerformanceReport(
    session: _session(),
    statistics: statistics ?? SessionStatistics.zero,
    screens: <ScreenPerformanceSummary>[],
    interactions: <InteractionPerformanceSummary>[],
    traces: <CompletedTrace>[],
    anomalies: <PerformanceAnomaly>[],
    worstAnomalies: <PerformanceAnomaly>[],
  );
}

/// Writer whose write() always fails — proves logging never propagates.
class ThrowingWriter implements LogWriter {
  @override
  void write(String value) => throw StateError('writer exploded');
}

void main() {
  group('PerformanceLogger visibility', () {
    test('silent style writes nothing, ever', () {
      final writer = MemoryLogWriter();
      final logger = PerformanceLogger(
        style: PerfScopeLogStyle.silent,
        writer: writer,
      );
      logger.handleEvent(anomalyEvent(uiBoundAnomaly()));
      logger.handleEvent(frameEvent(frameSample()));
      expect(writer.lines, isEmpty);
      expect(logger.renderReport(_report()), '');
    });

    test('pretty style prints anomalies by default', () {
      final writer = MemoryLogWriter();
      final logger = PerformanceLogger(
        style: PerfScopeLogStyle.pretty,
        writer: writer,
      );
      logger.handleEvent(anomalyEvent(uiBoundAnomaly()));
      expect(writer.lines, hasLength(1));
      final block = writer.lines.single;
      expect(block, contains('PerfScope — Performance anomaly'));
      // Exactly ONE trailing newline appended per rendered block.
      expect(block.endsWith('\n'), isTrue);
      expect(block.endsWith('\n\n'), isFalse);
    });

    test('printAnomalies false suppresses anomalies', () {
      final writer = MemoryLogWriter();
      final logger = PerformanceLogger(
        style: PerfScopeLogStyle.pretty,
        writer: writer,
        printAnomalies: false,
      );
      logger.handleEvent(anomalyEvent(uiBoundAnomaly()));
      expect(writer.lines, isEmpty);
    });

    test('normal frames suppressed unless printNormalFrames or verbose', () {
      // 8 ms total on a 16.667 ms budget: comfortably NORMAL.
      FrameSample normalSample() => frameSample(
            build: const Duration(milliseconds: 3),
            raster: const Duration(milliseconds: 5),
            total: const Duration(milliseconds: 8),
          );
      final suppressed = MemoryLogWriter();
      PerformanceLogger(
        style: PerfScopeLogStyle.compact,
        writer: suppressed,
      ).handleEvent(frameEvent(normalSample()));
      expect(suppressed.lines, isEmpty);

      final printed = MemoryLogWriter();
      PerformanceLogger(
        style: PerfScopeLogStyle.compact,
        writer: printed,
        printNormalFrames: true,
      ).handleEvent(frameEvent(normalSample()));
      expect(printed.lines.single, contains('PERF ProductList'));

      final viaVerbose = MemoryLogWriter();
      PerformanceLogger(
        style: PerfScopeLogStyle.compact,
        writer: viaVerbose,
        verbose: true,
      ).handleEvent(frameEvent(normalSample()));
      expect(viaVerbose.lines, hasLength(1));
    });

    test('warning frames follow printWarnings', () {
      FrameSample warningSample() => frameSample(
            id: 9,
            build: const Duration(microseconds: 12000),
            raster: const Duration(microseconds: 8000),
            total: const Duration(microseconds: 20000),
          );
      final off = MemoryLogWriter();
      PerformanceLogger(
        style: PerfScopeLogStyle.compact,
        writer: off,
      ).handleEvent(frameEvent(warningSample()));
      expect(off.lines, isEmpty);

      final on = MemoryLogWriter();
      PerformanceLogger(
        style: PerfScopeLogStyle.compact,
        writer: on,
        printWarnings: true,
      ).handleEvent(frameEvent(warningSample()));
      expect(on.lines.single, contains('WARNING'));
    });
  });

  group('PerformanceLogger report rendering', () {
    test('pretty summary contains the expected rows', () {
      final logger = PerformanceLogger(
        style: PerfScopeLogStyle.pretty,
        writer: MemoryLogWriter(),
      );
      final output = logger.renderReport(_report());
      expect(output, contains('PerfScope — Session Summary'));
      expect(output, contains('Duration'));
      expect(output, contains('0m 05s'));
      expect(output, contains('p50'));
      expect(output, contains('p90'));
      expect(output, contains('p95'));
      expect(output, contains('p99'));
      expect(output.endsWith('\n'), isFalse); // logger appends newline
    });

    test('compact summary is a one-liner', () {
      final logger = PerformanceLogger(
        style: PerfScopeLogStyle.compact,
        writer: MemoryLogWriter(),
      );
      final output = logger.renderReport(_report());
      expect(output.contains('\n'), isFalse);
      expect(output, startsWith('PERF SESSION 0m 05s | frames 0'));
    });

    test('json summary decodes as one line', () {
      final logger = PerformanceLogger(
        style: PerfScopeLogStyle.json,
        writer: MemoryLogWriter(),
      );
      final output = logger.renderReport(_report());
      expect(output.contains('\n'), isFalse);
      final map = output.isEmpty ? null : _decode(output);
      expect(map!['type'], 'performance_summary');
      expect(map['session_id'], 'ses_1');
    });
  });

  group('PerformanceLogger formatting helpers', () {
    test('formatSessionDuration tiers are deterministic', () {
      expect(
          PerformanceLogger.formatSessionDuration(
            const Duration(milliseconds: 42),
          ),
          '42ms');
      expect(
          PerformanceLogger.formatSessionDuration(
            const Duration(milliseconds: 900),
          ),
          '0.9s');
      expect(
          PerformanceLogger.formatSessionDuration(
            const Duration(seconds: 5),
          ),
          '0m 05s');
      expect(
          PerformanceLogger.formatSessionDuration(
            const Duration(minutes: 4, seconds: 32),
          ),
          '4m 32s');
    });
  });

  group('PerformanceLogger failure containment', () {
    test('throwing renderer internals never propagate', () {
      final logger = PerformanceLogger(
        style: PerfScopeLogStyle.json,
        writer: MemoryLogWriter(),
        sessionIdResolver: () => throw StateError('resolver exploded'),
      );
      expect(
        () => logger.handleEvent(anomalyEvent(uiBoundAnomaly())),
        returnsNormally,
      );
    });

    test('throwing writer never propagates', () {
      final logger = PerformanceLogger(
        style: PerfScopeLogStyle.pretty,
        writer: ThrowingWriter(),
      );
      expect(
        () => logger.handleEvent(anomalyEvent(uiBoundAnomaly())),
        returnsNormally,
      );
      expect(() => logger.renderReport(_report()), returnsNormally);
    });
  });
}

Map<String, dynamic> _decode(String line) =>
    jsonDecode(line) as Map<String, dynamic>;
