/// Non-io fallback CLI environment: everything fails closed.
///
/// The CLI is a VM tool; web targets never execute it. These stubs exist
/// only so the library stays importable without `dart:io`.
library;

import 'system_probe.dart';

/// Discards all output.
final class _NullSink implements StringSink {
  @override
  void write(Object? obj) {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? obj = '']) {}
}

/// Discarding stdout.
StringSink cliStdout() => _NullSink();

/// Discarding stderr.
StringSink cliStderr() => _NullSink();

/// Always throws: no filesystem on non-io targets.
String loadCliFile(String path) =>
    throw UnsupportedError('File reading requires dart:io.');

/// Probe that never finds anything.
SystemProbe createDefaultProbe() => const NullSystemProbe();
