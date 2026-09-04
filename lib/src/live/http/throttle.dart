/// Per-route snapshot throttle bookkeeping.
///
/// Slice 1 ships the STRUCTURE only: no route consults the tracker yet
/// (`/v1/status` is exempt by contract; snapshot-route enforcement lands in
/// Slice 2 with its 429 tests). Pure over injected clocks, unit-testable.
library;

/// Tracks last-served timestamps independently per route.
final class ThrottleTracker {
  /// Creates a tracker enforcing at least [window] between full snapshots.
  ThrottleTracker(this.window);

  /// Minimum interval between two full-snapshot responses on one route.
  final Duration window;

  final Map<String, DateTime> _lastServed = <String, DateTime>{};

  /// Returns the remaining wait when [route] was served inside [window],
  /// or null when a fresh snapshot may be served.
  Duration? shouldReject(String route, DateTime now) {
    final last = _lastServed[route];
    if (last == null) {
      return null;
    }
    final elapsed = now.difference(last);
    if (elapsed >= window) {
      return null;
    }
    return window - elapsed;
  }

  /// Records a served full snapshot for [route] at [now].
  void markServed(String route, DateTime now) {
    _lastServed[route] = now;
  }

  /// Whole seconds (rounded up) for the `Retry-After` header.
  static int retryAfterSeconds(Duration remaining) =>
      (remaining.inMilliseconds / 1000).ceil().clamp(1, 1 << 31);
}
