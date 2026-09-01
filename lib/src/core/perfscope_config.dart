/// Output style used when PerfScope reports findings.
enum PerfScopeLogStyle {
  /// Produces no output at all.
  silent,

  /// Produces terse single-line output.
  compact,

  /// Produces multi-line, human-friendly output.
  pretty,

  /// Emits one JSON object per line (NDJSON), suitable for machine parsing
  /// by log collectors and AI tooling.
  json,
}

/// Multipliers applied to the frame budget to derive severity tiers.
///
/// A frame whose total duration is greater than
/// `frameBudget * warningMultiplier` (but not slow) is a *warning* frame;
/// greater than `frameBudget * slowMultiplier` is *slow*; and greater than
/// `frameBudget * severeMultiplier` is *severe*. Comparisons are strictly
/// greater-than: a frame landing exactly on a threshold falls in the tier
/// below it.
class PerformanceThresholds {
  /// Creates thresholds with the required ordering:
  /// `severeMultiplier > slowMultiplier > warningMultiplier > 0`.
  const PerformanceThresholds({
    this.warningMultiplier = 1.0,
    this.slowMultiplier = 1.5,
    this.severeMultiplier = 3.0,
  })  : assert(
          severeMultiplier > slowMultiplier &&
              slowMultiplier > warningMultiplier,
          'Multipliers must be ordered severe > slow > warning',
        ),
        assert(warningMultiplier > 0, 'warningMultiplier must be positive');

  /// Canonical default thresholds (1.0x / 1.5x / 3.0x the frame budget).
  static const PerformanceThresholds defaults = PerformanceThresholds();

  /// Multiplier above which a frame is considered a warning.
  final double warningMultiplier;

  /// Multiplier above which a frame is considered slow.
  final double slowMultiplier;

  /// Multiplier above which a frame is considered severe.
  final double severeMultiplier;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerformanceThresholds &&
          runtimeType == other.runtimeType &&
          warningMultiplier == other.warningMultiplier &&
          slowMultiplier == other.slowMultiplier &&
          severeMultiplier == other.severeMultiplier;

  @override
  int get hashCode =>
      Object.hash(warningMultiplier, slowMultiplier, severeMultiplier);
}

/// Immutable configuration for PerfScope.
///
/// All fields have safe defaults; construct a const instance and use
/// [copyWith] to override only what you need.
class PerfScopeConfig {
  /// Creates an immutable configuration, validating invariants in debug mode.
  const PerfScopeConfig({
    this.enabled = true,
    this.targetFrameRate = 60,
    this.frameBufferSize = 500,
    this.contextFramesBefore = 5,
    this.contextFramesAfter = 5,
    this.logStyle = PerfScopeLogStyle.pretty,
    this.printNormalFrames = false,
    this.printWarnings = false,
    this.printAnomalies = true,
    this.autoStartSession = true,
    this.verbose = false,
    this.longTraceThreshold = const Duration(milliseconds: 50),
    this.maxStatisticSamples = 10000,
    this.thresholds = PerformanceThresholds.defaults,
  })  : assert(
          targetFrameRate > 0 && targetFrameRate <= 1000,
          'targetFrameRate must be within (0, 1000]',
        ),
        assert(frameBufferSize > 0, 'frameBufferSize must be positive'),
        assert(
          contextFramesBefore >= 0 && contextFramesAfter >= 0,
          'context frame counts must be non-negative',
        ),
        assert(
            maxStatisticSamples >= 100, 'maxStatisticSamples must be >= 100');

  /// Whether PerfScope instrumentation is active at all.
  final bool enabled;

  /// Refresh rate (Hz) used as the default basis for the frame budget.
  final int targetFrameRate;

  /// Maximum number of recent frames kept in memory for anomaly context.
  final int frameBufferSize;

  /// Number of preceding frames attached as context around an anomaly.
  final int contextFramesBefore;

  /// Number of following frames attached as context around an anomaly.
  final int contextFramesAfter;

  /// Style used when reporting findings to the console or logs.
  final PerfScopeLogStyle logStyle;

  /// Whether frames classified as normal are printed.
  final bool printNormalFrames;

  /// Whether frames classified as warnings are printed.
  final bool printWarnings;

  /// Whether detected anomalies are printed.
  final bool printAnomalies;

  /// Whether a session should be started automatically when PerfScope runs.
  final bool autoStartSession;

  /// Whether verbose diagnostics are emitted.
  final bool verbose;

  /// Traces longer than this duration are treated as long traces.
  final Duration longTraceThreshold;

  /// Bounded rolling window of frame durations kept for percentile
  /// statistics.
  ///
  /// Older samples are evicted once the window is full so memory usage stays
  /// constant regardless of session length. Must be at least 100.
  final int maxStatisticSamples;

  /// Severity multipliers applied to the effective frame budget.
  final PerformanceThresholds thresholds;

  /// Returns a copy of this config with the given fields replaced.
  PerfScopeConfig copyWith({
    bool? enabled,
    int? targetFrameRate,
    int? frameBufferSize,
    int? contextFramesBefore,
    int? contextFramesAfter,
    PerfScopeLogStyle? logStyle,
    bool? printNormalFrames,
    bool? printWarnings,
    bool? printAnomalies,
    bool? autoStartSession,
    bool? verbose,
    Duration? longTraceThreshold,
    int? maxStatisticSamples,
    PerformanceThresholds? thresholds,
  }) {
    return PerfScopeConfig(
      enabled: enabled ?? this.enabled,
      targetFrameRate: targetFrameRate ?? this.targetFrameRate,
      frameBufferSize: frameBufferSize ?? this.frameBufferSize,
      contextFramesBefore: contextFramesBefore ?? this.contextFramesBefore,
      contextFramesAfter: contextFramesAfter ?? this.contextFramesAfter,
      logStyle: logStyle ?? this.logStyle,
      printNormalFrames: printNormalFrames ?? this.printNormalFrames,
      printWarnings: printWarnings ?? this.printWarnings,
      printAnomalies: printAnomalies ?? this.printAnomalies,
      autoStartSession: autoStartSession ?? this.autoStartSession,
      verbose: verbose ?? this.verbose,
      longTraceThreshold: longTraceThreshold ?? this.longTraceThreshold,
      maxStatisticSamples: maxStatisticSamples ?? this.maxStatisticSamples,
      thresholds: thresholds ?? this.thresholds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerfScopeConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          targetFrameRate == other.targetFrameRate &&
          frameBufferSize == other.frameBufferSize &&
          contextFramesBefore == other.contextFramesBefore &&
          contextFramesAfter == other.contextFramesAfter &&
          logStyle == other.logStyle &&
          printNormalFrames == other.printNormalFrames &&
          printWarnings == other.printWarnings &&
          printAnomalies == other.printAnomalies &&
          autoStartSession == other.autoStartSession &&
          verbose == other.verbose &&
          longTraceThreshold == other.longTraceThreshold &&
          maxStatisticSamples == other.maxStatisticSamples &&
          thresholds == other.thresholds;

  @override
  int get hashCode => Object.hash(
        enabled,
        targetFrameRate,
        frameBufferSize,
        contextFramesBefore,
        contextFramesAfter,
        logStyle,
        printNormalFrames,
        printWarnings,
        printAnomalies,
        autoStartSession,
        verbose,
        longTraceThreshold,
        maxStatisticSamples,
        thresholds,
      );
}
