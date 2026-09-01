import 'package:perfscope/perfscope.dart';

/// Deterministic, manually advanced [Clock] for tests.
///
/// Starts at a fixed epoch-like timestamp and only moves when [advance]
/// is called, so durations derived from it are fully deterministic.
final class FakeClock implements Clock {
  /// Creates a clock pinned at [initial] (or a fixed default instant).
  FakeClock([DateTime? initial])
      : _now = initial ?? DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

  DateTime _now;

  /// Moves the clock forward by [delta]. Never moves backwards.
  void advance(Duration delta) => _now = _now.add(delta);

  @override
  DateTime now() => _now;
}
