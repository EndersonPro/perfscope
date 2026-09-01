import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/src/testing/fake_frame_source.dart';

import '../helpers/fake_clock.dart';

const _budget60 = Duration(microseconds: 16667);

/// Normal frame: comfortably within budget.
FrameSample _normal(int id) => _sample(id,
    build: const Duration(milliseconds: 3),
    raster: const Duration(milliseconds: 5));

/// Slow frame whose UI thread dominates (>2x raster): ui bottleneck.
FrameSample _slowUi(int id) => _sample(id,
    build: const Duration(milliseconds: 28),
    raster: const Duration(milliseconds: 4));

/// Slow frame whose raster thread dominates (>2x build): raster bottleneck.
FrameSample _slowRaster(int id) => _sample(id,
    build: const Duration(milliseconds: 4),
    raster: const Duration(milliseconds: 28));

/// Severe frame split evenly across both threads: mixed bottleneck.
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

PerfScopeEngine _engine(FakeFrameSource source,
        {PerfScopeConfig? config, LogWriter? logWriter}) =>
    PerfScopeEngine(
      config: config ?? const PerfScopeConfig(),
      frameSource: source,
      clock: FakeClock(),
      logWriter: logWriter ?? MemoryLogWriter(),
    );

void main() {
  group('PerfScopeEngine frame anomalies', () {
    test('normal frame streams produce no anomalies', () async {
      final source = FakeFrameSource();
      final engine = _engine(source);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);
      await engine.start();

      source.emitAll([_normal(1), _normal(2), _normal(3)]);
      await pumpEventQueue();

      expect(engine.anomalies, isEmpty);
      expect(events.whereType<AnomalyEvent>(), isEmpty);
      expect(engine.contextWindowFor('anm_1'), isNull);
    });

    test('slow UI-bound frame mid-stream opens a filling context window',
        () async {
      final source = FakeFrameSource();
      final engine = _engine(source); // defaults: 5 before / 5 after
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);
      await engine.start();

      source.emitAll([_normal(1), _normal(2), _normal(3), _normal(4)]);
      source.emit(_slowUi(5));
      await pumpEventQueue();

      // Exactly one AnomalyEvent carrying a UiBoundFrameAnomaly.
      final anomalyEvents = events.whereType<AnomalyEvent>().toList();
      expect(anomalyEvents.length, 1);
      final anomaly = anomalyEvents.single.anomaly as UiBoundFrameAnomaly;
      expect(anomaly.id, 'anm_1');
      expect(anomaly.severity, AnomalySeverity.high);
      expect(anomaly.sample.id, 5);

      // Before-window: the previous real frames, chronological order.
      final window = engine.contextWindowFor('anm_1')!;
      expect(window.before.map((s) => s.id).toList(), [1, 2, 3, 4]);
      expect(window.anomaly.id, 5);
      expect(window.isComplete, isFalse);
      expect(window.after, isEmpty);

      // After-window fills strictly with FOLLOWING frames.
      source.emit(_normal(6));
      await pumpEventQueue();
      expect(window.after.map((s) => s.id).toList(), [6]);
      expect(window.isComplete, isFalse);

      source.emitAll([_normal(7), _normal(8), _normal(9), _normal(10)]);
      await pumpEventQueue();

      expect(window.after.map((s) => s.id).toList(), [6, 7, 8, 9, 10]);
      expect(window.isComplete, isTrue);
      // The pipeline kept flowing throughout: every frame became an event.
      expect(events.whereType<FrameEvent>().length, 10);
    });

    test('two close anomalies fill their windows independently', () async {
      final source = FakeFrameSource();
      final engine = _engine(
        source,
        // Small windows so interleaving is easy to assert exactly.
        config: const PerfScopeConfig(
          contextFramesBefore: 2,
          contextFramesAfter: 2,
        ),
      );
      await engine.start();

      source.emitAll([
        _normal(1),
        _slowUi(2), // anm_1: before [1]
        _normal(3),
        _slowRaster(4), // anm_2: before [2, 3] (excludes itself)
      ]);
      await pumpEventQueue();

      final anomalies = engine.anomalies.whereType<FrameAnomaly>().toList();
      expect(anomalies.length, 2);
      expect(anomalies[0], isA<UiBoundFrameAnomaly>());
      expect(anomalies[1], isA<RasterBoundFrameAnomaly>());

      final first = engine.contextWindowFor('anm_1')!;
      final second = engine.contextWindowFor('anm_2')!;
      expect(first.before.map((s) => s.id).toList(), [1]);
      expect(second.before.map((s) => s.id).toList(), [2, 3]);

      // The first window already consumed BOTH strictly-following frames
      // from the same batch (frame 4 is another anomaly's frame — still a
      // real following frame for window 1).
      expect(first.isComplete, isTrue);
      expect(first.after.map((s) => s.id).toList(), [3, 4]);
      // The second window ignores only its OWN anomaly frame.
      expect(second.after, isEmpty);
      expect(second.isComplete, isFalse);

      // Interleaved offers keep feeding the still-pending window while the
      // completed one stays untouched.
      source.emit(_normal(5));
      await pumpEventQueue();
      expect(first.after.map((s) => s.id).toList(), [3, 4]);
      expect(second.after.map((s) => s.id).toList(), [5]);

      source.emit(_normal(6));
      await pumpEventQueue();
      expect(first.after.map((s) => s.id).toList(), [3, 4]);
      expect(second.after.map((s) => s.id).toList(), [5, 6]);
      expect(second.isComplete, isTrue);
    });

    test('severe frames are stored as critical mixed anomalies', () async {
      final source = FakeFrameSource();
      final engine = _engine(source);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);
      await engine.start();

      source.emitAll([_normal(1), _severeMixed(2)]);
      await pumpEventQueue();

      final stored = engine.anomalies.whereType<MixedFrameAnomaly>().toList();
      expect(stored.length, 1);
      expect(stored.single.severity, AnomalySeverity.critical);
      expect(events.whereType<AnomalyEvent>().length, 1);
      expect(engine.contextWindowFor(stored.single.id), isNotNull);
    });

    test('long-trace anomalies have no frame context window', () async {
      final source = FakeFrameSource();
      final clock = FakeClock();
      final engine = PerfScopeEngine(
        config: const PerfScopeConfig(),
        frameSource: source,
        clock: clock,
        logWriter: MemoryLogWriter(),
      );
      await engine.start();

      engine.trace('op', () {
        clock.advance(const Duration(milliseconds: 60));
      });
      await pumpEventQueue();

      final longTrace = engine.anomalies.whereType<LongTraceAnomaly>().single;
      expect(engine.contextWindowFor(longTrace.id), isNull);
    });

    test('pipeline keeps working after an anomaly burst', () async {
      final source = FakeFrameSource();
      final engine = _engine(
        source,
        // Small windows so three following frames complete them.
        config: const PerfScopeConfig(
          contextFramesBefore: 2,
          contextFramesAfter: 2,
        ),
      );
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);
      await engine.start();

      // Burst of back-to-back anomalies...
      source.emitAll([_slowUi(1), _slowRaster(2), _severeMixed(3)]);
      await pumpEventQueue();
      expect(events.whereType<AnomalyEvent>().length, 3);

      // ...and ordinary frames keep flowing afterwards.
      source.emitAll([_normal(4), _normal(5), _normal(6)]);
      await pumpEventQueue();

      expect(
        events.whereType<FrameEvent>().map((e) => e.sample.id).toList(),
        [1, 2, 3, 4, 5, 6],
      );
      expect(engine.recentFrames.map((s) => s.id).toList(), [1, 2, 3, 4, 5, 6]);

      // All burst windows completed on the following normal frames.
      for (final id in ['anm_1', 'anm_2']) {
        final window = engine.contextWindowFor(id)!;
        expect(window.isComplete, isTrue, reason: '$id should be complete');
      }
    });
  });
}
