import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

bool _isDebugWarning(String line) =>
    line.contains('DEBUG mode') && line.contains('--profile');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PerfScope.resetForTest();
  });

  tearDown(() {
    PerfScope.resetForTest();
  });

  group('initialize', () {
    test('is idempotent and keeps a single engine instance', () {
      PerfScope.initialize();
      final first = PerfScope.debugEngine;

      PerfScope.initialize();

      expect(PerfScope.isEnabled, isTrue);
      expect(identical(first, PerfScope.debugEngine), isTrue);
    });

    test('redundant calls log an already-initialized line once per call', () {
      final log = MemoryLogWriter();
      PerfScope.initialize(logWriter: log);

      PerfScope.initialize(logWriter: log); // one redundant call -> one line

      expect(
        log.lines.where((line) => line.contains('already initialized')),
        hasLength(1),
      );
    });

    test('writes the debug-mode warning exactly once per process', () async {
      final log = MemoryLogWriter();
      PerfScope.initialize(logWriter: log);
      await PerfScope.dispose();
      PerfScope.initialize(config: const PerfScopeConfig(), logWriter: log);

      // Re-initialization must not duplicate the once-per-process warning
      // (flutter test always runs with kDebugMode == true).
      expect(log.lines.where(_isDebugWarning), hasLength(kDebugMode ? 1 : 0));
    });

    test('exposes an events stream that receives lifecycle events', () async {
      PerfScope.initialize();
      final received = <PerformanceEvent>[];
      PerfScope.events.listen(received.add);

      PerfScope.debugEngine!.handleLifecycle(AppLifecycleState.inactive);
      await pumpEventQueue();

      expect(received.single, isA<LifecycleEvent>());
    });
  });

  group('dispose / re-initialize', () {
    test('dispose disables PerfScope', () async {
      PerfScope.initialize();

      await PerfScope.dispose();

      expect(PerfScope.isEnabled, isFalse);
      expect(PerfScope.debugEngine, isNull);
    });

    test('re-initialize creates a fresh working engine', () async {
      PerfScope.initialize();
      final oldEngine = PerfScope.debugEngine;
      await PerfScope.dispose();

      PerfScope.initialize();
      final newEngine = PerfScope.debugEngine;

      expect(newEngine, isNotNull);
      expect(identical(oldEngine, newEngine), isFalse);
      expect(PerfScope.isEnabled, isTrue);

      // Fresh engine still functions end to end.
      final received = <PerformanceEvent>[];
      PerfScope.events.listen(received.add);
      newEngine!.handleLifecycle(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(received.single, isA<LifecycleEvent>());
    });

    test('events stream before initialization is empty but subscribable',
        () async {
      var got = false;
      PerfScope.events.listen((_) => got = true);
      await pumpEventQueue();

      expect(got, isFalse);
      expect(PerfScope.isEnabled, isFalse);
    });
  });

  group('context APIs without initialization', () {
    test('screen, interactions, and metadata are safe no-ops', () async {
      final handle = PerfScope.startInteraction('checkout');

      expect(() {
        PerfScope.screen('home');
        PerfScope.interaction('tap');
        PerfScope.setMetadata('k', 'v');
        PerfScope.removeMetadata('k');
        PerfScope.clearMetadata();
        handle.end(); // inert: must be safe without an engine.
      }, returnsNormally);

      expect(PerfScope.isEnabled, isFalse);
      expect(handle.id, isEmpty);
      expect(handle.hasEnded, isTrue);
      expect(PerfScope.currentScreen, 'unknown');
      expect(PerfScope.contextWindowFor('anm_1'), isNull);
      // Give any stray async work a chance to surface hidden errors.
      await pumpEventQueue();
    });
  });

  group('context APIs happy path', () {
    test('screen override, interactions, and metadata reach the engine',
        () async {
      final log = MemoryLogWriter();
      PerfScope.initialize(logWriter: log);
      final received = <PerformanceEvent>[];
      PerfScope.events.listen(received.add);

      PerfScope.screen('wizard', metadata: <String, Object?>{'step': 2});
      await pumpEventQueue();

      expect(PerfScope.currentScreen, 'wizard');
      final screens = received.whereType<ScreenEvent>().toList();
      expect(screens.single.reason, ScreenChangeReason.manual);
      expect(screens.single.name, 'wizard');
      expect(
        PerfScope.debugEngine!.metadataStore.snapshot(),
        containsPair('step', 2),
      );

      final handle = PerfScope.startInteraction('checkout');
      await pumpEventQueue();
      expect(handle.id, isNotEmpty);
      final starts = received.whereType<InteractionEvent>().toList();
      expect(starts.single.kind, InteractionEventKind.start);
      expect(starts.single.name, 'checkout');

      handle.end();
      PerfScope.interaction('tap_pay');
      await pumpEventQueue();
      final markers = received
          .whereType<InteractionEvent>()
          .where((e) => e.kind == InteractionEventKind.marker)
          .toList();
      expect(markers.length, 1);
      expect(markers.single.interactionId, isNotEmpty);

      PerfScope.setMetadata('flag', true);
      expect(
        PerfScope.debugEngine!.metadataStore.containsKey('flag'),
        isTrue,
      );
      PerfScope.removeMetadata('flag');
      PerfScope.clearMetadata();
      expect(PerfScope.debugEngine!.metadataStore.snapshot(), isEmpty);
    });

    test('metadata validation still fails fast while enabled', () {
      PerfScope.initialize(logWriter: MemoryLogWriter());

      expect(
        () => PerfScope.setMetadata('bad', Object()),
        throwsArgumentError,
      );
    });

    test('state resets fully between cases via resetForTest', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      PerfScope.setMetadata('leftover', 1);
      PerfScope.screen('stale');
      await PerfScope.dispose();

      expect(PerfScope.isEnabled, isFalse);
      expect(PerfScope.currentScreen, 'unknown');

      PerfScope.initialize(logWriter: MemoryLogWriter());
      expect(PerfScope.currentScreen, 'unknown');
      expect(
        PerfScope.debugEngine!.metadataStore.containsKey('leftover'),
        isFalse,
      );
    });
  });

  group('manual tracing', () {
    test('trace runs the body untraced when not initialized', () async {
      final received = <PerformanceEvent>[];
      PerfScope.events.listen(received.add);

      var bodyRuns = 0;
      final result = PerfScope.trace<String>('op', () {
        bodyRuns++;
        return 'value';
      }, metadata: {'k': 'v'});

      final asyncResult = await PerfScope.traceAsync<int>('aop', () async => 7);

      await pumpEventQueue();

      expect(result, 'value');
      expect(asyncResult, 7);
      expect(bodyRuns, 1);
      expect(received, isEmpty);
      expect(PerfScope.recentTraces, isEmpty);
      expect(PerfScope.anomalies, isEmpty);
      expect(PerfScope.isEnabled, isFalse);
    });

    test('traceAsync passthrough propagates body failures untouched', () async {
      final sentinel = StateError('uninitialized boom');

      Object? caught;
      try {
        await PerfScope.traceAsync<int>(
            'op', () => Future<int>.error(sentinel));
      } catch (error) {
        caught = error;
      }

      expect(caught, same(sentinel));
    });

    test('happy-path trace emits a TraceEvent through the facade', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      final received = <PerformanceEvent>[];
      PerfScope.events.listen(received.add);

      final result =
          PerfScope.trace<int>('checkout_op', () => 42, metadata: {'items': 3});
      await pumpEventQueue();

      expect(result, 42);
      final event = received.whereType<TraceEvent>().single;
      expect(event.name, 'checkout_op');
      expect(event.didThrow, isFalse);
      expect(event.metadata, {'items': 3});
      expect(event.traceId, startsWith('trc_'));

      expect(PerfScope.recentTraces.single.id, event.traceId);
      expect(PerfScope.anomalies, isEmpty); // fast trace: no anomaly
    });

    test('anomalies/recentTraces getters stay reachable while enabled',
        () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());

      // Reachability + typing contract: both getters answer while an
      // engine is live (the populated-anomaly path is covered
      // deterministically by the FakeClock-driven engine tests).
      expect(PerfScope.anomalies, isEmpty);
      expect(PerfScope.recentTraces, isEmpty);
      expect(PerfScope.contextWindowFor('anm_missing'), isNull);
    });
  });

  group('performance sessions', () {
    test('an auto-started session exists right after initialize', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue(); // engine.start() is fire-and-forget

      final session = PerfScope.currentSession;

      expect(session, isNotNull);
      expect(session!.isActive, isTrue);
      expect(session.id, startsWith('ses_'));
      expect(session.endedAt, isNull);
    });

    test('startSession(name) finalizes the auto session and opens a named one',
        () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final auto = PerfScope.currentSession!;

      final named = PerfScope.startSession('release-check');

      expect(named.id, isNot(auto.id));
      expect(named.name, 'release-check');
      expect(auto.isActive, isFalse);
      expect(auto.endedAt, isNotNull);
      // The auto-finalized session stays retrievable through the engine.
      expect(PerfScope.debugEngine!.lastFinishedSession, same(auto));
      expect(PerfScope.currentSession!.id, named.id);
    });

    test('stopSession returns a report and sets lastReport', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.currentSession!;

      final report = await PerfScope.stopSession();

      expect(report.session.id, session.id);
      // Deterministic: no frames were pushed through the facade.
      expect(report.statistics.totalFrames, 0);
      expect(session.endedAt, isNotNull);
      expect(PerfScope.lastReport, same(report));
      expect(PerfScope.currentSession, isNull);
    });

    test('consecutive stopSession calls throw StateError', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      await PerfScope.stopSession();

      expect(PerfScope.stopSession(), throwsStateError);
    });

    test('session getters are null and no-throw while disabled', () async {
      // No engine in this test (setUp reset the facade): getters must
      // answer null instead of throwing.
      expect(PerfScope.currentSession, isNull);
      expect(PerfScope.lastReport, isNull);

      // Explicit lifecycle APIs fail fast when there is no engine at all,
      // unlike the passive getters.
      expect(() => PerfScope.startSession(), throwsStateError);
      await expectLater(PerfScope.stopSession(), throwsStateError);
      await pumpEventQueue();
    });

    test('initialize(sinks:) wires raw events through to sinks', () async {
      final memorySink = MemorySink();
      PerfScope.initialize(
        logWriter: MemoryLogWriter(),
        sinks: <PerformanceEventSink>[memorySink],
      );
      await pumpEventQueue();

      // Interaction events dispatch synchronously, independent of frames.
      final handle = PerfScope.startInteraction('tap_product');
      handle.end();
      await pumpEventQueue();

      final interactions = memorySink.events.whereType<InteractionEvent>();
      expect(interactions, isNotEmpty);
      expect(
        interactions.any((e) => e.name == 'tap_product'),
        isTrue,
      );
    });

    test('stopSession writes a rendered report to the same writer', () async {
      final writer = MemoryLogWriter();
      PerfScope.initialize(logWriter: writer);
      await pumpEventQueue();

      PerfScope.startSession('report-check');
      final report = await PerfScope.stopSession();
      await pumpEventQueue();

      expect(report, isNotNull);
      // Default pretty style renders a summary box into the writer.
      final reportLines =
          writer.lines.where((l) => l.contains('Session Summary'));
      expect(reportLines, isNotEmpty);
    });
  });

  group('export (Phase 8)', () {
    test('stopSession attaches the report to the finished session', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.currentSession!;
      expect(session.attachedReport, isNull);

      final report = await PerfScope.stopSession();

      expect(session.attachedReport, same(report));
    });

    test('auto-finalize attaches a report to the retired session', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final first = PerfScope.currentSession!;

      PerfScope.startSession('replacement');

      expect(first.isActive, isFalse);
      expect(first.attachedReport, isNotNull);
      expect(first.attachedReport!.session.id, first.id);
      // Auto-finalize deliberately does NOT publish lastReport.
      expect(PerfScope.lastReport?.session.id, isNot(first.id));
    });

    test('export flows end-to-end through InMemoryExporter', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final exporter = InMemoryExporter();

      await PerfScope.export(exporter: exporter);

      expect(exporter.count, 1);
      final doc = jsonDecode(exporter.lastJson!) as Map<Object?, Object?>;
      expect(doc[kKeySchemaVersion], 1);
      expect(
        (doc[kKeyGenerator]! as Map<Object?, Object?>)[kKeyName],
        'perfscope',
      );
      expect((doc[kKeySession]! as Map<Object?, Object?>)[kKeyId],
          PerfScope.currentSession!.id);

      // Round-trips through the public parser as well.
      final parsed = SessionParser().parseString(exporter.lastJson!);
      expect(parsed.session.id, PerfScope.currentSession!.id);
    });

    test('exportCurrentSessionAsJson returns a parseable v1 document',
        () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();

      final json = PerfScope.exportCurrentSessionAsJson();

      expect(json, isNotNull);
      final doc = jsonDecode(json!) as Map<Object?, Object?>;
      expect(doc[kKeySchemaVersion], 1);
      expect(doc[kKeyAnomalies], isEmpty);
    });

    test(
        'exportCurrentSessionAsJson survives stopSession via the '
        'last-finished-session fallback', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.startSession('post-stop-export');

      // No open session after the stop: the wart this test pins down used
      // to make the export return null here.
      final report = await PerfScope.stopSession();
      expect(PerfScope.currentSession, isNull);

      final json = PerfScope.exportCurrentSessionAsJson();
      expect(json, isNotNull);
      final doc = jsonDecode(json!) as Map<Object?, Object?>;
      expect(doc[kKeySchemaVersion], 1);
      expect(
        ((doc[kKeySession]! as Map<Object?, Object?>))[kKeyId],
        session.id,
      );
      // Round-trips through the public parser.
      expect(SessionParser().parseString(json).session.id, report.session.id);

      // Auto-finalize also attaches a report, so a replacement start keeps
      // the previous session exportable through the same fallback.
      PerfScope.startSession('replacement');
      expect(PerfScope.currentSession!.name, 'replacement');
      final retiredJson = PerfScope.exportCurrentSessionAsJson();
      expect(retiredJson, isNotNull);
      // The OPEN session wins when one exists.
      final openDoc = jsonDecode(retiredJson!) as Map<Object?, Object?>;
      final openSession = openDoc[kKeySession]! as Map<Object?, Object?>;
      expect(openSession[kKeyId], isNot(session.id));
    });

    test('exports isolate between tests via resetForTest', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final exporterA = InMemoryExporter();
      await PerfScope.export(exporter: exporterA);
      expect(exporterA.count, 1);

      await PerfScope.dispose();
      PerfScope.resetForTest();

      expect(PerfScope.exportCurrentSessionAsJson(), isNull);
    });
  });

  group('compareSessions', () {
    test('delegates to the pure comparator without an engine', () {
      // Pure facade entry point: no initialize() required.
      expect(PerfScope.isEnabled, isFalse);

      final before = _comparisonReport('baseline');
      final after = _comparisonReport('candidate');

      final comparison = PerfScope.compareSessions(before, after);

      expect(identical(comparison.before, before), isTrue);
      expect(identical(comparison.after, after), isTrue);
      expect(comparison.overall.map((m) => m.label), contains('p95'));
    });
  });
}

