import 'dart:convert' show base64Url, jsonDecode;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/perfscope_live.dart';
import 'package:perfscope/src/live/http/auth.dart';

import 'live_test_client.dart';

/// Slice 1 auth tests: unit gate (T02) + HTTP Bearer gate on status and
/// ai-context (T04–T05). Token-via-query is never accepted.
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

  group('constant-time compare (T02)', () {
    test('equal strings compare true', () {
      expect(constantTimeEquals('abc123', 'abc123'), isTrue);
    });

    test('different strings of equal length compare false', () {
      expect(constantTimeEquals('abc123', 'abc124'), isFalse);
    });

    test('different lengths compare false', () {
      expect(constantTimeEquals('short', 'much-longer-token'), isFalse);
      expect(constantTimeEquals('much-longer-token', 'short'), isFalse);
    });

    test('two empty strings compare true', () {
      expect(constantTimeEquals('', ''), isTrue);
    });
  });

  group('generateToken (T02)', () {
    test('produces at least 128 bits of entropy as base64Url', () {
      final token = generateToken();

      expect(token.length, greaterThanOrEqualTo(22));
      expect(base64Url.decode(token), hasLength(16));
    });

    test('two tokens differ', () {
      expect(generateToken(), isNot(equals(generateToken())));
    });
  });

  group('extractBearer (T02)', () {
    test('valid Bearer header yields the token', () {
      expect(extractBearer('Bearer abc123'), 'abc123');
    });

    test('missing header yields null', () {
      expect(extractBearer(null), isNull);
    });

    test('bare scheme without token yields null', () {
      expect(extractBearer('Bearer'), isNull);
      expect(extractBearer('Bearer '), isNull);
    });

    test('foreign scheme yields null', () {
      expect(extractBearer('Token abc123'), isNull);
    });
  });

  group('HTTP Bearer gate (T04–T05)', () {
    const routes = ['/v1/status', '/v1/ai-context'];

    for (final route in routes) {
      test('$route without header answers 401 unauthorized', () async {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();
        final handle = await LivePerfScope.serve(token: 'gate-$route');

        final res = await liveRequest(liveUri(handle.port, route));

        expect(res.statusCode, 401);
        expect(res.headers['www-authenticate'], 'Bearer');
        final body = jsonDecode(res.body) as Map<String, Object?>;
        final error = body['error'] as Map<String, Object?>;
        expect(error['code'], 'unauthorized');
        expect(body.containsKey('schema_version'), isFalse);
        expect(body.containsKey('session'), isFalse);
      });

      test('$route with a wrong token answers 401', () async {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();
        final handle = await LivePerfScope.serve(token: 'right-token');

        final res = await liveRequest(
          liveUri(handle.port, route),
          authorization: 'Bearer wrong-token',
        );

        expect(res.statusCode, 401);
        final body = jsonDecode(res.body) as Map<String, Object?>;
        expect(
          (body['error'] as Map<String, Object?>)['code'],
          'unauthorized',
        );
      });

      test('$route with a malformed header answers 401', () async {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();
        final handle = await LivePerfScope.serve(token: 'right-token');

        for (final malformed in ['Bearer', 'Token right-token']) {
          final res = await liveRequest(
            liveUri(handle.port, route),
            authorization: malformed,
          );
          expect(res.statusCode, 401, reason: malformed);
        }
      });

      test('$route ignores ?token= and still answers 401', () async {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();
        final handle = await LivePerfScope.serve(token: 'query-token');

        final res = await liveRequest(
          liveUri(handle.port, route, const {'token': 'query-token'}),
        );

        expect(res.statusCode, 401);
      });

      test('$route with the Bearer token answers 200', () async {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();
        final handle = await LivePerfScope.serve(token: 'good-token');

        final res = await liveRequest(
          liveUri(handle.port, route),
          authorization: 'Bearer good-token',
        );

        expect(res.statusCode, 200);
      });
    }
  });
}
