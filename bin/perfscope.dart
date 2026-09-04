/// Thin executable wrapper for the PerfScope CLI.
///
/// All logic lives in `runPerfScopeCli` so tests can drive it with
/// injected sinks and loaders; this file only bridges to the real
/// process streams and exit code.
library;

import 'dart:io' show exit;

import 'package:perfscope/src/cli/mcp/mcp_runner.dart' show runMcpCommand;
import 'package:perfscope/src/cli/perfscope_cli.dart';

Future<void> main(List<String> args) async {
  exit(await runPerfScopeCli(
    args,
    mcpRunner: (runnerArgs, out, err) =>
        runMcpCommand(runnerArgs, out: out, err: err),
  ));
}
