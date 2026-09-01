import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/src/testing/fake_frame_source.dart';

import '../helpers/fake_clock.dart';

const _budget60 = Duration(microseconds: 16667);
const _parser = SessionParser();
const _serializer = SessionSerializer();

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

/// Same scripted scenario as the serializer test, plus metadata set
/// BEFORE the session starts so its snapshot carries every allowed
/// primitive shape for the round-trip.
Future<(PerfScopeEngine, PerformanceReport)> _runScenario() async {
  final source = FakeFrameSource();
  final clock = FakeClock();
  final engine = PerfScopeEngine(
    config: const PerfScopeConfig(),
    frameSource: source,
    clock: clock,
    logWriter: MemoryLogWriter(),
  );
  engine.setMetadata('label', 'regression-run');
  engine.setMetadata('build_number', 42);
  engine.setMetadata('cpu_load', 0.75);
  engine.setMetadata('debug', false);
  engine.setMetadata('tags', <String>['cpu', 'gpu']);
  engine.setMetadata('extra', <String, Object?>{'depth': 2});
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
  return (engine, report);
}

/// Tolerance for ms values: serialization rounds to 3 decimals and parsing
/// multiplies back to whole microseconds, so 0.002 ms is generous.
const _msTolerance = 0.002;

void main() {
  group('SessionParser round-trip', () {
    test('restores statistics within tolerance', () async {
      final (_, report) = await _runScenario();
      final json = _serializer.serializeToString(report);
      final parsed = _parser.parseString(json);

      final original = report.statistics;
      final restored = parsed.statistics;
      expect(restored.totalFrames, original.totalFrames);
      expect(restored.normalFrames, original.normalFrames);
      expect(restored.warningFrames, original.warningFrames);
      expect(restored.slowFrames, original.slowFrames);
      expect(restored.severeFrames, original.severeFrames);
      expect(restored.slowFrameRate, closeTo(original.slowFrameRate, 1e-9));
      expect(restored.averageBuildMs,
          closeTo(original.averageBuildMs, _msTolerance));
      expect(restored.averageRasterMs,
          closeTo(original.averageRasterMs, _msTolerance));
      expect(restored.averageTotalMs,
          closeTo(original.averageTotalMs, _msTolerance));
      expect(restored.p50Ms, closeTo(original.p50Ms, _msTolerance));
      expect(restored.p90Ms, closeTo(original.p90Ms, _msTolerance));
      expect(restored.p95Ms, closeTo(original.p95Ms, _msTolerance));
      expect(restored.p99Ms, closeTo(original.p99Ms, _msTolerance));
      expect(
          restored.worstFrameMs, closeTo(original.worstFrameMs, _msTolerance));
    });

    test('restores session identity, environment, and metadata', () async {
      final (engine, report) = await _runScenario();
      final parsed = _parser.parseString(_serializer.serializeToString(
        report,
        resolveContextWindow: engine.contextWindowFor,
      ));

      final originalSession = report.session;
      final parsedSession = parsed.session;
      // Parsed snapshots are inert copies; a finished document yields an
      // inactive session either way.
      expect(parsedSession.id, originalSession.id);
      expect(parsedSession.name, originalSession.name);
      expect(parsedSession.isActive, isFalse);
      // Timestamps compare by instant: the wire format normalizes to UTC.
      expect(parsedSession.startedAt.microsecondsSinceEpoch,
          originalSession.startedAt.toUtc().microsecondsSinceEpoch);
      expect(parsedSession.endedAt!.microsecondsSinceEpoch,
          originalSession.endedAt!.toUtc().microsecondsSinceEpoch);
      expect(parsedSession.environment, originalSession.environment);
      expect(parsedSession.metadata, <String, Object?>{
        'label': 'regression-run',
        'build_number': 42,
        'cpu_load': 0.75,
        'debug': false,
        'tags': ['cpu', 'gpu'],
        'extra': {'depth': 2},
      });
      // The parser froze the decoded summary into the inert session...
      expect(parsedSession.statistics(), equals(parsed.statistics));
      // ...and attached the reconstructed report to it.
      expect(parsedSession.attachedReport, same(parsed));
      expect(parsedSession.anomalies.map((a) => a.id).toList(),
          parsed.anomalies.map((a) => a.id).toList());
    });

    test('restores screen summaries in order with equal counts', () async {
      final (_, report) = await _runScenario();
      final parsed = _parser.parseString(_serializer.serializeToString(report));

      expect(parsed.screens.map((s) => s.name).toList(),
          report.screens.map((s) => s.name).toList());
      for (var i = 0; i < report.screens.length; i++) {
        final original = report.screens[i];
        final restored = parsed.screens[i];
        expect(restored.totalFrames, original.totalFrames,
            reason: original.name);
        expect(restored.slowFrames, original.slowFrames, reason: original.name);
        expect(restored.severeFrames, original.severeFrames,
            reason: original.name);
        expect(restored.anomalyCount, original.anomalyCount,
            reason: original.name);
        expect(restored.slowFrameRate, closeTo(original.slowFrameRate, 1e-9),
            reason: original.name);
        expect(restored.p95Ms, closeTo(original.p95Ms, _msTolerance),
            reason: original.name);
        expect(restored.worstMs, closeTo(original.worstMs, _msTolerance),
            reason: original.name);
        expect(restored.probableBottleneck, original.probableBottleneck,
            reason: original.name);
      }
    });

    test('restores interaction summaries', () async {
      final (_, report) = await _runScenario();
      final parsed = _parser.parseString(_serializer.serializeToString(report));

      expect(parsed.interactions, hasLength(report.interactions.length));
      final original = report.interactions.single;
      final restored = parsed.interactions.single;
      expect(restored.name, original.name);
      expect(
          restored.mostRecentInteractionId, original.mostRecentInteractionId);
      expect(restored.spanCount, original.spanCount);
      expect(restored.frameCount, original.frameCount);
      expect(restored.anomalyCount, original.anomalyCount);
      expect(restored.totalSpanDuration, original.totalSpanDuration);
      expect(restored.p95Ms, closeTo(original.p95Ms, _msTolerance));
      expect(restored.worstMs, closeTo(original.worstMs, _msTolerance));
      expect(restored.probableBottleneck, original.probableBottleneck);
    });

    test('restores traces', () async {
      final (_, report) = await _runScenario();
      final parsed = _parser.parseString(_serializer.serializeToString(report));

      expect(parsed.traces, hasLength(report.traces.length));
      final original = report.traces.single;
      final restored = parsed.traces.single;
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.screen, original.screen);
      expect(restored.didThrow, original.didThrow);
      expect(
        restored.duration.inMicroseconds,
        inInclusiveRange(original.duration.inMicroseconds - 1,
            original.duration.inMicroseconds + 1),
      );
      expect(restored.startedAt.microsecondsSinceEpoch,
          original.startedAt.toUtc().microsecondsSinceEpoch);
    });

    test('reconstructs concrete anomaly subtypes with attribution', () async {
      final (_, report) = await _runScenario();
      final parsed = _parser.parseString(
        _serializer.serializeToString(
          report,
          resolveContextWindow: (id) =>
              null, // windows are intentionally NOT reconstructed
        ),
      );

      expect(parsed.anomalies.map((a) => a.id).toList(),
          report.anomalies.map((a) => a.id).toList());

      final ui = parsed.anomalies[0];
      expect(ui, isA<UiBoundFrameAnomaly>());
      expect(ui.severity, AnomalySeverity.high);
      expect(ui.screen, 'screen_a');

      final mixed = parsed.anomalies[1];
      expect(mixed, isA<MixedFrameAnomaly>());
      expect(mixed.severity, AnomalySeverity.critical);

      final raster = parsed.anomalies[2];
      expect(raster, isA<RasterBoundFrameAnomaly>());
      expect(raster.screen, 'screen_b');
      expect(raster.interactionId,
          report.interactions.single.mostRecentInteractionId);

      final longTrace = parsed.anomalies[3];
      expect(longTrace, isA<LongTraceAnomaly>());
      expect(longTrace.severity, AnomalySeverity.high);
      expect((longTrace as LongTraceAnomaly).name, 'load_catalog');
      expect(longTrace.traceId, report.traces.single.id);
      expect(longTrace.duration.inMilliseconds, 120);
      expect(longTrace.metadata, isEmpty);

      // Frame anomalies keep their probable bottleneck via classification.
      expect((ui as FrameAnomaly).bottleneck, FrameBottleneck.ui);
      expect((raster as FrameAnomaly).bottleneck, FrameBottleneck.raster);
      expect(
        ui.sample.totalDuration.inMicroseconds,
        inInclusiveRange(31999, 32001),
      );

      // worstAnomalies ranking is rebuilt deterministically, matching the
      // original report's ordering.
      expect(parsed.worstAnomalies.map((a) => a.id).toList(),
          report.worstAnomalies.map((a) => a.id).toList());
    });
  });

  group('SessionParser tolerance cases', () {
    test('accepts ended_at-less documents (mid-session export)', () async {
      final (_, report) = await _runScenario();
      final doc = _serializer.serialize(report);
      (doc[kKeySession]! as Map<Object?, Object?>).remove(kKeyEndedAt);

      final parsed = _parser.parse(doc);

      expect(parsed.session.isActive, isTrue); // documented inert semantics
      expect(parsed.session.endedAt, isNull);
      expect(parsed.session.attachedReport, same(parsed));
    });

    test('ignores unknown extra top-level keys (forward compatibility)',
        () async {
      final (_, report) = await _runScenario();
      final doc = _serializer.serialize(report);
      doc['future_extension'] = <String, Object?>{
        'new_thing': [1, 2],
      };

      expect(() => _parser.parse(doc), returnsNormally);
    });

    test('rejects unknown anomaly type strings naming the offender', () async {
      final (_, report) = await _runScenario();
      final doc = _serializer.serialize(report);
      ((doc[kKeyAnomalies]! as List<Object?>).first!
          as Map<Object?, Object?>)[kKeyType] = 'quantum_jank';

      expect(
        () => _parser.parse(doc),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('quantum_jank'),
        )),
      );
    });

    test('rejects invalid metadata with FormatException, never TypeError',
        () async {
      final (_, report) = await _runScenario();
      final doc = _serializer.serialize(report);
      // JSON-representable but outside the metadata allow-list: nested
      // collections are forbidden at depth > 1.
      (doc[kKeySession]! as Map<Object?, Object?>)[kKeyMetadata] =
          <String, Object?>{
        'nested': <Object?>[
          <Object?>[1]
        ],
      };

      expect(
        () => _parser.parse(doc),
        throwsA(isA<FormatException>()),
      );
      try {
        _parser.parse(jsonDecode(jsonEncode(doc))! as Map<String, Object?>);
        fail('expected FormatException');
      } on FormatException catch (error) {
        expect(error.message, contains('session.metadata'));
      } on TypeError {
        fail('metadata validation must not leak TypeError');
      }
    });
  });
}
