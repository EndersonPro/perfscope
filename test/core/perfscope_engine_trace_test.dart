import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/src/testing/fake_frame_source.dart';

import '../helpers/fake_clock.dart';

/// Fake Timeline adapter recording call balance for assertions.
class _RecordingAdapter implements TraceTimelineAdapter {
  final List<String> starts = <String>[];
  final List<Map<String, Object?>?> startArguments = <Map<String, Object?>?>[];
  int finishes = 0;

  @override
  void start(String name, Map<String, Object?>? arguments) {
    starts.add(name);
    startArguments.add(arguments);
  }

  @override
  void finish() => finishes++;
}

PerfScopeEngine _engine({
  required FakeClock clock,
  TraceTimelineAdapter? timelineAdapter,
  PerfScopeConfig? config,
}) {
  return PerfScopeEngine(
    config: config ??
        PerfScopeConfig(longTraceThreshold: const Duration(milliseconds: 50)),
    frameSource: FakeFrameSource(),
    clock: clock,
    logWriter: MemoryLogWriter(),
    timelineAdapter: timelineAdapter ?? NoopTimelineAdapter(),
  );
}

void main() {
  group('PerfScopeEngine trace (sync)', () {
    test('returns the body value unchanged', () {
      final engine = _engine(clock: FakeClock());

      final result = engine.trace('compute', () => 42);

      expect(result, 42);
    });

    test('records a completed trace and emits a TraceEvent', () async {
      final clock = FakeClock();
      final engine = _engine(clock: clock);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);

      engine.trace('load_home', () => 'ok');
      await pumpEventQueue();

      final trace = engine.recentTraces.single;
      expect(trace.id, startsWith('trc_'));
      expect(trace.name, 'load_home');
      expect(trace.didThrow, isFalse);
      expect(trace.duration, Duration.zero);
      expect(trace.screen, unknownScreenName);
      expect(trace.startedAt, clock.now());

      final event = events.whereType<TraceEvent>().single;
      expect(event.traceId, trace.id);
      expect(event.name, 'load_home');
      expect(event.didThrow, isFalse);
      expect(event.interactionId, isNull);
    });

    test('duration reflects manual clock advances inside the body', () {
      final clock = FakeClock();
      final engine = _engine(clock: clock);

      engine.trace('op', () {
        clock.advance(const Duration(milliseconds: 25));
      });

      expect(engine.recentTraces.single.duration,
          const Duration(milliseconds: 25));
    });

    test('rethrows the SAME error object with the ORIGINAL stack trace', () {
      final engine = _engine(clock: FakeClock());
      final sentinel = StateError('boom');
      final markerStack =
          StackTrace.fromString('#0 __sentinel_frame_marker__ (file.dart:1)');

      Object? caught;
      StackTrace? caughtStack;
      try {
        engine.trace<int>('op', () {
          Error.throwWithStackTrace(sentinel, markerStack);
        });
      } catch (error, stackTrace) {
        caught = error;
        caughtStack = stackTrace;
      }

      expect(caught, same(sentinel));
      // Exact preservation, not just a substring.
      expect(caughtStack.toString(), markerStack.toString());
    });

    test('a throwing body is still recorded with didThrow true', () async {
      final engine = _engine(clock: FakeClock());

      try {
        engine.trace('op', () => throw StateError('boom'));
      } catch (_) {
        // Swallowed on purpose; bookkeeping is what we assert.
      }
      await pumpEventQueue();

      expect(engine.recentTraces.single.didThrow, isTrue);
      expect(engine.recentTraces.single.name, 'op');
    });

    test('screen and interaction are captured at START, not live', () async {
      final clock = FakeClock();
      final engine = _engine(clock: clock);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);

      engine.onRoutePushed('home');
      final outer = engine.startInteraction('outer');
      await pumpEventQueue(); // flush start/interaction events

      events.clear();
      engine.trace('op', () {
        // Context changes mid-trace must NOT retro-attribute the record.
        engine.onRoutePushed('checkout');
        engine.startInteraction('inner').end();
      });
      await pumpEventQueue();

      final trace = engine.recentTraces.single;
      expect(trace.screen, 'home');

      final event = events.whereType<TraceEvent>().single;
      expect(event.screen, 'home');
      expect(event.interactionId, outer.id);
    });

    group('long-trace anomaly', () {
      test('60ms over a 50ms threshold yields exactly one medium anomaly',
          () async {
        final clock = FakeClock();
        final engine = _engine(clock: clock);
        final events = <PerformanceEvent>[];
        engine.events.listen(events.add);

        engine.trace('op', () {
          clock.advance(const Duration(milliseconds: 60));
        });
        await pumpEventQueue();

        final anomalies =
            engine.anomalies.whereType<LongTraceAnomaly>().toList();
        expect(anomalies.length, 1);
        expect(anomalies.single.severity, AnomalySeverity.medium);
        expect(anomalies.single.traceId, engine.recentTraces.single.id);
        expect(anomalies.single.duration, const Duration(milliseconds: 60));

        final anomalyEvents = events.whereType<AnomalyEvent>().toList();
        expect(anomalyEvents.length, 1);
        expect(anomalyEvents.single.anomaly, same(anomalies.single));
        // TraceEvent precedes AnomalyEvent.
        expect(
          events.indexOf(events.whereType<TraceEvent>().single),
          lessThan(events.indexOf(anomalyEvents.single)),
        );
      });

      test('severity tiers follow the documented multipliers', () async {
        Future<void> expectSeverity(
            Duration duration, AnomalySeverity severity) async {
          final clock = FakeClock();
          final engine = _engine(clock: clock);
          engine.trace('op', () {
            clock.advance(duration);
          });
          await pumpEventQueue();
          expect(engine.anomalies.single.severity, severity,
              reason: '$duration should map to $severity');
        }

        await expectSeverity(
            const Duration(milliseconds: 100), AnomalySeverity.high);
        await expectSeverity(
            const Duration(milliseconds: 249), AnomalySeverity.high);
        await expectSeverity(
            const Duration(milliseconds: 250), AnomalySeverity.critical);
        await expectSeverity(
            const Duration(milliseconds: 500), AnomalySeverity.critical);
      });

      test('short traces produce no anomaly at all', () async {
        final clock = FakeClock();
        final engine = _engine(clock: clock);

        engine.trace('quick', () {
          clock.advance(const Duration(milliseconds: 10));
        });
        // Exactly ON threshold is NOT long (strictly-greater contract).
        engine.trace('exact', () {
          clock.advance(const Duration(milliseconds: 50));
        });
        await pumpEventQueue();

        expect(engine.recentTraces.length, 2);
        expect(engine.anomalies, isEmpty);
      });

      test('throwing long traces still produce an anomaly', () async {
        final clock = FakeClock();
        final engine = _engine(clock: clock);

        try {
          engine.trace('op', () {
            clock.advance(const Duration(milliseconds: 120));
            throw StateError('boom');
          });
        } catch (_) {}
        await pumpEventQueue();

        expect(engine.recentTraces.single.didThrow, isTrue);
        expect(engine.anomalies.single.severity, AnomalySeverity.high);
      });
    });

    test('valid metadata flows into record, event, and anomaly', () async {
      final clock = FakeClock();
      final engine = _engine(clock: clock);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);

      final callerMetadata = <String, Object?>{'step': 2};
      engine.trace('op', () {
        clock.advance(const Duration(milliseconds: 80));
      }, metadata: callerMetadata);
      callerMetadata['step'] = 999; // later mutation must not leak
      await pumpEventQueue();

      expect(engine.recentTraces.single.metadata, {'step': 2});
      expect(events.whereType<TraceEvent>().single.metadata, {'step': 2});
      expect(
          (engine.anomalies.single as LongTraceAnomaly).metadata, {'step': 2});
    });

    test('invalid metadata fails fast before the body runs', () async {
      final engine = _engine(clock: FakeClock());
      var bodyRan = false;

      expect(
        () => engine.trace('op', () {
          bodyRan = true;
          return 1;
        }, metadata: {'bad': Object()}),
        throwsArgumentError,
      );
      expect(bodyRan, isFalse);
      expect(engine.recentTraces, isEmpty);
      await pumpEventQueue();
    });
  });

  group('PerfScopeEngine traceAsync', () {
    test('returns the awaited body value unchanged', () async {
      final engine = _engine(clock: FakeClock());

      final result = await engine.traceAsync('fetch', () async => 'data');

      expect(result, 'data');
    });

    test('records duration across awaits with manual clock advances', () async {
      final clock = FakeClock();
      final engine = _engine(clock: clock);

      await engine.traceAsync('op', () async {
        clock.advance(const Duration(milliseconds: 40));
      });

      expect(engine.recentTraces.single.duration,
          const Duration(milliseconds: 40));
    });

    test('Future.error path rethrows SAME error with ORIGINAL stack', () async {
      final engine = _engine(clock: FakeClock());
      final sentinel = StateError('async boom');
      final markerStack =
          StackTrace.fromString('#0 __async_sentinel_frame__ (net.dart:7)');

      Object? caught;
      StackTrace? caughtStack;
      try {
        await engine.traceAsync<int>(
            'op', () => Future<int>.error(sentinel, markerStack));
      } catch (error, stackTrace) {
        caught = error;
        caughtStack = stackTrace;
      }

      expect(caught, same(sentinel));
      expect(caughtStack.toString(), markerStack.toString());
      expect(engine.recentTraces.single.didThrow, isTrue);
    });

    test('throwing async function preserves error and stack marker', () async {
      final engine = _engine(clock: FakeClock());
      final sentinel = StateError('fn boom');

      Object? caught;
      StackTrace? caughtStack;
      try {
        await engine.traceAsync<int>('op', () async {
          Error.throwWithStackTrace(sentinel, StackTrace.current);
        });
      } catch (error, stackTrace) {
        caught = error;
        caughtStack = stackTrace;
      }

      expect(caught, same(sentinel));
      // The async machinery frames differ, but the error identity plus a
      // non-empty original stack must survive untouched.
      expect(caughtStack, isNotNull);
      expect(caughtStack.toString(), contains('.dart'));
    });

    test('long async traces emit exactly one anomaly event', () async {
      final clock = FakeClock();
      final engine = _engine(clock: clock);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);

      await engine.traceAsync('op', () async {
        clock.advance(const Duration(milliseconds: 300));
      });
      await pumpEventQueue();

      expect(events.whereType<AnomalyEvent>().length, 1);
      expect(engine.anomalies.single.severity, AnomalySeverity.critical);
    });
  });

  group('PerfScopeEngine timeline adapter', () {
    test('start/finish are balanced on success', () async {
      final adapter = _RecordingAdapter();
      final engine = _engine(clock: FakeClock(), timelineAdapter: adapter);

      engine.trace('op', () => 1);
      await engine.traceAsync<String>('aop', () async => 'x');

      // One injected adapter serves both flavors: two spans, two finishes.
      expect(adapter.starts, ['op', 'aop']);
      expect(adapter.finishes, 2);
    });

    test('finish is called even when the body throws', () {
      final adapter = _RecordingAdapter();
      final engine = _engine(clock: FakeClock(), timelineAdapter: adapter);

      try {
        engine.trace('op', () => throw StateError('boom'));
      } catch (_) {}

      expect(adapter.starts, ['op']);
      expect(adapter.finishes, 1);
      expect(adapter.startArguments.single, isNull);
    });

    test('arguments carry validated metadata', () {
      final adapter = _RecordingAdapter();
      final engine = _engine(clock: FakeClock(), timelineAdapter: adapter);

      engine.trace('op', () => 1, metadata: {'k': 'v'});

      expect(adapter.startArguments.single, {'k': 'v'});
    });

    test('real adapters swallow Timeline failures instead of crashing', () {
      // Real adapters run against dart:developer in a plain test env;
      // they must never propagate. Smoke-test both flavors.
      final syncEngine = _engine(
        clock: FakeClock(),
        timelineAdapter: const RealSyncTimelineAdapter(),
      );
      final asyncEngine = _engine(
        clock: FakeClock(),
        timelineAdapter: RealAsyncTimelineAdapter(),
      );

      expect(() => syncEngine.trace('op', () => 1), returnsNormally);
      expect(asyncEngine.traceAsync('op', () async => 2), completes);
    });
  });

  group('PerfScopeEngine trace after dispose', () {
    test('body still runs but nothing is recorded or emitted', () async {
      final clock = FakeClock();
      final engine = _engine(clock: clock);
      final events = <PerformanceEvent>[];
      engine.events.listen(events.add);
      await engine.dispose();

      final result = engine.trace('op', () => 'still-runs');
      await pumpEventQueue();

      expect(result, 'still-runs');
      expect(engine.recentTraces, isEmpty);
      expect(engine.anomalies, isEmpty);
      expect(events, isEmpty);
    });
  });
}
