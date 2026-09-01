/// Session-level frame statistics: exact counters, exact running sums, and
/// percentile estimates computed over a bounded rolling window.
///
/// Design contract:
/// * Severity counts, duration sums (microseconds), and the worst frame are
///   EXACT — plain integer accumulators, no drift.
/// * Percentiles are an APPROXIMATION over the most recent
///   `windowCapacity` total durations (oldest evicted once full), so
///   memory stays constant regardless of session length. Long sessions
///   therefore describe their recent past, not their entire history.
///
/// This library also exposes the pure helpers used by
/// [StatisticsCalculator] so other call sites can reuse the exact same
/// math: [nearestRankPercentileMicros] and [microsToMsRounded].
library;

import '../buffers/ring_buffer.dart';
import '../frames/frame_classifier.dart';
import '../frames/frame_sample.dart';

/// Default rolling-window capacity for [StatisticsCalculator].
///
/// Mirrors `PerfScopeConfig.maxStatisticSamples`' default; engines pass
/// the configured value explicitly, standalone callers fall back to this.
const int defaultStatisticWindowCapacity = 10000;

/// Nearest-rank percentile of an ASCENDING-sorted list of durations.
///
/// Algorithm (nearest-rank): with `n` samples, the rank of percentile `p`
/// is `rank = ceil(p / 100 * n)` (1-based), clamped to `[1, n]`, and the
/// returned value is `sorted[rank - 1]`. Examples: p50 of 4 samples picks
/// `ceil(2.0) = 2` → the 2nd smallest; p50 of 5 samples picks
/// `ceil(2.5) = 3` → the middle one; p95 of 11 samples picks
/// `ceil(10.45) = 11` → the maximum.
///
/// Precondition: [sortedMicros] must already be sorted ascending — the
/// helper never sorts (O(n log n) stays at the caller's discretion) and
/// silently treats any other order as-is. An empty list yields `0`.
int nearestRankPercentileMicros(List<int> sortedMicros, double p) {
  if (sortedMicros.isEmpty) {
    return 0;
  }
  final n = sortedMicros.length;
  var rank = (p / 100 * n).ceil();
  if (rank < 1) {
    rank = 1;
  }
  if (rank > n) {
    rank = n;
  }
  return sortedMicros[rank - 1];
}

/// Converts integer microseconds to milliseconds rounded to 3 decimals.
///
/// Because the input is an integer number of microseconds, a single
/// division by 1000 IS the correctly-rounded 3-decimal millisecond value:
/// the third decimal digit of ms corresponds exactly to whole µs.
double microsToMsRounded(int micros) =>
    micros / Duration.microsecondsPerMillisecond;

/// Rounds an arbitrary double to 3 decimal places (half away from zero).
double _round3(double value) =>
    (value * Duration.microsecondsPerMillisecond).roundToDouble() /
    Duration.microsecondsPerMillisecond;

/// Immutable snapshot of frame statistics for one session.
final class SessionStatistics {
  /// Creates an immutable statistics snapshot.
  const SessionStatistics({
    required this.totalFrames,
    required this.normalFrames,
    required this.warningFrames,
    required this.slowFrames,
    required this.severeFrames,
    required this.slowFrameRate,
    required this.averageBuildMs,
    required this.averageRasterMs,
    required this.averageTotalMs,
    required this.p50Ms,
    required this.p90Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.worstFrameMs,
  });

  /// Every frame observed, across all severity tiers.
  final int totalFrames;

  /// Frames within budget.
  final int normalFrames;

  /// Frames above budget but below the slow tier.
  final int warningFrames;

  /// Clearly over budget.
  final int slowFrames;

  /// Severely over budget; likely perceptible jank.
  final int severeFrames;

  /// `(slowFrames + severeFrames) / totalFrames`; exactly `0` when
  /// [totalFrames] is `0`.
  final double slowFrameRate;

  /// Mean build duration in ms, rounded to 3 decimals.
  final double averageBuildMs;

  /// Mean raster duration in ms, rounded to 3 decimals.
  final double averageRasterMs;

  /// Mean total frame duration in ms, rounded to 3 decimals.
  final double averageTotalMs;

  /// 50th percentile of total frame durations (nearest-rank over the
  /// bounded rolling window — see library docs), in ms.
  final double p50Ms;

  /// 90th percentile of total frame durations, in ms.
  final double p90Ms;

  /// 95th percentile of total frame durations, in ms.
  final double p95Ms;

  /// 99th percentile of total frame durations, in ms.
  final double p99Ms;

  /// Slowest observed frame, in ms. Exact (not window-bounded).
  final double worstFrameMs;

