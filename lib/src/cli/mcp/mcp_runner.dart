/// `mcp` subcommand runner (Slice 4, CLI side).
///
/// Lives behind this file (not `perfscope_cli.dart`) because it needs
/// `dart:io` (stdio + home-dir resolution) while `perfscope_cli.dart` stays
/// `dart:io`-free behind the platform shim. `bin/perfscope.dart` injects
/// [runMcpCommand] into `runPerfScopeCli`; tests inject fakes or call this
/// directly with fixture roots.
library;

import 'dart:io' show Directory, Platform;

import 'mcp_bridge.dart' show runMcpBridge;
import 'mcp_install.dart' show installMcpAgents, knownMcpAgents;

/// Runs `mcp <run|install ...>`, writing normal output to [out] and
/// diagnostics to [err]. Returns the process exit code.
///
/// [homeOverride] exists for tests (fixture dirs); production passes nothing
/// so the real home directory is used for agent configs.
Future<int> runMcpCommand(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  Directory? homeOverride,
}) async {
  final effectiveOut = out;
  final effectiveErr = err;
  void errLine(String line) => effectiveErr?.writeln(line);

  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    effectiveOut?.write(_mcpUsage);
    return 0;
  }
  switch (args.first) {
    case 'run':
      // stdio JSON-RPC ↔ HTTP bridge. stdout carries ONLY JSON-RPC (owned by
      // the bridge); diagnostics go to real process stderr.
      return runMcpBridge(
        rootOverride: _discoveryProjectRoot(),
      );
    case 'install':
      return _runInstall(
        args.sublist(1),
        out: effectiveOut,
        errLine: errLine,
        home: homeOverride ?? _homeDir(),
      );
    default:
      errLine("Unknown mcp subcommand: '${args.first}'.");
      errLine(_mcpUsageHint);
      return 1;
  }
}

const String _mcpUsageHint =
    "Run 'dart run perfscope:perfscope mcp --help' for usage.";

const String _mcpUsage = '''
PerfScope MCP bridge (live loopback → agent tools).

Usage: dart run perfscope:perfscope mcp <subcommand> [arguments]

Subcommands:
  run                          stdio JSON-RPC bridge (6 perfscope_* tools)
  install [--agent <name>|--all]  register the bridge in agent configs

Agents: claude, codex, pi, cursor, vscode

Global install first (the package needs the Flutter SDK):

  flutter pub global activate perfscope
''';

/// Project root for discovery lookup: the process working directory.
///
/// The bridge re-resolves per call from `Directory.current` anyway; passing
/// it explicitly keeps the seam testable.
Directory _discoveryProjectRoot() => Directory.current;

Directory _homeDir() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.isNotEmpty) {
    return Directory(home);
  }
  return Directory.current;
}

Future<int> _runInstall(
  List<String> args, {
  required StringSink? out,
  required void Function(String) errLine,
  required Directory home,
}) async {
  final agents = <String>[];
  var all = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--all') {
      all = true;
    } else if (arg == '--agent') {
      if (i + 1 >= args.length) {
        errLine('Missing value for --agent.');
        errLine(_mcpUsageHint);
        return 1;
      }
      agents.add(args[++i]);
    } else if (arg.startsWith('--agent=')) {
      agents.add(arg.substring('--agent='.length));
    } else if (arg == '--help' || arg == '-h') {
      out?.write(_mcpUsage);
      return 0;
    } else {
      errLine('Unknown mcp install flag: $arg.');
      errLine(_mcpUsageHint);
      return 1;
    }
  }
  final selected = all || agents.isEmpty ? knownMcpAgents : agents;
  for (final agent in selected) {
    if (!knownMcpAgents.contains(agent)) {
      errLine('Unknown agent "$agent". Known agents: '
          '${knownMcpAgents.join(', ')}.');
      return 1;
    }
  }
  final report = await installMcpAgents(
    root: home,
    agents: selected,
    out: out,
  );
  if (report.changed.isEmpty) {
    out?.writeln('mcp install: everything up to date.');
  } else {
    out?.writeln('mcp install: registered ${report.changed.join(', ')}.');
  }
  return 0;
}
