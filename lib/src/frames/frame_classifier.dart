import '../core/perfscope_config.dart';
import 'frame_sample.dart';

/// Severity tier assigned to a frame after classification.
enum FrameSeverity {
  /// Within budget; no action required.
  normal,

  /// Over budget but below the slow tier.
  warning,

  /// Clearly over budget.
  slow,

  /// Severely over budget; likely perceptible jank.
  severe,
}

/// Probable phase responsible for an expensive frame.
enum FrameBottleneck {
  /// UI thread (build/layout) work dominates.
  ui,

  /// Raster thread work dominates.
  raster,

  /// Both threads contribute comparably.
  mixed,

  /// No bottleneck could be inferred.
  unknown,
}

/// Result of classifying one frame: its severity and probable bottleneck.
class FrameClassification {
  /// Creates an immutable classification result.
  const FrameClassification(this.severity, this.bottleneck);

  /// Severity tier of the frame.
  final FrameSeverity severity;

  /// Probable bottleneck phase of the frame.
  final FrameBottleneck bottleneck;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrameClassification &&
          runtimeType == other.runtimeType &&
          severity == other.severity &&
          bottleneck == other.bottleneck;

  @override
  int get hashCode => Object.hash(severity, bottleneck);
}

/// Pure classifier mapping [FrameSample] values to severity and bottleneck.
///
/// Stateless and side-effect free: safe to share across call sites.
class FrameClassifier {
  /// Creates a classifier using [thresholds] (defaults when omitted).
  const FrameClassifier({this.thresholds = PerformanceThresholds.defaults});

  /// Multipliers applied to the sample's frame budget.
  final PerformanceThresholds thresholds;

  /// Classifies [sample] into a severity tier and probable bottleneck.
  FrameClassification classify(FrameSample sample) {
    final severity = _severity(sample.totalDuration, sample.frameBudget);
    return FrameClassification(severity, _bottleneck(sample, severity));
  }

  FrameSeverity _severity(Duration total, Duration budget) {
    // Strictly-greater comparisons: exactly-at-threshold falls in the lower
    // tier. Double math on microseconds avoids Duration rounding surprises.
    final budgetUs = budget.inMicroseconds;
    final totalUs = total.inMicroseconds;
    if (totalUs > budgetUs * thresholds.severeMultiplier) {
      return FrameSeverity.severe;
    }
    if (totalUs > budgetUs * thresholds.slowMultiplier) {
      return FrameSeverity.slow;
    }
    if (totalUs > budgetUs * thresholds.warningMultiplier) {
      return FrameSeverity.warning;
    }
    return FrameSeverity.normal;
  }

  /// HEURISTIC: the bottleneck is derived solely from frame timing
  /// durations. It indicates the *probable* bottleneck phase only — it is
  /// never proven cause. Timeline traces are required to attribute blame
  /// with certainty.
  FrameBottleneck _bottleneck(FrameSample sample, FrameSeverity severity) {
    if (severity == FrameSeverity.normal) {
      return FrameBottleneck.unknown;
    }
    final b = sample.buildDuration.inMicroseconds;
    final r = sample.rasterDuration.inMicroseconds;
    if (r == 0 && b > 0) return FrameBottleneck.ui;
    if (b == 0 && r > 0) return FrameBottleneck.raster;
    if (b > 0 && r > 0) {
      if (b >= 2 * r) return FrameBottleneck.ui;
      if (r >= 2 * b) return FrameBottleneck.raster;
      return FrameBottleneck.mixed;
    }
    return FrameBottleneck.unknown;
  }
}
