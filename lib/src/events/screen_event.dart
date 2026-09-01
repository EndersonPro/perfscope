part of 'performance_event.dart';

/// Why a [ScreenEvent] was produced.
enum ScreenChangeReason {
  /// A new route was pushed on top of the stack.
  push,

  /// The top route was popped.
  pop,

  /// The top route was replaced by another one.
  replace,

  /// A route was removed from an arbitrary stack position by the framework.
  remove,

  /// The application manually overrode the current screen.
  manual,
}

/// Emitted whenever PerfScope observes a change of the current screen.
///
/// Unnamed routes never appear here as null: they are normalized to the
/// literal `'unknown'` before emission.
final class ScreenEvent extends PerformanceEvent {
  /// Creates a screen event.
  const ScreenEvent({
    required super.id,
    required super.timestamp,
    required this.name,
    required this.previousName,
    required this.reason,
  });

  /// Screen name after the change (never null).
  final String name;

  /// Screen name before the change, or null when there was no previous
  /// screen worth reporting (e.g. first navigation).
  final String? previousName;

  /// Navigation operation that caused the change.
  final ScreenChangeReason reason;
}
