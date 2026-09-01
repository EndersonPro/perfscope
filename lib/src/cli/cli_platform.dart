/// Process-level dependencies for the PerfScope CLI: output sinks and
/// the session-file loader.
///
/// Split via conditional imports so `perfscope_cli.dart` itself never
/// touches `dart:io`: VM builds get real stdout/stderr plus filesystem
/// reads, every other target gets inert stubs (the CLI is not meant to
/// run there; tests inject fakes through [CommandRunnerDependencies]
/// instead).
library;

export 'cli_platform_default.dart' if (dart.library.io) 'cli_platform_io.dart';
