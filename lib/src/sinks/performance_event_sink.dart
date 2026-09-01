import 'package:flutter/foundation.dart' show debugPrint;

import '../events/performance_event.dart';

/// Destination for raw [PerformanceEvent]s outside the log stream.
///
/// Sinks receive events exactly once, alongside (not instead of) the
/// public broadcast stream. Implementations must be cheap: they run on the
/// frame pipeline path.
abstract interface class PerformanceEventSink {
  /// Whether [event] should be delivered to [add]. Returning false skips
  /// the sink entirely.
  bool accepts(PerformanceEvent event);

  /// Receives one event. Implementations must not throw under normal use;
  /// callers still guard every invocation.
  void add(PerformanceEvent event);
}

/// Default accept-everything policy for sinks without filtering needs.
mixin SinkAcceptsAllMixin {
  /// Accepts every event.
  bool accepts(covariant PerformanceEvent event) => true;
}

/// Fans one event out to every child sink.
///
/// Each child is guarded individually: a throwing `accepts` or `add` is
/// caught and reported through [debugPrint] with a `[PerfScope]` prefix,
/// and the remaining children still receive the event.
final class CompositeSink implements PerformanceEventSink {
  /// Creates a fan-out over [sinks]. The list is copied defensively.
  CompositeSink(Iterable<PerformanceEventSink> sinks)
      : _sinks = List<PerformanceEventSink>.unmodifiable(sinks);

  final List<PerformanceEventSink> _sinks;

  /// Number of children this composite fans out to.
  int get sinkCount => _sinks.length;

  @override
  bool accepts(covariant PerformanceEvent event) => true;

  @override
  void add(PerformanceEvent event) {
    for (final sink in _sinks) {
      try {
        if (!sink.accepts(event)) {
          continue;
        }
        sink.add(event);
      } catch (error) {
        debugPrint('[PerfScope] sink error: $error');
      }
    }
  }
}
