/// GET route table for Slices 1–2 + the uniform error envelope.
///
/// Pure dispatch over `HttpRequest`: method check → path match → auth gate →
/// engine check → throttle → snapshot. Slice 1 serves `/v1/status`,
/// `/v1/ai-context`, and `/v1/ai-context.json`; Slice 2 adds `/v1/session`,
/// `/v1/frames/stats`, `/v1/anomalies`, `/v1/anomalies/:id/context`, and
/// `/v1/traces`. Token-via-query is never read; unknown query params are
/// ignored except the validated filter params (`limit`, `severity`, `type`).
library;

import 'dart:convert' show jsonEncode;
import 'dart:io' show ContentType, HttpHeaders, HttpRequest, HttpStatus;

import 'package:perfscope/perfscope.dart';

import '../snapshot/live_snapshot.dart';
import 'auth.dart';
import 'sse.dart';
import 'throttle.dart';

/// Slice 1 paths (unthrottled status + snapshot ai-context routes).
const Set<String> slice1Paths = <String>{
  '/v1/status',
  '/v1/ai-context',
  '/v1/ai-context.json',
};

/// Slice 2 exact paths (all throttled snapshot routes).
const Set<String> slice2Paths = <String>{
  '/v1/session',
  '/v1/frames/stats',
  '/v1/anomalies',
  '/v1/traces',
};

/// Slice 3 event-stream path (self-paced, throttle-exempt, same Bearer gate).
const Set<String> ssePaths = <String>{
  '/v1/events',
};

/// Routes exempt from the snapshot throttle (cheap health probe +,
/// from Slice 3, the self-paced event stream).
const Set<String> throttleExemptPaths = <String>{
  '/v1/status',
  '/v1/events',
};

/// Matches `/v1/anomalies/<id>/context` and returns the `<id>`, or null when
/// [path] is not a context route (the caller then falls back to exact-match
/// routing, so malformed shapes end as 404 `not_found`, never as 404
/// `context_unavailable`).
String? matchAnomalyContextId(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.length == 4 &&
      segments[0] == 'v1' &&
      segments[1] == 'anomalies' &&
      segments[2].isNotEmpty &&
      segments[3] == 'context') {
    return segments[2];
  }
  return null;
}

