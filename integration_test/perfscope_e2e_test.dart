import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope_example/app/scenario.dart';
import 'package:perfscope_example/app/showcase_app.dart';

/// End-to-end tests driving the REAL example app against a real engine on
/// real platform bindings.
///
/// Flakiness guards by design:
/// * generous timeouts (10s wall-clock wait for anomalies),
/// * NO exact timing assertions anywhere (absolute frame numbers vary per
///   device/emulator),
/// * failure messages list every event type observed so far to make a
///   silent "frames never flowed" scenario diagnosable.
void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MemorySink sink;

  setUp(() {
    PerfScope.resetForTest();
    sink = MemorySink();
    // MemorySink injected through the sinks param — the raw event tap used
    // for assertions, separate from the public stream.
    PerfScope.initialize(sinks: <PerformanceEventSink>[sink]);
  });

  tearDown(() async {
    await PerfScope.dispose();
  });

  String describeSeenEvents() {
    if (sink.events.isEmpty) {
      return '<no events at all>';
    }
    final Map<String, int> counts = <String, int>{};
    for (final PerformanceEvent event in sink.events) {
      counts[event.runtimeType.toString()] =
          (counts[event.runtimeType.toString()] ?? 0) + 1;
    }
    final entries =
        counts.entries.map((e) => '${e.key} x${e.value}').join(', ');
    return 'event types seen: [$entries]';
  }

  testWidgets(
      'ui-thread jank scenario produces a FrameAnomaly and full session flow',
      (WidgetTester tester) async {
    // Pump the real showcase app WITH the navigator observer.
    await tester.pumpWidget(
      ShowcaseApp(observers: [PerfScopeNavigatorObserver()]),
    );
    await tester.pumpAndSettle();

    // Navigate to the UI-thread jank scenario by tapping its home tile.
    await tester
        .tap(find.byKey(const ValueKey<String>('menu-tile$routeUiThreadJank')));
    await tester.pumpAndSettle();

    // Fire the intentionally janky synchronous busy loop.
    await tester.tap(find.byKey(const ValueKey<String>('trigger-cpu-work')));
    await tester.pump();

    // Frames DO flow during integration tests on real bindings; poll the
    // sink until any AnomalyEvent arrives or we hit the generous timeout.
    final Stopwatch waited = Stopwatch()..start();
    bool sawAnomaly = false;
    while (!sawAnomaly && waited.elapsed < const Duration(seconds: 10)) {
      await binding.pump(const Duration(seconds: 3));
      sawAnomaly = sink.events.any((PerformanceEvent e) => e is AnomalyEvent);
    }
    expect(
      sawAnomaly,
      isTrue,
      reason:
          'Timed out after 10s waiting for an AnomalyEvent after triggering '
          'CPU work. ${describeSeenEvents()}',
    );

    final AnomalyEvent anomalyEvent =
        sink.events.whereType<AnomalyEvent>().first;
    final PerformanceAnomaly anomaly = anomalyEvent.anomaly;

    // The CPU-blocking demo must surface as a FRAME anomaly (not a trace
    // anomaly): the observable effect is a blown frame budget.
    final FrameAnomaly frameAnomaly = switch (anomaly) {
      FrameAnomaly f => f,
      _ =>
        fail('Expected a FrameAnomaly subtype but got ${anomaly.runtimeType}.'),
    };
    expect(frameAnomaly.sample, isNotNull,
        reason: 'Frame anomaly must carry its frame sample.');
    // Route naming nuance: depending on when the anomalous frame was
    // captured relative to route push, screen may be the named route or
    // the normalized fallback. Accept both.
    expect(
      frameAnomaly.screen,
      anyOf(equals(routeUiThreadJank), equals('unknown')),
      reason: 'Unexpected screen attribution '
          "'${frameAnomaly.screen}'.",
    );

    // Session lifecycle via the facade.
    final PerformanceSession session = PerfScope.startSession('e2e-session');
    expect(session.isActive, isTrue);
    final PerformanceReport report = await PerfScope.stopSession();
    expect(report.statistics.totalFrames, greaterThan(0),
        reason: 'A stopped session must have observed frames.');

    // Export requires an OPEN session; open one briefly and export it,
    // then prove the JSON parses back through the strict parser.
    PerfScope.startSession('e2e-export');
    await binding.pump(const Duration(seconds: 1));
    final String? exportedJson = PerfScope.exportCurrentSessionAsJson();
    expect(exportedJson, isNotNull,
        reason: 'Export with an open session must produce JSON.');
    final PerformanceReport parsed =
        const SessionParser().parseString(exportedJson!);
    expect(parsed.session.id, isNotEmpty);
    await PerfScope.stopSession();
  });

  testWidgets('navigation events report named routes',
      (WidgetTester tester) async {
    // Collect ScreenEvents from the PUBLIC stream (not just the sink).
    final List<ScreenEvent> screenEvents = <ScreenEvent>[];
    final StreamSubscription<PerformanceEvent> subscription =
        PerfScope.events.listen(
      (PerformanceEvent event) {
        if (event is ScreenEvent) {
          screenEvents.add(event);
        }
      },
    );

    await tester.pumpWidget(
      ShowcaseApp(observers: [PerfScopeNavigatorObserver()]),
    );
    await tester.pumpAndSettle();

    // smooth-navigation -> back -> long-scroll-list -> back.
    //
    // Fixed-duration pumps instead of pumpAndSettle: the smooth-navigation
    // baseline animates forever, so settling would never return, and the
    // home screen must be on top again before tapping the next tile.
    Future<void> pushViaHomeTile(String route) async {
      await tester.tap(find.byKey(ValueKey<String>('menu-tile$route')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> popBackHome() async {
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    await pushViaHomeTile(routeSmoothNavigation);
    await popBackHome();
    await pushViaHomeTile(routeLongScrollList);
    await popBackHome();

    final List<String> names =
        screenEvents.map((ScreenEvent e) => e.name).toList(growable: false);
    expect(names, contains(routeSmoothNavigation),
        reason: 'Screen events seen: $names');
    expect(names, contains(routeLongScrollList),
        reason: 'Screen events seen: $names');

    await subscription.cancel();
  });
}
