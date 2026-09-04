/// `mcp install` agent registration (Slice 4, CLI side, separate OS process).
///
/// Detects known agent config files and registers the `mcp run` bridge
/// additively (unrelated entries preserved) and idempotently (a second run
/// changes nothing). Prints the plan before writing.
///
/// Import discipline: `dart:convert` + `dart:io` ONLY — same as the bridge.
/// Tests run ONLY against fixture dirs (a required [root]); this file never
/// guesses the user's home on its own (the CLI runner passes it in).
library;

import 'dart:convert' show JsonEncoder, jsonDecode, jsonEncode;
import 'dart:io' show Directory, File, Platform;

/// Agents with a known config layout, in help-text order.
const List<String> knownMcpAgents = <String>[
  'claude',
  'codex',
  'pi',
  'cursor',
  'vscode',
];

/// Config file path for [agent], relative to the registration [root].
///
/// Layout (JSON everywhere, uniform `mcpServers` map):
/// * `claude` → `.claude.json`
/// * `codex` → `.codex/config.json`
/// * `pi` → `.pi/mcp.json`
/// * `cursor` → `.cursor/mcp.json`
/// * `vscode` → `.vscode/mcp.json`
String agentConfigRelativePath(String agent) {
  switch (agent) {
    case 'claude':
      return '.claude.json';
    case 'codex':
      return '.codex${Platform.pathSeparator}config.json';
    case 'pi':
      return '.pi${Platform.pathSeparator}mcp.json';
    case 'cursor':
      return '.cursor${Platform.pathSeparator}mcp.json';
    case 'vscode':
      return '.vscode${Platform.pathSeparator}mcp.json';
    default:
      throw ArgumentError('Unknown agent "$agent". '
          'Known agents: ${knownMcpAgents.join(', ')}.');
  }
}

/// Outcome of one [installMcpAgents] run.
final class McpInstallReport {
  const McpInstallReport({
    required this.changed,
    required this.upToDate,
    required this.planLines,
  });

  /// Agents whose config file was written.
  final List<String> changed;

  /// Agents already carrying an identical entry (no write).
  final List<String> upToDate;

  /// Human plan lines (printed before writing).
  final List<String> planLines;
}

/// Desired `perfscope` server entry pointing at the bridge.
Map<String, Object?> bridgeServerEntry({String command = 'perfscope'}) =>
    <String, Object?>{
      'command': command,
      'args': <String>['mcp', 'run'],
    };

bool _entriesEqual(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// Registers the bridge for [agents] under [root].
///
/// Reads each agent config (missing file = empty map; corrupt JSON is left
/// untouched and reported in the plan), merges `mcpServers.perfscope`
/// additively, and writes back only when the entry changed. Every planned
/// action is appended to [planLines] AND written to [out] before any write
/// happens. Never touches anything outside [root] (tests pass fixture dirs).
Future<McpInstallReport> installMcpAgents({
  required Directory root,
  required List<String> agents,
  String command = 'perfscope',
  StringSink? out,
}) async {
  final changed = <String>[];
  final upToDate = <String>[];
  final planLines = <String>[];
  final encoder = const JsonEncoder.withIndent('  ');

  void plan(String line) {
    planLines.add(line);
    out?.writeln(line);
  }

  final pending = <String, String>{};
  for (final agent in agents) {
    final relative = agentConfigRelativePath(agent);
    final file = File('${root.path}${Platform.pathSeparator}$relative');
    Map<String, Object?> document = <String, Object?>{};
    if (await file.exists()) {
      try {
        final parsed = jsonDecode(await file.readAsString());
        if (parsed is Map<String, Object?>) {
          document = Map<String, Object?>.of(parsed);
        } else if (parsed is Map) {
          document = (parsed).cast<String, Object?>();
        } else {
          plan('skip $agent ($relative): not a JSON object, left untouched.');
          continue;
        }
      } catch (_) {
        plan('skip $agent ($relative): unparseable JSON, left untouched.');
        continue;
      }
    }
    final servers = (document['mcpServers'] is Map)
        ? Map<String, Object?>.of(
            (document['mcpServers'] as Map).cast<String, Object?>())
        : <String, Object?>{};
    final desired = bridgeServerEntry(command: command);
    if (_entriesEqual(servers['perfscope'], desired)) {
      upToDate.add(agent);
      plan('up to date: $agent ($relative).');
      continue;
    }
    servers['perfscope'] = desired;
    document['mcpServers'] = servers;
    pending[agent] = encoder.convert(document);
    plan('will register perfscope bridge in $agent ($relative).');
  }

  for (final entry in pending.entries) {
    final file = File('${root.path}${Platform.pathSeparator}'
        '${agentConfigRelativePath(entry.key)}');
    await file.parent.create(recursive: true);
    await file.writeAsString('${entry.value}\n');
    changed.add(entry.key);
  }
  return McpInstallReport(
    changed: changed,
    upToDate: upToDate,
    planLines: planLines,
  );
}
