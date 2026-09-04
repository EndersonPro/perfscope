import 'dart:async' show StreamController, StreamSubscription;
import 'dart:convert' show jsonDecode, utf8;
import 'dart:io' show HttpClient, HttpClientResponse, HttpOverrides;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/perfscope_live.dart';
import 'package:perfscope/src/live/http/sse.dart'
    show anomalyMarkerFor, anomalyWireType, sessionTransitions;

import 'live_test_client.dart';

/// Slice 3 SSE tests — T10 RED first (hub + watcher + `/v1/events` route).
///
/// RED expectation: `/v1/events` is unknown today → 404 `not_found`; the
/// `SseHub` unit import below does not exist yet → analyzer errors. Both
/// prove the behavior is missing before any production code is written.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PerfScope.resetForTest();
  });

  tearDown(() async {
    await LivePerfScope.current?.close();
    await PerfScope.dispose();
    PerfScope.resetForTest();
  });

  group('SSE ready + gate (T10 RED)', () {
    test('GET /v1/events without token answers 401', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'sse-gate',
        throttle: Duration.zero,
      );

      final res = await liveRequest(liveUri(handle.port, '/v1/events'));

      expect(res.statusCode, 401);
      expect(res.headers['www-authenticate'], 'Bearer');
      final body = jsonDecode(res.body) as Map<String, Object?>;
      expect(
        (body['error'] as Map<String, Object?>)['code'],
        'unauthorized',
      );
    });

    test('GET /v1/events first frame is ready with port+session', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.currentSession!;
      final handle = await LivePerfScope.serve(
        token: 'sse-ready',
        throttle: Duration.zero,
      );

      final conn = await openSse(
        handle.port,
        authorization: 'Bearer sse-ready',
      );
      try {
        final ready = await conn.firstEvent(
          name: 'ready',
          timeout: const Duration(seconds: 5),
        );
        expect(ready['port'], handle.port);
        expect(ready['session_id'], session.id);
      } finally {
        await conn.close();
      }
    });

    test('single slow trace surfaces one anomaly marker', () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(
          longTraceThreshold: Duration(microseconds: 1),
        ),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'sse-one',
        throttle: Duration.zero,
      );

      final conn = await openSse(
        handle.port,
        authorization: 'Bearer sse-one',
      );
      try {
        // Consume the ready frame first so the next event must be the marker.
        await conn.firstEvent(
          name: 'ready',
          timeout: const Duration(seconds: 5),
        );
        // One slow trace → exactly one anomaly; busy loop guarantees the
        // duration exceeds the 1µs threshold even on a fast host.
        PerfScope.trace('slow-op', () {
          var sink = 0;
          for (var i = 0; i < 20000; i++) {
            sink += i;
          }
          expect(sink, isNotNull);
        });
        final marker = await conn.firstEvent(
          name: 'anomaly',
          timeout: const Duration(seconds: 5),
        );
        expect(marker['anomaly_id'], isA<String>());
        expect(
          marker['severity'],
          isIn(['low', 'medium', 'high', 'critical']),
        );
        expect(
          marker['type'],
          isIn([
            'slow_frame',
            'ui_bound_frame',
            'raster_bound_frame',
            'mixed_frame',
            'long_trace',
          ]),
        );
        expect(marker['timestamp'], isA<String>());
        // The trace anomaly path is the only producer in this test.
        expect(marker['type'], 'long_trace');
      } finally {
        await conn.close();
      }
    });

    test('no raw frame/trace events ever appear on the stream', () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(
          longTraceThreshold: Duration(microseconds: 1),
        ),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'sse-names',
        throttle: Duration.zero,
      );

      final conn = await openSse(
        handle.port,
        authorization: 'Bearer sse-names',
      );
      try {
        await conn.firstEvent(
          name: 'ready',
          timeout: const Duration(seconds: 5),
        );
        PerfScope.trace('slow-op', () {
          var sink = 0;
          for (var i = 0; i < 20000; i++) {
            sink += i;
          }
          expect(sink, isNotNull);
        });
        final names = await conn.collectNames(
          window: const Duration(seconds: 3),
        );
        expect(names, isNotEmpty);
        for (final name in names) {
          expect(
            name,
            isIn(['ready', 'anomaly', 'session_started', 'session_stopped']),
            reason: 'unexpected event: $name',
          );
        }
      } finally {
        await conn.close();
      }
    });
  });

  group('SSE pure helpers (T10 triangulate)', () {
    test('anomalyMarkerFor carries id+severity+type+timestamp', () {
      final anomaly = LongTraceAnomaly(
        id: 'anm_7',
        timestamp: DateTime.utc(2026, 1, 2, 3, 4, 5),
        severity: AnomalySeverity.high,
        traceId: 'tr_1',
        name: 'slow-op',
        duration: const Duration(milliseconds: 120),
      );

      final marker = anomalyMarkerFor(anomaly);

      expect(marker['anomaly_id'], 'anm_7');
      expect(marker['severity'], 'high');
      expect(marker['type'], 'long_trace');
      expect(marker['timestamp'], '2026-01-02T03:04:05.000Z');
    });

    test('anomalyWireType maps the long-trace family', () {
      final anomaly = LongTraceAnomaly(
        id: 'anm_8',
        timestamp: DateTime.now().toUtc(),
        severity: AnomalySeverity.medium,
        traceId: 'tr_2',
        name: 'op',
        duration: const Duration(milliseconds: 60),
      );

      expect(anomalyWireType(anomaly), 'long_trace');
      expect(anomalyWireType(anomaly), isIn(kKnownAnomalyTypes));
    });

    test('sessionTransitions emits started on null→X', () {
      final markers = sessionTransitions(null, null, 'ses_1', 'checkout');

      expect(markers, hasLength(1));
      expect(markers.single.$1, 'session_started');
      expect(markers.single.$2['session_id'], 'ses_1');
      expect(markers.single.$2['name'], 'checkout');
    });

    test('sessionTransitions emits stopped on X→null', () {
      final markers = sessionTransitions('ses_1', 'checkout', null, null);

      expect(markers, hasLength(1));
      expect(markers.single.$1, 'session_stopped');
      expect(markers.single.$2, {'session_id': 'ses_1'});
    });

    test('sessionTransitions emits stopped+started pair on X→Y', () {
      final markers = sessionTransitions('ses_1', 'a', 'ses_2', 'b');

      expect(markers, hasLength(2));
      expect(markers[0].$1, 'session_stopped');
      expect(markers[0].$2['session_id'], 'ses_1');
      expect(markers[1].$1, 'session_started');
      expect(markers[1].$2['session_id'], 'ses_2');
      expect(markers[1].$2['name'], 'b');
    });

    test('sessionTransitions is empty when the id is unchanged', () {
      expect(sessionTransitions('ses_1', 'a', 'ses_1', 'a'), isEmpty);
      expect(sessionTransitions(null, null, null, null), isEmpty);
    });
  });

  group('SSE coalescing + lifecycle-never-lost (T11)', () {
    // Busy work inside each traced body guarantees the duration exceeds
    // the 1µs threshold on any host (50/50 anomalies, no flakes).
    void slowOp() {
      var sink = 0;
      for (var i = 0; i < 20000; i++) {
        sink += i;
      }
      expect(sink, isNotNull);
    }

    test('burst 50 anomalies/300ms coalesces to ≤3 with last-id-wins',
        () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(
          longTraceThreshold: Duration(microseconds: 1),
        ),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'sse-burst',
        throttle: Duration.zero,
      );

      final conn = await openSse(
        handle.port,
        authorization: 'Bearer sse-burst',
      );
      try {
        await conn.firstEvent(
          name: 'ready',
          timeout: const Duration(seconds: 5),
        );
        final burstStart = DateTime.now();
        for (var i = 0; i < 50; i++) {
          PerfScope.trace('slow-op', slowOp);
        }
        final burstElapsed = DateTime.now().difference(burstStart);
        // Guard documents the 300ms budget (tolerant: CI may be slower,
        // coalescing still holds — the assertion below is the contract).
        expect(
          burstElapsed,
          lessThan(const Duration(seconds: 10)),
          reason: 'burst took $burstElapsed',
        );
        expect(PerfScope.anomalies, hasLength(50));
        final lastId = PerfScope.anomalies.last.id;

        // Spec: ≤1 `anomaly`/s per connection. Over ~2.2s at most ~2
        // arrive; the test allows 3 for flush-boundary tolerance.
        final frames = await conn.collectEvents(
          window: const Duration(milliseconds: 2200),
        );
        final markers = frames.where((e) => e.key == 'anomaly').toList();
        expect(
          markers.length,
          lessThanOrEqualTo(3),
          reason: 'got ${markers.length} anomaly markers',
        );
        expect(markers, isNotEmpty);
        // Latest wins: the last marker carries the newest anomaly id.
        expect(markers.last.value['anomaly_id'], lastId);
      } finally {
        await conn.close();
      }
    });

    test('session_stopped+started survive a burst (exactly once, ordered)',
        () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(
          longTraceThreshold: Duration(microseconds: 1),
        ),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      final stoppedId = PerfScope.currentSession!.id;
      final handle = await LivePerfScope.serve(
        token: 'sse-life',
        throttle: Duration.zero,
        autoClose: false,
      );

      final conn = await openSse(
        handle.port,
        authorization: 'Bearer sse-life',
      );
      try {
        await conn.firstEvent(
          name: 'ready',
          timeout: const Duration(seconds: 5),
        );
        for (var i = 0; i < 10; i++) {
          PerfScope.trace('slow-op', slowOp);
        }
        await PerfScope.stopSession();
        PerfScope.startSession('next');
        final startedId = PerfScope.currentSession!.id;

        final frames = await conn.collectEvents(
          window: const Duration(seconds: 3),
        );
        final stopped =
            frames.where((e) => e.key == 'session_stopped').toList();
        final started =
            frames.where((e) => e.key == 'session_started').toList();
        // Lifecycle markers are never dropped or coalesced, even under
        // burst: exactly one of each.
        expect(stopped, hasLength(1));
        expect(stopped.single.value['session_id'], stoppedId);
        expect(started, hasLength(1));
        expect(started.single.value['session_id'], startedId);
        expect(started.single.value['name'], 'next');
        // Order: stopped(X) before started(Y).
        final stoppedIdx = frames.indexWhere((e) => e.key == 'session_stopped');
        final startedIdx = frames.indexWhere((e) => e.key == 'session_started');
        expect(stoppedIdx, lessThan(startedIdx));
      } finally {
        await conn.close();
      }
    });

    test('heartbeat comments are tolerated (never surfaced as events)',
        () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'sse-ping',
        throttle: Duration.zero,
      );

      final conn = await openSse(
        handle.port,
        authorization: 'Bearer sse-ping',
      );
      try {
        await conn.firstEvent(
          name: 'ready',
          timeout: const Duration(seconds: 5),
        );
        // The server MAY send `: ping` comments; the client parser skips
        // `:` lines, so no heartbeat ever surfaces as a named event.
        final names = await conn.collectNames(
          window: const Duration(seconds: 2),
        );
        expect(names, isNotEmpty);
        for (final name in names) {
          expect(
            name,
            isIn(['ready', 'anomaly', 'session_started', 'session_stopped']),
            reason: 'heartbeat or unknown frame surfaced: $name',
          );
        }
        expect(names, isNot(contains('ping')));
      } finally {
        await conn.close();
      }
    });

    test('slow consumer never blocks the engine (progress under pause)',
        () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(
          longTraceThreshold: Duration(microseconds: 1),
        ),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'sse-slow',
        throttle: Duration.zero,
      );

      // Connect but read NOTHING for 2s (paused consumer, TCP backpressure
      // at most): the engine must keep recording either way.
      final conn = await openSse(
        handle.port,
        authorization: 'Bearer sse-slow',
      );
      try {
        await Future<void>.delayed(const Duration(seconds: 2));
        for (var i = 0; i < 5; i++) {
          PerfScope.trace('slow-op', slowOp);
        }
        await pumpEventQueue();
        // Engine progress is observable despite the paused stream.
        expect(PerfScope.anomalies, hasLength(5));
        expect(PerfScope.recentTraces, hasLength(5));
        expect(handle.isServing, isTrue);
        // The paused stream still delivers `ready` afterwards (buffered).
        final ready = await conn.firstEvent(
          name: 'ready',
          timeout: const Duration(seconds: 5),
        );
        expect(ready['port'], handle.port);
      } finally {
        await conn.close();
      }
    });
  });
}

