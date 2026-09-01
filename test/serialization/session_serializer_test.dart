import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/src/testing/fake_frame_source.dart';

import '../helpers/fake_clock.dart';

const _budget60 = Duration(microseconds: 16667);

FrameSample _normal(int id) => _sample(id,
    build: const Duration(milliseconds: 3),
    raster: const Duration(milliseconds: 5));

FrameSample _slowUi(int id) => _sample(id,
    build: const Duration(milliseconds: 28),
    raster: const Duration(milliseconds: 4));

FrameSample _slowRaster(int id) => _sample(id,
    build: const Duration(milliseconds: 4),
    raster: const Duration(milliseconds: 28));

FrameSample _severeMixed(int id) => _sample(id,
    build: const Duration(milliseconds: 26),
    raster: const Duration(milliseconds: 26));

FrameSample _sample(
  int id, {
  required Duration build,
  required Duration raster,
}) {
  return FrameSample(
    id: id,
    frameNumber: id,
    capturedAt: DateTime.fromMicrosecondsSinceEpoch(1700000000000000 + id),
    buildDuration: build,
    rasterDuration: raster,
    totalDuration: build + raster,
    vsyncOverhead: Duration.zero,
    frameBudget: _budget60,
    screen: null,
    interactionId: null,
  );
}

const _serializer = SessionSerializer();

