/// MCP stdio→HTTP bridge (Slice 4, CLI side, separate OS process).
///
/// `mcp run` reads the app discovery file
/// (`.dart_tool/perfscope-live.json`), presents its Bearer token on every app
/// call, and exposes exactly six `perfscope_*` tools over stdio JSON-RPC as
/// pure forwards to their HTTP twins (zero projection logic — parity is
/// HTTP-equality by construction).
///
/// Import discipline: `dart:async` + `dart:convert` + `dart:io` ONLY. This
/// file MUST NEVER import Flutter libraries, live-server sources, the
/// opt-in live barrel, or serializer internals (enforced by
/// `test/live/import_ban_test.dart`, which matches real directives).
/// The bridge has no access to live memory; it talks HTTP like `curl` does.
///
/// Wire format: newline-delimited JSON-RPC 2.0 on stdin/stdout. stdout carries
/// ONLY JSON-RPC; every diagnostic goes to stderr.
library;

import 'dart:async' show Completer, StreamSubscription;
import 'dart:convert' show LineSplitter, jsonDecode, jsonEncode, utf8;
import 'dart:io'
    show
        Directory,
        File,
        HttpClient,
        HttpClientResponse,
        HttpHeaders,
        HttpOverrides,
        Platform,
        Stdin,
        Stdout,
        stderr,
        stdin,
        stdout;

/// The six MCP tool names, in spec-table order.
const List<String> mcpToolNames = <String>[
  'perfscope_status',
  'perfscope_session',
  'perfscope_anomalies',
  'perfscope_anomaly_context',
  'perfscope_traces',
  'perfscope_ai_context',
];

/// Static tool definitions (name + description + JSON input schema).
List<Map<String, Object?>> mcpToolDefinitions() => <Map<String, Object?>>[
      {
        'name': 'perfscope_status',
        'description': 'Live loopback status (GET /v1/status twin).',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
        },
      },
      {
        'name': 'perfscope_session',
        'description': 'Full schema-v1 session document (GET /v1/session).',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
        },
      },
      {
        'name': 'perfscope_anomalies',
        'description': 'Filtered anomalies (GET /v1/anomalies twin).',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'limit': <String, Object?>{'type': 'integer'},
            'severity': <String, Object?>{
              'type': 'string',
              'enum': <String>['low', 'medium', 'high', 'critical'],
            },
            'type': <String, Object?>{
              'type': 'string',
              'enum': <String>[
                'slow_frame',
                'ui_bound_frame',
                'raster_bound_frame',
                'mixed_frame',
                'long_trace',
              ],
            },
          },
        },
      },
      {
        'name': 'perfscope_anomaly_context',
        'description': 'Context window for one anomaly id.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'anomaly_id': <String, Object?>{'type': 'string'},
          },
          'required': <String>['anomaly_id'],
        },
      },
      {
        'name': 'perfscope_traces',
        'description': 'Stored traces (GET /v1/traces twin).',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'limit': <String, Object?>{'type': 'integer'},
          },
        },
      },
      {
        'name': 'perfscope_ai_context',
        'description': 'AI-ready context, text (default) or json.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'format': <String, Object?>{
              'type': 'string',
              'enum': <String>['text', 'json'],
            },
          },
        },
      },
    ];

/// MCP-shaped error carrying the HTTP-twin `code` string.
final class McpBridgeError implements Exception {
  const McpBridgeError(this.code, this.message);

  /// Snake-case code forwarded from the HTTP error envelope
  /// (`unauthorized`, `bad_request`, `no_session`, …) or a bridge-local code
  /// (`discovery_missing`, `discovery_stale`, `transport_error`).
  final String code;

  /// Human message (stderr + MCP error text).
  final String message;

  @override
  String toString() => 'McpBridgeError($code): $message';
}

