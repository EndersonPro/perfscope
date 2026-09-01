/// Serializes a finished [PerformanceReport] into the PerfScope session
/// schema (version [kSchemaVersion], see `schema.dart` for every key).
///
/// Contract:
/// * Deterministic: identical reports always serialize to identical
///   strings — map insertion order is the canonical key order and no
///   clock, locale, or platform state is consulted.
/// * Lossless within the documented tolerance: millisecond doubles are
///   rounded to 3 decimals (integer microseconds ÷ 1000 is exact at that
///   precision); timestamps become ISO-8601 UTC strings.
/// * Context windows are OPT-IN via [SessionSerializer.serialize]'s
///   resolver parameter; only COMPLETE windows are embedded, pending ones
///   are skipped silently.
library;

import 'dart:convert';

import '../anomalies/frame_context_window.dart';
import '../anomalies/performance_anomaly.dart';
import '../frames/frame_sample.dart';
import '../reporting/interaction_summary.dart';
import '../reporting/performance_report.dart';
import '../reporting/screen_summary.dart';
import '../reporting/statistics.dart';
import '../sessions/performance_session.dart';
import '../traces/trace_tracker.dart';
import 'schema.dart';

/// Converts a [PerformanceReport] into the PerfScope JSON session shape.
final class SessionSerializer {
  /// Creates a serializer. Instances are stateless; a single const
  /// instance may be shared freely.
  const SessionSerializer();

  /// Builds the JSON-encodable document for [report].
  ///
  /// When [resolveContextWindow] is provided it is queried once per frame
  /// anomaly; a non-null COMPLETE window embeds its surrounding frames
  /// under the anomaly's `context_window` key, anything else (null or
  /// still-pending) contributes nothing.
  Map<String, Object?> serialize(
    PerformanceReport report, {
    FrameContextWindow? Function(String anomalyId)? resolveContextWindow,
  }) {
    final session = report.session;
    return <String, Object?>{
      kKeySchemaVersion: kSchemaVersion,
      kKeyGenerator: <String, Object?>{
        kKeyName: kGeneratorName,
        kKeyVersion: kGeneratorVersion,
      },
      kKeySession: _sessionEntry(session),
      kKeyEnvironment: <String, Object?>{
        kKeyPlatform: session.environment.platform,
        kKeyFrameBudgetFps: session.environment.frameBudgetFps,
        kKeyFrameBudgetMs: session.environment.frameBudgetMs,
        kKeyFrameBudgetSource: session.environment.frameBudgetSource.name,
      },
      kKeySummary: _summaryEntry(report.statistics),
      kKeyScreens: report.screens.map(_screenEntry).toList(),
      kKeyInteractions: report.interactions.map(_interactionEntry).toList(),
      kKeyTraces: report.traces.map(_traceEntry).toList(),
      kKeyAnomalies: report.anomalies
          .map((a) => _anomalyEntry(a, resolveContextWindow))
          .toList(),
    };
  }

  /// Single-line JSON encoding of [serialize] — deterministic because Dart
  /// maps preserve insertion order and [jsonEncode] follows it.
  String serializeToString(
    PerformanceReport report, {
    FrameContextWindow? Function(String anomalyId)? resolveContextWindow,
  }) =>
      jsonEncode(
        serialize(report, resolveContextWindow: resolveContextWindow),
      );

  Map<String, Object?> _sessionEntry(PerformanceSession session) =>
      <String, Object?>{
        kKeyId: session.id,
        if (session.name != null) kKeyName: session.name,
        kKeyStartedAt: _iso8601(session.startedAt),
        if (session.endedAt != null) kKeyEndedAt: _iso8601(session.endedAt!),
        kKeyMetadata: Map<String, Object?>.of(session.metadata),
      };

  Map<String, Object?> _summaryEntry(SessionStatistics stats) =>
      <String, Object?>{
        kKeyTotalFrames: stats.totalFrames,
        kKeyNormalFrames: stats.normalFrames,
        kKeyWarningFrames: stats.warningFrames,
        kKeySlowFrames: stats.slowFrames,
        kKeySevereFrames: stats.severeFrames,
        kKeySlowFrameRate: stats.slowFrameRate,
        kKeyAverageBuildMs: _round3(stats.averageBuildMs),
        kKeyAverageRasterMs: _round3(stats.averageRasterMs),
        kKeyAverageTotalMs: _round3(stats.averageTotalMs),
        kKeyP50Ms: _round3(stats.p50Ms),
        kKeyP90Ms: _round3(stats.p90Ms),
        kKeyP95Ms: _round3(stats.p95Ms),
        kKeyP99Ms: _round3(stats.p99Ms),
        kKeyWorstFrameMs: _round3(stats.worstFrameMs),
      };

  Map<String, Object?> _screenEntry(ScreenPerformanceSummary screen) =>
      <String, Object?>{
        kKeyName: screen.name,
        kKeyTotalFrames: screen.totalFrames,
        kKeySlowFrames: screen.slowFrames,
        kKeySevereFrames: screen.severeFrames,
        kKeyAnomalyCount: screen.anomalyCount,
        kKeySlowFrameRate: screen.slowFrameRate,
        kKeyP95Ms: _round3(screen.p95Ms),
        kKeyWorstMs: _round3(screen.worstMs),
        kKeyProbableBottleneck: screen.probableBottleneck.name,
      };

