import 'package:flutter/material.dart';

import '../demo_home_screen.dart';
import '../scenarios/frames/smooth_navigation.dart';
import 'scenario.dart';

/// Shared application shell for both entry points.
///
/// The release entry (`main.dart`) passes no observers and never imports
/// PerfScope; the profile entry (`main_profile.dart`) passes
/// `[PerfScopeNavigatorObserver()]` after initializing the engine. This
/// keeps initialization strictly out of release builds while sharing every
/// other line of app code. Screens degrade gracefully when PerfScope is not
/// enabled: each scenario replaces its action area with an explicit notice.
///
/// Call once from a `main` entry point.
void runShowcaseApp({List<NavigatorObserver>? observers}) {
  runApp(ShowcaseApp(observers: observers));
}

/// Root widget: named-route [MaterialApp] with an optional observer list.
///
/// Every scenario from [showcaseScenarios] is registered under its own
/// const route, plus the smooth-navigation detail subroute which is part of
/// that scenario's flow rather than a standalone entry.
final class ShowcaseApp extends StatelessWidget {
  /// Creates the app shell. Pass [observers] only from instrumented
  /// (profile) entry points.
  const ShowcaseApp({super.key, this.observers});

  /// Navigator observers forwarded to [MaterialApp]; typically exactly one
  /// [PerfScopeNavigatorObserver]-shaped observer in profile runs.
  final List<NavigatorObserver>? observers;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PerfScope Showcase',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      navigatorObservers: observers ?? const <NavigatorObserver>[],
      initialRoute: routeHome,
      routes: <String, WidgetBuilder>{
        routeHome: (_) => const DemoHomeScreen(),
        routeSmoothNavigationDetail: (_) =>
            const SmoothNavigationDetailScreen(),
        for (final Scenario scenario in showcaseScenarios)
          scenario.route: scenario.builder,
      },
    );
  }
}