/// Reads the discovery file (same relative path the app writes).
///
/// [rootOverride]/[fileOverride] exist for tests; production passes nothing.
/// Returns null when the file is missing or unparseable.
Future<Map<String, Object?>?> readBridgeDiscovery({
  Directory? rootOverride,
  File? fileOverride,
}) async {
  final file = fileOverride ??
      File('${(rootOverride ?? Directory.current).path}'
          '${Platform.pathSeparator}.dart_tool'
          '${Platform.pathSeparator}perfscope-live.json');
  try {
    if (!await file.exists()) {
      return null;
    }
    final parsed = jsonDecode(await file.readAsString());
    if (parsed is Map<String, Object?>) {
      return parsed;
    }
    if (parsed is Map) {
      return (parsed).cast<String, Object?>();
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Resolves one tool call to its HTTP twin request.
///
/// Returns `(method-path, query)`. Throws [McpBridgeError] with
/// `bad_request` for client-side arg errors (missing `anomaly_id`, bad
/// `format`) — mirroring the HTTP twin's 400 semantics without reimplementing
/// projection logic.
(String path, Map<String, String> query, {bool text}) resolveToolRequest(
  String tool,
  Map<String, Object?> args,
) {
  switch (tool) {
    case 'perfscope_status':
      return ('/v1/status', const <String, String>{}, text: false);
    case 'perfscope_session':
      return ('/v1/session', const <String, String>{}, text: false);
    case 'perfscope_anomalies':
      final query = <String, String>{};
      for (final key in const ['limit', 'severity', 'type']) {
        final value = args[key];
        if (value != null) {
          query[key] = '$value';
        }
      }
      return ('/v1/anomalies', query, text: false);
    case 'perfscope_anomaly_context':
      final id = args['anomaly_id'];
      if (id == null || (id is String && id.isEmpty)) {
        throw const McpBridgeError(
            'bad_request', 'Missing required argument "anomaly_id".');
      }
      final encoded = Uri.encodeComponent('$id');
      return (
        '/v1/anomalies/$encoded/context',
        const <String, String>{},
        text: false
      );
    case 'perfscope_traces':
      final query = <String, String>{};
      final limit = args['limit'];
      if (limit != null) {
        query['limit'] = '$limit';
      }
      return ('/v1/traces', query, text: false);
    case 'perfscope_ai_context':
      final format = args['format'];
      if (format == null || format == 'text') {
        return ('/v1/ai-context', const <String, String>{}, text: true);
      }
      if (format == 'json') {
        return ('/v1/ai-context.json', const <String, String>{}, text: false);
      }
      throw McpBridgeError(
          'bad_request', 'Unknown format "$format": use "text" or "json".');
    default:
      throw McpBridgeError('bad_request', 'Unknown tool "$tool".');
  }
}

/// Signature of the HTTP fetch used by [callTool].
///
/// Test seam: production passes the real loopback fetch; tests inject fakes
/// or point at a live test server.
typedef BridgeHttpFetch = Future<({int status, String body})> Function(
  Uri uri,
  String token,
);

/// Pass-through overrides restoring the real client inside the test zone.
///
/// `TestWidgetsFlutterBinding` installs a global mock answering 400 to every
/// request; a zoned override takes precedence over it (same pattern as
/// `test/live/live_test_client.dart`). In production there is no mock, so
/// this is a no-op there.
final class _UnmockedOverrides extends HttpOverrides {}

/// Default fetch: real `HttpClient` GET with the Bearer token.
Future<({int status, String body})> fetchBridgeHttp(
  Uri uri,
  String token,
) async {
  final client = HttpOverrides.runZoned(
    () => HttpClient(),
    createHttpClient: (context) =>
        _UnmockedOverrides().createHttpClient(context),
  );
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final HttpClientResponse response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: body);
  } finally {
    client.close();
  }
}

/// Calls one tool by forwarding to its HTTP twin.
///
/// Returns the decoded twin body (JSON map, or `{'text': …}` for the text
/// twin). HTTP error envelopes map to [McpBridgeError] carrying the same
/// `code` string. Discovery/transport failures map to `discovery_missing`,
/// `discovery_stale`, or `transport_error` with a human message (also
/// reported on stderr by the stdio loop).
Future<Map<String, Object?>> callTool(
  String tool,
  Map<String, Object?> args, {
  Directory? rootOverride,
  File? fileOverride,
  BridgeHttpFetch fetch = fetchBridgeHttp,
  void Function(String line)? onStderr,
}) async {
  void err(String line) => (onStderr ?? stderr.writeln)(line);

  final discovery = await readBridgeDiscovery(
      rootOverride: rootOverride, fileOverride: fileOverride);
  if (discovery == null) {
    err('perfscope: no live server found — '
        'expected .dart_tool/perfscope-live.json. '
        'Serve first (LivePerfScope.serve() in a profile run).');
    throw const McpBridgeError('discovery_missing',
        'No live server found (.dart_tool/perfscope-live.json missing).');
  }
  final port = discovery['port'];
  final token = discovery['token'];
  if (port is! int || token is! String || token.isEmpty) {
    err('perfscope: discovery file is corrupt — delete '
        '.dart_tool/perfscope-live.json and re-serve.');
    throw const McpBridgeError(
        'discovery_stale', 'Discovery file is corrupt or stale.');
  }

  final resolved = resolveToolRequest(tool, args);
  final uri = Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: port,
    path: resolved.$1,
    queryParameters: resolved.$2.isEmpty ? null : resolved.$2,
  );
  final ({String body, int status}) result;
  try {
    result = await fetch(uri, token);
  } catch (error) {
    err('perfscope: live server at 127.0.0.1:$port is unreachable '
        '(${error.runtimeType}) — stale discovery? Re-serve the app.');
    throw McpBridgeError('discovery_stale', 'Live server unreachable: $error.');
  }
  if (result.status == 401) {
    err('perfscope: live server rejected the discovery token (401) — '
        'stale .dart_tool/perfscope-live.json? Re-serve the app.');
    throw const McpBridgeError(
        'discovery_stale', 'Discovery token rejected (stale file).');
  }
  if (result.status != 200) {
    final code = _envelopeCode(result.body) ?? 'bridge_error';
    throw McpBridgeError(code, _envelopeMessage(result.body) ?? result.body);
  }
  if (resolved.text) {
    return <String, Object?>{'text': result.body};
  }
  final parsed = jsonDecode(result.body);
  if (parsed is Map<String, Object?>) {
    return parsed;
  }
  if (parsed is Map) {
    return (parsed).cast<String, Object?>();
  }
  return <String, Object?>{'value': parsed};
}

