/// Whether the compiled target is a web build.
///
/// Split via conditional imports so callers never need Flutter's
/// foundation library just for its web flag: VM/AOT builds use
/// the constant-false implementation, web targets (which provide
/// `dart:js_interop`) use the constant-true one. Keeping both sides as
/// consts lets the compiler tree-shake the dead branch.
library;

export 'is_web_default.dart' if (dart.library.js_interop) 'is_web_web.dart';

// Alternative condition kept documented: older toolchains can swap the
// guard to `dart.library.html`; `dart:js_interop` is the modern marker.
