part of 'performance_event.dart';

/// Emitted whenever the host application reports an app lifecycle change.
final class LifecycleEvent extends PerformanceEvent {
  /// Creates a lifecycle event.
  const LifecycleEvent({
    required super.id,
    required super.timestamp,
    required this.state,
  });

  /// The lifecycle state the application transitioned to.
  final AppLifecycleState state;
}