String? _envelopeCode(String body) {
  try {
    final parsed = jsonDecode(body);
    if (parsed is Map) {
      final error = (parsed)['error'];
      if (error is Map) {
        final code = (error)['code'];
        return code is String ? code : null;
      }
    }
  } catch (_) {}
  return null;
}

String? _envelopeMessage(String body) {
  try {
    final parsed = jsonDecode(body);
    if (parsed is Map) {
      final error = (parsed)['error'];
      if (error is Map) {
        final message = (error)['message'];
        return message is String ? message : null;
      }
    }
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// JSON-RPC dispatch (pure, stdout-safe — returns maps, never prints)
// ---------------------------------------------------------------------------

/// Handles one decoded JSON-RPC request map.
///
/// [call] forwards tool calls (defaults to [callTool]). Returns the response
/// map, or null for notifications (no response). Errors follow JSON-RPC
/// (`{jsonrpc, error: {code, message, data?}, id}`), with MCP tool failures
/// using code `-32000` and the twin `code` string in `data`.
Future<Map<String, Object?>?> handleMcpRequest(
  Map<String, Object?> request, {
  Future<Map<String, Object?>> Function(String tool, Map<String, Object?> args)?
      call,
}) async {
  final id = request['id'];
  final method = request['method'];
  final params = request['params'];
  final paramsMap =
      params is Map ? params.cast<String, Object?>() : <String, Object?>{};

  Map<String, Object?> ok(Object? result) => <String, Object?>{
        'jsonrpc': '2.0',
        if (id != null) 'id': id,
        'result': result,
      };
  Map<String, Object?> fail(int code, String message, [Object? data]) =>
      <String, Object?>{
        'jsonrpc': '2.0',
        if (id != null) 'id': id,
        'error': <String, Object?>{
          'code': code,
          'message': message,
          if (data != null) 'data': data,
        },
      };

  if (method == null) {
    return fail(-32600, 'Missing method.');
  }
  // Notifications (no id, `notifications/` prefix) get no response.
  if (id == null && (method is String) && method.startsWith('notifications/')) {
    return null;
  }

  switch (method) {
    case 'initialize':
      return ok(<String, Object?>{
        'protocolVersion': '2024-11-05',
        'capabilities': <String, Object?>{
          'tools': <String, Object?>{},
        },
        'serverInfo': <String, Object?>{
          'name': 'perfscope',
          'version': '0.1.0',
        },
      });
    case 'ping':
      return ok(<String, Object?>{});
    case 'tools/list':
      return ok(<String, Object?>{
        'tools': mcpToolDefinitions(),
      });
    case 'tools/call':
      final name = paramsMap['name'];
      if (name is! String) {
        return fail(-32602, 'Missing tool name.');
      }
      if (!mcpToolNames.contains(name)) {
        return fail(-32602, 'Unknown tool "$name".');
      }
      final rawArgs = paramsMap['arguments'];
      final args = rawArgs is Map
          ? (rawArgs).cast<String, Object?>()
          : <String, Object?>{};
      try {
        final result = await (call ?? callTool)(name, args);
        if (result.containsKey('text') && result.length == 1) {
          return ok(<String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'type': 'text',
                'text': result['text'],
              },
            ],
          });
        }
        return ok(<String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'text',
              'text': jsonEncode(result),
            },
          ],
        });
      } on McpBridgeError catch (error) {
        return fail(-32000, error.message, {'code': error.code});
      }
    default:
      return fail(-32601, 'Method not found: $method.');
  }
}

