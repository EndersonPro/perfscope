/// Discovery file for the live bridge (Slice 4, app side).
///
/// On every successful bind, `serve()` writes
/// `<project-root>/.dart_tool/perfscope-live.json` with connection info ONLY
/// (`port`, full local-only `token`, `pid`, `projectRoot`, `startedAt`).
/// The file is overwritten on re-bind and deleted on `close()` (every path:
/// explicit close, dispose/detach, auto-close). Disabled handles write nothing
/// (the facade returns before the io backend runs, so this file is never
/// touched for disabled handles).
///
/// Connection info only — never session payload (spec non-goal intact).
/// The token is written to this same-user file only; it is never logged
/// anywhere except the single console line owned by `live_server_io.dart`.
library;

import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show Directory, File, Platform, pid;

/// File name of the discovery document inside `.dart_tool/`.
const String discoveryFileName = 'perfscope-live.json';

/// Test-only override for the project root.
///
/// When set (via [setDiscoveryRootOverrideForTest]), [writeDiscovery],
/// [readDiscovery], and [deleteDiscovery] resolve against it instead of the
/// real [resolveProjectRoot]. Always null in production. The override is a
/// process-local static, so parallel test files (separate isolates) never
/// share it: each file points its servers at a fixture dir and the real
/// `.dart_tool/` stays untouched while tests run.
Directory? _debugRootOverride;

/// Points discovery file I/O at [root] (or clears it with null).
/// Test-only: production code never calls this.
void setDiscoveryRootOverrideForTest(Directory? root) {
  _debugRootOverride = root;
}

/// Relative path of the discovery document from the project root.
const String discoveryRelativePath = '.dart_tool/$discoveryFileName';

/// Resolves the project root by walking up from [start] (or the process
/// working directory) looking for a `pubspec.yaml`. Falls back to the
/// starting directory when none is found (never throws).
Directory resolveProjectRoot([Directory? start]) {
  var dir = start ?? Directory.current;
  while (true) {
    final marker = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
    if (marker.existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      return start ?? Directory.current;
    }
    dir = parent;
  }
}

/// Returns the discovery [File] for a project [root] (does not create it).
File discoveryFileFor(Directory root) =>
    File('${root.path}${Platform.pathSeparator}.dart_tool'
        '${Platform.pathSeparator}$discoveryFileName');

/// Writes (overwriting) the discovery file for [port]/[token].
///
/// [rootOverride] exists for tests (fixture dirs); production call sites omit
/// it so the real project root is resolved. Best-effort: filesystem failures
/// propagate to the caller, which decides whether to fail closed (tests) or
/// log-and-continue (server bind — currently fails closed too, since a bridge
/// without discovery is undebuggable; see `live_server_io.dart`).
Future<void> writeDiscovery({
  required int port,
  required String token,
  Directory? rootOverride,
  DateTime? startedAt,
}) async {
  final root = rootOverride ?? _debugRootOverride ?? resolveProjectRoot();
  final file = discoveryFileFor(root);
  await file.parent.create(recursive: true);
  final document = <String, Object?>{
    'port': port,
    'token': token,
    'pid': pid,
    'projectRoot': root.path,
    'startedAt': (startedAt ?? DateTime.now().toUtc()).toIso8601String(),
  };
  await file.writeAsString(jsonEncode(document));
}

/// Reads and parses the discovery file, or null when missing/unparseable.
///
/// Never throws: a corrupt file is treated like a missing one (the bridge
/// reports it as stale on stderr).
Future<Map<String, Object?>?> readDiscovery({
  Directory? rootOverride,
  File? fileOverride,
}) async {
  final file = fileOverride ??
      discoveryFileFor(
          rootOverride ?? _debugRootOverride ?? resolveProjectRoot());
  try {
    if (!await file.exists()) {
      return null;
    }
    final parsed = jsonDecode(await file.readAsString());
    if (parsed is! Map<String, Object?>) {
      if (parsed is! Map) {
        return null;
      }
      return (parsed).cast<String, Object?>();
    }
    return parsed;
  } catch (_) {
    return null;
  }
}

/// Deletes the discovery file if present. Never throws (missing file is a
/// no-op; races with concurrent deletes end here).
Future<void> deleteDiscovery({
  Directory? rootOverride,
  File? fileOverride,
}) async {
  final file = fileOverride ??
      discoveryFileFor(
          rootOverride ?? _debugRootOverride ?? resolveProjectRoot());
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Best effort only: close() must stay idempotent even when the
    // filesystem is racing us.
  }
}
