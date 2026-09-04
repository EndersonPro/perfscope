import 'dart:convert' show jsonDecode;
import 'dart:io' show IOException, Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/perfscope_live.dart';
import 'package:perfscope/src/live/live_server_io.dart' show isKillSwitchEnv;

import 'live_test_client.dart';

/// Slice 1 lifecycle tests: disabled handles (T01), bind/double-serve/close
/// over the real loopback backend (T04), kill switch + dispose auto-close (T05).
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

  group('disabled handle (T01)', () {
    test('enabled:false returns a disabled handle', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());

      final handle = await LivePerfScope.serve(enabled: false);

      expect(handle.isServing, isFalse);
      expect(handle.port, 0);
      expect(handle.token, isEmpty);
      await handle.close();
    });

    test('engine-off returns a disabled handle', () async {
      expect(PerfScope.isEnabled, isFalse);

      final handle = await LivePerfScope.serve();

      expect(handle.isServing, isFalse);
      expect(handle.port, 0);
      expect(handle.token, isEmpty);
      await handle.close();
    });
  });

  group('bind over loopback (T04)', () {
    test('first bind returns a usable handle on an ephemeral port', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();

      final handle = await LivePerfScope.serve();

      expect(handle.isServing, isTrue);
      expect(handle.port, isNot(0));
      expect(handle.token, isNotEmpty);
      final res = await liveRequest(
        liveUri(handle.port, '/v1/status'),
        authorization: 'Bearer ${handle.token}',
      );
      expect(res.statusCode, 200);
    });

    test('explicit port and token are honored', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final probe = await LivePerfScope.serve();
      final freePort = probe.port;
      await probe.close();

      final handle = await LivePerfScope.serve(
        port: freePort,
        token: 'explicit-token',
      );

      expect(handle.port, freePort);
      expect(handle.token, 'explicit-token');
      final res = await liveRequest(
        liveUri(handle.port, '/v1/status'),
        authorization: 'Bearer explicit-token',
      );
      expect(res.statusCode, 200);
    });

    test('second serve while serving returns the existing handle', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();

      final first = await LivePerfScope.serve(token: 'double-serve');
      final second = await LivePerfScope.serve(token: 'ignored');

      expect(identical(second, first), isTrue);
      expect(second.port, first.port);
      expect(second.token, 'double-serve');
    });

    test('close is idempotent and unbinds the socket', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(token: 'close-twice');
      final uri = liveUri(handle.port, '/v1/status');

      await handle.close();
      await handle.close();

      await expectLater(
        liveRequest(uri, authorization: 'Bearer close-twice'),
        throwsA(isA<IOException>()),
      );
    });
  });

  group('kill switch (T05)', () {
    test('predicate reads PERFSCOPE_LIVE=0 from an env map', () {
      expect(isKillSwitchEnv(const {'PERFSCOPE_LIVE': '0'}), isTrue);
      expect(isKillSwitchEnv(const {}), isFalse);
      expect(isKillSwitchEnv(const {'PERFSCOPE_LIVE': '1'}), isFalse);
    });

    test('real environment integrates with the guard', () async {
      if (Platform.environment['PERFSCOPE_LIVE'] == '0') {
        final handle = await LivePerfScope.serve();
        expect(handle.isServing, isFalse);
      } else {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();
        final handle = await LivePerfScope.serve();
        expect(handle.isServing, isTrue);
      }
    });
  });

  group('auto-close (T05)', () {
    test('dispose always closes, even with autoClose:false', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'dispose-probe',
        autoClose: false,
      );
      expect(handle.isServing, isTrue);
      final uri = liveUri(handle.port, '/v1/status');

      await PerfScope.dispose();

      var refused = false;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline) && !refused) {
        try {
          await liveRequest(uri, authorization: 'Bearer dispose-probe');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        } on IOException {
          refused = true;
        }
      }
      expect(refused, isTrue);
      await handle.close();
    });

    test('engine absent after bind answers 503 engine_disabled', () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue();
      final handle = await LivePerfScope.serve(
        token: 'gone-engine',
        autoClose: false,
      );

      // Engine gone without closing the stream: the server stays up.
      PerfScope.resetForTest();

      final res = await liveRequest(
        liveUri(handle.port, '/v1/status'),
        authorization: 'Bearer gone-engine',
      );
      expect(res.statusCode, 503);
      final body = jsonDecode(res.body) as Map<String, Object?>;
      final error = body['error'] as Map<String, Object?>;
      expect(error['code'], 'engine_disabled');
    });
  });
}