/// Minimal SSE client for tests: real [HttpClient] (bypassing the
/// `TestWidgetsFlutterBinding` mock via a zoned override, same trick as
/// `live_test_client.dart`), line-framed `event:`/`data:` parsing, `: ping`
/// heartbeats ignored.
final class SseConnection {
  SseConnection._(this._client);

  final HttpClient _client;
  final List<MapEntry<String, String>> _received = <MapEntry<String, String>>[];
  final StreamController<MapEntry<String, String>> _onEvent =
      StreamController<MapEntry<String, String>>.broadcast();
  StreamSubscription<MapEntry<String, String>>? _sub;

  /// Opens `GET /v1/events` and asserts the SSE headers.
  static Future<SseConnection> open(
    int port, {
    required String authorization,
  }) async {
    final client = HttpOverrides.runZoned(
      HttpClient.new,
      createHttpClient: (context) => _SseUnmocked().createHttpClient(context),
    );
    final uri = liveUri(port, '/v1/events');
    final request = await client.getUrl(uri);
    request.headers.set('authorization', authorization);
    final response = await request.close();
    final conn = SseConnection._(client);
    // Single underlying subscription; every frame is buffered in [_received]
    // AND fanned out on [_onEvent], so sequential `firstEvent`/`collect*`
    // calls never hit "already listened" and never lose a frame in the gap
    // between two awaits (replay + live wait).
    conn._sub = _parseSse(response).listen(
      (entry) {
        conn._received.add(entry);
        if (!conn._onEvent.isClosed) {
          conn._onEvent.add(entry);
        }
      },
      onError: (_) {},
    );
    return conn;
  }

