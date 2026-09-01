/// Name reported when no route name is available anywhere on the stack.
///
/// Unnamed routes are normalized to this literal so consumers always deal
/// with a concrete, comparable screen name instead of null handling.
const String unknownScreenName = 'unknown';

/// Result of a single mutating operation on [ScreenTracker].
///
/// The tracker deliberately emits nothing itself: it reports what changed
/// and lets the caller decide whether an event is worth emitting.
typedef ScreenStackChange = ({
  /// Screen name observed *before* the mutation (already normalized), or
  /// null when the mutation was a no-op and nothing was displaced.
  String? previous,

  /// Screen name observed *after* the mutation (never null).
  String current,

  /// Whether [current] differs from [previous] — i.e. whether the caller
  /// should consider emitting a screen-change event.
  bool changed,
});

/// Tracks the current application screen as a navigation name stack.
///
/// Pure state holder: no timers, no events, no framework dependencies, so
/// it is trivially unit-testable. Null route names are normalized to
/// [unknownScreenName] the moment they enter the stack.
///
/// Manual overrides: [override] replaces the whole notion of the current
/// screen for apps without a Navigator (custom routing). It stays in effect
/// until the next *effective* navigation mutation ([push], [pop],
/// [replace], [remove]) arrives, which discards the override and resumes
/// normal stack tracking. No-op mutations (e.g. popping an empty stack)
/// do not discard an override.
final class ScreenTracker {
  final List<String> _stack = <String>[];
  String? _override;

  /// Top-of-stack screen name, or [unknownScreenName] when nothing is on
  /// the stack. A manual [override] wins over the stack until discarded.
  String get current =>
      _override ?? (_stack.isEmpty ? unknownScreenName : _stack.last);

  /// Pushes [name] onto the stack (null normalizes to [unknownScreenName]).
  ScreenStackChange push(String? name) {
    final previous = current;
    _override = null;
    _stack.add(_normalize(name));
    return _changeFrom(previous);
  }

  /// Removes the top-of-stack entry. Safe no-op on an empty stack.
  ScreenStackChange pop() {
    if (_stack.isEmpty) {
      return _noOpChange();
    }
    final previous = current;
    _override = null;
    _stack.removeLast();
    return _changeFrom(previous);
  }

  /// Renames the top-of-stack entry. Safe no-op on an empty stack.
  ScreenStackChange replace(String? newName) {
    if (_stack.isEmpty) {
      return _noOpChange();
    }
    final previous = current;
    _override = null;
    _stack[_stack.length - 1] = _normalize(newName);
    return _changeFrom(previous);
  }

  /// Removes the top-of-stack entry without producing a return value.
  ///
  /// Semantically identical to [pop]; kept separate so callers can emit a
  /// distinct `remove` reason for framework `didRemove` notifications.
  ScreenStackChange remove() => pop();

  /// Manually pins [name] as the current screen, replacing any stack-based
  /// value, until the next effective navigation mutation arrives.
  ScreenStackChange override(String name) {
    final previous = current;
    _override = _normalize(name);
    return _changeFrom(previous);
  }

  String _normalize(String? name) => name ?? unknownScreenName;

  ScreenStackChange _changeFrom(String previous) {
    final now = current;
    return (previous: previous, current: now, changed: previous != now);
  }

  ScreenStackChange _noOpChange() =>
      (previous: null, current: current, changed: false);
}
