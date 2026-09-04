/// SSE hub for `GET /v1/events`: anomaly drop-coalesce + reliable session
/// lifecycle markers over a broadcast projection.
///
/// Design §2.4: one subscription to `PerfScope.events` filtered to
/// `AnomalyEvent` only (raw frames/traces/screens NEVER enter the hub) plus a
/// 250 ms `SessionWatcher` comparing `PerfScope.currentSession?.id`. Each
/// connection holds a single `pendingAnomaly` slot (latest wins) plus a FIFO
/// `reliableQueue` for session markers. A 1 s flush timer per connection emits
/// at most ONE `anomaly` then drains ALL reliable markers in order.
/// Serialization (`jsonEncode`) happens in the flush timer — off the frame
/// path. The engine subscription callback NEVER awaits the socket: it only
/// assigns slots synchronously.
///
/// Import discipline: `package:perfscope/perfscope.dart` + `dart:*` only. No
/// HTTP router imports (the router calls into the hub, not vice versa).
library;

import 'dart:async' show StreamSubscription, Timer;
import 'dart:convert' show jsonEncode;
import 'dart:io' show HttpRequest, HttpResponse;

import 'package:perfscope/perfscope.dart';

/// Flush cadence per SSE connection: at most one `anomaly` per interval.
const Duration sseFlushInterval = Duration(seconds: 1);

/// Session polling cadence: two O(1) facade reads per tick, off the frame path.
const Duration sseWatcherInterval = Duration(milliseconds: 250);

/// Wire discriminator for [anomaly], mirroring `SessionSerializer._anomalyType`
/// over the same public constants (so the vocabulary can never drift without
/// a compile-visible change here).
String anomalyWireType(PerformanceAnomaly anomaly) => switch (anomaly) {
      LongTraceAnomaly() => kAnomalyTypeLongTrace,
      SlowFrameAnomaly() => kAnomalyTypeSlowFrame,
      UiBoundFrameAnomaly() => kAnomalyTypeUiBoundFrame,
      RasterBoundFrameAnomaly() => kAnomalyTypeRasterBoundFrame,
      MixedFrameAnomaly() => kAnomalyTypeMixedFrame,
      // Forward-compatibility catch-all, same as the serializer: any future
      // `FrameAnomaly` subclass serializes under the plain slow-frame shape.
      FrameAnomaly() => kAnomalyTypeSlowFrame,
    };

/// Marker payload for one anomaly: id + severity + wire type + timestamp.
///
/// Pure over [anomaly] (no IO) so tests can assert the shape without a socket.
/// Timestamp uses the serializer's UTC ISO-8601 convention.
Map<String, Object?> anomalyMarkerFor(PerformanceAnomaly anomaly) =>
    <String, Object?>{
      'anomaly_id': anomaly.id,
      'severity': anomaly.severity.name,
      'type': anomalyWireType(anomaly),
      'timestamp': anomaly.timestamp.toUtc().toIso8601String(),
    };

/// Reliable lifecycle markers for an id transition, in emission order.
///
/// - `null → X`: one `session_started {session_id, name}`.
/// - `X → null`: one `session_stopped {session_id}`.
/// - `X → Y` (restart within one tick): `stopped(X)` then `started(Y)`.
/// - Same id (or both null): empty.
///
/// Pure over ids/names (no IO); the hub calls it from its watcher tick.
List<(String, Map<String, Object?>)> sessionTransitions(
  String? prevId,
  String? prevName,
  String? nowId,
  String? nowName,
) {
  if (prevId == nowId) {
    return const [];
  }
  final out = <(String, Map<String, Object?>)>[];
  if (prevId != null) {
    out.add(('session_stopped', <String, Object?>{'session_id': prevId}));
  }
  if (nowId != null) {
    out.add((
      'session_started',
      <String, Object?>{'session_id': nowId, 'name': nowName},
    ));
  }
  return out;
}

/// Fan-out hub owning the engine subscription, the session watcher, and every
/// open SSE response. One hub per serving handle (created in `_start`,
/// closed in `_doClose`).
final class SseHub {
  /// Creates a hub with production cadences (override only in tests).
  SseHub({
    Duration watcherInterval = sseWatcherInterval,
    Duration flushInterval = sseFlushInterval,
    void Function()? onSessionEnded,
  })  : _watcherInterval = watcherInterval,
        _flushInterval = flushInterval,
        _onSessionEnded = onSessionEnded;

  final Duration _watcherInterval;
  final Duration _flushInterval;

  /// Fired (once per observed open→none transition) AFTER the `stopped`
  /// marker is enqueued. The io backend wires it to auto-close when enabled.
  final void Function()? _onSessionEnded;

  final List<_SseConnectionState> _connections = <_SseConnectionState>[];
  StreamSubscription<PerformanceEvent>? _eventSub;
  Timer? _watcher;
  String? _lastSessionId;
  String? _lastSessionName;
  bool _closed = false;

  /// Starts the anomaly subscription + session watcher. Idempotent.
  void start() {
    if (_eventSub != null || _closed) {
      return;
    }
    _lastSessionId = PerfScope.currentSession?.id;
    _lastSessionName = PerfScope.currentSession?.name;
    // Frame-path discipline: this callback MUST stay synchronous and MUST
    // never await the socket — it only overwrites per-connection slots.
    _eventSub = PerfScope.events.listen((event) {
      try {
        if (event is! AnomalyEvent) {
          return;
        }
        final anomaly = event.anomaly;
        for (final conn in _connections) {
          conn.pendingAnomaly = anomaly;
        }
      } catch (_) {
        // Slot assignment cannot realistically throw; a failing hub must
        // never break the engine broadcast.
      }
    });
    _watcher = Timer.periodic(_watcherInterval, (_) => checkSessionsNow());
  }

