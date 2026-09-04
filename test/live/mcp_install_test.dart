import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/src/cli/mcp/mcp_install.dart' as install;

void main() {
  group('mcp install matrix (T14 RED)', () {
    test('known agents resolve to distinct config paths', () {
      final paths =
          install.knownMcpAgents.map(install.agentConfigRelativePath).toSet();
      expect(install.knownMcpAgents,
          containsAll(['claude', 'codex', 'pi', 'cursor', 'vscode']));
      expect(paths, hasLength(install.knownMcpAgents.length));
    });

    test('install is additive: unrelated entries survive', () async {
      final root = await Directory.systemTemp.createTemp('perfscope-install-');
      try {
        final cursorFile =
            File('${root.path}/${install.agentConfigRelativePath('cursor')}');
        await cursorFile.parent.create(recursive: true);
        await cursorFile.writeAsString(jsonEncode(<String, Object?>{
          'mcpServers': <String, Object?>{
            'other': <String, Object?>{'command': 'other-server'},
          },
        }));

        final report = await install.installMcpAgents(
          root: root,
          agents: const ['cursor'],
        );

        expect(report.changed, contains('cursor'));
        final body =
            jsonDecode(await cursorFile.readAsString()) as Map<String, Object?>;
        final servers = body['mcpServers'] as Map<String, Object?>;
        expect(servers['other'], isNotNull);
        expect(servers['perfscope'], isNotNull);
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('second run is a no-op (idempotent)', () async {
      final root = await Directory.systemTemp.createTemp('perfscope-install-');
      try {
        await install.installMcpAgents(
          root: root,
          agents: const ['pi'],
        );
        final second = await install.installMcpAgents(
          root: root,
          agents: const ['pi'],
        );
        expect(second.changed, isEmpty);
        expect(second.upToDate, contains('pi'));
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('--all covers every known agent', () async {
      final root = await Directory.systemTemp.createTemp('perfscope-install-');
      try {
        final report = await install.installMcpAgents(
          root: root,
          agents: install.knownMcpAgents,
        );
        expect(report.changed.toSet(), install.knownMcpAgents.toSet());
        for (final agent in install.knownMcpAgents) {
          final file =
              File('${root.path}/${install.agentConfigRelativePath(agent)}');
          expect(await file.exists(), isTrue, reason: agent);
        }
      } finally {
        await root.delete(recursive: true);
      }
    });
  });
}
