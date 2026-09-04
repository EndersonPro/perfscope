import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';

/// Import-ban + graph guards (T14): the live bridge stays out of release
/// builds, the CLI bridge stays Flutter-free, and the app never runs a
/// stdio/JSON-RPC loop (stdin/stdout belong to Flutter).
void main() {
  String read(String relative) =>
      File('${Directory.current.path}/$relative').readAsStringSync();

  /// True when [body] has an import/export of a banned target. Doc comments
  /// may NAME these targets (to document the ban); only real directives
  /// count as violations.
  bool hasBannedImport(String body) {
    final directive = RegExp(r'^(import|export)\s', multiLine: true);
    for (final line in body.split('\n')) {
      if (!directive.hasMatch(line)) {
        continue;
      }
      if (line.contains('package:flutter') ||
          line.contains('src/live') ||
          line.contains('perfscope_live')) {
        return true;
      }
    }
    return false;
  }

  List<File> dartFilesUnder(String relative) {
    final root = Directory('${Directory.current.path}/$relative');
    if (!root.existsSync()) {
      return const [];
    }
    return root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  group('import bans (T14 RED)', () {
    test('main barrel exports no live symbols', () {
      final barrel = read('lib/perfscope.dart');
      expect(hasBannedImport(barrel), isFalse);
    });

    test('release entry has no transitive live import', () {
      final main = read('example/lib/main.dart');
      expect(hasBannedImport(main), isFalse);
    });

    test('cli + bin are Flutter-free and live-free', () {
      final files = [
        ...dartFilesUnder('lib/src/cli'),
        ...dartFilesUnder('bin'),
      ];
      expect(files, isNotEmpty);
      for (final file in files) {
        final body = file.readAsStringSync();
        expect(hasBannedImport(body), isFalse,
            reason: '${file.path} imports a banned target');
      }
    });

    test('no stdio loop under lib/src/live', () {
      final files = dartFilesUnder('lib/src/live');
      expect(files, isNotEmpty);
      for (final file in files) {
        final body = file.readAsStringSync();
        expect(body, isNot(contains('stdin')),
            reason: '${file.path} touches stdin');
      }
      expect(
        Directory('${Directory.current.path}/lib/src/live/mcp').existsSync(),
        isFalse,
        reason: 'lib/src/live/mcp must not exist (bridge lives in the CLI)',
      );
    });

    test('no network packages in dependencies', () {
      final pubspec = read('pubspec.yaml');
      final dependencies = pubspec.split('dev_dependencies:').first;
      expect(dependencies, isNot(contains('shelf')));
      expect(dependencies, isNot(contains('mcp_dart')));
    });
  });
}
