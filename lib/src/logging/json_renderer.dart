/// One-line NDJSON renderer (json style).
///
/// Emits exactly one compact JSON object per event using an ordered
/// [Map] serialized with [jsonEncode] — insertion order is preserved by
/// Dart maps, so key order in the output matches the envelope spec:
///
/// ```json
/// {"schema_version":1,"type":"performance_anomaly","anomaly_type":"ui_bound_frame","event_id":"evt_1","session_id":"ses_1","timestamp":"2026-01-01T00:00:00.000Z","screen":"ProductList","interaction_id":"int_1","frame":{"build_ms":27.4,"raster_ms":4.8,"total_ms":33.1,"budget_ms":16.67},"severity":"high","probable_bottleneck":"ui"}
/// ```
///
/// Contract details:
/// * `session_id` comes from the injected [sessionIdResolver]; the whole
///   key is omitted when the resolver is absent or returns null.
/// * `screen` / `interaction_id` keys are omitted when unknown.
/// * Frame anomalies carry a `frame` object; [LongTraceAnomaly] instead
///   carries `duration_ms` and `trace_name`, and omits
///   `probable_bottleneck`.
/// * Millisecond values use 1 decimal, except `budget_ms` which keeps the
///   raw double string of a value rounded to 2 decimals.
/// * Non-anomaly events yield null unless [printNormalEvents] is set, in
///   which case frame events render as `type:"frame"` envelopes.
library;

import 'dart:convert';

import '../anomalies/performance_anomaly.dart';
import '../events/performance_event.dart';
import 'event_renderer.dart';

/// Renders events as single-line JSON envelopes.
final class JsonRenderer implements EventRenderer {
  /// Creates a renderer.
  const JsonRenderer({
    this.sessionIdResolver,
    this.printNormalEvents = false,
  });

  /// Returns the active session id, or null when no session is open.
  final String? Function()? sessionIdResolver;

  /// Whether non-anomaly frame events also render (as `type:"frame"`).
  final bool printNormalEvents;

  @override
  String? render(PerformanceEvent event) {
    return switch (event) {
      AnomalyEvent(:final anomaly) => _anomalyLine(event, anomaly),
      FrameEvent() when printNormalEvents => _frameLine(event),
      _ => null,
    };
  }

  // ---------------------------------------------------------------------------
  // Anomaly envelope
  // ---------------------------------------------------------------------------

  String _anomalyLine(AnomalyEvent event, PerformanceAnomaly anomaly) {
    final map = <String, Object?>{
      'schema_version': 1,
      'type': 'performance_anomaly',
      'anomaly_type': _anomalyTypeName(anomaly),
      'event_id': event.id,
      if (_sessionId case final sessionId?) 'session_id': sessionId,
      'timestamp': _timestamp(event.timestamp),
      if (anomaly.screen case final screen?) 'screen': screen,
      if (anomaly.interactionId case final interactionId?)
        'interaction_id': interactionId,
      ..._measureFields(anomaly),
      'severity': anomaly.severity.name,
      if (anomaly case FrameAnomaly(:final bottleneck))
        'probable_bottleneck': bottleneck.name,
    };
    return _encode(map);
  }

  /// Frame measurements: a `frame` object for frame anomalies, duration
  /// fields for long traces.
  Map<String, Object?> _measureFields(PerformanceAnomaly anomaly) =>
      switch (anomaly) {
        LongTraceAnomaly(:final duration, :final name) => <String, Object?>{
            'duration_ms': _ms1(duration.inMicroseconds),
            'trace_name': name,
          },
        final FrameAnomaly frame => <String, Object?>{
            'frame': <String, Object?>{
              'build_ms': _ms1(frame.sample.buildDuration.inMicroseconds),
              'raster_ms': _ms1(frame.sample.rasterDuration.inMicroseconds),
              'total_ms': _ms1(frame.sample.totalDuration.inMicroseconds),
              'budget_ms': _round2(
                frame.frameBudget.inMicroseconds /
                    Duration.microsecondsPerMillisecond,
              ),
            },
          },
      };

  String _anomalyTypeName(PerformanceAnomaly anomaly) => switch (anomaly) {
        LongTraceAnomaly() => 'long_trace',
        final FrameAnomaly frame => switch (frame) {
            SlowFrameAnomaly() => 'slow_frame',
            UiBoundFrameAnomaly() => 'ui_bound_frame',
            RasterBoundFrameAnomaly() => 'raster_bound_frame',
            MixedFrameAnomaly() => 'mixed_frame',
            // Unreachable today: FrameAnomaly subclasses are fixed above,
            // but the class itself is not sealed so the compiler requires
            // a fallback for hypothetical future extensions.
            _ => 'slow_frame',
          },
      };

  // ---------------------------------------------------------------------------
  // Verbose-normal frame envelope
  // ---------------------------------------------------------------------------

  String _frameLine(FrameEvent event) {
    final sample = event.sample;
    final map = <String, Object?>{
      'schema_version': 1,
      'type': 'frame',
      'event_id': event.id,
      if (_sessionId case final sessionId?) 'session_id': sessionId,
      'timestamp': _timestamp(event.timestamp),
      if (sample.screen case final screen?) 'screen': screen,
      if (sample.interactionId case final interactionId?)
        'interaction_id': interactionId,
      'frame': <String, Object?>{
        'build_ms': _ms1(sample.buildDuration.inMicroseconds),
        'raster_ms': _ms1(sample.rasterDuration.inMicroseconds),
        'total_ms': _ms1(sample.totalDuration.inMicroseconds),
        'budget_ms': _round2(sample.frameBudget.inMicroseconds / 1000),
      },
    };
    return _encode(map);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String? get _sessionId => sessionIdResolver?.call();

  String _timestamp(DateTime timestamp) => timestamp.toUtc().toIso8601String();

  /// Microseconds → ms rounded to 1 decimal, as a JSON number.
  double _ms1(int micros) => _round1(micros / 1000);

  double _round1(double value) => (value * 10).roundToDouble() / 10;

  double _round2(double value) => (value * 100).roundToDouble() / 100;

  /// Serializes [map] to one compact line. [jsonEncode] escapes newlines
  /// inside strings and never emits raw ones between tokens, so the result
  /// is guaranteed single-line; the assert documents that invariant.
  String _encode(Map<String, Object?> map) {
    final line = jsonEncode(map);
    assert(!line.contains('\n'));
    return line;
  }
}
