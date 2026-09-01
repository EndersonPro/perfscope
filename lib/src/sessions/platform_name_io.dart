/// VM/AOT platform resolution backed by `dart:io`.
///
/// The try/catch guard covers exotic embedders where `Platform` throws
/// instead of answering; PerfScope degrades to `'unknown'` rather than
/// ever breaking the host app.
library;

import 'dart:io' show Platform;

/// Returns the operating system name, or `'unknown'` when unavailable.
String resolvePlatformName() {
  try {
    return Platform.operatingSystem;
  } catch (_) {
    return 'unknown';
  }
}
