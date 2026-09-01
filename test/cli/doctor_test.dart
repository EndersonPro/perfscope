import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

// -----------------------------------------------------------------------------
// Doctor checks driven by a fake SystemProbe: fully deterministic, no
// process spawning, no filesystem access (pubspec served by a map loader).
// -----------------------------------------------------------------------------

final class _FakeProbe implements SystemProbe {
  _FakeProbe(this.results);

  final Map<String, ProbeResult?> results;

  @override
  Future<ProbeResult?> runVersion(String executable) async =>
      results[executable];
}

const String _flutterOk =
    'Flutter 3.44.1 • channel stable • https://github.com/flutter/flutter\n';
const String _dartOk = 'Dart SDK version: 3.9.4 (stable) ...\n';

Map<String, ProbeResult?> _allFound({
  String flutterBanner = _flutterOk,
  String dartBanner = _dartOk,
}) =>
    {
      'flutter': ProbeResult(exitCode: 0, stdout: flutterBanner, stderr: ''),
      'dart': ProbeResult(exitCode: 0, stdout: '', stderr: dartBanner),
    };

CommandRunnerDependencies _deps({
  required Map<String, ProbeResult?> probeResults,
  Map<String, String> files = const {'pubspec.yaml': 'name: perfscope\n'},
}) {
  return CommandRunnerDependencies(
    loadFile: (path) {
      final content = files[path];
      if (content == null) throw StateError('No such file: $path');
      return content;
    },
    probe: _FakeProbe(probeResults),
  );
}

void main() {
  group('doctor', () {
    test('all checks pass: four ok lines, recommendation, exit 0', () async {
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runPerfScopeCli(
        ['doctor'],
        out: out,
        err: err,
        deps: _deps(probeResults: _allFound()),
      );

      expect(code, 0);
      expect(err.toString(), isEmpty);
      final lines = out.toString().split('\n');
      expect(
        lines.take(4),
        everyElement(startsWith('ok')),
      );
      expect(lines[0], 'ok   Flutter detected (3.44.1)');
      expect(lines[1], 'ok   Dart detected (3.9.4)');
      expect(lines[2], 'ok   pubspec.yaml found');
      expect(lines[3], 'ok   Project detected (perfscope)');
      expect(out.toString(), contains('Recommended performance mode:'));
      expect(out.toString(), contains('  flutter run --profile'));
    });

    test('flutter missing on PATH: MISSING line, exit 4', () async {
      final out = StringBuffer();
      final code = await runPerfScopeCli(
        ['doctor'],
        out: out,
        err: StringBuffer(),
        deps: _deps(
          probeResults: _allFound()..['flutter'] = null,
        ),
      );

      expect(code, 4);
      expect(out.toString(), contains('MISSING Flutter not found on PATH'));
      // The remaining checks still run.
      expect(out.toString(), contains('ok   Dart detected'));
      expect(out.toString(), contains('ok   pubspec.yaml found'));
    });

    test('old Flutter version flagged as below minimum, exit 4', () async {
      final out = StringBuffer();
      final code = await runPerfScopeCli(
        ['doctor'],
        out: out,
        err: StringBuffer(),
        deps: _deps(
          probeResults: _allFound(
            flutterBanner: 'Flutter 3.16.0 • channel stable\n',
          ),
        ),
      );

      expect(code, 4);
      expect(
        out.toString(),
        contains('[warn] Flutter 3.16.0 found; version >= 3.24.0 required'),
      );
    });

    test('old Dart SDK flagged as below minimum, exit 4', () async {
      final out = StringBuffer();
      final code = await runPerfScopeCli(
        ['doctor'],
        out: out,
        err: StringBuffer(),
        deps: _deps(
          probeResults: _allFound(dartBanner: 'Dart SDK version: 3.4.0\n'),
        ),
      );

      expect(code, 4);
      expect(
        out.toString(),
        contains('[warn] Dart 3.4.0 found; version >= 3.5.0 required'),
      );
    });

    test('probe returning garbage output counts as unreadable, exit 4',
        () async {
      final out = StringBuffer();
      final code = await runPerfScopeCli(
        ['doctor'],
        out: out,
        err: StringBuffer(),
        deps: _deps(
          probeResults: _allFound(flutterBanner: '??? mysterious ???'),
        ),
      );

      expect(code, 4);
      expect(
        out.toString(),
        contains('[warn] Flutter found but its version could not be read'),
      );
    });

    test('no pubspec.yaml: project checks fail, exit 4', () async {
      final out = StringBuffer();
      final code = await runPerfScopeCli(
        ['doctor'],
        out: out,
        err: StringBuffer(),
        deps: _deps(
          probeResults: _allFound(),
          files: const {},
        ),
      );

      expect(code, 4);
      expect(
        out.toString(),
        contains('MISSING pubspec.yaml not found in current directory'),
      );
      expect(
        out.toString(),
        contains('MISSING Project not detected (no readable pubspec.yaml)'),
      );
    });

    test('pubspec without name key fails the project check', () async {
      final out = StringBuffer();
      final code = await runPerfScopeCli(
        ['doctor'],
        out: out,
        err: StringBuffer(),
        deps: _deps(
          probeResults: _allFound(),
          files: const {'pubspec.yaml': 'description: no name here\n'},
        ),
      );

      expect(code, 4);
      expect(out.toString(), contains('ok   pubspec.yaml found'));
      expect(
        out.toString(),
        contains("MISSING pubspec.yaml has no 'name:' key"),
      );
    });
  });
}