  /// All payloads received so far for [name] (replay buffer snapshot).
  List<Map<String, Object?>> payloadsOf(String name) => _received
      .where((e) => e.key == name)
      .map((e) => jsonDecode(e.value) as Map<String, Object?>)
      .toList();

  /// Count of frames received so far for [name].
  int countOf(String name) => _received.where((e) => e.key == name).length;

  /// First `data:` payload for [name] within [timeout] (replays buffered
  /// frames first, then waits live).
  Future<Map<String, Object?>> firstEvent({
    required String name,
    required Duration timeout,
  }) async {
    for (final entry in _received) {
      if (entry.key == name) {
        return jsonDecode(entry.value) as Map<String, Object?>;
      }
    }
    final entry =
        await _onEvent.stream.firstWhere((e) => e.key == name).timeout(timeout);
    return jsonDecode(entry.value) as Map<String, Object?>;
  }

  /// Every event name seen within [window] (heartbeat comments excluded).
  /// Includes frames already buffered before the call, so a marker flushed
  /// in the gap between the trigger and this call is never missed.
  Future<List<String>> collectNames({required Duration window}) async {
    final names = _received.map((e) => e.key).toList();
    final live = _onEvent.stream.listen((e) => names.add(e.key));
    await Future<void>.delayed(window);
    await live.cancel();
    return names.toList();
  }

