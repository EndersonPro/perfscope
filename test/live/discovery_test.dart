import 'dart:convert' show jsonDecode;
import 'dart:io' show Directory, File, Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/perfscope_live.dart';
import 'package:perfscope/src/live/discovery.dart' as discovery;

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

  group('discovery file contract (T12 RED)', () {
    test('write creates .dart_tool/perfscope-live.json with 5 keys only',
        () async {
      final root =
          await Directory.systemTemp.createTemp('perfscope-discovery-');
      try {
        await discovery.writeDiscovery(
          port: 54321,
          token: 'test-token-abc',
          rootOverride: root,
        );

        final file = File('${root.path}${Platform.pathSeparator}.dart_tool'
            '${Platform.pathSeparator}perfscope-live.json');
        expect(await file.exists(), isTrue);
        final body =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        expect(body.keys.toSet(),
            {'port', 'token', 'pid', 'projectRoot', 'startedAt'});
        expect(body['port'], 54321);
        expect(body['token'], 'test-token-abc');
        expect(body['pid'], isA<int>());
        expect(body['projectRoot'], root.path);
        expect(DateTime.tryParse(body['startedAt'] as String), isNotNull);
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('second write overwrites the first (re-bind)', () async {
      final root =
          await Directory.systemTemp.createTemp('perfscope-discovery-');
      try {
        await discovery.writeDiscovery(
            port: 1111, token: 'first', rootOverride: root);
        await discovery.writeDiscovery(
            port: 2222, token: 'second', rootOverride: root);

        final parsed = await discovery.readDiscovery(rootOverride: root);
        expect(parsed!['port'], 2222);
        expect(parsed['token'], 'second');
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('delete removes the file and is a no-op when missing', () async {
      final root =
          await Directory.systemTemp.createTemp('perfscope-discovery-');
      try {
        await discovery.writeDiscovery(
            port: 3333, token: 't', rootOverride: root);
        await discovery.deleteDiscovery(rootOverride: root);
        final file = discovery.discoveryFileFor(root);
        expect(await file.exists(), isFalse);
        // Second delete must not throw.
        await discovery.deleteDiscovery(rootOverride: root);
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('serving writes the discovery file; close deletes it', () async {
      // Hermetic: the test-only root override points this isolate's servers
      // at a fixture dir, so parallel test files (separate isolates, same
      // repo `.dart_tool/`) can never overwrite or delete our file.
      final root =
          await Directory.systemTemp.createTemp('perfscope-discovery-');
      discovery.setDiscoveryRootOverrideForTest(root);
      try {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();

        final handle = await LivePerfScope.serve(
          token: 'discovery-live-token',
          throttle: Duration.zero,
        );
        try {
          final file = discovery.discoveryFileFor(root);
          expect(await file.exists(), isTrue,
              reason: 'serve() must write .dart_tool/perfscope-live.json');
          final body =
              jsonDecode(await file.readAsString()) as Map<String, Object?>;
          expect(body['port'], handle.port);
          expect(body['token'], 'discovery-live-token');
          expect(body['projectRoot'], root.path);
        } finally {
          await handle.close();
        }
        expect(await discovery.discoveryFileFor(root).exists(), isFalse,
            reason: 'close() must delete the discovery file');
      } finally {
        discovery.setDiscoveryRootOverrideForTest(null);
        await root.delete(recursive: true);
      }
    });

    test('disabled handle writes nothing', () async {
      final root =
          await Directory.systemTemp.createTemp('perfscope-discovery-');
      discovery.setDiscoveryRootOverrideForTest(root);
      try {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();

        final handle = await LivePerfScope.serve(enabled: false);
        expect(handle.isServing, isFalse);
        expect(await discovery.discoveryFileFor(root).exists(), isFalse);
        await handle.close();
      } finally {
        discovery.setDiscoveryRootOverrideForTest(null);
        await root.delete(recursive: true);
      }
    });

    test('resolveProjectRoot walks up to pubspec.yaml', () async {
      final root =
          await Directory.systemTemp.createTemp('perfscope-discovery-');
      try {
        await File('${root.path}/pubspec.yaml').writeAsString('name: demo\n');
        final nested =
            await Directory('${root.path}/a/b').create(recursive: true);
        expect(discovery.resolveProjectRoot(nested).path, root.path);
        expect(discovery.resolveProjectRoot(root).path, root.path);
      } finally {
        await root.delete(recursive: true);
      }
    });
  });
}
