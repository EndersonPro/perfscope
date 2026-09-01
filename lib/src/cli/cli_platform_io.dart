/// VM/AOT CLI environment backed by `dart:io`.
library;

import 'dart:io' show File, stderr, stdout;

import 'system_probe.dart';
import 'system_probe_io.dart' show createIoProbe;

/// Real stdout for the host process.
StringSink cliStdout() => stdout;

/// Real stderr for the host process.
StringSink cliStderr() => stderr;

/// Reads [path] as text; relative paths resolve against the process's
/// working directory. Throws when the file cannot be read — callers map
/// any throw to the "Cannot read file" exit path.
String loadCliFile(String path) => File(path).readAsStringSync();

/// Probe backed by real process spawning.
SystemProbe createDefaultProbe() => createIoProbe();
