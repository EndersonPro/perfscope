import 'dart:convert' show jsonDecode;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/perfscope_live.dart';

import 'live_test_client.dart';

/// Slice 1 status/ai-context tests: snapshot fns (T03) + HTTP shape, parity,
/// and error envelope over the real backend (T04–T05).
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

  group('snapshot-fns (T03)', () {
    test('liveStatus carries exact keys and live session id', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.currentSession!;

      final status = liveStatus(uptimeMs: 5000);

      expect(status['schema_version'], 1);
      expect(status['enabled'], isTrue);
      expect(status['mode'], isIn(<String>['profile', 'debug']));
      expect(
        status['session'],
        session.name == null
            ? <String, Object?>{'id': session.id}
            : <String, Object?>{'id': session.id, 'name': session.name},
      );
      expect(status['uptime_ms'], 5000);
      final budget = status['budget'] as Map<String, Object?>?;
      expect(budget, isNotNull);
      expect(budget!['frame_budget_fps'], session.environment.frameBudgetFps);
      expect(budget['frame_budget_ms'], session.environment.frameBudgetMs);
      expect(
        budget['frame_budget_source'],
        session.environment.frameBudgetSource.name,
      );
    });

    test('ai-context text is byte-identical to the in-process rendering',
        () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.currentSession!;

      expect(
        liveAiContextText(),
        buildAiContextText(
          reportForExport(session),
          config: const AiContextConfig(),
        ),
      );
    });

    test('ai-context json is deep-equal to the in-process rendering', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.currentSession!;
      final now = DateTime.utc(2026, 3, 1, 12);

      expect(
        liveAiContextJson(now: () => now),
        buildAiContextJson(
          reportForExport(session),
          config: const AiContextConfig(),
          now: () => now,
        ),
      );
    });

    test('no session ever means null ai-context (router maps to 404)',
        () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(autoStartSession: false),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      expect(PerfScope.currentSession, isNull);

      expect(liveAiContextText(), isNull);
      expect(liveAiContextJson(), isNull);
    });
  });

  group('HTTP status shape (T05)', () {
    test('keys are exact, session matches, uptime is monotonic', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final session = PerfScope.currentSession!;
      final handle = await LivePerfScope.serve(token: 'shape-token');
      final uri = liveUri(handle.port, '/v1/status');

      Future<Map<String, Object?>> fetch() async {
        final res = await liveRequest(uri, authorization: 'Bearer shape-token');
        expect(res.statusCode, 200);
        return jsonDecode(res.body) as Map<String, Object?>;
      }

      final first = await fetch();
      expect(
        first.keys.toSet(),
        {'schema_version', 'enabled', 'mode', 'session', 'uptime_ms', 'budget'},
      );
      expect(first['schema_version'], 1);
      expect(first['enabled'], isTrue);
      expect(first['mode'], isIn(<String>['profile', 'debug']));
      expect(
        (first['session'] as Map<String, Object?>)['id'],
        session.id,
      );
      final budget = first['budget'] as Map<String, Object?>;
      expect(budget['frame_budget_fps'], session.environment.frameBudgetFps);
      expect(budget['frame_budget_ms'], session.environment.frameBudgetMs);
      expect(
        budget['frame_budget_source'],
        session.environment.frameBudgetSource.name,
      );

      final second = await fetch();
      expect(
        (second['uptime_ms'] as num).toInt() >=
            (first['uptime_ms'] as num).toInt(),
        isTrue,
      );
    });

    test('unknown query params are ignored', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(token: 'query-tolerant');

      final res = await liveRequest(
        liveUri(handle.port, '/v1/status', const {'foo': 'bar'}),
        authorization: 'Bearer query-tolerant',
      );

      expect(res.statusCode, 200);
    });

    test('POST answers 405 with Allow: GET and the error envelope', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(token: 'method-token');

      final res = await liveRequest(
        liveUri(handle.port, '/v1/status'),
        method: 'POST',
        authorization: 'Bearer method-token',
      );

      expect(res.statusCode, 405);
      expect(res.headers['allow'], contains('GET'));
      final body = jsonDecode(res.body) as Map<String, Object?>;
      expect(
        (body['error'] as Map<String, Object?>)['code'],
        'method_not_allowed',
      );
    });

    test('unknown path answers 404 not_found', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(token: 'path-token');

      final res = await liveRequest(
        liveUri(handle.port, '/v1/nope'),
        authorization: 'Bearer path-token',
      );

      expect(res.statusCode, 404);
      final body = jsonDecode(res.body) as Map<String, Object?>;
      expect((body['error'] as Map<String, Object?>)['code'], 'not_found');
    });
  });

  group('HTTP ai-context parity (T05)', () {
    test('GET /v1/ai-context equals the in-process text', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(token: 'ctx-token');

      final res = await liveRequest(
        liveUri(handle.port, '/v1/ai-context'),
        authorization: 'Bearer ctx-token',
      );

      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('text/plain'));
      expect(res.body, liveAiContextText());
    });

    test('GET /v1/ai-context.json equals the in-process map', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(token: 'ctxj-token');

      final res = await liveRequest(
        liveUri(handle.port, '/v1/ai-context.json'),
        authorization: 'Bearer ctxj-token',
      );

      expect(res.statusCode, 200);
      final decoded = jsonDecode(res.body) as Map<String, Object?>;
      final expected = liveAiContextJson()!;
      expect(decoded.keys.toSet(), expected.keys.toSet());
      for (final key in expected.keys) {
        if (key == 'generated_at') {
          continue;
        }
        expect(decoded[key], expected[key], reason: key);
      }
    });

    test('no session ever answers 404 no_session on both routes', () async {
      PerfScope.initialize(
        config: const PerfScopeConfig(autoStartSession: false),
        logWriter: MemoryLogWriter(),
      );
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(token: 'empty-token');

      for (final route in ['/v1/ai-context', '/v1/ai-context.json']) {
        final res = await liveRequest(
          liveUri(handle.port, route),
          authorization: 'Bearer empty-token',
        );
        expect(res.statusCode, 404, reason: route);
        final body = jsonDecode(res.body) as Map<String, Object?>;
        expect(
          (body['error'] as Map<String, Object?>)['code'],
          'no_session',
          reason: route,
        );
      }
    });
  });
}
