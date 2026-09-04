/// Shared snapshot layer, Slices 1–2: status + AI context + session/stats/
/// anomalies/context/traces.
///
/// The ONLY place that calls `reportForExport` / `buildAiContext*` for the
/// live bridge. HTTP routes and (later) MCP tools are thin bindings over
/// these functions — no transport may reimplement projection logic.
///
/// Slice-2 projections are derived by calling the REAL `SessionSerializer`
/// on `reportForExport(session)` and slicing the resulting map
/// (filter/clamp/project) — never hand-formatted, so a v1 key change moves
/// both paths together. Clamp bounds come from the core stores
/// (`maxStoredAnomalies` / `maxStoredTraces`), never copied literals.
///
/// Import discipline: `package:perfscope` + `flutter/foundation` (build mode)
/// only. No socket imports, no HTTP types, no MCP types.
library;

import 'package:flutter/foundation.dart' show kProfileMode;
import 'package:perfscope/perfscope.dart';

/// Live status document (spec Req-HTTP-STATUS shape).
///
/// `uptimeMs` is milliseconds since bind (monotonic clock, owned by the io
/// backend's `Stopwatch`); `session` is the currently open session or null;
/// `budget` reuses the session environment values, or null when no session
/// ever existed.
Map<String, Object?> liveStatus({required int uptimeMs}) {
  final engine = PerfScope.maybeEngine;
  final current = PerfScope.currentSession;
  final budgetSource =
      current?.environment ?? engine?.lastFinishedSession?.environment;
  return <String, Object?>{
    'schema_version': 1,
    'enabled': engine != null,
    'mode': kProfileMode ? 'profile' : 'debug',
    'session': current == null
        ? null
        : <String, Object?>{
            'id': current.id,
            if (current.name != null) 'name': current.name,
          },
    'uptime_ms': uptimeMs,
    'budget': budgetSource == null
        ? null
        : <String, Object?>{
            'frame_budget_fps': budgetSource.frameBudgetFps,
            'frame_budget_ms': budgetSource.frameBudgetMs,
            'frame_budget_source': budgetSource.frameBudgetSource.name,
          },
  };
}

/// Validation failure with 400 `bad_request` semantics.
///
/// Thrown by the Slice-2 snapshot fns for non-integer/zero/negative limits
/// and unknown severity/type filters. The router catches it and answers 400
/// with the uniform error envelope; in-process callers observe the throw.
final class LiveBadRequest implements Exception {
  /// Creates a failure carrying a human-readable [message].
  const LiveBadRequest(this.message);

  /// Human-readable reason (surfaced as the envelope `message`).
  final String message;

  @override
  String toString() => 'LiveBadRequest: $message';
}

/// Resolves the snapshot source session: open first, last finished fallback.
PerformanceSession? _snapshotSession() =>
    PerfScope.currentSession ?? PerfScope.maybeEngine?.lastFinishedSession;

/// Full schema-v1 session document with complete context windows resolved.
///
/// Byte-shape-identical to `SessionSerializer.serialize` over
/// `reportForExport(session)` with `includeContextWindows: true` (pending
/// windows skipped silently per serializer contract). Null when no session
/// was ever recorded (the router maps this to 404 `no_session`).
Map<String, Object?>? liveSessionDocument() {
  final engine = PerfScope.maybeEngine;
  final session = _snapshotSession();
  if (engine == null || session == null) {
    return null;
  }
  return const SessionSerializer().serialize(
    reportForExport(session),
    resolveContextWindow: engine.contextWindowFor,
  );
}

/// Schema-v1 `summary` block for the source session.
///
/// Projected by serializing the full document with the REAL serializer and
/// extracting `['summary']`, so rounding/keys can never drift from schema.
/// The router wraps it as `{"schema_version": 1, "summary": …}`.
/// Null when no session was ever recorded (router → 404 `no_session`).
Map<String, Object?>? liveFramesStats() {
  final session = _snapshotSession();
  if (PerfScope.maybeEngine == null || session == null) {
    return null;
  }
  final doc = const SessionSerializer().serialize(reportForExport(session));
  return (doc['summary'] as Map).cast<String, Object?>();
}

