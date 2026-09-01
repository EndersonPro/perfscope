/// Web target: any toolchain providing `dart:js_interop` is a web build.
library;

/// `true` when compiled for the web (dart2js or dart2wasm).
const bool kRunsOnWeb = true;
