import '../core/clock.dart';
import '../core/ids.dart';
import '../frames/frame_classifier.dart';
import '../frames/frame_sample.dart';
import 'performance_anomaly.dart';

/// Pure decision point for frame anomalies: given an already-enriched
/// [FrameSample] and its [FrameClassification], decides whether the frame
/// deserves an anomaly and builds it.
///
/// The detector is deliberately dumb and stateless about frames — it holds
/// no history, opens no context windows, owns no buffers. Classification
/// itself is done upstream by a shared [FrameClassifier]; this type turns
/// an existing verdict into an anomaly or nothing. The engine calls it per
/// classified frame; window collection lives in
/// [FrameContextWindowCollector] (detector decides IF, collector captures
/// CONTEXT).
final class AnomalyDetector {
  /// Creates a detector. Ids come from [anomalyIds] (the engine's `anm`
  /// generator) and timestamps from [clock].
  AnomalyDetector({Clock clock = const SystemClock(), IdGenerator? anomalyIds})
      : _clock = clock,
        _anomalyIds = anomalyIds ?? IdGenerator('anm');

  final Clock _clock;
  final IdGenerator _anomalyIds;

  /// Returns a [FrameAnomaly] for [sample]/[classification], or null when
  /// the severity tier does not warrant one (only slow/severe do; warning
  /// frames stay plain events).
  ///
  /// Screen and interaction id are read off the ALREADY-ENRICHED sample —
  /// temporal correlation only, never causation.
  FrameAnomaly? detect(FrameSample sample, FrameClassification classification) {
    switch (classification.severity) {
      case FrameSeverity.normal:
      case FrameSeverity.warning:
        return null;
      case FrameSeverity.slow:
      case FrameSeverity.severe:
        return createFrameAnomaly(
          id: _anomalyIds.next(),
          timestamp: _clock.now(),
          sample: sample,
          classification: classification,
        );
    }
  }
}
