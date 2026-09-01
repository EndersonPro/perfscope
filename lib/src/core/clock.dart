/// Abstract source of wall-clock time.
///
/// Abstracting time keeps domain logic testable: tests can inject a fixed
/// or fake clock instead of depending on the real system clock.
abstract interface class Clock {
  /// Returns the current point in time.
  DateTime now();
}

/// Default [Clock] backed by [DateTime.now].
class SystemClock implements Clock {
  /// Creates a constant system clock instance.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