void main() {
  group('SessionSerializer scripted engine report', () {
    test('produces the full v1 document shape with generator constants',
        () async {
      final source = FakeFrameSource();
      final clock = FakeClock();
      final engine = PerfScopeEngine(
        config: const PerfScopeConfig(),
        frameSource: source,
        clock: clock,
        logWriter: MemoryLogWriter(),
      );
      await engine.start();

      engine.overrideScreen('screen_a');
      source.emitAll([
        _normal(1),
        _normal(2),
        _normal(3),
        _normal(4),
        _normal(5),
        _normal(6),
        _slowUi(7), // anm_1
        _severeMixed(8), // anm_2
      ]);
      // Deliver the queued frames BEFORE switching screens so their
      // attribution reflects screen_a.
      await pumpEventQueue();
      final handle = engine.startInteraction('checkout');
      engine.overrideScreen('screen_b');
      source.emitAll([_normal(9), _normal(10)]);
      source.emit(_slowRaster(11)); // anm_3
      await pumpEventQueue();
      clock.advance(const Duration(milliseconds: 30));
      handle.end();
      await pumpEventQueue();
      engine.trace('load_catalog', () {
        clock.advance(const Duration(milliseconds: 120));
      }); // anm_4
      await pumpEventQueue();

      final report = await engine.stopSession();
      final doc = _serializer.serialize(report);

      // --- Top-level structure ------------------------------------------
      expect(
        doc.keys.toList(),
        containsAllInOrder(<String>[
          kKeySchemaVersion,
          kKeyGenerator,
          kKeySession,
          kKeyEnvironment,
          kKeySummary,
          kKeyScreens,
          kKeyInteractions,
          kKeyTraces,
          kKeyAnomalies,
        ]),
      );
      expect(doc[kKeySchemaVersion], kSchemaVersion);
      expect(kSchemaVersion, 1);
      expect(doc[kKeyGenerator], <String, Object?>{
        kKeyName: 'perfscope',
        kKeyVersion: '0.1.0',
      });
      expect(kGeneratorName, 'perfscope');
      expect(kGeneratorVersion, '0.1.0');

      // --- Session block --------------------------------------------------
      final session = doc[kKeySession] as Map<Object?, Object?>;
      expect(session[kKeyId], report.session.id);
      expect(session[kKeyName], isNull); // session started without a name
      expect(
        session[kKeyStartedAt],
        report.session.startedAt.toUtc().toIso8601String(),
      );
      expect(
        session[kKeyEndedAt],
        report.session.endedAt!.toUtc().toIso8601String(),
      );
      expect(session[kKeyMetadata], <String, Object?>{});

      // --- Environment block ------------------------------------------------
      final environment = doc[kKeyEnvironment] as Map<Object?, Object?>;
      expect(environment[kKeyPlatform], report.session.environment.platform);
      expect(
        environment[kKeyFrameBudgetFps],
        report.session.environment.frameBudgetFps,
      );
      expect(
        environment[kKeyFrameBudgetMs],
        report.session.environment.frameBudgetMs,
      );
      expect(
        environment[kKeyFrameBudgetSource],
        report.session.environment.frameBudgetSource.name,
      );

      // --- Summary block (hand-computed in performance_report_test) -----
      final summary = doc[kKeySummary] as Map<Object?, Object?>;
      expect(summary[kKeyTotalFrames], 11);
      expect(summary[kKeyNormalFrames], 8);
      expect(summary[kKeyWarningFrames], 0);
      expect(summary[kKeySlowFrames], 2);
      expect(summary[kKeySevereFrames], 1);
      expect(summary[kKeySlowFrameRate], closeTo(3 / 11, 1e-9));
      expect(summary[kKeyAverageBuildMs], 7.455);
      expect(summary[kKeyAverageRasterMs], 8.909);
      expect(summary[kKeyAverageTotalMs], 16.364);
      expect(summary[kKeyP50Ms], 8.0);
      expect(summary[kKeyP90Ms], 32.0);
      expect(summary[kKeyP95Ms], 52.0);
      expect(summary[kKeyP99Ms], 52.0);
      expect(summary[kKeyWorstFrameMs], 52.0);

      // --- Screens --------------------------------------------------------
      final screens = doc[kKeyScreens] as List<Object?>;
      expect(screens, hasLength(2));
      final a = screens[0] as Map<Object?, Object?>;
      expect(a[kKeyName], 'screen_a');
      expect(a[kKeyTotalFrames], 8);
      expect(a[kKeySlowFrames], 1);
      expect(a[kKeySevereFrames], 1);
      expect(a[kKeyAnomalyCount], 2);
      expect(a[kKeySlowFrameRate], closeTo(2 / 8, 1e-9));
      expect(a[kKeyP95Ms], 52.0);
      expect(a[kKeyWorstMs], 52.0);
      expect(a[kKeyProbableBottleneck], 'ui');
      final b = screens[1] as Map<Object?, Object?>;
      expect(b[kKeyName], 'screen_b');
      expect(b[kKeyTotalFrames], 3);
      expect(b[kKeyAnomalyCount], 2);
      expect(b[kKeyProbableBottleneck], 'raster');

      // --- Interactions -----------------------------------------------------
      final interactions = doc[kKeyInteractions] as List<Object?>;
      expect(interactions, hasLength(1));
      final checkout = interactions.single as Map<Object?, Object?>;
      expect(checkout[kKeyName], 'checkout');
      expect(checkout[kKeyMostRecentInteractionId], startsWith('iax_'));
      expect(checkout[kKeySpanCount], 1);
      expect(checkout[kKeyFrameCount], 3);
      expect(checkout[kKeyAnomalyCount], 1);
      expect(checkout[kKeyTotalSpanDurationMs], 30.0);
      expect(checkout[kKeyP95Ms], 32.0);
      expect(checkout[kKeyWorstMs], 32.0);
      expect(checkout[kKeyProbableBottleneck], 'raster');

      // --- Traces -----------------------------------------------------------
      final traces = doc[kKeyTraces] as List<Object?>;
      expect(traces, hasLength(1));
      final trace = traces.single as Map<Object?, Object?>;
      expect(trace[kKeyId], startsWith('trc_'));
      expect(trace[kKeyName], 'load_catalog');
      expect(trace[kKeyDurationMs], 120.0);
      expect(trace[kKeyScreen], 'screen_b');
      expect(trace[kKeyDidThrow], false);

      // --- Anomalies --------------------------------------------------------
      final anomalies = doc[kKeyAnomalies] as List<Object?>;
      expect(anomalies, hasLength(4));
      final a1 = anomalies[0] as Map<Object?, Object?>;
      expect(a1[kKeyId], 'anm_1');
      expect(a1[kKeyType], kAnomalyTypeUiBoundFrame);
      expect(a1[kKeySeverity], 'high');
      expect(a1[kKeyScreen], 'screen_a');
      expect((a1[kKeyFrame]! as Map<Object?, Object?>)[kKeyTotalMs], 32.0);
      expect(a1[kKeyProbableBottleneck], 'ui');
      final a2 = anomalies[1] as Map<Object?, Object?>;
      expect(a2[kKeyType], kAnomalyTypeMixedFrame);
      expect(a2[kKeySeverity], 'critical');
      final a3 = anomalies[2] as Map<Object?, Object?>;
      expect(a3[kKeyType], kAnomalyTypeRasterBoundFrame);
      expect(a3[kKeyInteractionId], checkout[kKeyMostRecentInteractionId]);
      final a4 = anomalies[3] as Map<Object?, Object?>;
      expect(a4[kKeyType], kAnomalyTypeLongTrace);
      expect(a4[kKeySeverity], 'high'); // 120ms >= 2x threshold(50ms)
      expect(a4[kKeyTraceId], trace[kKeyId]);
      expect(a4[kKeyName], 'load_catalog');
      expect(a4[kKeyDurationMs], 120.0);
      expect(a4.containsKey(kKeyFrame), isFalse);
    });

    test('serializeToString is byte-deterministic', () async {
      final source = FakeFrameSource();
      final clock = FakeClock();
      final engine = PerfScopeEngine(
        config: const PerfScopeConfig(),
        frameSource: source,
        clock: clock,
        logWriter: MemoryLogWriter(),
      );
      await engine.start();
      source.emitAll([_normal(1), _slowUi(2)]);
      await pumpEventQueue();
      final report = await engine.stopSession();

      final first = _serializer.serializeToString(report);
      final second = _serializer.serializeToString(report);
      expect(first, second);
      expect(first.contains('\n'), isFalse); // single line
    });
  });

  group('SessionSerializer anomaly discriminator coverage', () {
    test('all five anomaly families serialize under their type string', () {
      final timestamp = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

      FrameAnomaly anomalyFor(FrameBottleneck bottleneck) {
        final sample = FrameSample(
          id: 1,
          frameNumber: null,
          capturedAt: timestamp,
          buildDuration: bottleneck == FrameBottleneck.raster
              ? Duration.zero
              : const Duration(milliseconds: 28),
          rasterDuration: bottleneck == FrameBottleneck.ui
              ? Duration.zero
              : const Duration(milliseconds: 4),
          totalDuration: const Duration(milliseconds: 32),
          vsyncOverhead: Duration.zero,
          frameBudget: _budget60,
          screen: null,
          interactionId: null,
        );
        return createFrameAnomaly(
          id: 'anm_${bottleneck.name}',
          timestamp: timestamp,
          sample: sample,
          classification: FrameClassification(FrameSeverity.slow, bottleneck),
        );
      }

      final unknownPhases = FrameSample(
        id: 2,
        frameNumber: null,
        capturedAt: timestamp,
        buildDuration: Duration.zero,
        rasterDuration: Duration.zero,
        totalDuration: const Duration(milliseconds: 40),
        vsyncOverhead: Duration.zero,
        frameBudget: _budget60,
        screen: null,
        interactionId: null,
      );
      final slowUnknown = createFrameAnomaly(
        id: 'anm_unknown',
        timestamp: timestamp,
        sample: unknownPhases,
        classification:
            FrameClassification(FrameSeverity.slow, FrameBottleneck.unknown),
      );
      final longTrace = LongTraceAnomaly(
        id: 'anm_long',
        timestamp: timestamp,
        severity: AnomalySeverity.high,
        traceId: 'trc_9',
        name: 'op',
        duration: const Duration(milliseconds: 120),
        metadata: {'k': 'v'},
      );

      final session = PerformanceSession(
        id: 'ses_x',
        name: null,
        startedAt: timestamp,
        environment: PerformanceEnvironment(
          frameBudgetFps: 60.0,
          frameBudgetMs: 16.667,
          frameBudgetSource: FrameBudgetSource.fallback,
          platform: 'test',
        ),
        calculator: StatisticsCalculator(),
        anomalies: <PerformanceAnomaly>[],
      );
      final report = buildPerformanceReport(
        session: session,
        statistics: SessionStatistics.zero,
        screenAccumulators: const [],
        interactionAccumulators: const [],
        traces: const [],
        anomalies: [
          slowUnknown,
          anomalyFor(FrameBottleneck.ui),
          anomalyFor(FrameBottleneck.raster),
          anomalyFor(FrameBottleneck.mixed),
          longTrace,
        ],
      );

      final anomalies =
          (_serializer.serialize(report)[kKeyAnomalies]! as List<Object?>)
              .cast<Map<Object?, Object?>>();

      expect(anomalies.map((e) => e[kKeyType]).toList(), [
        kAnomalyTypeSlowFrame,
        kAnomalyTypeUiBoundFrame,
        kAnomalyTypeRasterBoundFrame,
        kAnomalyTypeMixedFrame,
        kAnomalyTypeLongTrace,
      ]);
      for (final entry in anomalies.take(4)) {
        final frame = entry[kKeyFrame]! as Map<Object?, Object?>;
        expect(
            frame.keys,
            containsAll(
                [kKeyBuildMs, kKeyRasterMs, kKeyTotalMs, kKeyBudgetMs]));
        expect(entry.containsKey(kKeyTraceId), isFalse);
      }
      expect(anomalies[4][kKeyTraceId], 'trc_9');
      expect(anomalies[4][kKeyMetadata], {'k': 'v'});
    });
  });

  group('SessionSerializer context windows', () {
    test('complete windows embedded, pending skipped, resolver-less omits',
        () async {
      final source = FakeFrameSource();
      final clock = FakeClock();
      final engine = PerfScopeEngine(
        config: const PerfScopeConfig(),
        frameSource: source,
        clock: clock,
        logWriter: MemoryLogWriter(),
      );
      await engine.start();

      engine.overrideScreen('ctx');
      source.emitAll([_normal(1), _normal(2)]);
      source.emit(_slowUi(3)); // anm_1 opens a window wanting 5 after-frames
      // Exactly 5 following frames complete anm_1's window...
      source.emitAll([
        _normal(4),
        _normal(5),
        _normal(6),
        _normal(7),
        _normal(8),
      ]);
      // ...and this last anomalous frame's window can never complete.
      source.emit(_slowRaster(9)); // anm_2
      await pumpEventQueue();

      final report = await engine.stopSession();
      expect(engine.contextWindowFor('anm_1')!.isComplete, isTrue);
      expect(engine.contextWindowFor('anm_2')!.isComplete, isFalse);

      final withoutResolver = _serializer.serialize(report);
      var anomalies = withoutResolver[kKeyAnomalies]! as List<Object?>;
      expect(
        anomalies.any((a) =>
            (a! as Map<Object?, Object?>).containsKey(kKeyContextWindow)),
        isFalse,
      );

      final withResolver = _serializer.serialize(
        report,
        resolveContextWindow: engine.contextWindowFor,
      );
      anomalies = withResolver[kKeyAnomalies]! as List<Object?>;
      final a1 = anomalies[0] as Map<Object?, Object?>;
      final a2 = anomalies[1] as Map<Object?, Object?>;

      expect(a1.containsKey(kKeyContextWindow), isTrue);
      final window = a1[kKeyContextWindow]! as Map<Object?, Object?>;
      final before = window[kKeyBefore]! as List<Object?>;
      final after = window[kKeyAfter]! as List<Object?>;
      expect(before, hasLength(2)); // only f1..f2 preceded anm_1
      expect(after, hasLength(5)); // f4..f8 completed the after-window
      for (final entry in before.followedBy(after)) {
        // Compact frame entries carry exactly the three phase durations.
        expect((entry! as Map<Object?, Object?>).keys.toList(),
            unorderedEquals([kKeyBuildMs, kKeyRasterMs, kKeyTotalMs]));
      }
      expect(before.first != null, isTrue);
      expect((before.first! as Map<Object?, Object?>)[kKeyTotalMs],
          8.0); // normal frame: 3+5ms

      // Pending windows are skipped silently.
      expect(a2.containsKey(kKeyContextWindow), isFalse);
    });

    test('mid-session export falls back to a minimal session-only report',
        () async {
      final source = FakeFrameSource();
      final clock = FakeClock();
      final engine = PerfScopeEngine(
        config: const PerfScopeConfig(),
        frameSource: source,
        clock: clock,
        logWriter: MemoryLogWriter(),
      );
      await engine.start();
      engine.overrideScreen('live');
      source.emit(_slowUi(1));
      await pumpEventQueue();

      final session = engine.currentSession!;
      expect(session.attachedReport, isNull);

      final json = _serializer.serializeToString(reportForExport(session));
      final doc = jsonDecode(json)! as Map<Object?, Object?>;
      final summary = doc[kKeySummary]! as Map<Object?, Object?>;
      expect(summary[kKeyTotalFrames], 1);
      expect(summary[kKeySlowFrames], 1);
      // No breakdowns exist mid-session; the anomaly IS attributed.
      expect(doc[kKeyScreens], isEmpty);
      expect(doc[kKeyInteractions], isEmpty);
      expect(doc[kKeyTraces], isEmpty);
      expect(doc[kKeyAnomalies], hasLength(1));
    });
  });
}
