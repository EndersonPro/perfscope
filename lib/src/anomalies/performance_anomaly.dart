/// Base type for every anomaly PerfScope detects.
///
/// [PerformanceAnomaly] is `sealed` so consumers get exhaustive pattern
/// matching over the full, compile-time-known set of anomalies. Dart
/// restricts `sealed` subtypes to their defining library, therefore
/// concrete anomalies — the trace family ([LongTraceAnomaly]) and the
/// frame family ([FrameAnomaly] and its subclasses) — are declared in
/// `part` files of this library.
///
/// Anomalies are observations about *correlated* records, never claims of
/// causation: an anomaly may state that a long trace happened while a
/// given screen was visible, but it must never claim the trace caused any
/// specific frame or jank incident.
library;

import '../frames/frame_classifier.dart';
import '../frames/frame_sample.dart';

part 'frame_anomaly.dart';
part 'trace_anomaly.dart';

/// Qualitative seriousness of a [PerformanceAnomaly].
enum AnomalySeverity {
  /// Worth recording; unlikely to matter on its own.
  low,

  /// Notable deviation from expected behavior.
  medium,

  /// Clear outlier that likely affects user experience.
  high,

  /// Extreme outlier; almost certainly user-perceivable.
  critical,
}

sealed class PerformanceAnomaly {
  const PerformanceAnomaly({
    required this.id,
    required this.timestamp,
    required this.severity,
    this.screen,
    this.interactionId,
    Map<String, Object?>? metadata,
  }) : metadata = metadata ?? const <String, Object?>{};

  /// Local correlation identifier unique within this PerfScope session.
  final String id;

  /// Wall-clock time at which the anomaly was detected.
  final DateTime timestamp;

  /// Qualitative seriousness of the anomaly.
  final AnomalySeverity severity;

  /// Screen name captured when the anomalous record started, if known.
  ///
  /// Temporal correlation only: the screen being visible does not imply
  /// it caused the anomaly.
  final String? screen;

  /// Interaction id active when the anomalous record started, if any.
  ///
  /// Temporal correlation only: co-occurrence is not causation.
  final String? interactionId;

  /// Caller-supplied context attached to the anomalous record.
  final Map<String, Object?> metadata;
}
