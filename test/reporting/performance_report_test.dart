import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/src/testing/fake_frame_source.dart';

import '../helpers/fake_clock.dart';

const _budget60 = Duration(microseconds: 16667);

/// Normal frame: comfortably within budget (8 ms total).
FrameSample _normal(int id) => _sample(id,
    build: const Duration(milliseconds: 3),
    raster: const Duration(milliseconds: 5));

/// Slow UI-bound frame: 32 ms total, build >= 2x raster.
FrameSample _slowUi(int id) => _sample(id,
    build: const Duration(milliseconds: 28),
    raster: const Duration(milliseconds: 4));

/// Slow raster-bound frame: 32 ms total, raster >= 2x build.
FrameSample _slowRaster(int id) => _sample(id,
    build: const Duration(milliseconds: 4),
    raster: const Duration(milliseconds: 28));

/// Severe mixed frame: 52 ms total (> 3x budget), comparable threads.
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

void main() {
  group('PerformanceReport end-to-end scenario', () {
    test('scripted session produces hand-computed summaries and ranking',
        () async {
      final source = FakeFrameSource();
      final clock = FakeClock();
      final engine = PerfScopeEngine(
        config: const PerfScopeConfig(),
        frameSource: source,
        clock: clock,
        logWriter: MemoryLogWriter(),
      );
      await engine.start(); // auto-started session
      expect(engine.currentSession, isNotNull);

      // Screen A: six normal frames + one slow UI-bound + one severe mixed.
      engine.overrideScreen('screen_a');
      source.emitAll([
        _normal(1),
        _normal(2),
        _normal(3),
        _normal(4),
        _normal(5),
        _normal(6),
        _slowUi(7), // anm_1: high severity, ui bottleneck
        _severeMixed(8), // anm_2: critical severity, mixed bottleneck
      ]);
      await pumpEventQueue();

      // One interaction span covering every screen B frame.
      final handle = engine.startInteraction('checkout');
      engine.overrideScreen('screen_b');
      source.emitAll([_normal(9), _normal(10)]);
      source.emit(_slowRaster(11)); // anm_3: high severity, raster bottleneck
      // Deliver the queued frames WHILE the span is still open: the
      // broadcast source only hands samples over on microtask drains, so
      // ending first would strip their interaction attribution.
      await pumpEventQueue();
      clock.advance(const Duration(milliseconds: 30));
      handle.end(); // span duration = exactly 30 ms
      await pumpEventQueue();

      // One long trace on screen B with no active interaction:
      // 120 ms >= 2x the 50 ms threshold -> HIGH severity long-trace anomaly.
      engine.trace('load_catalog', () {
        clock.advance(const Duration(milliseconds: 120));
      });
      await pumpEventQueue();

      final report = await engine.stopSession();

      // --- Session-wide statistics (manual sums over all 11 frames) ---
      // Build µs: 6x3000 + 28000 + 26000 + 3000 + 3000 + 4000 = 82000
      //   -> 82/11 ms = 7.4545... -> rounds to 7.455
      // Raster µs: 6x5000 + 4000 + 26000 + 5000 + 5000 + 28000 = 98000
      //   -> 98/11 ms = 8.9090... -> rounds to 8.909
      // Total µs: 6x8000 + 32000 + 52000 + 8000 + 8000 + 32000 = 180000
      //   -> 180/11 ms = 16.3636... -> rounds to 16.364
      //
      // Sorted totals [8x8, 32, 32, 52] (n=11), nearest-rank:
      //   p50 rank ceil(5.5)=6 -> 8; p90 ceil(9.9)=10 -> 32;
      //   p95/p99 rank 11 -> 52.
      const expectedStatistics = SessionStatistics(
        totalFrames: 11,
        normalFrames: 8,
        warningFrames: 0,
        slowFrames: 2,
        severeFrames: 1,
        slowFrameRate: 3 / 11,
        averageBuildMs: 7.455,
        averageRasterMs: 8.909,
        averageTotalMs: 16.364,
        p50Ms: 8.0,
        p90Ms: 32.0,
        p95Ms: 52.0,
        p99Ms: 52.0,
        worstFrameMs: 52.0,
      );
      expect(report.statistics, equals(expectedStatistics));
      // The finished session's live calculator still agrees with the
      // frozen report values.
      expect(report.session.statistics(), equals(report.statistics));

      // --- Screen summaries ---
      // Ranking rule: anomalyCount DESC -> p95Ms DESC -> name ASC.
      // screen_a: anomalies 2 (anm_1, anm_2); screen_b: 2 (anm_3 + long
      // trace). Tie on count, so p95 decides: A (52 ms) before B (32 ms).
      expect(
          report.screens.map((s) => s.name).toList(), ['screen_a', 'screen_b']);

      final a = report.screens[0];
      expect(a.totalFrames, 8);
      expect(a.slowFrames, 1);
      expect(a.severeFrames, 1);
      expect(a.anomalyCount, 2);
      expect(a.slowFrameRate, 2 / 8);
      // Sorted [8x6, 32, 52]: rank ceil(0.95*8) = 8 -> 52.
      expect(a.p95Ms, 52.0);
      expect(a.worstMs, 52.0);
      // Bottleneck tally {ui:1, mixed:1}: tie resolves by declaration
      // order (ui before mixed).
      expect(a.probableBottleneck, FrameBottleneck.ui);

      final b = report.screens[1];
      expect(b.totalFrames, 3);
      expect(b.slowFrames, 1);
      expect(b.severeFrames, 0);
      expect(b.anomalyCount, 2); // raster anomaly + long-trace anomaly
      expect(b.slowFrameRate, 1 / 3);
      // Sorted [8, 8, 32]: rank ceil(0.95*3) = 3 -> 32.
      expect(b.p95Ms, 32.0);
      expect(b.worstMs, 32.0);
      // Only FRAME anomalies feed the mode: the lone raster anomaly wins;
      // the long trace contributes no bottleneck.
      expect(b.probableBottleneck, FrameBottleneck.raster);

      // --- Interaction summary ---
      final checkout = report.interactions.single;
      expect(checkout.name, 'checkout');
      expect(checkout.mostRecentInteractionId, startsWith('iax_'));
      expect(checkout.spanCount, 1);
      expect(checkout.frameCount, 3);
      expect(checkout.anomalyCount, 1); // only the attributed raster anomaly
      expect(checkout.totalSpanDuration, const Duration(milliseconds: 30));
      expect(checkout.p95Ms, 32.0);
      expect(checkout.worstMs, 32.0);
      expect(checkout.probableBottleneck, FrameBottleneck.raster);

      // --- Traces and anomalies ---
      expect(report.traces, hasLength(1));
      expect(report.traces.single.name, 'load_catalog');

      // Detection order: ui-slow, mixed-severe, raster-slow, long trace.
      expect(
        report.anomalies.map((a) => a.id).toList(),
        ['anm_1', 'anm_2', 'anm_3', 'anm_4'],
      );
      // Worst-first: critical mixed (52 ms) -> HIGH tier ordered by duration
      // DESC (long trace 120 ms beats both 32 ms frames) -> id ASC breaks
      // the remaining tie between anm_1 and anm_3.
      expect(
        report.worstAnomalies.map((a) => a.id).toList(),
        ['anm_2', 'anm_4', 'anm_1', 'anm_3'],
      );

      // --- Lifecycle after stop ---
      expect(engine.currentSession, isNull);
      expect(engine.lastFinishedSession, isNotNull);
      expect(engine.lastFinishedSession!.isActive, isFalse);
      expect(engine.lastReport, same(report));
    });
  });
}
