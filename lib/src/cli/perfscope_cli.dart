/// PerfScope offline command-line interface.
///
/// Pure orchestration: parses arguments with `package:args`, loads
/// session files through an injectable loader, and writes every byte of
/// output through injected [StringSink]s so tests never touch the real
/// filesystem or console. `dart:io` lives exclusively behind the
/// conditional-import shim (`cli_platform.dart`) and the thin `bin/`
/// wrapper.
///
/// Exit codes:
/// * 0 — success (including help).
/// * 1 — unknown command or malformed arguments.
/// * 2 — session file could not be read.
/// * 3 — session file parsed as invalid ([FormatException] message
///   passthrough).
/// * 4 — doctor reported at least one failing environment check.
library;

import 'package:args/args.dart';

import '../ai/ai_context_builder.dart';
import '../exporters/text_report_formatter.dart';
import '../logging/format_session_duration.dart' show formatSessionDuration;
import '../reporting/comparison_formatter.dart';
import '../reporting/performance_report.dart';
import '../reporting/session_comparison.dart';
import '../serialization/session_parser.dart';
import 'cli_platform.dart';
import 'system_probe.dart';

const String _usageHint =
    "Run 'dart run perfscope:perfscope --help' for usage.";

final ArgParser _topLevelParser = ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help');

ArgParser _commandParser() =>
    ArgParser()..addFlag('help', abbr: 'h', negatable: false);

/// Injectable process dependencies for [runPerfScopeCli].
///
/// Defaults resolve through the conditional-import shim; tests override
/// [loadFile] (map-based fixtures) and [probe] (fake versions).
final class CommandRunnerDependencies {
  /// Creates dependencies. Omitted members fall back to the platform
  /// implementations.
  factory CommandRunnerDependencies({
    String Function(String path)? loadFile,
    SystemProbe? probe,
  }) =>
      CommandRunnerDependencies._(
        loadFile: loadFile ?? loadCliFile,
        probe: probe ?? createDefaultProbe(),
      );

  CommandRunnerDependencies._({
    required this.loadFile,
    required this.probe,
  });

  /// Reads a session file's text; any throw maps to exit code 2.
  final String Function(String path) loadFile;

  /// Environment probe used by the `doctor` command.
  final SystemProbe probe;
}

/// Runs the PerfScope CLI against [args], writing normal output to [out]
/// and diagnostics to [err] (defaults come from the platform shim).
///
/// Resolves with the process exit code once all work completes; the
/// `bin/perfscope.dart` wrapper awaits it before exiting.
Future<int> runPerfScopeCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  CommandRunnerDependencies? deps,
}) async {
  final effectiveOut = out ?? cliStdout();
  final effectiveErr = err ?? cliStderr();
  final effectiveDeps =
      deps ?? CommandRunnerDependencies(loadFile: loadCliFile);

  final ArgResults parsedArgs;
  try {
    parsedArgs = _topLevelParser.parse(args);
  } on ArgParserException catch (error) {
    effectiveErr
      ..writeln(error.message)
      ..writeln(_usageHint);
    return 1;
  }
  if (parsedArgs.flag('help')) {
    effectiveOut.write(_usageText());
    return 0;
  }
  final rest = parsedArgs.rest;

  if (rest.isEmpty) {
    effectiveErr
      ..writeln('No command given.')
      ..writeln(_usageHint);
    return 1;
  }

  switch (rest.first) {
    case 'analyze':
      return _runAnalyze(
        rest.sublist(1),
        effectiveOut,
        effectiveErr,
        effectiveDeps.loadFile,
      );
    case 'report':
      return _runReport(
        rest.sublist(1),
        effectiveOut,
        effectiveErr,
        effectiveDeps.loadFile,
      );
    case 'compare':
      return _runCompare(
        rest.sublist(1),
        effectiveOut,
        effectiveErr,
        effectiveDeps.loadFile,
      );
    case 'ai-context':
      return _runAiContext(
        rest.sublist(1),
        effectiveOut,
        effectiveErr,
        effectiveDeps.loadFile,
      );
    case 'doctor':
      return _runDoctor(effectiveOut, effectiveDeps);
    default:
      effectiveErr
        ..writeln("Unknown command: '${rest.first}'.")
        ..writeln(_usageHint);
      return 1;
  }
}

// ---------------------------------------------------------------------------
// Shared loading helpers
// ---------------------------------------------------------------------------

/// Either a parsed report or the exit code to return (message already on
/// stderr). A null report always means "return exitCode".
typedef _LoadOutcome = (PerformanceReport? report, int exitCode);

Future<_LoadOutcome> _loadReportAtPath(
  String path,
  StringSink err,
  String Function(String path) loadFile,
) async {
  final String raw;
  try {
    raw = loadFile(path);
  } on Object {
    err.writeln('Cannot read file: $path');
    return (null, 2);
  }
  try {
    return (const SessionParser().parseString(raw), 0);
  } on FormatException catch (error) {
    err.writeln(error.message);
    return (null, 3);
  }
}

