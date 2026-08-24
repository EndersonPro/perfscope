import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope_example/app/scenario.dart';
import 'package:perfscope_example/app/scenario_scaffold.dart';
import 'package:perfscope_example/app/showcase_app.dart';

/// Regression coverage for the scenario screens' LAYOUT CONTRACT.
///
/// ScenarioScaffold places each scenario's child as a leaf of its own
/// ListView, so children receive UNBOUNDED height. Any child using
/// Expanded/Flexible or embedding an unbounded viewport (ListView,
/// GridView) crashes on device with `Infinity or NaN toInt`-style layout
/// exceptions.
///
/// CRITICAL BLIND SPAT THIS FILE CLOSES: when PerfScope is NOT initialized
/// the scaffold swaps every child for a disabled notice, so pumping the app
/// without an engine exercises NONE of the scenario layouts. These tests
/// therefore initialize a silent engine first and only then pump every
/// route, asserting no layout exception is thrown.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PerfScope.initialize(
      config: const PerfScopeConfig(logStyle: PerfScopeLogStyle.silent),
    );
  });

  tearDown(() async {
    await PerfScope.dispose();
  });

  testWidgets('home renders all category sections', (tester) async {
    await tester.pumpWidget(const ShowcaseApp());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('PerfScope Showcase'), findsOneWidget);
  });

  for (final Scenario scenario in showcaseScenarios) {
    testWidgets('${scenario.route} lays out with the engine enabled', (
      tester,
    ) async {
      await tester.pumpWidget(ShowcaseApp(initialRoute: scenario.route));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Scenario screen at ${scenario.route} threw during layout. '
            'Remember the ScenarioScaffold contract: children get unbounded '
            'height, so embedded viewports need explicit extents.',
      );
      expect(find.byType(ScenarioScaffold), findsOneWidget);
    });
  }
}
