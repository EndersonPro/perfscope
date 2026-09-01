import 'dart:developer';

/// Seam between manual tracing and `dart:developer` Timeline events.
///
/// The engine calls [start] immediately before the traced body and
/// [finish] immediately after it (success or failure), so implementations
/// must tolerate unpaired calls gracefully — PerfScope guarantees the
/// pairing order, never that no exception interrupts a span.
abstract interface class TraceTimelineAdapter {
  /// Opens a timeline span labeled [name].
  void start(String name, Map<String, Object?>? arguments);

  /// Closes the most recently opened timeline span.
  void finish();
}

/// Real adapter used by [PerfScopeEngine.trace]: emits synchronous
/// Timeline spans (`Timeline.startSync` / `Timeline.finishSync`).
///
/// Every call is guarded: a failing Timeline integration must never break
/// host application flow, so errors are swallowed silently here.
final class RealSyncTimelineAdapter implements TraceTimelineAdapter {
  /// Creates a sync Timeline adapter.
  const RealSyncTimelineAdapter();

  @override
  void start(String name, Map<String, Object?>? arguments) {
    try {
      Timeline.startSync(name, arguments: arguments);
    } catch (_) {
      // Timeline failures must never break app flow.
    }
  }

  @override
  void finish() {
    try {
      Timeline.finishSync();
    } catch (_) {
      // Timeline failures must never break app flow.
    }
  }
}

/// Real adapter used by [PerfScopeEngine.traceAsync]: emits asynchronous
/// Timeline spans through [TimelineTask] (`start` / `finish`), the
/// dart:developer API for async spans.
///
/// Note: the SDK has no `Timeline.startAsync`/`finishAsync`; [TimelineTask]
/// is the supported async counterpart. Opened tasks are stacked so nested
/// async traces close in reverse order. Every call is guarded for the same
/// reason as [RealSyncTimelineAdapter].
final class RealAsyncTimelineAdapter implements TraceTimelineAdapter {
  /// Creates an async Timeline adapter.
  RealAsyncTimelineAdapter();

  final List<TimelineTask> _openTasks = <TimelineTask>[];

  @override
  void start(String name, Map<String, Object?>? arguments) {
    try {
      final task = TimelineTask();
      _openTasks.add(task);
      task.start(name, arguments: arguments);
    } catch (_) {
      // Timeline failures must never break app flow.
    }
  }

  @override
  void finish() {
    try {
      if (_openTasks.isEmpty) {
        return;
      }
      _openTasks.removeLast().finish();
    } catch (_) {
      // Timeline failures must never break app flow.
    }
  }
}

/// Inert adapter for tests and embedding scenarios that must not touch
/// `dart:developer` at all.
final class NoopTimelineAdapter implements TraceTimelineAdapter {
  /// Creates a no-op adapter.
  const NoopTimelineAdapter();

  @override
  void start(String name, Map<String, Object?>? arguments) {}

  @override
  void finish() {}
}
