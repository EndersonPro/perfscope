import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/src/testing/fake_frame_source.dart';

/// Deterministic fixed timestamp — no real clock involved.
final _capturedAt = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

class _FakeClock implements Clock {
  @override
  DateTime now() => _capturedAt;
}

const _budget60 = Duration(microseconds: 16667);

FrameSample _sample(int id,
    {Duration total = const Duration(milliseconds: 8)}) {
  return FrameSample(
    id: id,
    frameNumber: id,
    capturedAt: _capturedAt,
    buildDuration: const Duration(milliseconds: 3),
    rasterDuration: const Duration(milliseconds: 5),
    totalDuration: total,
    vsyncOverhead: Duration.zero,
    frameBudget: _budget60,
    screen: null,
    interactionId: null,
  );
}

PerfScopeEngine _engine({
  required FakeFrameSource source,
  int bufferSize = 500,
  LogWriter? logWriter,
}) {
  return PerfScopeEngine(
    config: PerfScopeConfig(frameBufferSize: bufferSize),
    frameSource: source,
    clock: _FakeClock(),
    logWriter: logWriter ?? MemoryLogWriter(),
  );
}

void main() {
  group('PerfScopeEngine frames pipeline', () {
    test('start starts the frame source exactly once', () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);

      await engine.start();
      await engine.start(); // idempotent

      expect(source.started, isTrue);
      expect(source.stopped, isFalse);
    });

    test('emitted samples produce ordered FrameEvents', () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);

      await engine.start();
      source.emitAll([_sample(1), _sample(2), _sample(3)]);
      await pumpEventQueue();

      expect(events.length, 3);
      expect(events.whereType<FrameEvent>().length, 3);
      expect(
        events.cast<FrameEvent>().map((e) => e.sample.id).toList(),
        [1, 2, 3],
      );
      expect(events.first.id, 'evt_1');
    });

    test('recentFrames respects ring capacity (5 pushed, capacity 3)',
        () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source, bufferSize: 3);

      await engine.start();
      source.emitAll(
          [_sample(1), _sample(2), _sample(3), _sample(4), _sample(5)]);
      await pumpEventQueue();

      expect(engine.recentFrames.length, 3);
      expect(
        engine.recentFrames.map((s) => s.id).toList(),
        [3, 4, 5],
      );
    });

    test('exception inside a listener does not break other listeners',
        () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);
      final received = <PerformanceEvent>[];

      runZonedGuarded(() {
        engine.events.listen((event) => throw StateError('bad listener'));
        engine.events.listen(received.add);
      }, (_, __) {});

      await engine.start();
      source.emitAll([_sample(1), _sample(2)]);
      await pumpEventQueue();

      expect(received.length, 2);
    });
  });

  group('PerfScopeEngine lifecycle', () {
    test('handleLifecycle stores state and emits LifecycleEvent', () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);
      await engine.start();

      engine.handleLifecycle(AppLifecycleState.paused);
      await pumpEventQueue();

      expect(engine.lastLifecycleState, AppLifecycleState.paused);
      final lifecycle = events.whereType<LifecycleEvent>().toList();
      expect(lifecycle.length, 1);
      expect(lifecycle.single.state, AppLifecycleState.paused);
      expect(lifecycle.single.id, startsWith('evt_'));
    });
  });

  group('PerfScopeEngine context enrichment', () {
    test('frame during an active interaction carries its interactionId',
        () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);
      await engine.start();

      final handle = engine.startInteraction('checkout');
      source.emit(_sample(1));
      // FakeFrameSource delivers asynchronously: let this frame be
      // enriched before mutating context again.
      await pumpEventQueue();

      final frame = events.whereType<FrameEvent>().single;
      expect(frame.sample.interactionId, handle.id);
      expect(frame.sample.screen, unknownScreenName);

      // After the span ends attribution falls back to null.
      handle.end();
      source.emit(_sample(2));
      await pumpEventQueue();

      expect(
        events.whereType<FrameEvent>().last.sample.interactionId,
        isNull,
      );
    });

    test('pending quick marker is consumed by the first frame only', () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);
      await engine.start();

      engine.markInteraction('tap_pay');
      await pumpEventQueue(); // deliver the marker event first
      final markers = events
          .whereType<InteractionEvent>()
          .where((e) => e.kind == InteractionEventKind.marker)
          .toList();
      expect(markers.length, 1);

      source.emitAll([_sample(1), _sample(2)]);
      await pumpEventQueue();

      final frames = events.whereType<FrameEvent>().toList();
      expect(frames.first.sample.interactionId, markers.single.interactionId);
      expect(frames.last.sample.interactionId, isNull);
    });

    test('frame without any context keeps a null interactionId', () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);
      await engine.start();

      source.emit(_sample(1));
      await pumpEventQueue();

      expect(
          events.whereType<FrameEvent>().single.sample.interactionId, isNull);
    });

    test('frames are stamped with the current screen', () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);
      await engine.start();

      engine.onRoutePushed('home');
      source.emit(_sample(1));
      await pumpEventQueue(); // frame 1 processed while screen == 'home'

      // Unnamed routes normalize to 'unknown'.
      engine.onRoutePushed(null);
      source.emit(_sample(2));
      await pumpEventQueue();

      final frames = events.whereType<FrameEvent>().toList();
      expect(frames[0].sample.screen, 'home');
      expect(frames[1].sample.screen, 'unknown');

      final screens = events.whereType<ScreenEvent>().toList();
      expect(screens.length, 2);
      expect(screens[0].reason, ScreenChangeReason.push);
      expect(screens[1].name, 'unknown');
      expect(engine.currentScreen, 'unknown');
    });

    test('setMetadata stores values reachable through the store', () {
      final source = FakeFrameSource();
      final engine = _engine(source: source);

      engine.setMetadata('build_flavor', 'dev');
      engine.setMetadata('tags', <String>['a', 'b']);

      expect(engine.metadataStore.snapshot(), {
        'build_flavor': 'dev',
        'tags': ['a', 'b'],
      });

      engine.removeMetadata('build_flavor');
      engine.clearMetadata();
      expect(engine.metadataStore.snapshot(), isEmpty);
    });
  });

  group('PerfScopeEngine dispose', () {
    test('dispose is idempotent and stops the source', () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);

      await engine.start();
      await engine.dispose();
      await engine.dispose();

      expect(source.stopped, isTrue);
    });

    test('emits after dispose produce no events', () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);

      await engine.start();
      source.emit(_sample(1));
      await pumpEventQueue();
      expect(events, isNotEmpty);

      await engine.dispose();
      source.emit(_sample(2));
      await pumpEventQueue();

      expect(events.length, 1);
    });

    test('handleLifecycle after dispose is a no-op', () async {
      final source = FakeFrameSource();
      final engine = _engine(source: source);

      await engine.dispose();

      expect(() => engine.handleLifecycle(AppLifecycleState.resumed),
          returnsNormally);
      expect(engine.lastLifecycleState, isNull);
    });
  });

  group('PerfScopeEngine event sinks', () {
    test('configured sinks receive raw anomaly events', () async {
      final source = FakeFrameSource();
      final sink = MemorySink();
      final engine = PerfScopeEngine(
        config: const PerfScopeConfig(),
        frameSource: source,
        clock: _FakeClock(),
        logWriter: MemoryLogWriter(),
        sinks: <PerformanceEventSink>[sink],
      );
      await engine.start();

      // Slow UI-bound frame: build 28ms vs raster 4ms.
      final slow = FrameSample(
        id: 1,
        frameNumber: 1,
        capturedAt: _capturedAt,
        buildDuration: const Duration(milliseconds: 28),
        rasterDuration: const Duration(milliseconds: 4),
        totalDuration: const Duration(milliseconds: 32),
        vsyncOverhead: Duration.zero,
        frameBudget: _budget60,
        screen: null,
        interactionId: null,
      );
      source.emit(slow);
      await pumpEventQueue();

      final anomalies = sink.events.whereType<AnomalyEvent>().toList();
      expect(anomalies, hasLength(1));
      expect(anomalies.single.anomaly, isA<UiBoundFrameAnomaly>());
      // Frames still reach the sink as raw events too.
      expect(sink.events.whereType<FrameEvent>(), isNotEmpty);
    });

    test('a throwing sink never breaks the event stream', () async {
      final source = FakeFrameSource();
      final recorder = MemorySink();
      final composite = CompositeSink(<PerformanceEventSink>[
        _ExplodingSink(),
        recorder,
      ]);
      final events = <PerformanceEvent>[];
      final engine = PerfScopeEngine(
        config: const PerfScopeConfig(),
        frameSource: source,
        clock: _FakeClock(),
        logWriter: MemoryLogWriter(),
        sinks: <PerformanceEventSink>[composite],
      );
      engine.events.listen(events.add);
      await engine.start();

      source.emit(_sample(1));
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(recorder.events, hasLength(1));
    });
  });
}

/// Sink whose add() always throws — failure containment fixture.
class _ExplodingSink with SinkAcceptsAllMixin implements PerformanceEventSink {
  @override
  bool accepts(covariant PerformanceEvent event) => true;

  @override
  void add(covariant PerformanceEvent event) =>
      throw StateError('sink exploded');
}
