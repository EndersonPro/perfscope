/// Web/disabled backend for the live bridge: identical signature, no binding.
///
/// This file MUST NOT import the socket library (it compiles into the web unit).
/// The facade checks [backendIsSupported] before calling [bindServe], so the
/// latter is unreachable here; it exists only for backend-interface parity.
library;

import 'package:flutter/foundation.dart' show debugPrint;

import 'live_server.dart';

/// False on this backend: `serve()` always resolves to a disabled handle.
const bool backendIsSupported = false;

/// The kill-switch env var cannot be read without the socket library;
/// the stub never serves, so there is nothing to disable.
bool isEnvKillSwitchActive() => false;

/// Unreachable (the facade returns a disabled handle first). Kept for
/// interface parity with the io backend.
Future<LiveServerHandle> bindServe({
  required int port,
  required String? token,
  required Duration throttle,
  required bool autoClose,
  required void Function(LiveServerHandle closed) onClosed,
}) async {
  debugPrint('[PerfScope][live] live bridge unsupported on web in v0.2');
  return const _StubDisabledHandle();
}

/// Disabled handle owned by the stub backend.
final class _StubDisabledHandle implements LiveServerHandle {
  const _StubDisabledHandle();

  @override
  bool get isServing => false;

  @override
  int get port => 0;

  @override
  String get token => '';

  @override
  Future<void> close() async {}
}
