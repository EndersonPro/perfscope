/// Resolves the host platform name for [PerformanceEnvironment].
///
/// Split via conditional imports so web builds never link `dart:io`:
/// VM/AOT builds use the io-backed implementation, every other target
/// (web) falls back to the stub. The `kIsWeb` gate lives with the caller.
library;

export 'platform_name_default.dart'
    if (dart.library.io) 'platform_name_io.dart';
