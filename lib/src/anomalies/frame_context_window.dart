import '../frames/frame_sample.dart';

/// Maximum number of context windows the engine tracks at once, across
/// pending AND completed windows (oldest dropped first).
///
/// Deliberately config-independent: context windows are a bounded
/// diagnostic aid for recently detected anomalies, not a tunable history.
const int maxPendingWindows = 32;

/// Frames surrounding one detected frame anomaly: the [before] frames that
/// preceded it and the [after] frames that strictly follow it.
///
/// The anomaly frame itself is deliberately excluded from its own
/// after-window — an anomaly's context is *other* frames. Offering the
/// anomaly frame back to its own window is a safe no-op.
final class FrameContextWindow {
  /// Creates a window around [anomaly], seeded with the already-collected
  /// [before] frames (copied defensively; never padded to reach a target
  /// length) and expecting at most [afterCount] following frames.
  FrameContextWindow({
    required this.anomalyId,
    required List<FrameSample> before,
    required this.anomaly,
    required int afterCount,
  })  : assert(afterCount >= 0, 'afterCount must be non-negative'),
        before = List<FrameSample>.unmodifiable(before),
        _after = <FrameSample>[],
        _needed = afterCount;

  /// Correlation id of the anomaly this window was opened for.
  final String anomalyId;

  /// Preceding frames in chronological order (shorter than requested when
  /// fewer frames were available at detection time).
  final List<FrameSample> before;

  /// The enriched frame that triggered the anomaly.
  final FrameSample anomaly;

  final List<FrameSample> _after;
  final int _needed;

  /// Whether exactly [_needed] following frames have been collected (or
  /// the window asked for none in the first place).
  bool get isComplete => _after.length >= _needed;

  /// Unmodifiable snapshot of the following frames collected so far,
  /// chronological order; never longer than the requested count.
  List<FrameSample> get after => List<FrameSample>.unmodifiable(_after);

  /// Adds one strictly-following frame unless the window is already
  /// complete or the frame IS the anomaly frame itself.
  void offer(FrameSample frame) {
    if (isComplete || identical(frame, anomaly)) {
      return;
    }
    _after.add(frame);
  }
}

/// Collects the frames FOLLOWING freshly detected anomalies so each one can
/// be reported with surrounding context.
///
/// Separation of concerns: [AnomalyDetector] decides IF a frame is
/// anomalous; this collector captures CONTEXT around the decision. The
/// detector stays stateless about history; the collector stays ignorant of
/// classification.
///
/// Windows are keyed by anomaly id ([windowFor] answers for pending AND
/// completed windows). Everything this collector tracks is bounded by the
/// constructor cap (default [maxPendingWindows]): once exceeded, the
/// OLDEST window — pending or completed — is dropped entirely.
final class FrameContextWindowCollector {
  /// Creates a collector tracking at most [pendingCapacity] windows.
  FrameContextWindowCollector({int pendingCapacity = maxPendingWindows})
      : assert(pendingCapacity > 0, 'capacity must be positive'),
        _capacity = pendingCapacity;

  final int _capacity;

  /// Insertion-ordered map from anomaly id to window. Holds PENDING and
  /// COMPLETED windows alike ("pending" simply means the window's
  /// after-collection is still incomplete); insertion order gives the
  /// global oldest-first order used for eviction.
  final Map<String, FrameContextWindow> _windows =
      <String, FrameContextWindow>{};

  /// Opens a window for [anomalyId] around [anomalySample], seeding it with
  /// [beforeFrames] and expecting [afterCount] following frames via [offer].
  ///
  /// Windows asking for zero following frames are born complete: they are
  /// still tracked (and resolvable through [windowFor]) until evicted.
  FrameContextWindow open(
    String anomalyId,
    FrameSample anomalySample,
    List<FrameSample> beforeFrames,
    int afterCount,
  ) {
    // Re-opening an id must not resurrect stale ordering; ids are unique
    // in practice, this only guards against misuse.
    _windows.remove(anomalyId);
    _windows[anomalyId] = FrameContextWindow(
      anomalyId: anomalyId,
      before: beforeFrames,
      anomaly: anomalySample,
      afterCount: afterCount,
    );
    _evictOverflow();
    return _windows[anomalyId]!;
  }

  /// Feeds [frame] to every still-pending window. Completed windows stop
  /// consuming but stay resolvable through [windowFor].
  void offer(FrameSample frame) {
    if (_windows.isEmpty) {
      return;
    }
    for (final window in _windows.values) {
      if (!window.isComplete) {
        window.offer(frame);
      }
    }
  }

  /// Returns the window opened for [anomalyId] — pending OR completed — or
  /// null when unknown/evicted.
  FrameContextWindow? windowFor(String anomalyId) => _windows[anomalyId];

  void _evictOverflow() {
    while (_windows.length > _capacity) {
      _windows.remove(_windows.keys.first);
    }
  }
}