/// Positional arguments after `package:args` validation. Unknown flags
/// throw inside ArgParser, so typos like `analyze --junk x` fail loudly;
/// `-h` inside a command prints the full usage to [out].
///
/// Returns `(paths, 0)` on success or `(null, exitCode)` with the error
/// already written.
(List<String>?, int) _commandPositionals({
  required List<String> rest,
  required StringSink out,
  required StringSink err,
  required int expectedCount,
  required String usageLine,
}) {
  final ArgResults parsed;
  try {
    parsed = _commandParser().parse(rest);
  } on ArgParserException catch (error) {
    err
      ..writeln(error.message)
      ..writeln(_usageHint);
    return (null, 1);
  }
  if (parsed.flag('help')) {
    out.write(_usageText());
    return (null, 0);
  }
  if (parsed.rest.length != expectedCount) {
    _usageError(err, usageLine);
    return (null, 1);
  }
  return (parsed.rest, 0);
}

int _usageError(StringSink err, String usageLine) {
  err
    ..writeln('Usage: dart run perfscope:perfscope $usageLine')
    ..writeln(_usageHint);
  return 1;
}

// ---------------------------------------------------------------------------
// analyze / report / compare / ai-context
// ---------------------------------------------------------------------------

Future<int> _runAnalyze(
  List<String> rest,
  StringSink out,
  StringSink err,
  String Function(String path) loadFile,
) async {
  final (paths, argCode) = _commandPositionals(
    rest: rest,
    out: out,
    err: err,
    expectedCount: 1,
    usageLine: 'analyze <session.json>',
  );
  if (paths == null) {
    return argCode;
  }
  final (report, code) = await _loadReportAtPath(paths.single, err, loadFile);
  if (report == null) {
    return code;
  }
  final stats = report.statistics;
  final duration = (report.session.endedAt ?? report.session.startedAt)
      .difference(report.session.startedAt);

  out.writeln('Session: ${report.session.id}');
  final name = report.session.name;
  if (name != null) {
    out.writeln('Name: $name');
  }
  out.writeln(
    'Duration: ${formatSessionDuration(duration)}',
  );
  out.writeln('Frames: ${stats.totalFrames}');
  out.writeln(
    'Slow-frame rate: ${(stats.slowFrameRate * 100).toStringAsFixed(1)}%',
  );
  out
    ..write('p50: ${stats.p50Ms.round()}ms | ')
    ..write('p95: ${stats.p95Ms.round()}ms | ')
    ..writeln('p99: ${stats.p99Ms.round()}ms');
  out.writeln('Worst frame: ${stats.worstFrameMs.round()}ms');
  out.writeln('Anomalies: ${report.anomalies.length}');

  final topScreens = report.screens.take(3).toList();
  if (topScreens.isNotEmpty) {
    out.writeln('Top screens by anomalies:');
    for (var i = 0; i < topScreens.length; i++) {
      out.writeln('  ${i + 1}. ${topScreens[i].name}'
          ' - ${topScreens[i].anomalyCount}');
    }
  }
  return 0;
}

Future<int> _runReport(
  List<String> rest,
  StringSink out,
  StringSink err,
  String Function(String path) loadFile,
) async {
  final (paths, argCode) = _commandPositionals(
    rest: rest,
    out: out,
    err: err,
    expectedCount: 1,
    usageLine: 'report <session.json>',
  );
  if (paths == null) {
    return argCode;
  }
  final (report, code) = await _loadReportAtPath(paths.single, err, loadFile);
  if (report == null) {
    return code;
  }
  // formatReportText omits the trailing newline; add it here.
  out.writeln(formatReportText(report));
  return 0;
}

Future<int> _runCompare(
  List<String> rest,
  StringSink out,
  StringSink err,
  String Function(String path) loadFile,
) async {
  final (paths, argCode) = _commandPositionals(
    rest: rest,
    out: out,
    err: err,
    expectedCount: 2,
    usageLine: 'compare <before.json> <after.json>',
  );
  if (paths == null) {
    return argCode;
  }
  final (before, beforeCode) = await _loadReportAtPath(paths[0], err, loadFile);
  if (before == null) {
    return beforeCode;
  }
  final (after, afterCode) = await _loadReportAtPath(paths[1], err, loadFile);
  if (after == null) {
    return afterCode;
  }

  out.write(formatSessionComparison(SessionComparator.compare(before, after)));
  return 0;
}

Future<int> _runAiContext(
  List<String> rest,
  StringSink out,
  StringSink err,
  String Function(String path) loadFile,
) async {
  final (paths, argCode) = _commandPositionals(
    rest: rest,
    out: out,
    err: err,
    expectedCount: 1,
    usageLine: 'ai-context <session.json>',
  );
  if (paths == null) {
    return argCode;
  }
  final (report, code) = await _loadReportAtPath(paths.single, err, loadFile);
  if (report == null) {
    return code;
  }
  // Single trailing newline keeps shell redirection clean.
  out.writeln(buildAiContextText(report));
  return 0;
}

