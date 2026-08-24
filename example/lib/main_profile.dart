import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import 'app/showcase_app.dart';
import 'perf_bootstrap.dart';

// Profile-only entry point. PerfScope is initialized here and nowhere else;
// the release entry (`main.dart`) has no PerfScope import at all, so the
// observability engine is tree-shaken out of release builds.
//
// Alternative for apps that DO ship in debug builds:
//   if (kDebugMode || kProfileMode) bootstrapPerfScope();
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  bootstrapPerfScope();
  runShowcaseApp(observers: <NavigatorObserver>[PerfScopeNavigatorObserver()]);
}
