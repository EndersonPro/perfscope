/// Fallback platform resolution for targets without `dart:io` (web).
library;

/// Callers gate on `kIsWeb` first and report `'web'`; this stub only
/// covers unreachable-in-practice non-io, non-web edge cases.
String resolvePlatformName() => 'unknown';