// ---------------------------------------------------------------------------
// doctor
// ---------------------------------------------------------------------------

/// One semantic version triple with lexicographic ordering.
final class Version {
  /// Creates an immutable version triple.
  const Version(this.major, this.minor, this.patch);

  /// Major component.
  final int major;

  /// Minor component.
  final int minor;

  /// Patch component (0 when absent).
  final int patch;

  /// Extracts the first `major.minor[.patch]` triple found anywhere in
  /// [text]; null when none matches. Banner lines ("Flutter 3.44.1 -",
  /// "Dart SDK version: 3.9.4 ...") carry prefixes before the number,
  /// so the search is unanchored.
  static Version? tryExtract(String text) {
    final match = RegExp(r'\d+\.\d+(?:\.\d+)?').firstMatch(text);
    if (match == null) return null;
    final parts = match.group(0)!.split('.');
    return Version(
      int.parse(parts[0]),
      int.parse(parts[1]),
      parts.length > 2 ? int.parse(parts[2]) : 0,
    );
  }

  bool operator <(Version other) => _compare(other) < 0;

  int _compare(Version other) {
    final byMajor = major.compareTo(other.major);
    if (byMajor != 0) return byMajor;
    final byMinor = minor.compareTo(other.minor);
    if (byMinor != 0) return byMinor;
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

Future<int> _runDoctor(StringSink out, CommandRunnerDependencies deps) async {
  var anyFailure = false;

  void check(String line, {required bool ok}) {
    if (!ok) anyFailure = true;
    out.writeln(line);
  }

  _emitToolCheck(
    check,
    toolLabel: 'Flutter',
    result: await deps.probe.runVersion('flutter'),
    minimum: const Version(3, 24, 0),
    notFoundMessage: 'not found on PATH',
  );
  _emitToolCheck(
    check,
    toolLabel: 'Dart',
    result: await deps.probe.runVersion('dart'),
    minimum: const Version(3, 5, 0),
    notFoundMessage: 'not found on PATH',
  );

  _emitProjectCheck(check, deps);

  out
    ..writeln()
    ..writeln('Recommended performance mode:')
    ..writeln('  flutter run --profile');

  return anyFailure ? 4 : 0;
}

void _emitToolCheck(
  void Function(String line, {required bool ok}) check, {
  required String toolLabel,
  required ProbeResult? result,
  required Version minimum,
  required String notFoundMessage,
}) {
  if (result == null) {
    check('MISSING $toolLabel $notFoundMessage', ok: false);
    return;
  }
  final version = _extractVersion(result);
  if (version == null) {
    check("[warn] $toolLabel found but its version could not be read",
        ok: false);
    return;
  }
  if (version < minimum) {
    check(
        '[warn] $toolLabel $version found;'
        ' version >= $minimum required',
        ok: false);
    return;
  }
  check('ok   $toolLabel detected ($version)', ok: true);
}

/// Version probes print banner lines ("Flutter 3.44.1 - channel...",
/// "Dart SDK version: 3.9.4 ..."); search both streams for the first
/// recognizable triple.
Version? _extractVersion(ProbeResult result) {
  for (final text in [result.stdout, result.stderr]) {
    final version = Version.tryExtract(text);
    if (version != null) {
      return version;
    }
  }
  return null;
}

void _emitProjectCheck(
  void Function(String line, {required bool ok}) check,
  CommandRunnerDependencies deps,
) {
  final String content;
  try {
    content = deps.loadFile('pubspec.yaml');
  } on Object {
    check('MISSING pubspec.yaml not found in current directory', ok: false);
    check('MISSING Project not detected (no readable pubspec.yaml)', ok: false);
    return;
  }
  check('ok   pubspec.yaml found', ok: true);
  final match = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(content);
  if (match == null) {
    check("MISSING pubspec.yaml has no 'name:' key", ok: false);
    return;
  }
  check('ok   Project detected (${match.group(1)})', ok: true);
}

// ---------------------------------------------------------------------------
// Usage
// ---------------------------------------------------------------------------

String _usageText() => '''
PerfScope CLI - local performance observability tooling.

Usage: dart run perfscope:perfscope <command> [arguments]

Commands:
  analyze <session.json>       Compact session summary
  report <session.json>        Full formatted session report
  compare <before> <after>     Before/after comparison table
  ai-context <session.json>    AI-ready context (for shell redirection)
  doctor                       Environment checks

Options:
  -h, --help                   Show this help and exit

Exit codes:
  0 success   1 usage error   2 unreadable file
  3 invalid session file   4 doctor found missing requirements
''';
