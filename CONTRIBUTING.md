# Contributing to PerfScope

Thank you for helping improve PerfScope. This document covers setup,
the quality gates every change must pass, and what reviewers expect.

## Setup

Requirements:

* Flutter SDK (stable channel). The package targets `sdk: ^3.5.0` and
  `flutter: >=3.24.0`.

```bash
git clone <your-fork-url>
cd perfscope
flutter pub get
cd example && flutter pub get && cd ..
```

## Everyday commands

```bash
# Unit tests (the full suite must stay green)
flutter test

# Formatting (CI enforces it exactly)
dart format --output=none --set-exit-if-changed .
dart format .            # apply fixes locally

# Static analysis (zero issues is the bar)
flutter analyze
(cd example && flutter analyze)

# API docs must build without warnings you introduce
dart doc

# Publishability gate (must pass; no placeholders in pubspec)
dart pub publish --dry-run
```

### Benchmarks

Performance-sensitive changes must come with before/after numbers from
the benchmark suite:

```bash
dart run benchmark/frame_classification_benchmark.dart
dart run benchmark/ring_buffer_benchmark.dart
dart run benchmark/anomaly_creation_benchmark.dart
dart run benchmark/statistics_benchmark.dart
dart run benchmark/serialization_benchmark.dart
```

Numbers are machine-specific — report them as relative deltas from your
own machine, never as absolute claims for the README.

### Live-bridge gates (Slice 4: `lib/src/live/` + `lib/src/cli/mcp/`)

The live bridge is a dev-only, loopback-only surface with structural
guarantees enforced by `test/live/import_ban_test.dart` and the
`live-guards` CI job. Every change touching it must keep all of these
green:

```bash
flutter test test/live/import_ban_test.dart test/live/discovery_test.dart \
  test/live/mcp_bridge_test.dart test/live/mcp_install_test.dart
```

* **Release entry stays clean.** `example/lib/main.dart` and
      `lib/perfscope.dart` import zero `src/live` symbols (release builds
      show no size delta — the CI size guard greps this).
* **CLI stays Flutter-free.** Nothing under `lib/src/cli/` or `bin/`
      imports `package:flutter`, `src/live`, or `perfscope_live` (the `mcp
      run` bridge is a separate OS process talking HTTP, never live memory).
* **App never runs stdio.** No file under `lib/src/live/` touches
      `stdin`; bridge stdout is JSON-RPC-only, diagnostics go to stderr.
* **Discovery discipline.** `.dart_tool/perfscope-live.json` holds the
      FULL token (local-only, same-user, never committed) plus connection
      info only — no session payload. Written on bind, deleted on every
      close path, never written when disabled.
* **`mcp install` tests use fixtures only.** Never touch real user
      configs in tests; installs are additive and idempotent.

## Pull request expectations

* **One unit of work per commit.** Each commit is a reviewable unit that
  builds and passes tests on its own. Tests and documentation travel with
  the code they cover, not in a separate "fix tests" commit.
* **Tests included.** Every behavior change or bug fix includes a test
  that fails without it. Bug fixes pin the bug first.
* **Docs updated.** Public API changes update the README snippets and doc
  comments in the same PR. README code samples must compile against real
  signatures.
* **No new dependencies without justification.** The dependency set is
  deliberately minimal (Flutter SDK + `args`). Any new dependency needs a
  written justification in the PR description covering why it cannot be
  avoided and what it costs (size, supply chain, platform scope).
* **Issue first.** Open an issue (or comment on an existing one) describing
  the problem before large refactors or new features. Small, obvious fixes
  may go ahead — link the issue anyway when one exists.

## Scope guide

PerfScope is local-only observability. Rejection is almost certain for:

* anything adding network access, telemetry, or analytics,
* cloud sync features (host apps own transport),
* heavy per-frame work on the hot path (classify + enqueue only),
* speculative metrics without an honest, documented collection mechanism.

## Reporting bugs

Include: Flutter version (`flutter --version`), platform, a minimal
reproduction and — when relevant — an exported session JSON file. Sanitize
any metadata you attached via `PerfScope.setMetadata`; session files
contain exactly what your app put there.
