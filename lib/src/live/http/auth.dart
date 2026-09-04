/// Token helpers for the live bridge: generation, comparison, extraction.
///
/// Pure functions (no IO) so the gate is unit-testable in isolation.
library;

import 'dart:convert' show base64UrlEncode;
import 'dart:math' show Random;

/// Entropy bytes per generated token (16 B = 128 bits).
const int tokenEntropyBytes = 16;

/// Generates a fresh per-process Bearer token: 16 cryptographically secure
/// random bytes, base64Url-encoded (URL-safe alphabet).
String generateToken() {
  final bytes = List<int>.generate(
    tokenEntropyBytes,
    (_) => Random.secure().nextInt(256),
  );
  return base64UrlEncode(bytes);
}

/// Compares two tokens in constant time over the longer length.
///
/// Lengths are folded into the accumulator first so unequal lengths cannot
/// early-exit; every code unit is always visited.
bool constantTimeEquals(String a, String b) {
  final aUnits = a.codeUnits;
  final bUnits = b.codeUnits;
  var diff = aUnits.length ^ bUnits.length;
  final longest = aUnits.length > bUnits.length ? aUnits.length : bUnits.length;
  for (var i = 0; i < longest; i++) {
    final x = i < aUnits.length ? aUnits[i] : 0;
    final y = i < bUnits.length ? bUnits[i] : 0;
    diff |= x ^ y;
  }
  return diff == 0;
}

/// Extracts the Bearer token from a raw `Authorization` header value.
///
/// Returns null for a missing header, a bare scheme, or any foreign scheme.
/// Token-via-query is never read here (callers must not pass query values).
String? extractBearer(String? headerValue) {
  if (headerValue == null) {
    return null;
  }
  const scheme = 'Bearer ';
  if (!headerValue.startsWith(scheme)) {
    return null;
  }
  final token = headerValue.substring(scheme.length);
  if (token.isEmpty || token.contains(' ')) {
    return null;
  }
  return token;
}
