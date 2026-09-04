/// Real (`dart:io`) backend for the live bridge: loopback bind, request
/// dispatch, token ownership, uptime clock, and auto-close subscriptions.
///
/// Reachable only through the conditional import in `live_server.dart`, so
/// the web compilation unit never sees `dart:io`. Guards (kill switch,
/// release mode, engine off) are evaluated by the facade BEFORE [bindServe].
library;

import 'dart:async' show StreamSubscription;
import 'dart:io' show HttpServer, InternetAddress, Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:perfscope/perfscope.dart';

import 'discovery.dart';
import 'http/auth.dart';
import 'http/router.dart';
import 'http/sse.dart';
import 'http/throttle.dart';
import 'live_server.dart';

/// True on this backend: `serve()` binds a real socket.
const bool backendIsSupported = true;

/// Pure kill-switch predicate over an env map (injectable for tests).
bool isKillSwitchEnv(Map<String, String> env) => env['PERFSCOPE_LIVE'] == '0';

/// Reads the real process environment. `dart:io`-only by design: this is why
/// the check lives in the io backend instead of the shared facade.
bool isEnvKillSwitchActive() => isKillSwitchEnv(Platform.environment);

/// Binds `InternetAddress.loopbackIPv4` (no host option exists anywhere) and
/// returns a serving handle. The token defaults to a fresh crypto-secure one.
Future<LiveServerHandle> bindServe({
  required int port,
  required String? token,
  required Duration throttle,
  required bool autoClose,
  required void Function(LiveServerHandle closed) onClosed,
}) async {
  final effectiveToken = token ?? generateToken();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final handle = _IoLiveServerHandle(
    server: server,
    token: effectiveToken,
    throttle: ThrottleTracker(throttle),
    autoClose: autoClose,
    onClosed: onClosed,
  );
  handle._start();
  // Slice 4 discovery: publish connection info (port, FULL local-only
  // token, pid, project root, timestamp) for the CLI `mcp run` bridge.
  // Overwrites any stale file; deleted on every close path. Never logged
  // beyond the single console token line below.
  await writeDiscovery(port: server.port, token: effectiveToken);
  // Single console site carrying the token (auditable by grep): the URL line
  // plus exactly one token line, printed once at bind time.
  // ignore: avoid_print
  print('PerfScope live: http://127.0.0.1:${server.port}/v1/status');
  // ignore: avoid_print
  print('PerfScope live token: $effectiveToken');
  return handle;
}

/// Serving handle owned by the io backend.
final class _IoLiveServerHandle implements LiveServerHandle {
  _IoLiveServerHandle({
    required HttpServer server,
    required String token,
    required ThrottleTracker throttle,
    required bool autoClose,
    required void Function(LiveServerHandle closed) onClosed,
  })  : _server = server,
        _token = token,
        _throttle = throttle,
        _autoClose = autoClose,
        _onClosed = onClosed;

  final HttpServer _server;
  final String _token;

  /// Per-route snapshot throttle (Slice 2): every snapshot route consults it
  /// via the router; `/v1/status` (and later `/v1/events`) are exempt.
  final ThrottleTracker _throttle;

  final bool _autoClose;
  final void Function(LiveServerHandle closed) _onClosed;

  final Stopwatch _uptime = Stopwatch();
  StreamSubscription<PerformanceEvent>? _engineDone;
  SseHub? _sseHub;
  bool _closed = false;
  Future<void>? _closeFuture;
  bool _closeNotified = false;

  void _start() {
    _uptime.start();
    // Slice 3 hub owns the ONLY session watcher now: it enqueues reliable
    // `session_stopped` markers BEFORE firing `onSessionEnded`, so auto-close
    // can never drop lifecycle markers (the hub drains them in `close()`).
    // A restart within one tick (X→Y) keeps serving; only X→null closes.
    final hub = SseHub(
      onSessionEnded: _autoClose ? () => close() : null,
    );
    _sseHub = hub;
    hub.start();
    _server.listen((request) async {
      try {
        await routeLiveRequest(
          request,
          token: _token,
          uptimeMs: _uptime.elapsedMilliseconds,
          throttle: _throttle,
          sseHub: hub,
          port: _server.port,
        );
      } catch (_) {
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {
          // Socket already gone; nothing left to do.
        }
      }
    });
    // Engine dispose closes the events stream: always unbind with it,
    // regardless of [autoClose] (spec auto-close contract).
    _engineDone = PerfScope.events.listen(null, onDone: () => close());
  }

  @override
  bool get isServing => !_closed;

  @override
  int get port => _server.port;

  @override
  String get token => _token;

  @override
  Future<void> close() {
    if (_closed) {
      return _closeFuture ?? Future<void>.value();
    }
    _closed = true;
    _closeFuture = _doClose();
    return _closeFuture!;
  }

  Future<void> _doClose() async {
    try {
      await _engineDone?.cancel();
    } catch (_) {
      // Cancellation after engine dispose is best-effort.
    }
    _engineDone = null;
    // Drain reliable SSE markers before unbinding, so `session_stopped`
    // survives an auto-close triggered by session end.
    try {
      await _sseHub?.close();
    } catch (_) {
      // Best effort only; the socket close below still runs.
    }
    _sseHub = null;
    // Slice 4 discovery: remove the published connection info on EVERY
    // close path (explicit close, dispose/detach, auto-close). Best
    // effort — close() stays idempotent even when the FS races us.
    try {
      await deleteDiscovery();
    } catch (_) {
      // Filesystem failures must never break close().
    }
    try {
      await _server.close(force: true);
    } catch (_) {
      // Double-unbind races end here; close stays idempotent.
    }
    if (!_closeNotified) {
      _closeNotified = true;
      try {
        _onClosed(this);
      } catch (_) {
        // Singleton bookkeeping must never break close().
      }
    }
    debugPrint('[PerfScope][live] server closed');
  }
}