  /// Canonical all-zero snapshot for an empty session.
  static const SessionStatistics zero = SessionStatistics(
    totalFrames: 0,
    normalFrames: 0,
    warningFrames: 0,
    slowFrames: 0,
    severeFrames: 0,
    slowFrameRate: 0,
    averageBuildMs: 0,
    averageRasterMs: 0,
    averageTotalMs: 0,
    p50Ms: 0,
    p90Ms: 0,
    p95Ms: 0,
    p99Ms: 0,
    worstFrameMs: 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionStatistics &&
          runtimeType == other.runtimeType &&
          totalFrames == other.totalFrames &&
          normalFrames == other.normalFrames &&
          warningFrames == other.warningFrames &&
          slowFrames == other.slowFrames &&
          severeFrames == other.severeFrames &&
          slowFrameRate == other.slowFrameRate &&
          averageBuildMs == other.averageBuildMs &&
          averageRasterMs == other.averageRasterMs &&
          averageTotalMs == other.averageTotalMs &&
          p50Ms == other.p50Ms &&
          p90Ms == other.p90Ms &&
          p95Ms == other.p95Ms &&
          p99Ms == other.p99Ms &&
          worstFrameMs == other.worstFrameMs;

  @override
  int get hashCode => Object.hash(
        totalFrames,
        normalFrames,
        warningFrames,
        slowFrames,
        severeFrames,
        slowFrameRate,
        averageBuildMs,
        averageRasterMs,
        averageTotalMs,
        p50Ms,
        p90Ms,
        p95Ms,
        p99Ms,
        worstFrameMs,
      );
}

/// Incremental accumulator producing [SessionStatistics].
///
/// Counts, sums, and the worst frame are updated in O(1) per frame;
/// percentiles are computed only when [snapshot] is called, over the
/// bounded rolling window described in the library docs.
final class StatisticsCalculator {
  /// Creates a calculator whose percentile window holds at most
  /// [windowCapacity] total-duration samples.
  StatisticsCalculator({int windowCapacity = defaultStatisticWindowCapacity})
      : assert(windowCapacity > 0, 'windowCapacity must be positive'),
        _window = RingBuffer<int>(windowCapacity);

  final RingBuffer<int> _window;

  int _normal = 0;
  int _warning = 0;
  int _slow = 0;
  int _severe = 0;
  int _buildSumUs = 0;
  int _rasterSumUs = 0;
  int _totalSumUs = 0;
  int _worstUs = 0;

  /// Records one classified frame into every accumulator.
  void addFrame(FrameSample sample, FrameSeverity severity) {
    switch (severity) {
      case FrameSeverity.normal:
        _normal++;
      case FrameSeverity.warning:
        _warning++;
      case FrameSeverity.slow:
        _slow++;
      case FrameSeverity.severe:
        _severe++;
    }
    final buildUs = sample.buildDuration.inMicroseconds;
    final rasterUs = sample.rasterDuration.inMicroseconds;
    final totalUs = sample.totalDuration.inMicroseconds;
    _buildSumUs += buildUs;
    _rasterSumUs += rasterUs;
    _totalSumUs += totalUs;
    if (totalUs > _worstUs) {
      _worstUs = totalUs;
    }
    _window.add(totalUs);
  }

  /// Builds an immutable snapshot of everything accumulated so far.
  ///
  /// Percentiles are nearest-rank ([nearestRankPercentileMicros]) over the
  /// sorted window contents — an approximation bounded by the window, not
  /// the whole session history (see library docs).
  SessionStatistics snapshot() {
    final total = _normal + _warning + _slow + _severe;
    final sortedWindow = _window.toList()..sort();
    return SessionStatistics(
      totalFrames: total,
      normalFrames: _normal,
      warningFrames: _warning,
      slowFrames: _slow,
      severeFrames: _severe,
      slowFrameRate: total == 0 ? 0 : (_slow + _severe) / total,
      averageBuildMs: total == 0
          ? 0
          : _round3(_buildSumUs / total / Duration.microsecondsPerMillisecond),
      averageRasterMs: total == 0
          ? 0
          : _round3(_rasterSumUs / total / Duration.microsecondsPerMillisecond),
      averageTotalMs: total == 0
          ? 0
          : _round3(_totalSumUs / total / Duration.microsecondsPerMillisecond),
      p50Ms: microsToMsRounded(nearestRankPercentileMicros(sortedWindow, 50)),
      p90Ms: microsToMsRounded(nearestRankPercentileMicros(sortedWindow, 90)),
      p95Ms: microsToMsRounded(nearestRankPercentileMicros(sortedWindow, 95)),
      p99Ms: microsToMsRounded(nearestRankPercentileMicros(sortedWindow, 99)),
      worstFrameMs: microsToMsRounded(_worstUs),
    );
  }

  /// Clears every counter, sum, and windowed sample.
  void reset() {
    _normal = 0;
    _warning = 0;
    _slow = 0;
    _severe = 0;
    _buildSumUs = 0;
    _rasterSumUs = 0;
    _totalSumUs = 0;
    _worstUs = 0;
    _window.clear();
  }
}
