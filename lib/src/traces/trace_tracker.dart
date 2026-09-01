import '../buffers/ring_buffer.dart';
import '../context/metadata_validator.dart';

/// Maximum number of completed traces kept in memory.
///
/// Deliberately config-independent and fixed: traces are a bounded
/// diagnostic window, not an unbounded history, so memory stays constant
/// regardless of session length.
const int maxStoredTraces = 500;

/// A finished manual trace, whether its body succeeded or threw.
///
/// Immutable by construction; [metadata] is already defensively copied at
/// creation time, so later caller-side mutations never leak in.
final class CompletedTrace {
  /// Creates a completed trace record.
  ///
  /// Not const on purpose: [metadata] is defensively copied here so later
  /// mutations of caller-held collections never leak into stored records.
  CompletedTrace({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.duration,
    required this.screen,
    required this.didThrow,
    Map<String, Object?>? metadata,
  }) : metadata = metadata == null
            ? const <String, Object?>{}
            : metadata.map((key, value) =>
                MapEntry(key, MetadataValidator.defensiveCopy(value)));

  /// Local correlation identifier unique within this PerfScope session
  /// (prefix `trc`), shared with the matching [TraceEvent].
  final String id;

  /// Caller-provided label of the traced operation.
  final String name;

  /// Wall-clock time at which the trace started.
  final DateTime startedAt;

  /// How long the traced operation took, including the failure path.
  final Duration duration;

  /// Screen name captured when the trace *started* (not live values):
  /// screen changes mid-trace do not retroactively re-attribute it.
  final String screen;

  /// Whether the traced body threw before completing.
  ///
  /// A throwing body is still a completed observation — PerfScope records
  /// it and rethrows untouched.
  final bool didThrow;

  /// Validated, defensively copied caller-supplied context.
  final Map<String, Object?> metadata;
}

/// Bounded store of [CompletedTrace]s in chronological order.
///
/// Backed by a ring buffer of [maxStoredTraces] entries (overridable for
/// tests); adding beyond capacity silently drops the oldest trace.
final class TraceTracker {
  /// Creates a tracker holding at most [capacity] completed traces.
  TraceTracker({int capacity = maxStoredTraces})
      : _traces = RingBuffer(capacity);

  final RingBuffer<CompletedTrace> _traces;

  /// Maximum number of traces this tracker retains.
  int get capacity => _traces.capacity;

  /// Records a completed trace, dropping the oldest entry when full.
  void record(CompletedTrace trace) => _traces.add(trace);

  /// Chronological snapshot of the stored traces.
  List<CompletedTrace> get traces => _traces.toList();

  /// Removes every stored trace without deallocating backing storage.
  void clear() => _traces.clear();
}
