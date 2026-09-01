/// Per-interaction performance aggregates for a session report.
///
/// An interaction groups every frame attributed to one named user flow
/// (span starts, quick markers) plus the wall-clock time its spans stayed
/// open. Like screens, interactions are temporal correlation only: frames
/// DURING an interaction are not necessarily CAUSED by it.
library;

import '../anomalies/performance_anomaly.dart';
import '../frames/frame_classifier.dart';
import '../frames/frame_sample.dart';
import 'statistics.dart';

/// Immutable per-interaction aggregate shown in a [PerformanceReport].
final class InteractionPerformanceSummary {
  /// Creates an immutable interaction summary.
  const InteractionPerformanceSummary({
    required this.name,
    required this.mostRecentInteractionId,
    required this.spanCount,
    required this.frameCount,
    required this.anomalyCount,
    required this.totalSpanDuration,
    required this.p95Ms,
    required this.worstMs,
    required this.probableBottleneck,
  });

  /// Caller-provided label shared by every span of this flow.
  final String name;

  /// Id of the most recently noted span under [name], null when none.
  final String? mostRecentInteractionId;

  /// Number of spans/quick markers noted under this name (per unique id).
  final int spanCount;

  /// Frames attributed to any span of this flow.
  final int frameCount;

  /// Anomalies attributed to this interaction's spans.
  final int anomalyCount;

  /// Sum of completed span durations (start→end); markers never add.
  final Duration totalSpanDuration;

  /// 95th percentile of total frame durations, in ms.
  final double p95Ms;

  /// Slowest attributed frame, in ms.
  final double worstMs;

  /// Mode bottleneck among ANOMALOUS frames of this interaction;
  /// [FrameBottleneck.unknown] when there were none. Ties resolve to the
  /// earliest declared enum value for determinism.
  final FrameBottleneck probableBottleneck;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InteractionPerformanceSummary &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          mostRecentInteractionId == other.mostRecentInteractionId &&
          spanCount == other.spanCount &&
          frameCount == other.frameCount &&
          anomalyCount == other.anomalyCount &&
          totalSpanDuration == other.totalSpanDuration &&
          p95Ms == other.p95Ms &&
          worstMs == other.worstMs &&
          probableBottleneck == other.probableBottleneck;

  @override
  int get hashCode => Object.hash(
        name,
        mostRecentInteractionId,
        spanCount,
        frameCount,
        anomalyCount,
        totalSpanDuration,
        p95Ms,
        worstMs,
        probableBottleneck,
      );
}

/// Incremental accumulator behind one [InteractionPerformanceSummary].
///
/// Building block used by the session manager; one instance exists per
/// distinct interaction NAME seen during a session (many span ids can map
/// to the same name). Frame math is delegated to a composed
/// [StatisticsCalculator] instead of duplicating it.
final class InteractionPerformanceAccumulator {
  /// Creates an accumulator for interactions labeled [name].
  InteractionPerformanceAccumulator(
    this.name, {
    int windowCapacity = defaultStatisticWindowCapacity,
  }) : _stats = StatisticsCalculator(windowCapacity: windowCapacity);

  /// Interaction label this accumulator aggregates.
  final String name;

  final StatisticsCalculator _stats;
  int _anomalyCount = 0;
  final Map<FrameBottleneck, int> _bottleneckTally = <FrameBottleneck, int>{};
  int _spanCount = 0;
  Duration _totalSpanDuration = Duration.zero;
  String? _mostRecentInteractionId;

  /// Notes a new span (or quick marker — markers count as spans) under
  /// this interaction's name.
  void noteSpan(String interactionId) {
    _spanCount++;
    _mostRecentInteractionId = interactionId;
  }

  /// Adds a completed span's duration to the running total.
  void addSpanDuration(Duration duration) {
    _totalSpanDuration += duration;
  }

  /// Records one classified frame attributed to this interaction.
  void addFrame(FrameSample sample, FrameSeverity severity) =>
      _stats.addFrame(sample, severity);

  /// Credits an anomaly to this interaction. Every anomaly bumps
  /// [InteractionPerformanceSummary.anomalyCount]; only frame anomalies
  /// feed the probable-bottleneck mode.
  void addAnomaly(PerformanceAnomaly anomaly) {
    _anomalyCount++;
    if (anomaly is FrameAnomaly) {
      final bottleneck = anomaly.classification.bottleneck;
      _bottleneckTally[bottleneck] = (_bottleneckTally[bottleneck] ?? 0) + 1;
    }
  }

  /// Builds the immutable summary for the records accumulated so far.
  InteractionPerformanceSummary build() {
    final stats = _stats.snapshot();
    return InteractionPerformanceSummary(
      name: name,
      mostRecentInteractionId: _mostRecentInteractionId,
      spanCount: _spanCount,
      frameCount: stats.totalFrames,
      anomalyCount: _anomalyCount,
      totalSpanDuration: _totalSpanDuration,
      p95Ms: stats.p95Ms,
      worstMs: stats.worstFrameMs,
      probableBottleneck: _modeBottleneck(),
    );
  }

  /// Highest-tally bottleneck among anomalous frames; declaration-order
  /// wins ties so results stay deterministic across runs.
  FrameBottleneck _modeBottleneck() {
    var best = FrameBottleneck.unknown;
    var bestCount = 0;
    for (final candidate in FrameBottleneck.values) {
      final count = _bottleneckTally[candidate] ?? 0;
      if (count > bestCount) {
        best = candidate;
        bestCount = count;
      }
    }
    return best;
  }
}