/// Dispatches one request. Never throws: handler failures in the io backend
/// are contained around this call.
///
/// Slice 3: `/v1/events` hijacks the response as an SSE stream via [sseHub]
/// (same Bearer gate, throttle-exempt). The hub owns the response until the
/// client disconnects; this function returns without closing it. [port] feeds
/// the `ready{port,session_id}` first frame. Both are optional only so older
/// call sites keep compiling; serving always passes them (missing hub/port on
/// an events request throws, surfaced by the io backend as a bare 500).
Future<void> routeLiveRequest(
  HttpRequest request, {
  required String token,
  required int uptimeMs,
  required ThrottleTracker throttle,
  SseHub? sseHub,
  int? port,
}) async {
  if (request.method != 'GET') {
    await writeError(
      request,
      HttpStatus.methodNotAllowed,
      'method_not_allowed',
      'Only GET is served.',
      extraHeaders: const {'allow': 'GET'},
    );
    return;
  }
  final path = request.uri.path;
  final contextId = matchAnomalyContextId(request.uri);
  final known = slice1Paths.contains(path) ||
      slice2Paths.contains(path) ||
      ssePaths.contains(path) ||
      contextId != null;
  if (!known) {
    await writeError(
      request,
      HttpStatus.notFound,
      'not_found',
      'Unknown path: $path.',
    );
    return;
  }
  final provided =
      extractBearer(request.headers.value(HttpHeaders.authorizationHeader));
  if (provided == null || !constantTimeEquals(provided, token)) {
    await writeError(
      request,
      HttpStatus.unauthorized,
      'unauthorized',
      'Missing or invalid bearer token.',
      extraHeaders: const {'www-authenticate': 'Bearer'},
    );
    return;
  }
  if (PerfScope.maybeEngine == null) {
    await writeError(
      request,
      HttpStatus.serviceUnavailable,
      'engine_disabled',
      'PerfScope engine is not running.',
    );
    return;
  }
  if (!throttleExemptPaths.contains(path)) {
    final remaining = throttle.shouldReject(path, DateTime.now());
    if (remaining != null) {
      await writeError(
        request,
        HttpStatus.tooManyRequests,
        'rate_limited',
        'Snapshot throttle: retry after ${ThrottleTracker.retryAfterSeconds(remaining)}s.',
        extraHeaders: {
          'retry-after': '${ThrottleTracker.retryAfterSeconds(remaining)}',
        },
      );
      return;
    }
  }
  switch (path) {
    case '/v1/status':
      await writeJson(request, HttpStatus.ok, liveStatus(uptimeMs: uptimeMs));
    case '/v1/events':
      final hub = sseHub;
      final eventsPort = port;
      if (hub == null || eventsPort == null) {
        throw StateError('SseHub/port missing for /v1/events.');
      }
      // Same Bearer gate + engine check above already ran; the stream is
      // self-paced (throttle-exempt). The hub owns the response now.
      await hub.serveRequest(request, port: eventsPort);
      return;
    case '/v1/ai-context':
      final text = liveAiContextText();
      if (text == null) {
        await writeError(
          request,
          HttpStatus.notFound,
          'no_session',
          'No session has been recorded yet.',
        );
        return;
      }
      throttle.markServed(path, DateTime.now());
      await writeText(request, HttpStatus.ok, text);
    case '/v1/ai-context.json':
      final document = liveAiContextJson();
      if (document == null) {
        await writeError(
          request,
          HttpStatus.notFound,
          'no_session',
          'No session has been recorded yet.',
        );
        return;
      }
      throttle.markServed(path, DateTime.now());
      await writeJson(request, HttpStatus.ok, document);
    case '/v1/session':
      final document = liveSessionDocument();
      if (document == null) {
        await writeError(
          request,
          HttpStatus.notFound,
          'no_session',
          'No session has been recorded yet.',
        );
        return;
      }
      throttle.markServed(path, DateTime.now());
      await writeJson(request, HttpStatus.ok, document);
    case '/v1/frames/stats':
      final summary = liveFramesStats();
      if (summary == null) {
        await writeError(
          request,
          HttpStatus.notFound,
          'no_session',
          'No session has been recorded yet.',
        );
        return;
      }
      throttle.markServed(path, DateTime.now());
      await writeJson(
        request,
        HttpStatus.ok,
        <String, Object?>{'schema_version': 1, 'summary': summary},
      );
    case '/v1/anomalies':
      final query = request.uri.queryParameters;
      try {
        final result = liveAnomalies(
          limit: _parseLimit(query['limit']),
          severity: query['severity'],
          type: query['type'],
        );
        if (result == null) {
          await writeError(
            request,
            HttpStatus.notFound,
            'no_session',
            'No session has been recorded yet.',
          );
          return;
        }
        throttle.markServed(path, DateTime.now());
        await writeJson(request, HttpStatus.ok, result);
      } on LiveBadRequest catch (error) {
        await writeError(
          request,
          HttpStatus.badRequest,
          'bad_request',
          error.message,
        );
      }
    case '/v1/traces':
      final query = request.uri.queryParameters;
      try {
        final result = liveTraces(limit: _parseLimit(query['limit']));
        if (result == null) {
          await writeError(
            request,
            HttpStatus.notFound,
            'no_session',
            'No session has been recorded yet.',
          );
          return;
        }
        throttle.markServed(path, DateTime.now());
        await writeJson(request, HttpStatus.ok, result);
      } on LiveBadRequest catch (error) {
        await writeError(
          request,
          HttpStatus.badRequest,
          'bad_request',
          error.message,
        );
      }
    default:
      // The only remaining known shape is `/v1/anomalies/:id/context`.
      final id = contextId;
      if (id == null) {
        await writeError(
          request,
          HttpStatus.notFound,
          'not_found',
          'Unknown path: $path.',
        );
        return;
      }
      if (PerfScope.currentSession == null &&
          PerfScope.maybeEngine?.lastFinishedSession == null) {
        await writeError(
          request,
          HttpStatus.notFound,
          'no_session',
          'No session has been recorded yet.',
        );
        return;
      }
      final context = liveAnomalyContext(id);
      if (context == null) {
        await writeError(
          request,
          HttpStatus.notFound,
          'context_unavailable',
          'No complete context window for anomaly "$id".',
        );
        return;
      }
      throttle.markServed(path, DateTime.now());
      await writeJson(request, HttpStatus.ok, context);
  }
}

/// Parses a `limit` query value: absent → null (serve all); present →
/// integer (validated downstream, non-integers throw 400 semantics here).
int? _parseLimit(String? raw) {
  if (raw == null) {
    return null;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null) {
    throw LiveBadRequest('Invalid limit "$raw": must be an integer >= 1.');
  }
  return parsed;
}

/// Writes a JSON body: `{"error": {"code": ..., "message": ...}}`.
///
/// Single function through which every error flows (uniform envelope).
Future<void> writeError(
  HttpRequest request,
  int status,
  String code,
  String message, {
  Map<String, String> extraHeaders = const {},
}) async {
  final response = request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json;
  extraHeaders.forEach(response.headers.set);
  response.write(jsonEncode({
    'error': {'code': code, 'message': message},
  }));
  await response.close();
}

/// Writes a 200-class JSON document.
Future<void> writeJson(
  HttpRequest request,
  int status,
  Map<String, Object?> document,
) async {
  final response = request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json;
  response.write(jsonEncode(document));
  await response.close();
}

/// Writes a `text/plain; charset=utf-8` body (ai-context text form).
Future<void> writeText(HttpRequest request, int status, String body) async {
  final response = request.response
    ..statusCode = status
    ..headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
  response.write(body);
  await response.close();
}