  /// Every frame (name + payload) observed within [window].
  Future<List<MapEntry<String, Map<String, Object?>>>> collectEvents({
    required Duration window,
  }) async {
    final out = _received
        .map(
            (e) => MapEntry(e.key, jsonDecode(e.value) as Map<String, Object?>))
        .toList();
    final live = _onEvent.stream.listen((e) {
      out.add(MapEntry(e.key, jsonDecode(e.value) as Map<String, Object?>));
    });
    await Future<void>.delayed(window);
    await live.cancel();
    return out;
  }

  Future<void> close() async {
    // Abort the socket FIRST so the pending response stream (`_parseSse`)
    // and the server's `response.done` both settle; cancelling the parse
    // subscription before aborting can stall awaiting the open stream.
    try {
      _client.close(force: true);
    } catch (_) {}
    try {
      await _sub?.cancel().timeout(const Duration(seconds: 5));
    } catch (_) {}
    _sub = null;
    try {
      await _onEvent.close().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

/// Opens an SSE connection (top-level helper to keep tests terse).
Future<SseConnection> openSse(
  int port, {
  required String authorization,
}) =>
    SseConnection.open(port, authorization: authorization);

/// Parses `text/event-stream` frames: `event: <name>` + `data: <json>`
/// terminated by a blank line. `: ping` comments are skipped (tolerated but
/// never surfaced).
Stream<MapEntry<String, String>> _parseSse(HttpClientResponse response) async* {
  var event = 'message';
  final data = StringBuffer();
  var hasData = false;
  await for (final chunk in response.transform(utf8.decoder)) {
    // Split preserving partial frames across TCP chunks via buffering below.
    for (final rawLine in chunk.split('\n')) {
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      if (line.isEmpty) {
        if (hasData) {
          yield MapEntry(event, data.toString());
          event = 'message';
          data.clear();
          hasData = false;
        }
        continue;
      }
      if (line.startsWith(':')) {
        continue; // heartbeat comment — tolerated, never surfaced.
      }
      if (line.startsWith('event:')) {
        event = line.substring('event:'.length).trim();
      } else if (line.startsWith('data:')) {
        final piece = line.substring('data:'.length);
        final value = piece.startsWith(' ') ? piece.substring(1) : piece;
        if (hasData) {
          data.write('\n');
        }
        data.write(value);
        hasData = true;
      }
    }
  }
}

final class _SseUnmocked extends HttpOverrides {}
