import 'package:flutter/material.dart';

import '../scenarios/ai_export/ai_context_viewer.dart';
import '../scenarios/ai_export/before_after_compare.dart';
import '../scenarios/ai_export/session_json_viewer.dart';
import '../scenarios/context/interaction_spans.dart';
import '../scenarios/context/screen_context.dart';
import '../scenarios/frames/long_scroll_list.dart';
import '../scenarios/frames/raster_pressure.dart';
import '../scenarios/frames/smooth_navigation.dart';
import '../scenarios/frames/ui_thread_jank.dart';
import '../scenarios/sessions/live_event_console.dart';
import '../scenarios/sessions/session_report.dart';
import '../scenarios/tracing/async_trace_long_operation.dart';
import '../scenarios/tracing/sync_trace.dart';

/// Route of the categorized showcase home.
const String routeHome = '/';

// ---------------------------------------------------------------------------
// Frames
// ---------------------------------------------------------------------------

/// Baseline healthy navigation between two subroutes.
const String routeSmoothNavigation = '/frames/smooth-navigation';

/// Second subroute pushed by [routeSmoothNavigation]; exists so the
/// navigator observer has a named destination to report.
const String routeSmoothNavigationDetail = '/frames/smooth-navigation/detail';

/// Heavy synchronous build work blowing the frame budget.
const String routeUiThreadJank = '/frames/ui-thread-jank';

/// Expensive paint work stressing the raster thread.
const String routeRasterPressure = '/frames/raster-pressure';

/// Scroll jank over a large, optionally expensive list.
const String routeLongScrollList = '/frames/long-scroll-list';

// ---------------------------------------------------------------------------
// Tracing
// ---------------------------------------------------------------------------

/// Synchronous manual traces via `PerfScope.trace`.
const String routeSyncTrace = '/tracing/sync-trace';

/// Async traces long enough to raise a LongTraceAnomaly.
const String routeAsyncTraceLongOperation =
    '/tracing/async-trace-long-operation';

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

/// Interaction spans and quick markers during a simulated task.
const String routeInteractionSpans = '/context/interaction-spans';

/// Manual screen override plus metadata store demo.
const String routeScreenContext = '/context/screen-context';

// ---------------------------------------------------------------------------
// Sessions and reports
// ---------------------------------------------------------------------------

/// Start, feed, stop, and render a session report as text.
const String routeSessionReport = '/sessions/session-report';

/// Live console over PerfScope.events and the shared MemorySink.
const String routeLiveEventConsole = '/sessions/live-event-console';

// ---------------------------------------------------------------------------
// AI and export
// ---------------------------------------------------------------------------

/// AI-ready context rendering from the last finished session report.
const String routeAiContextViewer = '/ai-export/ai-context-viewer';

/// JSON export viewer for the current or last session.
const String routeSessionJsonViewer = '/ai-export/session-json-viewer';

/// Before/after comparison of two identical workloads.
const String routeBeforeAfterCompare = '/ai-export/before-after-compare';

/// Category a scenario belongs to; drives home-screen grouping.
enum ScenarioCategory {
  /// Frame pipeline behavior: smooth baselines and jank recipes.
  frames,

  /// Manual operation timing through the trace API family.
  tracing,

  /// Screen/interaction attribution context around frames and traces.
  context,

  /// Session lifecycle, live events, and formatted reports.
  sessionsAndReports,

  /// AI-ready output, JSON export, and before/after comparisons.
  aiAndExport,
}

/// Presentation metadata for [ScenarioCategory].
extension ScenarioCategoryInfo on ScenarioCategory {
  /// Short human-readable label used on chips and section headers.
  String get label => switch (this) {
    ScenarioCategory.frames => 'Frames',
    ScenarioCategory.tracing => 'Tracing',
    ScenarioCategory.context => 'Context',
    ScenarioCategory.sessionsAndReports => 'Sessions & reports',
    ScenarioCategory.aiAndExport => 'AI & export',
  };

  /// Accent color identifying the category across the app.
  Color get color => switch (this) {
    ScenarioCategory.frames => const Color(0xFF3F6FD8),
    ScenarioCategory.tracing => const Color(0xFF2E8B6E),
    ScenarioCategory.context => const Color(0xFF9C6F1E),
    ScenarioCategory.sessionsAndReports => const Color(0xFF7A4FB5),
    ScenarioCategory.aiAndExport => const Color(0xFFB54F6E),
  };

  /// Material icon identifying the category on home cards.
  IconData get icon => switch (this) {
    ScenarioCategory.frames => Icons.speed,
    ScenarioCategory.tracing => Icons.timeline,
    ScenarioCategory.context => Icons.my_location,
    ScenarioCategory.sessionsAndReports => Icons.description,
    ScenarioCategory.aiAndExport => Icons.upload_file,
  };
}

