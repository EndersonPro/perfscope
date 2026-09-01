import '../buffers/ring_buffer.dart';
import '../events/performance_event.dart';
import 'performance_event_sink.dart';

/// Default capacity of a [MemorySink] when none is given.
const int defaultMemorySinkCapacity = 500;

/// Sink storing RAW events (not rendered text) in a bounded ring buffer.
///
/// Oldest events are dropped once capacity is reached, so memory stays
/// constant regardless of session length. Intended for tests, in-app
/// diagnostics screens, and short-lived inspection windows.
final class MemorySink
    with SinkAcceptsAllMixin
    implements PerformanceEventSink {
  /// Creates a sink holding at most [capacity] raw events.
  MemorySink({int capacity = defaultMemorySinkCapacity})
      : _buffer = RingBuffer<PerformanceEvent>(capacity);

  final RingBuffer<PerformanceEvent> _buffer;

  /// Maximum number of retained events.
  int get capacity => _buffer.capacity;

  /// Current number of stored events.
  int get length => _buffer.length;

  /// Chronological snapshot of stored RAW events, oldest first.
  List<PerformanceEvent> get events => _buffer.toList();

  /// Removes every stored event without deallocating backing storage.
  void clear() => _buffer.clear();

  @override
  void add(covariant PerformanceEvent event) => _buffer.add(event);
}
