/// The injectable environment probe used by `doctor`, plus its result.
///
/// The interface keeps the CLI library free of `dart:io`: tests supply
/// fakes, VM builds get the conditional-import-backed implementation
/// from `system_probe_io.dart`.
library;

/// One completed external-version probe.
final class ProbeResult {
  /// Creates an immutable probe result.
  const ProbeResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Process exit code.
  final int exitCode;

  /// Standard output of the probe command.
  final String stdout;

  /// Standard error of the probe command (`dart --version` writes here).
  final String stderr;
}

/// Spawns version probes for executables on PATH.
abstract interface class SystemProbe {
  /// Runs `<executable> --version`.
  ///
  /// Returns null when the executable cannot be spawned at all (not
  /// found, not executable, timed out); a non-zero exit code with output
  /// is still returned as a result and interpreted by the caller.
  Future<ProbeResult?> runVersion(String executable);
}

/// Probe whose every lookup fails: used by non-io builds.
final class NullSystemProbe implements SystemProbe {
  /// Creates the stub. Instances are stateless.
  const NullSystemProbe();

  @override
  Future<ProbeResult?> runVersion(String executable) async => null;
}
