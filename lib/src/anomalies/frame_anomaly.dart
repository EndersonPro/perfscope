part of 'performance_anomaly.dart';

/// Base type for anomalies raised around a single expensive frame.
///
/// HEURISTIC: every [FrameAnomaly] describes the *probable* bottleneck of
/// one frame, derived solely from its `FrameTiming`-derived durations (see
/// [FrameClassifier]). Timing shapes indicate where the time went; they
/// never prove why. A frame anomaly is an observation that a frame was
/// slow *while* a given screen/interaction was current — never a claim
/// that any phase, screen, or interaction caused the jank.
abstract class FrameAnomaly extends PerformanceAnomaly {
  /// Creates a frame anomaly.
  ///
  /// Prefer [createFrameAnomaly] so the concrete subclass always matches
  /// [classification]'s probable bottleneck.
  const FrameAnomaly({
    required super.id,
    required super.timestamp,
    required super.severity,
    required this.sample,
    required this.classification,
    required this.frameBudget,
    super.screen,
    super.interactionId,
    super.metadata,
  });

  /// The enriched frame that triggered this anomaly (carries the screen /
  /// interaction attribution captured when the frame was observed).
  final FrameSample sample;

  /// Classifier verdict for [sample]: severity tier and probable bottleneck.
  final FrameClassification classification;

  /// Budget the triggering frame was expected to meet (e.g. 16.667ms at
  /// 60Hz), repeated from the sample for quick access.
  final Duration frameBudget;

  /// Probable bottleneck phase carried by [classification].
  FrameBottleneck get bottleneck => classification.bottleneck;

  /// Maps a frame [severity] onto [AnomalySeverity].
  ///
  /// Documented contract: only slow and severe frames ever reach anomaly
  /// creation — `slow` maps to [AnomalySeverity.high] and `severe` to
  /// [AnomalySeverity.critical]. Warning-tier frames are recorded as
  /// events but never become anomalies.
  static AnomalySeverity severityFor(FrameSeverity severity) {
    switch (severity) {
      case FrameSeverity.slow:
        return AnomalySeverity.high;
      case FrameSeverity.severe:
        return AnomalySeverity.critical;
      case FrameSeverity.normal:
      case FrameSeverity.warning:
        throw ArgumentError.value(
          severity,
          'severity',
          'only slow/severe frames can produce a frame anomaly',
        );
    }
  }
}

/// Slow frame whose probable bottleneck could not be inferred from timing
/// durations alone ([FrameBottleneck.unknown]).
final class SlowFrameAnomaly extends FrameAnomaly {
  /// Creates a slow-frame anomaly with unknown bottleneck.
  const SlowFrameAnomaly({
    required super.id,
    required super.timestamp,
    required super.severity,
    required super.sample,
    required super.classification,
    required super.frameBudget,
    super.screen,
    super.interactionId,
    super.metadata,
  });
}

/// Slow frame whose UI thread work dominates
/// ([FrameBottleneck.ui]) — probable build/layout/paint blame.
final class UiBoundFrameAnomaly extends FrameAnomaly {
  /// Creates a UI-bound frame anomaly.
  const UiBoundFrameAnomaly({
    required super.id,
    required super.timestamp,
    required super.severity,
    required super.sample,
    required super.classification,
    required super.frameBudget,
    super.screen,
    super.interactionId,
    super.metadata,
  });
}

/// Slow frame whose raster thread work dominates
/// ([FrameBottleneck.raster]).
final class RasterBoundFrameAnomaly extends FrameAnomaly {
  /// Creates a raster-bound frame anomaly.
  const RasterBoundFrameAnomaly({
    required super.id,
    required super.timestamp,
    required super.severity,
    required super.sample,
    required super.classification,
    required super.frameBudget,
    super.screen,
    super.interactionId,
    super.metadata,
  });
}

/// Slow frame where both threads contribute comparably
/// ([FrameBottleneck.mixed]).
final class MixedFrameAnomaly extends FrameAnomaly {
  /// Creates a mixed-bottleneck frame anomaly.
  const MixedFrameAnomaly({
    required super.id,
    required super.timestamp,
    required super.severity,
    required super.sample,
    required super.classification,
    required super.frameBudget,
    super.screen,
    super.interactionId,
    super.metadata,
  });
}

/// Builds the concrete [FrameAnomaly] matching [classification]: the
/// subclass mirrors the classification bottleneck (unknown →
/// [SlowFrameAnomaly], ui → [UiBoundFrameAnomaly], raster →
/// [RasterBoundFrameAnomaly], mixed → [MixedFrameAnomaly]).
///
/// Severity follows [FrameAnomaly.severityFor]; screen and interaction id
/// are read off the ALREADY-ENRICHED [sample] (temporal correlation only).
/// Pure creation logic: callers inject the correlation [id] (engine's
/// `anm` generator) and wall-clock [timestamp].
FrameAnomaly createFrameAnomaly({
  required String id,
  required DateTime timestamp,
  required FrameSample sample,
  required FrameClassification classification,
}) {
  final severity = FrameAnomaly.severityFor(classification.severity);
  switch (classification.bottleneck) {
    case FrameBottleneck.unknown:
      return SlowFrameAnomaly(
        id: id,
        timestamp: timestamp,
        severity: severity,
        sample: sample,
        classification: classification,
        frameBudget: sample.frameBudget,
        screen: sample.screen,
        interactionId: sample.interactionId,
      );
    case FrameBottleneck.ui:
      return UiBoundFrameAnomaly(
        id: id,
        timestamp: timestamp,
        severity: severity,
        sample: sample,
        classification: classification,
        frameBudget: sample.frameBudget,
        screen: sample.screen,
        interactionId: sample.interactionId,
      );
    case FrameBottleneck.raster:
      return RasterBoundFrameAnomaly(
        id: id,
        timestamp: timestamp,
        severity: severity,
        sample: sample,
        classification: classification,
        frameBudget: sample.frameBudget,
        screen: sample.screen,
        interactionId: sample.interactionId,
      );
    case FrameBottleneck.mixed:
      return MixedFrameAnomaly(
        id: id,
        timestamp: timestamp,
        severity: severity,
        sample: sample,
        classification: classification,
        frameBudget: sample.frameBudget,
        screen: sample.screen,
        interactionId: sample.interactionId,
      );
  }
}