// ---------------------------------------------------------------------------
// Stdio loop (`mcp run` entry)
// ---------------------------------------------------------------------------

/// Runs the stdio→HTTP bridge until stdin closes.
///
/// stdout carries ONLY JSON-RPC response lines; every diagnostic goes to
/// [stderrSink] (defaults to process stderr). Returns the process exit code
/// (0 on clean EOF). A missing discovery file does NOT prevent startup:
/// `tools/list` still answers (static), while `tools/call` fails per-call
/// with a human `discovery_missing` error (also logged to stderr).
Future<int> runMcpBridge({
  Stdin? stdinSource,
  Stdout? stdoutSink,
  void Function(String line)? stderrSink,
  Future<Map<String, Object?>> Function(String tool, Map<String, Object?> args)?
      call,
  Directory? rootOverride,
  File? fileOverride,
}) async {
  final Stdin input = stdinSource ?? stdin;
  final Stdout output = stdoutSink ?? stdout;
  void err(String line) => (stderrSink ?? stderr.writeln)(line);

  Future<Map<String, Object?>> boundCall(
      String tool, Map<String, Object?> args) {
    if (call != null) {
      return call(tool, args);
    }
    return callTool(tool, args,
        rootOverride: rootOverride, fileOverride: fileOverride, onStderr: err);
  }

  final discovery = await readBridgeDiscovery(
      rootOverride: rootOverride, fileOverride: fileOverride);
  if (discovery == null) {
    err('perfscope: no live server found — '
        'expected .dart_tool/perfscope-live.json. '
        'Serve first (LivePerfScope.serve() in a profile run). '
        'tools/list stays available; tools/call will fail until it exists.');
  }

  final completer = Completer<int>();
  late final StreamSubscription<String> subscription;
  subscription = input
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) async {
    if (line.trim().isEmpty) {
      return;
    }
    Map<String, Object?>? request;
    try {
      final parsed = jsonDecode(line);
      if (parsed is Map<String, Object?>) {
        request = parsed;
      } else if (parsed is Map) {
        request = (parsed).cast<String, Object?>();
      }
    } catch (_) {
      request = null;
    }
    if (request == null) {
      output.writeln(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': null,
        'error': <String, Object?>{
          'code': -32700,
          'message': 'Parse error.',
        },
      }));
      return;
    }
    final response = await handleMcpRequest(request, call: boundCall);
    if (response != null) {
      output.writeln(jsonEncode(response));
    }
  }, onDone: () {
    if (!completer.isCompleted) {
      completer.complete(0);
    }
  }, onError: (_, __) {
    if (!completer.isCompleted) {
      completer.complete(1);
    }
  }, cancelOnError: false);

  final code = await completer.future;
  await subscription.cancel();
  return code;
}
