import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/perfscope_live.dart';
import 'package:perfscope/src/cli/mcp/mcp_bridge.dart' as bridge;
import 'package:perfscope/src/live/discovery.dart' as discovery;

import 'live_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mcp bridge registry (T12 RED)', () {
    test('exposes exactly the six perfscope_* tools', () {
      expect(bridge.mcpToolNames, [
        'perfscope_status',
        'perfscope_session',
        'perfscope_anomalies',
        'perfscope_anomaly_context',
        'perfscope_traces',
        'perfscope_ai_context',
      ]);
    });

    test('tool definitions carry name + description + inputSchema', () {
      final defs = bridge.mcpToolDefinitions();
      expect(defs, hasLength(6));
      for (final def in defs) {
        expect(def['name'], startsWith('perfscope_'));
        expect(def['description'], isNotEmpty);
        expect(def['inputSchema'], isA<Map<String, Object?>>());
      }
    });
  });

  group('tool→twin mapping (T12 triangulate)', () {
    test('each tool resolves to its HTTP twin path', () {
      expect(
        bridge.resolveToolRequest('perfscope_status', {}).$1,
        '/v1/status',
      );
      expect(
        bridge.resolveToolRequest('perfscope_session', {}).$1,
        '/v1/session',
      );
      final anomalies = bridge.resolveToolRequest(
        'perfscope_anomalies',
        {'limit': 10, 'severity': 'high'},
      );
      expect(anomalies.$1, '/v1/anomalies');
      expect(anomalies.$2, {'limit': '10', 'severity': 'high'});
      final context = bridge.resolveToolRequest(
        'perfscope_anomaly_context',
        {'anomaly_id': 'anm_1'},
      );
      expect(context.$1, '/v1/anomalies/anm_1/context');
      final traces =
          bridge.resolveToolRequest('perfscope_traces', {'limit': 5});
      expect(traces.$1, '/v1/traces');
      expect(traces.$2, {'limit': '5'});
      expect(
        bridge.resolveToolRequest('perfscope_ai_context', {}).$1,
        '/v1/ai-context',
      );
      expect(
        bridge
            .resolveToolRequest('perfscope_ai_context', {'format': 'json'}).$1,
        '/v1/ai-context.json',
      );
    });

    test('missing anomaly_id and bad format are bad_request', () {
      expect(
        () => bridge.resolveToolRequest('perfscope_anomaly_context', {}),
        throwsA(isA<bridge.McpBridgeError>()
            .having((e) => e.code, 'code', 'bad_request')),
      );
      expect(
        () => bridge
            .resolveToolRequest('perfscope_ai_context', {'format': 'yaml'}),
        throwsA(isA<bridge.McpBridgeError>()
            .having((e) => e.code, 'code', 'bad_request')),
      );
      expect(
        () => bridge.resolveToolRequest('perfscope_nope', {}),
        throwsA(isA<bridge.McpBridgeError>()),
      );
    });

    test('JSON-RPC: initialize + tools/list + unknown method', () async {
      final init = await bridge.handleMcpRequest({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {},
      });
      expect((init!['result'] as Map)['serverInfo'], isA<Map>());
      final list = await bridge.handleMcpRequest({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
        'params': {},
      });
      final tools = (list!['result'] as Map)['tools'] as List;
      expect(tools, hasLength(6));
      final unknown = await bridge.handleMcpRequest({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/dance',
        'params': {},
      });
      expect((unknown!['error'] as Map)['code'], -32601);
      // Notifications get no response.
      final note = await bridge.handleMcpRequest({
        'method': 'notifications/initialized',
      });
      expect(note, isNull);
    });

    test('readBridgeDiscovery returns null when the file is missing', () async {
      final root = await Directory.systemTemp.createTemp('perfscope-bridge-');
      try {
        expect(
          await bridge.readBridgeDiscovery(rootOverride: root),
          isNull,
        );
      } finally {
        await root.delete(recursive: true);
      }
    });
  });

  group('parity bridge↔HTTP (T13)', () {
    setUp(() {
      PerfScope.resetForTest();
    });

    tearDown(() async {
      await LivePerfScope.current?.close();
      await PerfScope.dispose();
      PerfScope.resetForTest();
    });

    test('every tool deep-equals its HTTP twin for the same session', () async {
      // Hermetic: this isolate's server publishes into a fixture dir (see
      // discovery_test.dart), so parallel suites can never steal our
      // discovery file mid-parity.
      final root = await Directory.systemTemp.createTemp('perfscope-bridge-');
      discovery.setDiscoveryRootOverrideForTest(root);
      try {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();
        final handle = await LivePerfScope.serve(
          token: 'bridge-parity',
          throttle: Duration.zero,
        );
        final auth = 'Bearer ${handle.token}';

        Future<Map<String, Object?>> httpJson(String path,
            [Map<String, String>? query]) async {
          final res = await liveRequest(
            liveUri(handle.port, path, query),
            authorization: auth,
          );
          expect(res.statusCode, 200, reason: path);
          return jsonDecode(res.body) as Map<String, Object?>;
        }

        // `uptime_ms` is a live clock reading sampled per request, so parity
        // ignores that one volatile key (same reason T05 compares ai-context
        // JSON minus `generated_at`).
        Map<String, Object?> stable(Map<String, Object?> doc) {
          final copy = Map<String, Object?>.of(doc)
            ..remove('uptime_ms')
            ..remove('generated_at');
          return copy;
        }

        expect(
          stable(await bridge.callTool('perfscope_status', {},
              rootOverride: root)),
          stable(await httpJson('/v1/status')),
        );
        expect(
          stable(await bridge.callTool('perfscope_session', {},
              rootOverride: root)),
          stable(await httpJson('/v1/session')),
        );
        expect(
          stable(await bridge.callTool('perfscope_anomalies', {'limit': 10},
              rootOverride: root)),
          stable(await httpJson('/v1/anomalies', {'limit': '10'})),
        );
        expect(
          stable(await bridge.callTool('perfscope_traces', {'limit': 5},
              rootOverride: root)),
          stable(await httpJson('/v1/traces', {'limit': '5'})),
        );
        final aiJson = await bridge.callTool(
            'perfscope_ai_context', {'format': 'json'},
            rootOverride: root);
        expect(stable(aiJson), stable(await httpJson('/v1/ai-context.json')));
      } finally {
        discovery.setDiscoveryRootOverrideForTest(null);
        await root.delete(recursive: true);
      }
    });

    test('ai_context text default equals the /v1/ai-context body', () async {
      final root = await Directory.systemTemp.createTemp('perfscope-bridge-');
      discovery.setDiscoveryRootOverrideForTest(root);
      try {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();
        final handle = await LivePerfScope.serve(
          token: 'bridge-aitext',
          throttle: Duration.zero,
        );
        final httpRes = await liveRequest(
          liveUri(handle.port, '/v1/ai-context'),
          authorization: 'Bearer ${handle.token}',
        );
        expect(httpRes.statusCode, 200);
        final viaBridge = await bridge.callTool('perfscope_ai_context', {},
            rootOverride: root);
        expect(viaBridge['text'], httpRes.body);
      } finally {
        discovery.setDiscoveryRootOverrideForTest(null);
        await root.delete(recursive: true);
      }
    });

    test('bad severity surfaces bad_request (no fallback data)', () async {
      final root = await Directory.systemTemp.createTemp('perfscope-bridge-');
      discovery.setDiscoveryRootOverrideForTest(root);
      try {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();
        await LivePerfScope.serve(
          token: 'bridge-badreq',
          throttle: Duration.zero,
        );
        await expectLater(
          bridge.callTool('perfscope_anomalies', {'severity': 'spicy'},
              rootOverride: root),
          throwsA(isA<bridge.McpBridgeError>()
              .having((e) => e.code, 'code', 'bad_request')),
        );
      } finally {
        discovery.setDiscoveryRootOverrideForTest(null);
        await root.delete(recursive: true);
      }
    });

    test('tools/call over JSON-RPC wraps twin JSON as text content', () async {
      final root = await Directory.systemTemp.createTemp('perfscope-bridge-');
      discovery.setDiscoveryRootOverrideForTest(root);
      try {
        PerfScope.initialize(logWriter: MemoryLogWriter());
        await pumpEventQueue();
        await LivePerfScope.serve(
          token: 'bridge-rpc',
          throttle: Duration.zero,
        );
        Future<Map<String, Object?>> boundCall(
                String tool, Map<String, Object?> args) =>
            bridge.callTool(tool, args, rootOverride: root);
        final response = await bridge.handleMcpRequest(
          {
            'jsonrpc': '2.0',
            'id': 7,
            'method': 'tools/call',
            'params': {
              'name': 'perfscope_status',
              'arguments': <String, Object?>{},
            },
          },
          call: boundCall,
        );
        final content = (response!['result'] as Map)['content'] as List;
        expect(content, hasLength(1));
        expect((content.single as Map)['type'], 'text');
        // Payload is pure JSON-RPC-serializable (stdout-safe).
        final roundTrip = jsonDecode(jsonEncode(response));
        expect(roundTrip, isA<Map>());
      } finally {
        discovery.setDiscoveryRootOverrideForTest(null);
        await root.delete(recursive: true);
      }
    });

    test('missing discovery fails human + stderr (no unauth fallback)',
        () async {
      final root = await Directory.systemTemp.createTemp('perfscope-bridge-');
      try {
        final errLines = <String>[];
        await expectLater(
          bridge.callTool('perfscope_status', {},
              rootOverride: root, onStderr: errLines.add),
          throwsA(isA<bridge.McpBridgeError>()
              .having((e) => e.code, 'code', 'discovery_missing')),
        );
        expect(errLines.join('\n'), contains('perfscope-live.json'));
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('unreachable port reads as stale discovery', () async {
      final root = await Directory.systemTemp.createTemp('perfscope-bridge-');
      try {
        final file = File('${root.path}/.dart_tool/perfscope-live.json');
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(<String, Object?>{
          'port': 1,
          'token': 'stale-token',
          'pid': 999999,
          'projectRoot': root.path,
          'startedAt': DateTime.now().toUtc().toIso8601String(),
        }));
        await expectLater(
          bridge.callTool('perfscope_status', {}, rootOverride: root),
          throwsA(isA<bridge.McpBridgeError>()
              .having((e) => e.code, 'code', 'discovery_stale')),
        );
      } finally {
        await root.delete(recursive: true);
      }
    });
  });
}
