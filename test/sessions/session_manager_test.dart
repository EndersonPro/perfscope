import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

import '../helpers/fake_clock.dart';

/// Deterministic fixed timestamp — no real clock involved.
final _capturedAt = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

FrameSample _sample({
  String? screen,
  String? interactionId,
  Duration build = const Duration(milliseconds: 3),
  Duration raster = const Duration(milliseconds: 5),
  Duration total = const Duration(milliseconds: 8),
}) {
  return FrameSample(
    id: total.inMicroseconds,
    frameNumber: null,
    capturedAt: _capturedAt,
    buildDuration: build,
    rasterDuration: raster,
    totalDuration: total,
    vsyncOverhead: Duration.zero,
    frameBudget: const Duration(microseconds: 16667),
    screen: screen,
    interactionId: interactionId,
  );
}

SessionManager _manager({
  FakeClock? clock,
  MetadataStore? store,
  int interactionNameCacheCapacity = defaultInteractionNameCacheCapacity,
}) {
  return SessionManager(
    traceTracker: TraceTracker(capacity: 8),
    clock: clock ?? FakeClock(),
    frameBudgetProvider: FixedFrameBudget.fromFps(60),
    metadataSnapshot: store == null ? null : () => store.snapshot(),
    interactionNameCacheCapacity: interactionNameCacheCapacity,
  );
}

