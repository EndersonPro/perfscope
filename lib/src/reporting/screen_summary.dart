/// Per-screen performance aggregates for a session report.
///
/// A screen summary answers "how does THIS screen behave?" from the same
/// records the session already holds: its frame distribution, anomaly
/// count, and the probable bottleneck mode among its anomalous frames.
/// Correlation only — a screen being visible during jank never proves it
/// caused the jank.
library;

import '../anomalies/performance_anomaly.dart';
import '../frames/frame_classifier.dart';
import '../frames/frame_sample.dart';
import 'statistics.dart';

/// Immutable per-screen aggregate shown in a [PerformanceReport].
final class ScreenPerformanceSummary {
  /// Creates an immutable screen summary.
  const ScreenPerformanceSummary({
    required this.name,
    required this.totalFrames,
    required this.slowFrames,
    required this.severeFrames,
    required this.anomalyCount,
    required this.slowFrameRate,
    required this.p95Ms,
    required this.worstMs,
    required this.probableBottleneck,
  });

  /// Screen name as captured on frames/anomalies (never null; unnamed
  /// routes are normalized to `'unknown'` upstream).
  final String name;

  /// Frames observed while this screen was visible.
  final int totalFrames;

  /// Slow frames observed on this screen.
  final int slowFrames;

  /// Severe frames observed on this screen.
  final int severeFrames;

  /// Anomalies attributed to this screen (frame and long-trace families).
  final int anomalyCount;

  /// `(slow + severe) / total`; `0` when no frames were seen.
  final double slowFrameRate;

  /// 95th percentile of total frame durations, in ms.
  final double p95Ms;

  /// Slowest frame seen on this screen, in ms.
  final double worstMs;

  /// Mode (most frequent) bottleneck among ANOMALOUS frames on this
  /// screen; [FrameBottleneck.unknown] when there were none. Ties resolve
  /// to the earliest declared enum value for determinism.
  final FrameBottleneck probableBottleneck;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenPerformanceSummary &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          totalFrames == other.totalFrames &&
          slowFrames == other.slowFrames &&
          severeFrames == other.severeFrames &&
          anomalyCount == other.anomalyCount &&
          slowFrameRate == other.slowFrameRate &&
          p95Ms == other.p95Ms &&
          worstMs == other.worstMs &&
          probableBottleneck == other.probableBottleneck;

  @override
  int get hashCode => Object.hash(name, totalFrames, slowFrames, severeFrames,
      anomalyCount, slowFrameRate, p95Ms, worstMs, probableBottleneck);
}

/// Incremental accumulator behind one [ScreenPerformanceSummary].
///
/// Building block used by the session manager; one instance exists per
/// screen seen during a session. Frame math is delegated to a composed
/// [StatisticsCalculator] instead of duplicating it.
final class ScreenPerformanceAccumulator {
  /// Creates an accumulator for screen [name].
  ScreenPerformanceAccumulator(
    this.name, {
    int windowCapacity = defaultStatisticWindowCapacity,
  }) : _stats = StatisticsCalculator(windowCapacity: windowCapacity);

  /// Screen name this accumulator aggregates.
  final String name;

  final StatisticsCalculator _stats;
  int _anomalyCount = 0;
  final Map<FrameBottleneck, int> _bottleneckTally = <FrameBottleneck, int>{};

  /// Records one classified frame rendered on this screen.
  void addFrame(FrameSample sample, FrameSeverity severity) =>
      _stats.addFrame(sample, severity);

  /// Credits an anomaly to this screen. Every anomaly bumps
  /// [ScreenPerformanceSummary.anomalyCount]; only frame anomalies feed
  /// the probable-bottleneck mode — long traces carry no frame phases.
  void addAnomaly(PerformanceAnomaly anomaly) {
    _anomalyCount++;
    if (anomaly is FrameAnomaly) {
      final bottleneck = anomaly.classification.bottleneck;
      _bottleneckTally[bottleneck] = (_bottleneckTally[bottleneck] ?? 0) + 1;
    }
  }

  /// Builds the immutable summary for the records accumulated so far.
  ScreenPerformanceSummary build() {
    final stats = _stats.snapshot();
    return ScreenPerformanceSummary(
      name: name,
      totalFrames: stats.totalFrames,
      slowFrames: stats.slowFrames,
      severeFrames: stats.severeFrames,
      anomalyCount: _anomalyCount,
      slowFrameRate: stats.slowFrameRate,
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
