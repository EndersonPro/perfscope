/// Non-web fallback (VM, AOT, tests): constant `false`.
library;

/// `false` on every target without `dart:js_interop`.
const bool kRunsOnWeb = false;
