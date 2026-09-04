# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Live bridge (loopback + MCP)

- Opt-in live server: `LivePerfScope.serve()` in a profile entrypoint serves
  read-only snapshots over `127.0.0.1` (token-gated, auto-closing, SSE event
  stream at `GET /v1/events`). Kill switch: `enabled: false` or
  `PERFSCOPE_LIVE=0`.
- Discovery file `.dart_tool/perfscope-live.json` (port, full local-only
  token, pid, project root, timestamp; deleted on close).
- Bridge CLI: `perfscope mcp run` exposes six tools (`perfscope_status`,
  `perfscope_session`, `perfscope_anomalies`, `perfscope_anomaly_context`,
  `perfscope_traces`, `perfscope_ai_context`) over stdio JSON-RPC;
  `perfscope mcp install [--agent claude|codex|pi|cursor|vscode|--all]`
  registers the bridge additively. Global install:
  `flutter pub global activate perfscope`.

## 0.1.0 - 2026-09-03

Local performance observability for Flutter: on-device frame anomaly
detection, sessions, reports, comparisons, and AI-ready context. No cloud,
no backend, no DevTools dependency.

### Core engine

- Frame monitoring via `SchedulerBinding.addTimingsCallback` with
  O(1) per-frame classification into normal / warning / slow / severe levels
  against a configurable frame budget (default 60 Hz; refresh-rate resolution
  with documented fallback provenance).
- Likely-bottleneck heuristic per slow frame (UI / raster / mixed
  / unknown) derived from build-vs-raster timing shapes.
- Failure containment: exceptions inside PerfScope are routed to the
  log writer and never propagate to the host app.
- Injectable `Clock`, fire-and-forget engine start, idempotent initialize,
  hot-restart-friendly dispose.

### Anomalies

- Five anomaly types: `SlowFrameAnomaly`, `UiBoundFrameAnomaly`,
  `RasterBoundFrameAnomaly`, `MixedFrameAnomaly` and `LongTraceAnomaly`.
- Severity contract: slow frames map to high, severe ones to critical;
  warning-level frames never become anomalies. Long traces
  escalate at 2x/5x of the configured threshold (default 50 ms).
- Bounded frame context windows around each frame anomaly
  (`contextFramesBefore` / `contextFramesAfter`).

### Context attribution

- Screen tracking via `PerfScopeNavigatorObserver` or
  manual `PerfScope.screen()` override; unnamed routes are
  normalized to `'unknown'`.
- Interactions: fast one-shot markers plus nestable spans with
  parent id linking and depth guard; out-of-order span
  closes supported.
- Validated metadata store with defensive copy.

### Manual tracing

- `PerfScope.trace` / `traceAsync` with record-first-rethrow-untouched
  failure semantics and Timeline integration (sync spans
  via `Timeline.startSync`, async ones via `TimelineTask`),
  both guarded against adapter failures.

### Sessions, reports, comparisons

- Auto-started or manual sessions; double start auto-finalizes the
  previous session; explicit stop returns a complete `PerformanceReport` and
  attaches it to the finished session for later export.
- Session statistics: exact counters/sums/worst frame plus nearest-rank
  percentiles over a bounded sliding window
  (`maxStatisticSamples`, default 10,000).
- Per-screen and per-interaction summaries with deterministic ranking;
  top-10 worst anomalies list.
- Pure before/after `SessionComparator` with formatted comparison
  tables.

### Export & serialization

- Deterministic v1 JSON schema with parser round-trip guarantee;
  exports work mid-session (minimal snapshot) and after
  stop (fallback to the attached report).
- Export seams: `CallbackExporter`, `InMemoryExporter`,
  `TextExporter`.

### Logging

- Four output styles (`silent`, `compact`, `pretty`, `json`/NDJSON) with
  deterministic renderers covered by snapshot tests; raw event
  stream (`PerfScope.events`) and injectable sinks alongside logging.

### AI integration

- Token-optimized AI context builders (`buildAiContextText`,
  `buildAiContextJson`) that omit missing data instead of inventing it.

### Tooling

- Offline CLI (`dart run perfscope:perfscope`) with `analyze`,
  `report`, `compare`, `ai-context` and `doctor` commands and stable exit codes.
- Benchmark suite under `benchmark/` covering classification,
  ring buffer performance, anomaly creation, statistics, and serialization.
- Demo app under `example/` demonstrating the strict
  profile-only setup.