void main() {
  group('SessionManager lifecycle', () {
    test('start/isActive/stop produce a finished session and a report', () {
      final manager = _manager();
      expect(manager.hasActiveSession, isFalse);

      final session = manager.start(name: 'probe');
      expect(manager.hasActiveSession, isTrue);
      expect(session.isActive, isTrue);
      expect(session.id, startsWith('ses_'));
      expect(session.name, 'probe');

      final report = manager.stop();
      expect(report.session.id, session.id);
      expect(session.isActive, isFalse);
      expect(session.endedAt, isNotNull);
      expect(manager.hasActiveSession, isFalse);
      expect(manager.lastFinishedSession, same(session));
      expect(manager.lastReport, same(report));
    });

    test('stop without an active session throws StateError', () async {
      final manager = _manager();
      expect(manager.stop, throwsStateError);

      manager.start();
      manager.stop();
      // And again after the first stop.
      expect(manager.stop, throwsStateError);
    });

    test('double start auto-finalizes the first session', () {
      final clock = FakeClock();
      final manager = _manager(clock: clock);

      final first = manager.start();
      manager.recordFrame(_sample(), FrameSeverity.slow);
      clock.advance(const Duration(milliseconds: 5));

      final second = manager.start(name: 'second');
      expect(second.id, isNot(first.id));
      expect(first.isActive, isFalse);
      expect(first.endedAt, clock.now());
      expect(manager.lastFinishedSession, same(first));

      // Fresh accumulators: the new session starts from zero while the
      // retired one keeps its frozen statistics.
      expect(first.statistics().totalFrames, 1);
      expect(second.statistics().totalFrames, 0);
    });

    test('metadata snapshot isolation both directions', () {
      final store = MetadataStore();
      store.set('k', 'v');
      final manager = _manager(store: store);

      final session = manager.start();
      expect(session.metadata, {'k': 'v'});

      // Store mutations after start never leak into the session record.
      store.set('late', 42);
      store.remove('k');
      expect(session.metadata, {'k': 'v'});

      // Mutating the exposed map never corrupts later sessions either.
      session.metadata['hacked'] = true;
      final next = manager.start();
      expect(next.metadata.containsKey('hacked'), isFalse);
    });

    test('recording APIs are no-ops without an active session', () {
      final manager = _manager();

      void recordEverything() {
        manager.recordFrame(_sample(screen: 'x'), FrameSeverity.normal);
        manager.noteInteraction('i1', 'flow');
        manager.endInteraction('i1', const Duration(milliseconds: 5));
        manager.recordAnomaly(
          LongTraceAnomaly(
            id: 'anm_x',
            timestamp: _capturedAt,
            severity: AnomalySeverity.medium,
            traceId: 'trc_x',
            name: 'op',
            duration: const Duration(milliseconds: 90),
            screen: 'x',
          ),
        );
      }

      expect(recordEverything, returnsNormally);

      manager.start();
      manager.recordFrame(_sample(screen: 'x'), FrameSeverity.normal);
      final stopped = manager.stop();
      expect(stopped.statistics.totalFrames, 1);

      recordEverything(); // inactive again
      expect(manager.lastReport, same(stopped));
      expect(stopped.statistics.totalFrames, 1); // unchanged
    });

    test('environment captures budget provenance deterministically', () {
      final manager = _manager();
      final env = manager.start().environment;

      expect(env.frameBudgetFps, 60.0);
      expect(env.frameBudgetMs, 16.667);
      expect(env.frameBudgetSource, FrameBudgetSource.configured);
      expect(env.platform, isNotEmpty);
    });
  });

  group('SessionManager interaction aggregates', () {
    test('noteInteraction/endInteraction accumulate per name', () {
      final manager = _manager();
      manager.start();

      manager.noteInteraction('i1', 'checkout');
      manager.noteInteraction('i2', 'checkout'); // same name, new span
      manager.endInteraction('i1', const Duration(milliseconds: 5));
      manager.endInteraction('i2', const Duration(milliseconds: 12));
      manager.endInteraction('ghost', const Duration(milliseconds: 99));
      manager.recordFrame(
        _sample(interactionId: 'i2'),
        FrameSeverity.normal,
      );

      final summary = manager.stop().interactions.single;
      expect(summary.name, 'checkout');
      expect(summary.spanCount, 2);
      expect(summary.mostRecentInteractionId, 'i2');
      expect(summary.totalSpanDuration, const Duration(milliseconds: 17));
      expect(summary.frameCount, 1);
    });

    test('repeated noteInteraction for one id counts a single span', () {
      final manager = _manager();
      manager.start();

      manager.noteInteraction('dup', 'flow');
      manager.noteInteraction('dup', 'flow');

      expect(manager.stop().interactions.single.spanCount, 1);
    });

    test('id→name cache evicts oldest insertion beyond the cap', () {
      final manager = _manager(interactionNameCacheCapacity: 2);
      manager.start();

      manager.noteInteraction('a', 'flow_a');
      manager.noteInteraction('b', 'flow_b');
      manager.noteInteraction('c', 'flow_c'); // evicts 'a'

      manager.endInteraction('a', const Duration(milliseconds: 10));
      manager.endInteraction('c', const Duration(milliseconds: 7));
      manager.recordFrame(
        _sample(screen: 'scr', interactionId: 'a'),
        FrameSeverity.normal,
      );

      final report = manager.stop();
      final byName = {
        for (final i in report.interactions) i.name: i,
      };
      expect(byName['flow_a']!.totalSpanDuration, Duration.zero);
      // Evicted id: the frame still lands on its SCREEN, but not on any
      // interaction summary.
      expect(byName['flow_a']!.frameCount, 0);
      expect(
          byName['flow_c']!.totalSpanDuration, const Duration(milliseconds: 7));
      expect(
        report.screens.singleWhere((s) => s.name == 'scr').totalFrames,
        1,
      );
    });
  });

  group('SessionManager anomaly routing (sealed switch)', () {
    test('FrameAnomaly credits its sample screen and interaction', () {
      final manager = _manager();
      manager.start();

      final sample = _sample(
        screen: 'scr',
        interactionId: 'i1',
        build: const Duration(milliseconds: 30),
        raster: Duration.zero,
        total: const Duration(milliseconds: 30),
      );
      manager.noteInteraction('i1', 'checkout');
      manager.recordFrame(sample, FrameSeverity.slow);
      manager.recordAnomaly(createFrameAnomaly(
        id: 'anm_t1',
        timestamp: _capturedAt,
        sample: sample,
        classification: const FrameClassification(
          FrameSeverity.slow,
          FrameBottleneck.ui,
        ),
      ));

      final report = manager.stop();
      final screen = report.screens.single;
      expect(screen.name, 'scr');
      expect(screen.anomalyCount, 1);
      expect(screen.slowFrames, 1);
      expect(screen.probableBottleneck, FrameBottleneck.ui);
      expect(report.interactions.single.anomalyCount, 1);
    });

    test('LongTraceAnomaly never touches frame statistics', () {
      final manager = _manager();
      manager.start();

      manager.recordAnomaly(LongTraceAnomaly(
        id: 'anm_t2',
        timestamp: _capturedAt,
        severity: AnomalySeverity.high,
        traceId: 'trc_9',
        name: 'load_catalog',
        duration: const Duration(milliseconds: 120),
        screen: 'other',
        interactionId: 'i9',
      ));
      manager.noteInteraction('i9', 'browsing');

      final stats = manager.stop().statistics;
      expect(stats.totalFrames, 0);
      expect(stats.slowFrames, 0);
      expect(stats.p95Ms, 0.0);
    });

    test('LongTraceAnomaly credits its screen anomaly counter only', () {
      final manager = _manager();
      manager.start();

      manager.recordAnomaly(LongTraceAnomaly(
        id: 'anm_t3',
        timestamp: _capturedAt,
        severity: AnomalySeverity.medium,
        traceId: 'trc_8',
        name: 'op',
        duration: const Duration(milliseconds: 60),
        screen: 'other',
      ));

      final report = manager.stop();
      final screen = report.screens.single;
      expect(screen.name, 'other');
      expect(screen.anomalyCount, 1);
      expect(screen.totalFrames, 0);
      expect(screen.probableBottleneck, FrameBottleneck.unknown);
      expect(report.anomalies.single.id, 'anm_t3');
    });
  });

  group('SessionManager traces', () {
    test('recordTrace reuses the injected tracker, active or not', () {
      final tracker = TraceTracker(capacity: 8);
      final manager = SessionManager(traceTracker: tracker);

      CompletedTrace trace(String id) => CompletedTrace(
            id: id,
            name: 'op',
            startedAt: _capturedAt,
            duration: const Duration(milliseconds: 10),
            screen: 'unknown',
            didThrow: false,
          );

      manager.recordTrace(trace('trc_1')); // no active session
      manager.start();
      manager.recordTrace(trace('trc_2'));
      manager.stop();

      expect(tracker.traces.map((t) => t.id).toList(), ['trc_1', 'trc_2']);
      expect(manager.lastReport!.traces.map((t) => t.id).toList(),
          ['trc_1', 'trc_2']);
    });
  });
}