/// Filtered anomaly wrapper over the engine ring (`PerfScope.anomalies`).
///
/// Shape: `{"schema_version": 1, "total": matching-before-limit,
/// "limit": effective, "anomalies": [schema-v1 entries, chronological,
/// context windows NOT inline>]}`. Entries are the REAL serializer output
/// for the engine ring (via a report carrying exactly those anomalies), so
/// the `type` vocabulary can never drift; filters match on the emitted wire
/// strings with AND semantics. `limit` omitted serves all matching;
/// explicit values clamp into `[1, maxStoredAnomalies]` (core constant).
/// Throws [LiveBadRequest] for `limit <= 0` and unknown severity/type.
/// Null when no session was ever recorded (router → 404 `no_session`).
Map<String, Object?>? liveAnomalies({
  int? limit,
  String? severity,
  String? type,
}) {
  final session = _snapshotSession();
  if (PerfScope.maybeEngine == null || session == null) {
    return null;
  }
  if (limit != null && limit <= 0) {
    throw LiveBadRequest('Invalid limit "$limit": must be >= 1.');
  }
  if (severity != null &&
      !AnomalySeverity.values.any((s) => s.name == severity)) {
    throw LiveBadRequest('Unknown severity "$severity".');
  }
  if (type != null && !kKnownAnomalyTypes.contains(type)) {
    throw LiveBadRequest('Unknown anomaly type "$type".');
  }
  final anomalies = PerfScope.anomalies;
  final doc = const SessionSerializer().serialize(
    PerformanceReport(
      session: session,
      statistics: session.statistics(),
      screens: const [],
      interactions: const [],
      traces: const [],
      anomalies: anomalies,
      worstAnomalies: anomalies,
    ),
  );
  var entries = (doc['anomalies'] as List).cast<Map<String, Object?>>();
  if (severity != null) {
    entries = entries.where((e) => e['severity'] == severity).toList();
  }
  if (type != null) {
    entries = entries.where((e) => e['type'] == type).toList();
  }
  final total = entries.length;
  final effective = limit == null
      ? total
      : (limit > maxStoredAnomalies ? maxStoredAnomalies : limit);
  return <String, Object?>{
    'schema_version': 1,
    'total': total,
    'limit': effective,
    'anomalies': entries.take(effective).toList(),
  };
}

/// Context window for one anomaly id, or null when unknown, evicted, or
/// still pending (incomplete). Complete windows reuse the serializer's
/// context-frame math (`microsToMsRounded`) with v1 frame keys.
///
/// Null ALSO covers "no session ever" — the router checks session
/// existence first and answers `no_session` there, so a null here with a
/// live session always means 404 `context_unavailable`.
Map<String, Object?>? liveAnomalyContext(String id) {
  final engine = PerfScope.maybeEngine;
  if (engine == null || _snapshotSession() == null) {
    return null;
  }
  final window = engine.contextWindowFor(id);
  if (window == null || !window.isComplete) {
    return null;
  }
  Map<String, Object?> frameEntry(FrameSample frame) => <String, Object?>{
        'build_ms': microsToMsRounded(frame.buildDuration.inMicroseconds),
        'raster_ms': microsToMsRounded(frame.rasterDuration.inMicroseconds),
        'total_ms': microsToMsRounded(frame.totalDuration.inMicroseconds),
      };
  return <String, Object?>{
    'schema_version': 1,
    'anomaly_id': id,
    'is_complete': true,
    'context_window': <String, Object?>{
      'before': window.before.map(frameEntry).toList(),
      'after': window.after.map(frameEntry).toList(),
    },
  };
}

/// Trace wrapper over the engine ring (`PerfScope.recentTraces`).
///
/// Shape: `{"schema_version": 1, "total": stored, "limit": effective,
/// "traces": [<schema-v1 entries, chronological>]}`. Entries are the REAL
/// serializer output for exactly the stored traces. `limit` omitted serves
/// all stored; explicit values clamp into `[1, maxStoredTraces]`.
/// Throws [LiveBadRequest] for `limit <= 0`.
/// Null when no session was ever recorded (router → 404 `no_session`).
Map<String, Object?>? liveTraces({int? limit}) {
  final session = _snapshotSession();
  if (PerfScope.maybeEngine == null || session == null) {
    return null;
  }
  if (limit != null && limit <= 0) {
    throw LiveBadRequest('Invalid limit "$limit": must be >= 1.');
  }
  final traces = PerfScope.recentTraces;
  final doc = const SessionSerializer().serialize(
    PerformanceReport(
      session: session,
      statistics: session.statistics(),
      screens: const [],
      interactions: const [],
      traces: traces,
      anomalies: const [],
      worstAnomalies: const [],
    ),
  );
  final entries = (doc['traces'] as List).cast<Map<String, Object?>>();
  final total = entries.length;
  final effective = limit == null
      ? total
      : (limit > maxStoredTraces ? maxStoredTraces : limit);
  return <String, Object?>{
    'schema_version': 1,
    'total': total,
    'limit': effective,
    'traces': entries.take(effective).toList(),
  };
}

/// Resolves the AI-context source session: open first, last finished fallback.
PerformanceSession? _aiContextSession() =>
    PerfScope.currentSession ?? PerfScope.maybeEngine?.lastFinishedSession;

/// Live AI context as plain text, byte-identical to the in-process rendering
/// with `const AiContextConfig()`. Null when no session ever existed (the
/// router maps this to 404 `no_session` — never an empty context).
String? liveAiContextText() {
  final session = _aiContextSession();
  if (session == null) {
    return null;
  }
  return buildAiContextText(
    reportForExport(session),
    config: const AiContextConfig(),
  );
}

/// Live AI context as a JSON-encodable map, deep-equal to the in-process
/// rendering with `const AiContextConfig()`. Null when no session ever
/// existed. The optional [now] clock exists for deterministic tests.
Map<String, Object?>? liveAiContextJson({DateTime Function()? now}) {
  final session = _aiContextSession();
  if (session == null) {
    return null;
  }
  return buildAiContextJson(
    reportForExport(session),
    config: const AiContextConfig(),
    now: now,
  );
}
