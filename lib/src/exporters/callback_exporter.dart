/// [PerformanceExporter] that hands serialized JSON to a caller callback.
///
/// The simplest integration seam: apps decide where bytes go (logger,
/// database, network, share sheet) while PerfScope owns the schema.
library;

import 'dart:convert';

import '../anomalies/frame_context_window.dart' show FrameContextWindow;
import '../serialization/session_serializer.dart';
import '../sessions/performance_session.dart';
import 'performance_exporter.dart';

/// Serializes the session and passes the resulting JSON string to
/// [onJson].
///
/// With [pretty] enabled the JSON is indented for human inspection;
/// otherwise it is a single deterministic line. Pretty output is still
/// deterministic — same input, same bytes.
final class CallbackExporter implements PerformanceExporter {
  /// Creates an exporter invoking [onJson] once per export call.
  CallbackExporter({
    required void Function(String json) onJson,
    bool pretty = false,
  })  : _onJson = onJson,
        _encoder = pretty ? JsonEncoder.withIndent('  ') : const JsonEncoder();

  final void Function(String json) _onJson;
  final JsonEncoder _encoder;

  @override
  Future<void> export(
    PerformanceSession session, {
    FrameContextWindow? Function(String anomalyId)? resolveContextWindow,
  }) async {
    final json = _encoder.convert(
      const SessionSerializer().serialize(
        reportForExport(session),
        resolveContextWindow: resolveContextWindow,
      ),
    );
    _onJson(json);
  }
}
