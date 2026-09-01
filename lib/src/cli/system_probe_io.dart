/// VM/AOT probe backed by real process spawning (`dart:io`).
library;

import 'dart:io' show Process, ProcessResult;

import 'system_probe.dart';

/// Creates the real process-spawning probe.
IoSystemProbe createIoProbe() => const IoSystemProbe();

/// Spawns `<executable> --version` processes with a 10-second timeout;
/// every failure mode (not found, permission denied, timeout) collapses
/// to null so the caller treats it as "missing".
final class IoSystemProbe implements SystemProbe {
  /// Creates the probe. Instances are stateless.
  const IoSystemProbe();

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<ProbeResult?> runVersion(String executable) async {
    final ProcessResult result;
    try {
      result =
          await Process.run(executable, const ['--version']).timeout(_timeout);
    } on Object {
      // Not found, permission denied, timeout... → treated as missing.
      return null;
    }
    return ProbeResult(
      exitCode: result.exitCode,
      stdout: result.stdout as String? ?? '',
      stderr: result.stderr as String? ?? '',
    );
  }
}
