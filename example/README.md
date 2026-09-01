# PerfScope Scenario Showcase

**Languages:** [English](README.md) · [Español](README.es.md) · [Português](README.pt.md)

A professional, categorized showcase app exercising every PerfScope capability
against the real API surface - no mocks, no fakes. Each scenario is a dedicated
screen that explains what PerfScope captures, shows the exact usage code on
screen (copy-paste-correct), and renders live results from real engine events.

## Entry points

### Recommended: profile mode with PerfScope enabled

```bash
flutter run --profile -t lib/main_profile.dart
```

`main_profile.dart` calls `bootstrapPerfScope()` from `perf_bootstrap.dart`,
which initializes the engine with `PerfScopeConfig(printWarnings: true)`,
registers a shared `MemorySink`, opens the named `'showcase'` session, and
attaches `PerfScopeNavigatorObserver()` so named routes become screen names.

Running in debug builds instead prints exactly one warning line:

```text
[PerfScope] Running in DEBUG mode: performance measurements are NOT representative of real-world behavior. Use `flutter run --profile` for trustworthy numbers.
```

Frame numbers measured in debug mode carry assertions and JIT overhead; treat
them as directional only.

### Release-safe baseline (degraded showcase)

```bash
flutter run -t lib/main.dart
```

`main.dart` contains no PerfScope import and no initialization. The app still
runs: every scenario screen detects the disabled engine and replaces its action
area with an explicit notice ("PerfScope is disabled in this entry point...")
instead of crashing or silently showing empty results. The home screen shows an
equivalent status banner. Use this entry to verify release builds stay clean.

## Scenarios

| Category | Scenario | Route | API exercised | What to watch for |
| --- | --- | --- | --- | --- |
| Frames | Smooth navigation baseline | `/frames/smooth-navigation` | `PerfScopeNavigatorObserver` | ScreenEvents with route names; zero anomalies |
| Frames | UI-thread jank | `/frames/ui-thread-jank` | none (passive detection) | Slow/severe frame anomalies, probable bottleneck UI |
| Frames | Raster pressure | `/frames/raster-pressure` | none (passive detection) | Raster-bound anomalies; raster_ms dominating |
| Frames | Long scroll list | `/frames/long-scroll-list` | none (passive detection) | Rising slow-frame count under one screen name |
| Tracing | Synchronous trace | `/tracing/sync-trace` | `PerfScope.trace`, `recentTraces` | CompletedTrace records with metadata attached |
| Tracing | Async trace: long operation | `/tracing/async-trace-long-operation` | `PerfScope.traceAsync`, `anomalies` | LongTraceAnomaly scaled against `longTraceThreshold` |
| Context | Interaction spans | `/context/interaction-spans` | `startInteraction`, `interaction` | start/end pairs with durations; quick markers |
| Context | Screen context override | `/context/screen-context` | `screen()`, `setMetadata` | ScreenEvent with reason `manual`; metadata merge |
| Sessions & reports | Session report | `/sessions/session-report` | `startSession`, `stopSession`, `formatReportText` | Full text report box on screen |
| Sessions & reports | Live event console | `/sessions/live-event-console` | `events`, `MemorySink` | Raw sealed event hierarchy, severity colored |
| AI & export | AI context viewer | `/ai-export/ai-context-viewer` | `report.toAiContext()` | Token-optimized PERFSCOPE_SESSION block |
| AI & export | Session JSON export | `/ai-export/session-json-viewer` | `exportCurrentSessionAsJson` | Deterministic schema-v1 JSON |
| AI & export | Before / after compare | `/ai-export/before-after-compare` | `compareSessions`, `formatSessionComparison` | Signed deltas; low-sample warnings expected |

The busy loops are device-adaptive: they time a probe batch first and scale to
the target duration, never hardcoding iteration counts.

## Usage snippets by category

Real fragments - the same code each screen displays.

### Frames

```dart
MaterialApp(
  navigatorObservers: [PerfScopeNavigatorObserver()],
  routes: {'/products': (_) => const ProductsScreen()},
);
// Named routes become PerfScope screen names automatically.
```

Jank recipes need no API at all: synchronous work inside `build` or expensive
paint decorations blow the budget and PerfScope classifies the frames on its
own (`UiBoundFrameAnomaly`, `RasterBoundFrameAnomaly`).

### Tracing

```dart
final prices = PerfScope.trace('calculate_prices', () => computePrices(cart));
await PerfScope.traceAsync('load_products', () async {
  await api.loadProducts(); // > longTraceThreshold raises LongTraceAnomaly
});
print(PerfScope.recentTraces.length);
```

### Context

```dart
final handle = PerfScope.startInteraction('checkout');
await pay();
handle.end();
PerfScope.interaction('add_to_cart'); // quick marker

PerfScope.screen('checkout', metadata: {'step': 'payment'}); // manual override
PerfScope.setMetadata('cart_items', 3);
```

### Sessions and reports

```dart
PerfScope.startSession('release-check'); // auto-finalizes previous
await runWorkload();
final report = await PerfScope.stopSession();
print(formatReportText(report)); // reports have NO toText()

PerfScope.events.listen((PerformanceEvent event) {
  if (event is AnomalyEvent) debugPrint(event.anomaly.severity.name);
});
```

### AI and export

```dart
Clipboard.setData(ClipboardData(text: report.toAiContext()));
final json = PerfScope.exportCurrentSessionAsJson();

final comparison = PerfScope.compareSessions(beforeReport, afterReport);
print(formatSessionComparison(comparison)); // negative delta = improvement
```

## Project layout

```text
lib/
  main.dart                  release-safe entry (no PerfScope)
  main_profile.dart          profile entry: bootstrap + navigator observer
  perf_bootstrap.dart        shared MemorySink + initialize/shutdown helpers
  app/
    showcase_app.dart        MaterialApp shell and named routes
    scenario.dart            Scenario model, categories, catalog
    scenario_card.dart       home-list card per scenario
    scenario_scaffold.dart   shared detail scaffold (summary/captures/code)
    code_block.dart          monospace selectable snippet container
    busy_work.dart           adaptive CPU-spin helper shared by scenarios
  scenarios/
    frames/                  navigation baseline + three jank recipes
    tracing/                 sync traces and long async traces
    context/                 interaction spans and manual screen context
    sessions/                session reports and live event console
    ai_export/               AI context, JSON export, before/after compare
```

## End-to-end tests

`integration_test/perfscope_e2e_test.dart` drives this app by its home tiles
(`menu-tile<route>` keys) through a real engine with an injected `MemorySink`,
asserting frame anomaly detection, session lifecycle, JSON round-trip parsing,
and named-route screen attribution.
