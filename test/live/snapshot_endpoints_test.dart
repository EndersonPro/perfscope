import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/perfscope_live.dart';

import 'live_test_client.dart';

/// Slice 2 snapshot + HTTP tests (T07–T09).
///
/// T07 ships the in-process snapshot fns (`snapshot-fns-only` group);
/// T08 wires them to HTTP + throttle; T09 closes the matrix + goldens.
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

  group('snapshot-fns-only (T07)', () {
    test('liveSessionDocument mirrors the serializer with context windows',
        () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.currentSession!;
      final engine = PerfScope.maybeEngine!;

      final doc = liveSessionDocument();

      expect(doc, isNotNull);
      final expected = const SessionSerializer().serialize(
        reportForExport(session),
        resolveContextWindow: engine.contextWindowFor,
      );
      expect(doc!['schema_version'], 1);
      expect(
        (doc['session'] as Map<String, Object?>)['id'],
        session.id,
      );
      // Byte-shape identity with the real serializer (same keys, same values).
      expect(doc.keys.toSet(), expected.keys.toSet());
      // Parses with the v1 parser (round-trip at the snapshot layer).
      final parsed = const SessionParser().parseString(jsonEncode(doc));
      expect(parsed.session.id, session.id);
    });

    test('liveSessionDocument is null with no session ever', () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(autoStartSession: false),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();

      expect(liveSessionDocument(), isNull);
    });

    test('liveFramesStats projects the serializer summary block', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.currentSession!;

      final stats = liveFramesStats();

      expect(stats, isNotNull);
      final expected = const SessionSerializer()
              .serialize(reportForExport(session))['summary']
          as Map<String, Object?>;
      expect(stats!.keys.toSet(), expected.keys.toSet());
      for (final key in expected.keys) {
        expect(stats[key], expected[key], reason: key);
      }
    });

    test('liveAnomalies clamps limit 5000 to maxStoredAnomalies', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();

      final result = liveAnomalies(limit: 5000)!;

      expect(result['schema_version'], 1);
      expect(result['limit'], maxStoredAnomalies);
    });

    test('liveTraces clamps limit 9999 to maxStoredTraces', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();

      final result = liveTraces(limit: 9999)!;

      expect(result['schema_version'], 1);
      expect(result['limit'], maxStoredTraces);
    });

    test('liveAnomalies filters combine with AND', () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(
          longTraceThreshold: Duration(microseconds: 1),
        ),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      PerfScope.trace('slow-op', () {});
      await pumpEventQueue();
      expect(PerfScope.anomalies, hasLength(1));

      final all = liveAnomalies()!;
      expect((all['anomalies'] as List), hasLength(1));
      final entry = (all['anomalies'] as List).single as Map<String, Object?>;
      final severity = entry['severity'] as String;
      final type = entry['type'] as String;
      // No context windows inline on the list view.
      expect(entry.containsKey('context_window'), isFalse);

      final matching = liveAnomalies(severity: severity, type: type)!;
      expect((matching['anomalies'] as List), hasLength(1));

      final otherSeverity = severity == 'high' ? 'critical' : 'high';
      final mismatched = liveAnomalies(
        severity: otherSeverity,
        type: type,
      )!;
      expect((mismatched['anomalies'] as List), isEmpty);
      expect(mismatched['total'], 0);
    });

    test('liveAnomalies rejects invalid filters with 400 semantics', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();

      expect(() => liveAnomalies(severity: 'nope'),
          throwsA(isA<LiveBadRequest>()));
      expect(() => liveAnomalies(type: 'nope'), throwsA(isA<LiveBadRequest>()));
      expect(() => liveAnomalies(limit: 0), throwsA(isA<LiveBadRequest>()));
      expect(() => liveAnomalies(limit: -5), throwsA(isA<LiveBadRequest>()));
    });

    test('liveTraces rejects invalid limit with 400 semantics', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();

      expect(() => liveTraces(limit: 0), throwsA(isA<LiveBadRequest>()));
      expect(() => liveTraces(limit: -1), throwsA(isA<LiveBadRequest>()));
    });

    test('liveAnomalyContext returns null for unknown id', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();

      expect(liveAnomalyContext('never-seen'), isNull);
    });

    test('liveTraces preserves chronological order', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      PerfScope.trace('first', () {});
      PerfScope.trace('second', () {});
      PerfScope.trace('third', () {});
      await pumpEventQueue();

      final result = liveTraces()!;
      final traces = result['traces'] as List;
      expect(traces, hasLength(3));
      expect(
        traces.map((t) => (t as Map<String, Object?>)['name']).toList(),
        ['first', 'second', 'third'],
      );
      expect(result['total'], 3);
      expect(result['limit'], 3);
    });
  });

  group('HTTP session + stats (T08)', () {
    test('GET /v1/session round-trips through SessionParser', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.currentSession!;
      final handle = await LivePerfScope.serve(
        token: 'session-token',
        throttle: Duration.zero,
      );

      final res = await liveRequest(
        liveUri(handle.port, '/v1/session'),
        authorization: 'Bearer session-token',
      );

      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('application/json'));
      final parsed = const SessionParser().parseString(res.body);
      expect(parsed.session.id, session.id);
    });

    test('GET /v1/session with no session ever answers 404 no_session',
        () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(autoStartSession: false),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'empty-session',
        throttle: Duration.zero,
      );

      final res = await liveRequest(
        liveUri(handle.port, '/v1/session'),
        authorization: 'Bearer empty-session',
      );

      expect(res.statusCode, 404);
      final body = jsonDecode(res.body) as Map<String, Object?>;
      expect((body['error'] as Map<String, Object?>)['code'], 'no_session');
    });

    test('GET /v1/frames/stats matches the engine snapshot', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'stats-token',
        throttle: Duration.zero,
      );

      final res = await liveRequest(
        liveUri(handle.port, '/v1/frames/stats'),
        authorization: 'Bearer stats-token',
      );

      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, Object?>;
      expect(body['schema_version'], 1);
      final summary = body['summary'] as Map<String, Object?>;
      final session = PerfScope.currentSession!;
      // total_frames ties directly to the engine's live statistics snapshot.
      expect(summary['total_frames'], session.statistics().totalFrames);
      final expected = const SessionSerializer()
              .serialize(reportForExport(session))['summary']
          as Map<String, Object?>;
      expect(summary.keys.toSet(), expected.keys.toSet());
      for (final key in expected.keys) {
        expect(summary[key], expected[key], reason: key);
      }
      // No per-frame dump exists on any endpoint.
      expect(body.containsKey('frames'), isFalse);
      expect(summary.containsKey('frames'), isFalse);
    });

    test('POST /v1/session answers 405 with Allow: GET', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(token: 'method-s2');

      final res = await liveRequest(
        liveUri(handle.port, '/v1/session'),
        method: 'POST',
        authorization: 'Bearer method-s2',
      );

      expect(res.statusCode, 405);
      expect(res.headers['allow'], contains('GET'));
      final body = jsonDecode(res.body) as Map<String, Object?>;
      expect(
        (body['error'] as Map<String, Object?>)['code'],
        'method_not_allowed',
      );
    });
  });

  group('HTTP anomalies + traces (T08)', () {
    test('GET /v1/anomalies clamps limit=5000 to the core ring', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'clamp-token',
        throttle: Duration.zero,
      );

      final res = await liveRequest(
        liveUri(handle.port, '/v1/anomalies', const {'limit': '5000'}),
        authorization: 'Bearer clamp-token',
      );

      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, Object?>;
      expect(body['schema_version'], 1);
      expect(body['limit'], maxStoredAnomalies);
      expect(body.containsKey('total'), isTrue);
      expect(body['anomalies'], isA<List>());
    });

    test('GET /v1/anomalies filters combine with AND over live data', () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(
          longTraceThreshold: Duration(microseconds: 1),
        ),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      PerfScope.trace('slow-op', () {});
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'filter-token',
        throttle: Duration.zero,
      );
      const auth = 'Bearer filter-token';

      Future<List> fetch(Map<String, String>? query) async {
        final res = await liveRequest(
          liveUri(handle.port, '/v1/anomalies', query),
          authorization: auth,
        );
        expect(res.statusCode, 200);
        final body = jsonDecode(res.body) as Map<String, Object?>;
        return body['anomalies'] as List;
      }

      final all = await fetch(null);
      expect(all, hasLength(1));
      final entry = all.single as Map<String, Object?>;
      final severity = entry['severity'] as String;
      final type = entry['type'] as String;
      expect(entry.containsKey('context_window'), isFalse);

      final matching = await fetch({'severity': severity, 'type': type});
      expect(matching, hasLength(1));
      // AND: right type but wrong severity matches nothing.
      final other = severity == 'high' ? 'critical' : 'high';
      final mismatched = await fetch({'severity': other, 'type': type});
      expect(mismatched, isEmpty);
    });

    test('GET /v1/anomalies rejects invalid filters with 400', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'bad-filter',
        throttle: Duration.zero,
      );
      const auth = 'Bearer bad-filter';

      for (final query in [
        {'limit': 'abc'},
        {'limit': '0'},
        {'limit': '-3'},
        {'severity': 'nope'},
        {'type': 'nope'},
      ]) {
        final res = await liveRequest(
          liveUri(handle.port, '/v1/anomalies', query),
          authorization: auth,
        );
        expect(res.statusCode, 400, reason: '$query');
        final body = jsonDecode(res.body) as Map<String, Object?>;
        expect(
          (body['error'] as Map<String, Object?>)['code'],
          'bad_request',
          reason: '$query',
        );
      }
    });

    test('GET /v1/anomalies/:id/context answers 404 context_unavailable',
        () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'ctx404-token',
        throttle: Duration.zero,
      );

      final res = await liveRequest(
        liveUri(handle.port, '/v1/anomalies/never-seen/context'),
        authorization: 'Bearer ctx404-token',
      );

      expect(res.statusCode, 404);
      final body = jsonDecode(res.body) as Map<String, Object?>;
      expect(
        (body['error'] as Map<String, Object?>)['code'],
        'context_unavailable',
      );
    });

    test('GET /v1/traces clamps limit=9999 and stays chronological', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      PerfScope.trace('first', () {});
      PerfScope.trace('second', () {});
      PerfScope.trace('third', () {});
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'traces-token',
        throttle: Duration.zero,
      );

      final res = await liveRequest(
        liveUri(handle.port, '/v1/traces', const {'limit': '9999'}),
        authorization: 'Bearer traces-token',
      );

      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, Object?>;
      expect(body['schema_version'], 1);
      expect(body['limit'], maxStoredTraces);
      expect(body['total'], 3);
      final traces = body['traces'] as List;
      expect(
        traces.map((t) => (t as Map<String, Object?>)['name']).toList(),
        ['first', 'second', 'third'],
      );
    });

    test('GET /v1/traces rejects invalid limit with 400', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'bad-tlimit',
        throttle: Duration.zero,
      );

      for (final query in [
        {'limit': 'abc'},
        {'limit': '0'},
        {'limit': '-1'},
      ]) {
        final res = await liveRequest(
          liveUri(handle.port, '/v1/traces', query),
          authorization: 'Bearer bad-tlimit',
        );
        expect(res.statusCode, 400, reason: '$query');
        final body = jsonDecode(res.body) as Map<String, Object?>;
        expect(
          (body['error'] as Map<String, Object?>)['code'],
          'bad_request',
          reason: '$query',
        );
      }
    });
  });

  group('HTTP throttle 429 + 503 (T08)', () {
    test('hot polling answers 429 with Retry-After; status stays 200',
        () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(token: 'throttle-token');
      const auth = 'Bearer throttle-token';
      final sessionUri = liveUri(handle.port, '/v1/session');

      final fresh = await liveRequest(sessionUri, authorization: auth);
      expect(fresh.statusCode, 200);

      final hot = await liveRequest(sessionUri, authorization: auth);
      expect(hot.statusCode, 429);
      final retryAfter = int.tryParse(hot.headers['retry-after'] ?? '');
      expect(retryAfter, isNotNull);
      expect(retryAfter!, greaterThanOrEqualTo(1));
      final body = jsonDecode(hot.body) as Map<String, Object?>;
      expect(
        (body['error'] as Map<String, Object?>)['code'],
        'rate_limited',
      );

      // The exempt route serves in the same moment.
      final status = await liveRequest(
        liveUri(handle.port, '/v1/status'),
        authorization: auth,
      );
      expect(status.statusCode, 200);
    });

    test('snapshot routes answer 503 after the engine is gone', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'gone-s2',
        autoClose: false,
        throttle: Duration.zero,
      );

      // Engine gone without closing the stream: the server stays up.
      PerfScope.resetForTest();

      for (final path in [
        '/v1/session',
        '/v1/frames/stats',
        '/v1/anomalies',
        '/v1/traces',
        '/v1/anomalies/anm_1/context',
      ]) {
        final res = await liveRequest(
          liveUri(handle.port, path),
          authorization: 'Bearer gone-s2',
        );
        expect(res.statusCode, 503, reason: path);
        final body = jsonDecode(res.body) as Map<String, Object?>;
        expect(
          (body['error'] as Map<String, Object?>)['code'],
          'engine_disabled',
          reason: path,
        );
      }
    });

    test('snapshot routes require Bearer (401 without token)', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'gate-s2',
        throttle: Duration.zero,
      );

      for (final path in [
        '/v1/session',
        '/v1/frames/stats',
        '/v1/anomalies',
        '/v1/traces',
        '/v1/anomalies/anm_1/context',
      ]) {
        final res = await liveRequest(liveUri(handle.port, path));
        expect(res.statusCode, 401, reason: path);
        expect(res.headers['www-authenticate'], 'Bearer', reason: path);
      }
    });

    test('snapshot routes answer 404 no_session with no session ever',
        () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(autoStartSession: false),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'empty-s2',
        throttle: Duration.zero,
      );
      const auth = 'Bearer empty-s2';

      for (final path in [
        '/v1/session',
        '/v1/frames/stats',
        '/v1/anomalies',
        '/v1/traces',
        '/v1/anomalies/anm_1/context',
      ]) {
        final res = await liveRequest(
          liveUri(handle.port, path),
          authorization: auth,
        );
        expect(res.statusCode, 404, reason: path);
        final body = jsonDecode(res.body) as Map<String, Object?>;
        expect(
          (body['error'] as Map<String, Object?>)['code'],
          'no_session',
          reason: path,
        );
      }
    });
  });

  group('goldens esquema-v1 (T09)', () {
    Future<Map<String, Object?>> readGolden(String name) async {
      final raw = await File('test/live/goldens/$name').readAsString();
      return jsonDecode(raw) as Map<String, Object?>;
    }

    test('session.json golden guards the /v1/session shape', () async {
      final golden = await readGolden('session.json');
      expect(golden['schema_version'], 1);

      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'golden-session',
        throttle: Duration.zero,
      );
      final res = await liveRequest(
        liveUri(handle.port, '/v1/session'),
        authorization: 'Bearer golden-session',
      );
      expect(res.statusCode, 200);
      final live = jsonDecode(res.body) as Map<String, Object?>;

      // Any v1 key drift — in the serializer or in the golden — fails loudly.
      expect(live.keys.toSet(), golden.keys.toSet());
      expect(
        (live['summary'] as Map<String, Object?>).keys.toSet(),
        (golden['summary'] as Map<String, Object?>).keys.toSet(),
      );
      expect(
        (live['session'] as Map<String, Object?>).containsKey('id'),
        isTrue,
      );
    });

    test('frames_stats.json golden guards the /v1/frames/stats shape',
        () async {
      final golden = await readGolden('frames_stats.json');
      expect(golden['schema_version'], 1);
      expect(golden.keys.toSet(), {'schema_version', 'summary'});

      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'golden-stats',
        throttle: Duration.zero,
      );
      final res = await liveRequest(
        liveUri(handle.port, '/v1/frames/stats'),
        authorization: 'Bearer golden-stats',
      );
      expect(res.statusCode, 200);
      final live = jsonDecode(res.body) as Map<String, Object?>;

      expect(live.keys.toSet(), golden.keys.toSet());
      expect(
        (live['summary'] as Map<String, Object?>).keys.toSet(),
        (golden['summary'] as Map<String, Object?>).keys.toSet(),
      );
    });
  });
}