  Map<String, Object?> _interactionEntry(
    InteractionPerformanceSummary interaction,
  ) =>
      <String, Object?>{
        kKeyName: interaction.name,
        if (interaction.mostRecentInteractionId != null)
          kKeyMostRecentInteractionId: interaction.mostRecentInteractionId,
        kKeySpanCount: interaction.spanCount,
        kKeyFrameCount: interaction.frameCount,
        kKeyAnomalyCount: interaction.anomalyCount,
        kKeyTotalSpanDurationMs: _durationMs(interaction.totalSpanDuration),
        kKeyP95Ms: _round3(interaction.p95Ms),
        kKeyWorstMs: _round3(interaction.worstMs),
        kKeyProbableBottleneck: interaction.probableBottleneck.name,
      };

  Map<String, Object?> _traceEntry(CompletedTrace trace) => <String, Object?>{
        kKeyId: trace.id,
        kKeyName: trace.name,
        kKeyStartedAt: _iso8601(trace.startedAt),
        kKeyDurationMs: _durationMs(trace.duration),
        kKeyScreen: trace.screen,
        kKeyDidThrow: trace.didThrow,
      };

  /// Exhaustive switch over the sealed [PerformanceAnomaly] hierarchy so a
  /// new anomaly subtype fails to compile here instead of silently
  /// disappearing from serialized files.
  Map<String, Object?> _anomalyEntry(
    PerformanceAnomaly anomaly,
    FrameContextWindow? Function(String anomalyId)? resolveContextWindow,
  ) =>
      switch (anomaly) {
        final LongTraceAnomaly longTrace => _longTraceEntry(longTrace),
        final FrameAnomaly frameAnomaly =>
          _frameAnomalyEntry(frameAnomaly, resolveContextWindow),
      };

  Map<String, Object?> _longTraceEntry(LongTraceAnomaly anomaly) =>
      _anomalyHeader(anomaly, kAnomalyTypeLongTrace)
        ..addAll(<String, Object?>{
          kKeyTraceId: anomaly.traceId,
          kKeyName: anomaly.name,
          kKeyDurationMs: _durationMs(anomaly.duration),
        });

  Map<String, Object?> _frameAnomalyEntry(
    FrameAnomaly anomaly,
    FrameContextWindow? Function(String anomalyId)? resolveContextWindow,
  ) {
    final entry = _anomalyHeader(anomaly, _anomalyType(anomaly))
      ..addAll(<String, Object?>{
        kKeyFrame: <String, Object?>{
          kKeyBuildMs: _durationMs(anomaly.sample.buildDuration),
          kKeyRasterMs: _durationMs(anomaly.sample.rasterDuration),
          kKeyTotalMs: _durationMs(anomaly.sample.totalDuration),
          kKeyBudgetMs: _durationMs(anomaly.frameBudget),
        },
        kKeyProbableBottleneck: anomaly.bottleneck.name,
      });
    if (resolveContextWindow != null) {
      final window = resolveContextWindow(anomaly.id);
      // Pending windows are skipped silently: their after-frames are still
      // incomplete, so embedding them would freeze a half-told story.
      if (window != null && window.isComplete) {
        entry[kKeyContextWindow] = <String, Object?>{
          kKeyBefore: window.before.map(_contextFrameEntry).toList(),
          kKeyAfter: window.after.map(_contextFrameEntry).toList(),
        };
      }
    }
    return entry;
  }

  Map<String, Object?> _anomalyHeader(
    PerformanceAnomaly anomaly,
    String type,
  ) =>
      <String, Object?>{
        kKeyId: anomaly.id,
        kKeyType: type,
        kKeySeverity: anomaly.severity.name,
        kKeyTimestamp: _iso8601(anomaly.timestamp),
        if (anomaly.screen != null) kKeyScreen: anomaly.screen,
        if (anomaly.interactionId != null)
          kKeyInteractionId: anomaly.interactionId,
        kKeyMetadata: Map<String, Object?>.of(anomaly.metadata),
      };

  /// Maps every anomaly to its wire discriminator string.
  ///
  /// Covers every concrete anomaly declared by PerfScope. [FrameAnomaly]
  /// itself is deliberately open (not sealed), so the final case is a
  /// forward-compatibility catch-all: any future/foreign subclass
  /// serializes under the plain slow-frame shape instead of crashing.
  String _anomalyType(PerformanceAnomaly anomaly) => switch (anomaly) {
        LongTraceAnomaly() => kAnomalyTypeLongTrace,
        SlowFrameAnomaly() => kAnomalyTypeSlowFrame,
        UiBoundFrameAnomaly() => kAnomalyTypeUiBoundFrame,
        RasterBoundFrameAnomaly() => kAnomalyTypeRasterBoundFrame,
        MixedFrameAnomaly() => kAnomalyTypeMixedFrame,
        // Forward-compatibility catch-all for any other FrameAnomaly.
        FrameAnomaly() => kAnomalyTypeSlowFrame,
      };

  /// Compact per-frame entry used inside context windows.
  Map<String, Object?> _contextFrameEntry(FrameSample frame) =>
      <String, Object?>{
        kKeyBuildMs: _durationMs(frame.buildDuration),
        kKeyRasterMs: _durationMs(frame.rasterDuration),
        kKeyTotalMs: _durationMs(frame.totalDuration),
      };
}

/// ISO-8601 UTC timestamp string; always UTC so files compare byte-equal
/// regardless of the writer's local timezone.
String _iso8601(DateTime value) => value.toUtc().toIso8601String();

/// Milliseconds for an integer-microsecond [Duration]: dividing by 1000 IS
/// the correctly-rounded 3-decimal millisecond value.
double _durationMs(Duration duration) =>
    microsToMsRounded(duration.inMicroseconds);

/// Rounds an arbitrary double to 3 decimal places (half away from zero).
double _round3(double value) =>
    (value * Duration.microsecondsPerMillisecond).roundToDouble() /
    Duration.microsecondsPerMillisecond;