/// Minimal hand-built report for the compareSessions smoke test.
PerformanceReport _comparisonReport(String name) {
  return PerformanceReport(
    session: PerformanceSession(
      id: 'ses_$name',
      name: name,
      startedAt: DateTime.utc(2026, 2, 1, 9),
      environment: const PerformanceEnvironment(
        frameBudgetFps: 60.0,
        frameBudgetMs: 16.667,
        frameBudgetSource: FrameBudgetSource.detected,
        platform: 'test',
      ),
      calculator: StatisticsCalculator(),
      anomalies: const [],
    ),
    statistics: const SessionStatistics(
      totalFrames: 1000,
      normalFrames: 900,
      warningFrames: 0,
      slowFrames: 80,
      severeFrames: 20,
      slowFrameRate: 0.1,
      averageBuildMs: 7.455,
      averageRasterMs: 8.909,
      averageTotalMs: 16.364,
      p50Ms: 8.0,
      p90Ms: 16.0,
      p95Ms: 20.0,
      p99Ms: 40.0,
      worstFrameMs: 80.0,
    ),
    screens: [
      const ScreenPerformanceSummary(
        name: 'Home',
        totalFrames: 500,
        slowFrames: 20,
        severeFrames: 5,
        anomalyCount: 4,
        slowFrameRate: 0.05,
        p95Ms: 20.0,
        worstMs: 40.0,
        probableBottleneck: FrameBottleneck.ui,
      ),
    ],
    interactions: const [],
    traces: const [],
    anomalies: const [],
    worstAnomalies: const [],
  );
}