  /// Single watcher tick (public for tests): diffs the live session id,
  /// enqueues reliable markers into EVERY connection, fires [onSessionEnded]
  /// on open→none. Synchronous; never touches the socket.
  void checkSessionsNow() {
    if (_closed) {
      return;
    }
    final nowId = PerfScope.currentSession?.id;
    final nowName = PerfScope.currentSession?.name;
    final markers = sessionTransitions(
      _lastSessionId,
      _lastSessionName,
      nowId,
      nowName,
    );
    final hadSession = _lastSessionId != null;
    _lastSessionId = nowId;
    _lastSessionName = nowName;
    if (markers.isEmpty) {
      return;
    }
    for (final conn in _connections) {
      conn.reliableQueue.addAll(markers);
    }
    if (hadSession && nowId == null) {
      try {
        _onSessionEnded?.call();
      } catch (_) {
        // Auto-close bookkeeping must never break the watcher.
      }
    }
  }

  /// Hijacks [request]'s response as an SSE stream: sets headers, writes the
  /// `ready` frame, registers the connection, and returns WITHOUT closing.
  /// The hub owns the response until the client disconnects or [close].
  Future<void> serveRequest(HttpRequest request, {required int port}) async {
    final response = request.response
      ..statusCode = 200
      ..headers.set('content-type', 'text/event-stream')
      ..headers.set('cache-control', 'no-cache')
      ..headers.set('connection', 'keep-alive')
      ..bufferOutput = false;
    final sessionId = PerfScope.currentSession?.id;
    _writeEvent(response, 'ready', <String, Object?>{
      'port': port,
      'session_id': sessionId,
    });
    try {
      await response.flush();
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
      return;
    }
    if (_closed) {
      try {
        await response.close();
      } catch (_) {}
      return;
    }
    final conn = _SseConnectionState(response: response);
    _connections.add(conn);
    conn.flushTimer =
        Timer.periodic(_flushInterval, (_) => _flushConnection(conn));
    // Client disconnect: drop the connection (flush timer cancelled).
    try {
      await response.done;
    } catch (_) {
      // Disconnects surface as errors here; fall through to removal.
    } finally {
      _removeConnection(conn);
    }
  }

  /// One flush tick for [conn]: emits at most ONE pending `anomaly` (latest
  /// wins, then cleared) plus ALL queued reliable markers in order.
  /// Serialization happens HERE — off the frame path. Slow-consumer failures
  /// drop only that connection, never the engine.
  Future<void> _flushConnection(_SseConnectionState conn) async {
    if (conn.closed || !_connections.contains(conn)) {
      return;
    }
    var wrote = false;
    try {
      final pending = conn.pendingAnomaly;
      if (pending != null) {
        conn.pendingAnomaly = null;
        _writeEvent(conn.response, 'anomaly', anomalyMarkerFor(pending));
        wrote = true;
      }
      if (conn.reliableQueue.isNotEmpty) {
        final markers = conn.reliableQueue.toList();
        conn.reliableQueue.clear();
        for (final (name, data) in markers) {
          _writeEvent(conn.response, name, data);
        }
        wrote = true;
      }
      // Empty ticks write nothing (the `ready` frame was already flushed at
      // connect); flushing only on payload keeps slow consumers unloaded.
      if (wrote) {
        await conn.response.flush();
      }
    } catch (_) {
      _removeConnection(conn);
    }
  }

  /// Removes [conn], cancelling its flush timer and closing its response.
  void _removeConnection(_SseConnectionState conn) {
    if (conn.closed) {
      return;
    }
    conn.closed = true;
    try {
      conn.flushTimer?.cancel();
    } catch (_) {}
    conn.flushTimer = null;
    _connections.remove(conn);
    try {
      conn.response.close();
    } catch (_) {
      // Already gone; nothing left to do.
    }
  }

  /// Best-effort synchronous drain of reliable markers before teardown, so an
  /// auto-close triggered by session end never loses `session_stopped`.
  /// Pending (coalesced) anomalies are intentionally dropped here.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      _watcher?.cancel();
    } catch (_) {}
    _watcher = null;
    try {
      await _eventSub?.cancel();
    } catch (_) {}
    _eventSub = null;
    final conns = _connections.toList();
    _connections.clear();
    for (final conn in conns) {
      try {
        conn.flushTimer?.cancel();
      } catch (_) {}
      conn.flushTimer = null;
      if (!conn.closed) {
        try {
          if (conn.reliableQueue.isNotEmpty) {
            for (final (name, data) in conn.reliableQueue) {
              _writeEvent(conn.response, name, data);
            }
            conn.reliableQueue.clear();
            await conn.response.flush();
          }
        } catch (_) {
          // Best effort only.
        }
        conn.closed = true;
        try {
          await conn.response.close();
        } catch (_) {}
      }
    }
  }

  /// Open connection count (for tests/diagnostics).
  int get connectionCount => _connections.length;
}

/// Per-connection SSE state: one coalescing anomaly slot + FIFO reliable
/// lifecycle queue + its own flush timer.
final class _SseConnectionState {
  _SseConnectionState({required this.response});

  final HttpResponse response;
  PerformanceAnomaly? pendingAnomaly;
  final List<(String, Map<String, Object?>)> reliableQueue =
      <(String, Map<String, Object?>)>[];
  Timer? flushTimer;
  bool closed = false;
}

/// Writes one SSE frame: `event: <name>\ndata: <json>\n\n`. Synchronous string
/// write only — the caller decides when to `flush()` (off the frame path).
void _writeEvent(
    HttpResponse response, String event, Map<String, Object?> data) {
  response.write('event: $event\ndata: ${jsonEncode(data)}\n\n');
}