/// One entry of the showcase: a dedicated screen demonstrating exactly one
/// PerfScope capability, together with all copy needed to teach it.
///
/// Instances are fully const-capable data; the [builder] indirection keeps
/// route construction lazy like any `MaterialApp.routes` value.
final class Scenario {
  /// Creates a scenario descriptor.
  const Scenario({
    required this.route,
    required this.title,
    required this.category,
    required this.summary,
    required this.captures,
    required this.codeSnippet,
    required this.builder,
  });

  /// Named route the screen lives at; also the screen name PerfScope's
  /// navigator observer reports for it.
  final String route;

  /// Human-readable scenario title.
  final String title;

  /// Grouping category used by the categorized home screen.
  final ScenarioCategory category;

  /// One-line summary shown on the home card and detail header.
  final String summary;

  /// What PerfScope records while this scenario runs.
  final String captures;

  /// Copy-paste-correct usage snippet displayed on the screen.
  final String codeSnippet;

  /// Builds the scenario screen (used as a `MaterialApp` route builder).
  final WidgetBuilder builder;
}

/// Every showcase scenario in intended visiting order, grouped by category
/// on the home screen.
///
/// Not `const` because each entry closes over a widget builder closure;
/// every other field is compile-time constant data.
final List<Scenario> showcaseScenarios = <Scenario>[
  Scenario(
    route: routeSmoothNavigation,
    title: 'Smooth navigation baseline',
    category: ScenarioCategory.frames,
    summary:
        'Navigates between two lightweight subroutes that should stay '
        'inside the frame budget.',
    captures:
        'One FrameEvent per frame classified normal, plus a '
        'ScreenEvent per push/pop with the named routes as screen names.',
    codeSnippet: '''
MaterialApp(
  navigatorObservers: [PerfScopeNavigatorObserver()],
  routes: {'/products': (_) => const ProductsScreen()},
);
// Named routes become PerfScope screen names automatically.''',
    builder: (_) => const SmoothNavigationScreen(),
  ),
  Scenario(
    route: routeUiThreadJank,
    title: 'UI-thread jank',
    category: ScenarioCategory.frames,
    summary:
        'Runs heavy synchronous work inside build, blocking the UI '
        'thread past the frame budget.',
    captures:
        'Slow/severe FrameEvents and frame anomalies whose probable '
        'bottleneck is the UI phase (UiBoundFrameAnomaly).',
    codeSnippet: '''
// Synchronous work inside build blocks the UI thread:
Widget build(BuildContext context) {
  spinFor(const Duration(milliseconds: 60)); // janks this frame
  return const HeavyTree();
}
// PerfScope classifies the blown frame automatically - no API calls.''',
    builder: (_) => const UiThreadJankScreen(),
  ),
  Scenario(
    route: routeRasterPressure,
    title: 'Raster pressure',
    category: ScenarioCategory.frames,
    summary:
        'Rebuilds a grid of heavily decorated cards in bursts to load '
        'the raster thread.',
    captures:
        'Frame anomalies whose probable bottleneck is the raster '
        'phase (RasterBoundFrameAnomaly).',
    codeSnippet: '''
// Layered shadows and gradients make paint expensive:
DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(colors: [base, base.withValues(alpha: .4)]),
    boxShadow: [BoxShadow(blurRadius: 18), BoxShadow(blurRadius: 10)],
  ),
);
// Watch raster_ms dominate build_ms in the captured anomalies.''',
    builder: (_) => const RasterPressureScreen(),
  ),
  Scenario(
    route: routeLongScrollList,
    title: 'Long scroll list',
    category: ScenarioCategory.frames,
    summary:
        'A 500-item list with a toggle between cheap and expensive '
        'tiles to flip mid-scroll.',
    captures:
        'A rising slow-frame count while expensive tiles are on; '
        'per-screen attribution under one stable screen name.',
    codeSnippet: '''
ListView.builder(
  itemCount: 500,
  itemBuilder: (_, i) => expensive ? ExpensiveTile(i) : CheapTile(i),
);
// Flip the toggle mid-scroll and watch slow_frame_rate climb.''',
    builder: (_) => const LongScrollListScreen(),
  ),
  Scenario(
    route: routeSyncTrace,
    title: 'Synchronous trace',
    category: ScenarioCategory.tracing,
    summary:
        'Wraps synchronous work in PerfScope.trace and inspects the '
        'completed-trace window.',
    captures:
        'One TraceEvent and one CompletedTrace per run; metadata is '
        'validated and attached to both.',
    codeSnippet: '''
final prices = PerfScope.trace(
  'calculate_prices',
  () => computePrices(cart),
  metadata: {'items': cart.length},
);
print(PerfScope.recentTraces.length); // bounded completed window''',
    builder: (_) => const SyncTraceScreen(),
  ),
  Scenario(
    route: routeAsyncTraceLongOperation,
    title: 'Async trace: long operation',
    category: ScenarioCategory.tracing,
    summary:
        'Times a multi-hundred-millisecond future with traceAsync until '
        'a LongTraceAnomaly fires.',
    captures:
        'A TraceEvent followed immediately by an AnomalyEvent carrying '
        'a LongTraceAnomaly scaled against longTraceThreshold.',
    codeSnippet: '''
await PerfScope.traceAsync('load_products', () async {
  await api.loadProducts(); // > longTraceThreshold (default 50 ms)
});
final long = PerfScope.anomalies.whereType<LongTraceAnomaly>();''',
    builder: (_) => const AsyncTraceLongOperationScreen(),
  ),
  Scenario(
    route: routeInteractionSpans,
    title: 'Interaction spans',
    category: ScenarioCategory.context,
    summary:
        'Opens an interaction span, drops quick markers inside it, and '
        'ends it out-of-band.',
    captures:
        'InteractionEvent start/end pairs with wall-clock durations, '
        'plus marker events attributed to the next observed frame.',
    codeSnippet: '''
final handle = PerfScope.startInteraction('checkout');
await pay();
handle.end(); // repeated calls are safe no-ops

PerfScope.interaction('add_to_cart'); // quick marker''',
    builder: (_) => const InteractionSpansScreen(),
  ),
  Scenario(
    route: routeScreenContext,
    title: 'Screen context override',
    category: ScenarioCategory.context,
    summary:
        'Manually overrides the current screen and stores metadata '
        'without touching the Navigator.',
    captures:
        'A ScreenEvent with reason manual, metadata merged into every '
        'subsequent record, and the live currentScreen value.',
    codeSnippet: '''
PerfScope.screen('checkout', metadata: {'step': 'payment'});
PerfScope.setMetadata('cart_items', 3);
print(PerfScope.currentScreen); // 'checkout'
''',
    builder: (_) => const ScreenContextScreen(),
  ),
  Scenario(
    route: routeSessionReport,
    title: 'Session report',
    category: ScenarioCategory.sessionsAndReports,
    summary:
        'Opens a named session, runs workload, stops it, and renders '
        'the formatted text report on screen.',
    captures:
        'The full PerformanceReport: exact counters, percentiles, '
        'per-screen/per-interaction summaries, ranked anomalies.',
    codeSnippet: '''
PerfScope.startSession('release-check'); // auto-finalizes previous
await runWorkload();
final report = await PerfScope.stopSession();
final text = formatReportText(report); // reports have NO toText()''',
    builder: (_) => const SessionReportScreen(),
  ),
  Scenario(
    route: routeLiveEventConsole,
    title: 'Live event console',
    category: ScenarioCategory.sessionsAndReports,
    summary:
        'Subscribes to PerfScope.events and mirrors the shared '
        'MemorySink into a severity-colored event list.',
    captures:
        'Every raw PerformanceEvent as it happens: frames, screens, '
        'interactions, traces, anomalies, lifecycle.',
    codeSnippet: '''
PerfScope.events.listen((PerformanceEvent event) {
  if (event is AnomalyEvent) {
    debugPrint(event.anomaly.severity.name); // low..critical
  }
});''',
    builder: (_) => const LiveEventConsoleScreen(),
  ),
  Scenario(
    route: routeAiContextViewer,
    title: 'AI context viewer',
    category: ScenarioCategory.aiAndExport,
    summary:
        'Renders report.toAiContext() from the last finished session '
        'and copies it to the clipboard.',
    captures:
        'The token-optimized PERFSCOPE_SESSION block ready to paste '
        'into an LLM prompt.',
    codeSnippet: '''
final report = PerfScope.lastReport;
if (report != null) {
  Clipboard.setData(ClipboardData(text: report.toAiContext()));
}''',
    builder: (_) => const AiContextViewerScreen(),
  ),
  Scenario(
    route: routeSessionJsonViewer,
    title: 'Session JSON export',
    category: ScenarioCategory.aiAndExport,
    summary:
        'Serializes the open (or last finished) session to schema-v1 '
        'JSON with embedded context windows.',
    captures:
        'Deterministic single-line JSON; null only when nothing was '
        'ever recorded.',
    codeSnippet: '''
final json = PerfScope.exportCurrentSessionAsJson(
  includeContextWindows: true,
);
// Works mid-session (live snapshot) AND after stopSession().''',
    builder: (_) => const SessionJsonViewerScreen(),
  ),
  Scenario(
    route: routeBeforeAfterCompare,
    title: 'Before / after compare',
    category: ScenarioCategory.aiAndExport,
    summary:
        'Records the same workload twice (slow, then optimized) and '
        'compares the two reports.',
    captures:
        'Signed percentage deltas per metric; negative deltas mean '
        'improvement because every compared metric is lower-is-better.',
    codeSnippet: '''
final before = await PerfScope.stopSession();
PerfScope.startSession('after');
await runSameWorkload();
final after = await PerfScope.stopSession();
print(formatSessionComparison(PerfScope.compareSessions(before, after)));''',
    builder: (_) => const BeforeAfterCompareScreen(),
  ),
];
