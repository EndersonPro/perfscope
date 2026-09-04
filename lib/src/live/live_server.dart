/// Facade for the live bridge: guards, singleton handle, conditional backend.
///
/// No socket library may appear in this file (web compilation unit). The real
/// socket backend lives in `live_server_io.dart`, reached through the
/// conditional import below; the web/disabled backend is `live_server_stub.dart`.
library;

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:perfscope/perfscope.dart';

import 'live_server_stub.dart' if (dart.library.io) 'live_server_io.dart'
    as backend;

/// Handle to a live-bridge server (serving or disabled).
///
/// A disabled handle reports `isServing == false`, `port == 0`, an empty
/// token, and a no-op [close]. (Declared non-final so the io/stub backends —
/// separate libraries behind the conditional import — can implement it; the
/// public shape matches the design contract.)
abstract class LiveServerHandle {
  /// Whether a socket is currently bound.
  bool get isServing;

  /// Effective port (`0` when disabled).
  int get port;

  /// Effective Bearer token (`''` when disabled).
  String get token;

  /// Unbinds the server. Idempotent; safe to call after auto-close.
  Future<void> close();
}

/// Disabled handle: kill switch, release mode, engine off, or web stub.
final class _DisabledHandle implements LiveServerHandle {
  const _DisabledHandle();

  @override
  bool get isServing => false;

  @override
  int get port => 0;

  @override
  String get token => '';

  @override
  Future<void> close() async {}
}

/// Entry point for the live bridge.
abstract final class LivePerfScope {
  static LiveServerHandle? _current;
  static Future<LiveServerHandle>? _binding;

  /// The serving handle, or null when nothing is serving.
  ///
  /// Disabled handles are never published here.
  static LiveServerHandle? get current {
    final handle = _current;
    return (handle != null && handle.isServing) ? handle : null;
  }

  /// Binds a loopback HTTP server and returns its handle.
  ///
  /// Guard order (first hit wins → disabled handle + one warning line):
  /// `enabled == false`, `PERFSCOPE_LIVE == '0'`, release mode,
  /// engine off, web stub. A second call while serving returns the existing
  /// handle unchanged (concurrent callers share one bind future).
  static Future<LiveServerHandle> serve({
    int port = 0,
    String? token,
    Duration throttle = const Duration(milliseconds: 250),
    bool autoClose = true,
    bool enabled = true,
  }) {
    final serving = _current;
    if (serving != null && serving.isServing) {
      debugPrint('[PerfScope][live] serve() ignored: already serving');
      return Future.value(serving);
    }
    final pending = _binding;
    if (pending != null) {
      return pending;
    }
    final future = _serveOnce(
      port: port,
      token: token,
      throttle: throttle,
      autoClose: autoClose,
      enabled: enabled,
    );
    _binding = future;
    return future.whenComplete(() {
      _binding = null;
    });
  }

  static Future<LiveServerHandle> _serveOnce({
    required int port,
    required String? token,
    required Duration throttle,
    required bool autoClose,
    required bool enabled,
  }) async {
    if (!enabled) {
      return _disabled('disabled via enabled:false');
    }
    if (backend.isEnvKillSwitchActive()) {
      return _disabled('disabled via PERFSCOPE_LIVE=0');
    }
    if (kReleaseMode) {
      return _disabled('disabled in release mode');
    }
    if (PerfScope.maybeEngine == null) {
      return _disabled('disabled: PerfScope engine is off');
    }
    if (!backend.backendIsSupported) {
      return _disabled('live bridge unsupported on web in v0.2');
    }
    final handle = await backend.bindServe(
      port: port,
      token: token,
      throttle: throttle,
      autoClose: autoClose,
      onClosed: (closed) {
        if (identical(_current, closed)) {
          _current = null;
        }
      },
    );
    _current = handle;
    return handle;
  }

  static LiveServerHandle _disabled(String reason) {
    debugPrint('[PerfScope][live] $reason');
    return const _DisabledHandle();
  }
}
