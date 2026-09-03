# PerfScope

[![pub package](https://img.shields.io/pub/v/perfscope.svg)](https://pub.dev/packages/perfscope) [![pub points](https://img.shields.io/pub/points/perfscope.svg)](https://pub.dev/packages/perfscope/score) [![likes](https://img.shields.io/pub/likes/perfscope.svg)](https://pub.dev/packages/perfscope/score) [![CI](https://github.com/EndersonPro/perfscope/actions/workflows/ci.yml/badge.svg)](https://github.com/EndersonPro/perfscope/actions/workflows/ci.yml) [![codecov](https://codecov.io/gh/EndersonPro/perfscope/graph/badge.svg)](https://codecov.io/gh/EndersonPro/perfscope) [![License: MIT](https://img.shields.io/github/license/EndersonPro/perfscope.svg)](https://github.com/EndersonPro/perfscope/blob/main/LICENSE) [![Dart](https://img.shields.io/badge/dart-%5E3.5.0-blue.svg)] [![Flutter](https://img.shields.io/badge/flutter-%3E%3D3.24.0-blue.svg)]

**Local performance observability for Flutter.**

- No cloud.
- No backend.
- No DevTools dependency.

**Languages:** [English](README.md) · [Español](README.es.md) · [Português](README.pt.md)

PerfScope detects frame anomalies, tracks screens and interactions, records
sessions, compares regressions against baselines, and generates AI-ready
performance reports — entirely on-device and in-process.

## Why PerfScope

DevTools answers "what happened in THIS tethered session?". PerfScope answers
"how does my app behave during REAL usage, on real devices, over time?" —
without a desktop connection:

- **Always-on frame monitoring** via `SchedulerBinding.addTimingsCallback`,
  classified into severity tiers with a probable-bottleneck heuristic.
- **Sessions** you control: auto-started, named, stopped, compared.
- **Shareable artifacts**: deterministic JSON (schema v1), formatted text
  reports, before/after comparison tables.
- **AI-ready output**: a token-optimized context block you can paste straight
  into an LLM conversation to debug a jank regression.

PerfScope observes; it never transmits. See [Privacy](#privacy).

## Installation

```bash
flutter pub add --dev perfscope
```

PerfScope is a *dev dependency*: it is instrumentation you run while
developing and profiling, not something your production users need.

## 30-second setup

```dart
import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PerfScope.initialize();
  runApp(const MyApp());
}
```

That's it. A session starts automatically (`autoStartSession` defaults to
`true`), frames are classified as they arrive, anomalies print to the console,
and `await PerfScope.stopSession()` returns the full `PerformanceReport`.

> **Warning — Profile mode only for trustworthy numbers.**
> Debug builds carry assertions and JIT overhead: frame timings measured under
> `flutter run` (debug) are NOT representative of real-world behavior.
> PerfScope prints exactly one warning when initialized in debug mode:
>
> ```
> [PerfScope] Running in DEBUG mode: performance measurements are NOT
> representative of real-world behavior. Use `flutter run --profile` for
> trustworthy numbers.
> ```
>
> Always measure with `flutter run --profile`.

### Strict profile-only setup (recommended)

The example app demonstrates the cleanest arrangement: release entry points
never import PerfScope at all, so the observability code is tree-shaken out of
release builds entirely. Three files:

```dart
// lib/main.dart — RELEASE entry. No PerfScope import anywhere.
import 'app/showcase_app.dart';

void main() => runShowcaseApp();
```

```dart
// lib/main_profile.dart — PROFILE entry. PerfScope initializes here only.
import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import 'app/showcase_app.dart';
import 'perf_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  bootstrapPerfScope();
  runShowcaseApp(observers: <NavigatorObserver>[PerfScopeNavigatorObserver()]);
}
```

```dart
// lib/perf_bootstrap.dart — engine wiring only: shared MemorySink,
// PerfScope.initialize(config:, sinks:), named session open/close.
```

Run it with:

```bash
flutter run --profile -t lib/main_profile.dart
```

If your app must also work in debug builds, initialize behind a mode check:
`if (kDebugMode || kProfileMode) PerfScope.initialize();`.

## Scenario showcase

The `example/` package is a categorized scenario-showcase app: every PerfScope
capability gets a dedicated screen that explains what is captured, displays the
exact usage code on screen, and renders live results from real engine events -
frame jank recipes, tracing, interaction/screen context, sessions and reports,
live event console, AI context, JSON export, and before/after comparison. It
also demonstrates graceful degradation when PerfScope is not initialized.

See [example/README.md](example/README.md) for run instructions, the
scenario-to-API map, and per-category code snippets.

## Frame monitoring

PerfScope subscribes to Flutter's frame timing stream once, per engine start.
Every completed frame becomes an immutable `FrameSample`
(build / raster / total durations vsync overhead) enriched with the current
screen and interaction attribution, then classified against the effective
frame budget:

| Total duration vs budget | Tier    |
|--------------------------|---------|
| <= budget                | normal  |
| > budget                 | warning |
| > budget x 1.5           | slow    |
| > budget x 3             | severe  |

The budget defaults to 60 Hz (`targetFrameRate`) and can be overridden or
resolved from refresh-rate detection. Thresholds are configurable through
`PerformanceThresholds(warningMultiplier:, slowMultiplier:, severeMultiplier:)`.

Per-frame bookkeeping is O(1): counters, running sums, and one ring-buffer
slot (see [Performance overhead](#performance-overhead)). Percentile math is
deferred to snapshot time.

## Anomalies

Only slow/severe frames become anomalies — warning-tier frames stay events.
Five anomaly types ship out of the box:

| Type                     | Raised when                                            |
|--------------------------|--------------------------------------------------------|
| `SlowFrameAnomaly`       | slow/severe frame, bottleneck could not be inferred     |
| `UiBoundFrameAnomaly`    | UI-thread work dominates (build >= 2x raster)          |
| `RasterBoundFrameAnomaly`| Raster-thread work dominates (raster >= 2x build)      |
| `MixedFrameAnomaly`      | Both phases contribute comparably                       |
| `LongTraceAnomaly`       | A manual trace exceeded `longTraceThreshold`            |

Severity mapping (documented contract):

- Frame anomalies: `slow` -> **high**, `severe` -> **critical**. Warning-tier
  frames never reach anomaly creation.
- Long-trace anomalies scale with the configured threshold (default 50 ms):
  >= 2x threshold -> **high**, >= 5x -> **critical**, otherwise **medium**.

The bottleneck is a HEURISTIC derived solely from frame timing shapes. It
indicates the *probable* phase — never proven cause. Recent anomalies are
reachable through `PerfScope.anomalies`, each frame anomaly's surrounding
frames through `PerfScope.contextWindowFor(anomalyId)`.

## Navigation

Attach the observer and screens name themselves from routes:

```dart
MaterialApp(
  navigatorObservers: [PerfScopeNavigatorObserver()],
  routes: {'/checkout': (_) => const CheckoutScreen()},
)
```

- Named routes become screen names; frames, anomalies, traces, and report
  summaries attribute themselves to the visible screen.
- Apps without a Navigator can override manually:
  `PerfScope.screen('checkout');`.
- Unnamed routes report `'unknown'`. Give important routes names.

## Interactions

Two complementary styles:

**Quick marker** — one-liner for tap-like flows. The marker is attributed to
the very next observed frame batch; nothing else to close:

```dart
PerfScope.interaction('add_to_cart');
```

**Span** — for flows that outlive a single frame. Returns a handle; call
`end()` exactly once (out-of-order endings are supported):

```dart
final handle = PerfScope.startInteraction('checkout');
await pay();
handle.end();
```

Spans nest: each `InteractionEvent` carries the innermost-active span's id as
its parent, so a `tap_pay` inside `checkout` stays attributable. Nesting is
guarded at 16 levels (runaway starts are caller bugs; deeper starts return an
inert handle). Frames rendered while a span is open are attributed to it —
temporal correlation, not causation.

## Tracing

Time any operation and feed both the session record and the Timeline:

```dart
final prices = PerfScope.trace('calculate_prices', () =>
    computePrices(items));

final user = await PerfScope.traceAsync('fetch_user', () => api.getUser());
```

Exception contract: if `body` throws, PerfScope records the trace as failed
(`didThrow`, duration included) and then rethrows the ORIGINAL error and stack
trace untouched. Metadata passed via `metadata:` is validated and embedded in
the resulting event. Traces exceeding `longTraceThreshold` (default 50 ms)
raise a `LongTraceAnomaly`.

Timeline integration: synchronous traces emit `Timeline.startSync` /
`finishSync`; async traces emit `TimelineTask` spans (the SDK has no async
`startSync`). Adapter failures are swallowed — Timeline problems can never
break app flow. Recent traces: `PerfScope.recentTraces`.

## Sessions

A session is one recorded observation window. By default one starts
automatically at `initialize()`.

```dart
final session = PerfScope.startSession('release-check'); // auto-finalizes any open session
// ... exercise the app ...
final report = await PerfScope.stopSession(); // full PerformanceReport
```

- Double-start is safe: opening a new session auto-finalizes the previous one
  (its report stays reachable via its attached report).
- Consecutive `stopSession()` calls throw — there is nothing open.
- `PerfScope.currentSession` and `PerfScope.lastReport` answer passively;
  they never throw.

## Logs

Four styles via `PerfScopeConfig(logStyle:)`: `silent`, `compact`, `pretty`,
`json`. Samples below are exact renderer output.

**compact** — one line per anomaly/warning:

```text
PERF ProductList | UI 27.4ms | Raster 4.8ms | Total 33.1ms | Budget 16.7ms | HIGH ui-bound
PERF TRACE calculate_prices | 127.0ms | HIGH
```

**pretty** (default) — box-drawing cards:

```text
╭──────────────────────────────────────────────────────────╮
│ PerfScope — Performance anomaly                          │
├──────────────────────────────────────────────────────────┤
│ Screen        ProductList                                │
│ Interaction   product_list_scroll                        │
│                                                          │
│ Build         27.400 ms                                  │
│ Raster         4.800 ms                                  │
│ Total         33.100 ms                                  │
│ Budget        16.667 ms                                  │
│                                                          │
│ Severity      HIGH                                       │
│ Type          UiBoundFrame                               │
│ Probable      UI                                         │
╰──────────────────────────────────────────────────────────╯
```

**json** — NDJSON envelopes, machine-parseable:

```json
{"schema_version":1,"type":"performance_anomaly","anomaly_type":"ui_bound_frame","event_id":"evt_1","session_id":"ses_1","timestamp":"2026-01-01T00:00:00.000Z","screen":"ProductList","interaction_id":"int_1","frame":{"build_ms":27.4,"raster_ms":4.8,"total_ms":33.1,"budget_ms":16.67},"severity":"high","probable_bottleneck":"ui"}
```

**silent** — no output.

Raw events bypass logging entirely through the broadcast `PerfScope.events`
stream and injectable sinks.

## Reports

Stopping a session renders a fixed-width summary box (identical layout via
`TextExporter` or `formatReportText`):

```text
╭──────────────────────────────────────────────────────────╮
│ PerfScope — Session Summary                              │
├──────────────────────────────────────────────────────────┤
│ Session                    ses_7                         │
│ Duration                  1m 00s                         │
│ Frames                       400                         │
│ Slow frames                    1                         │
│ Severe frames                  0                         │
│ Slow-frame rate            0.25%                         │
│ Worst frame              32.2 ms                         │
│                                                          │
│ p50                      10.0 ms                         │
│ p90                      13.4 ms                         │
│ p95                      14.1 ms                         │
│ p99                      15.0 ms                         │
╰──────────────────────────────────────────────────────────╯
```

Reports rank screens and interactions deterministically (anomaly count, then
p95, then name) and list the worst anomalies first.

## JSON export

Deterministic single-line JSON, schema version 1:

```dart
final json = PerfScope.exportCurrentSessionAsJson();

// After stopSession() there is no OPEN session anymore; the export falls
// back to the last finished session's attached report instead of returning
// null, so post-stop export just works.
final report = await PerfScope.stopSession();
final stopped = PerfScope.exportCurrentSessionAsJson();
```

Round-trip guarantee — everything the writer emits, the parser reads back:

```dart
final parsed = SessionParser().parseString(json);
expect(parsed.session.id, originalId); // in tests
```

Destinations are host concerns; PerfScope ships three seams:

- `CallbackExporter(onJson:)` — you decide where bytes go.
- `InMemoryExporter` — buffers JSON strings for tests/debug screens.
- `TextExporter` — human-readable summary box.

## AI Context

One call turns a report into LLM-ready context
(`report.toAiContext()` or `buildAiContextText(report)`):

```text
PERFSCOPE_SESSION

name: checkout-performance
duration: 4m 32s
frames: 18421
slow_frames: 37
slow_frame_rate: 0.20%

p50_ms: 7.1
p95_ms: 14.4
p99_ms: 28.7
worst_frame_ms: 71.3

TOP_ISSUES:

1:
screen: ProductList
anomalies: 12
worst_frame_ms: 46
p95_ms: 29
probable_bottleneck: UI
```

Output is token-optimized, hard-capped, and never invents data it does not
have. Pipe it through the CLI: `dart run perfscope:perfscope ai-context
session.json > context.txt`.

Recommended prompt to pair with it:

```text
You are a senior Flutter performance engineer. Below is a PerfScope session
summary captured on-device in profile mode. Identify the most probable root
causes, rank them by user impact (p95/worst frames, anomaly density), and
propose concrete code-level fixes. Treat probable_bottleneck values as
heuristics derived from frame timing shapes, not proven causes; recommend
timeline tracing where certainty is needed.

<paste context.txt here>
```

## Before/After comparisons

Pure, engine-free comparison of any two reports:

```dart
final comparison = PerfScope.compareSessions(baselineReport, candidateReport);
print(formatSessionComparison(comparison));
```

Or straight from files:

```bash
dart run perfscope:perfscope compare baseline.json candidate.json
```

Metric deltas are reported per label (frames, p50/p95/p99, worst frame,
anomalies, ...) so regressions surface as signed percentages instead of gut
feelings.

## CLI

Offline tooling over exported session files:

```text
Usage: dart run perfscope:perfscope <command> [arguments]

Commands:
  analyze <session.json>       Compact session summary
  report <session.json>        Full formatted session report
  compare <before> <after>     Before/after comparison table
  ai-context <session.json>    AI-ready context (for shell redirection)
  doctor                       Environment checks

Exit codes:
  0 success   1 usage error   2 unreadable file
  3 invalid session file   4 doctor found missing requirements
```

Sanity-check your environment (actual output; versions vary by machine):

```text
$ dart run perfscope:perfscope doctor
ok   Flutter detected (3.44.1)
ok   Dart detected (3.12.1)
ok   pubspec.yaml found
ok   Project detected (perfscope)

Recommended performance mode:
  flutter run --profile
```

## Privacy

PerfScope collects NOTHING and transmits NOTHING. There is no network code in
the package — not for telemetry, not for error reporting, not for "anonymous
usage statistics". Explicitly, PerfScope never touches:

- device identifiers or advertising IDs,
- user identifiers or account data,
- screen contents, text entered, or images rendered,
- crash logs or stack traces of YOUR exceptions (only PerfScope's own traced
  failures are recorded, locally),
- any analytics or telemetry pipeline.

Everything lives in bounded in-process memory until YOU export it through your
own chosen channel. Correlation ids (`ses_1`, `anm_2`, `trc_3`) are local-only
sequence numbers — useful within one process, meaningless outside it.

## Performance overhead

Honest accounting:

- Per-frame work is classification plus enqueue ONLY: a few integer
  comparisons, counter updates, and one slot write into a preallocated ring
  buffer. No allocation per frame, no sorting, no string building.
- Percentiles sort a bounded window (default 10,000 samples) only when a
  snapshot/export happens — never on the frame path.
- Absolute numbers vary by device; do not trust anyone else's benchmarks,
  including these docs. Run them yourself:

```bash
dart run benchmark/frame_classification_benchmark.dart
dart run benchmark/ring_buffer_benchmark.dart
dart run benchmark/anomaly_creation_benchmark.dart
dart run benchmark/statistics_benchmark.dart
dart run benchmark/serialization_benchmark.dart
```

Each prints median ns/op and ops/sec over timed batches after warmup.

## Platform support

| Capability                        | Android | iOS | macOS | Windows | Linux | Web |
|-----------------------------------|---------|-----|-------|---------|-------|-----|
| Frame monitoring (`FrameTiming`)  | yes     | yes | yes   | yes     | yes   | ?   |
| Manual tracing / interactions     | yes     | yes | yes   | yes     | yes   | yes |
| Sessions, reports, JSON, CLI      | yes     | yes | yes   | yes     | yes   | yes |

Refresh-rate detection is platform-dependent: where the OS will not disclose
the display's actual refresh rate, PerfScope falls back to the configured
budget and says so in the session environment (`frameBudgetSource`).

The web column for frame monitoring is an honest `?`: Flutter's
`addTimingsCallback` web behavior is undocumented upstream, so PerfScope makes
no claim it cannot verify. Everything else is pure Dart and works everywhere
Dart runs.

## Architecture

One glance at `lib/src`:

```
core/          engine wiring, config, clock abstraction, id generators
frames/        FrameSample, classifier, budgets, Flutter frame source
anomalies/     anomaly models, detector, frame context windows
buffers/       RingBuffer — the only mutable hot-path structure
context/       screen tracker, interaction tracker, metadata store
events/        the typed event hierarchy (frame/screen/interaction/trace/anomaly/lifecycle)
sessions/      session lifecycle and aggregates
reporting/     statistics, screen/interaction summaries, report builder, comparisons
serialization/ schema v1, serializer, parser (round-trip safe)
exporters/     callback / in-memory / text exporters
logging/       log writer + silent/compact/pretty/json renderers
navigation/    navigator observer
traces/        manual trace tracking, Timeline adapters
sinks/         console/json/memory event sinks
ai/            AI context builders
cli/           offline command-line interface
testing/       test fakes and fixtures
```

Dependencies: Flutter SDK and `args` (CLI parsing). Nothing else.

## Limitations

- **FrameTiming cannot name guilty functions.** The engine sees per-phase
  durations, not stack samples. `probableBottleneck` is a heuristic over
  timing shapes; attributing blame to specific widgets requires timeline
  tracing (which PerfScope makes easy, but does not fake).
- **Percentiles come from a bounded rolling window**
  (`maxStatisticSamples`, default 10,000). Long sessions describe their recent
  past, not their entire history; counters and sums stay exact throughout.
- **Unnamed routes report `'unknown'`.** Name your routes.
- **Web frame monitoring is unverified.** `addTimingsCallback` behavior on
  web is undocumented upstream; treat the web column above as unknown rather
  than broken.
- **Correlation ids are process-local** — never use them as database keys.

## Roadmap

- **v0.2** — runtime bridge direction: expose live sessions/streams to
  external tooling (MCP-style integration) so agents and dashboards can query
  PerfScope while the app runs.
- Later — additional metrics beyond frames/traces: CPU, memory, GC pressure,
  isolate activity. Each lands only with an honest, documented collection
  mechanism.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
quality gates, and expectations.

## License

[MIT](LICENSE)
