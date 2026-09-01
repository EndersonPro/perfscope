import 'package:flutter/foundation.dart' show debugPrint;

import '../events/performance_event.dart';
import '../logging/event_renderer.dart';
import '../logging/json_renderer.dart';
import '../logging/log_writer.dart';
import 'performance_event_sink.dart';

/// Sink that writes one JSON line per event (NDJSON) through a
/// [LogWriter].
///
/// Each accepted event renders via [JsonRenderer] into a single-line JSON
/// object terminated by one newline — directly consumable by log
/// collectors and structured-log pipelines.
final class JsonSink with SinkAcceptsAllMixin implements PerformanceEventSink {
  /// Creates an NDJSON sink. Pass [sessionIdResolver] so envelopes can
  /// carry the active session id; pass a custom [renderer] to override the
  /// envelope shape in tests.
  JsonSink({
    required this.writer,
    String? Function()? sessionIdResolver,
    EventRenderer? renderer,
  }) : _renderer = renderer ??
            JsonRenderer(
              sessionIdResolver: sessionIdResolver,
            );

  /// Destination for rendered NDJSON lines.
  final LogWriter writer;

  final EventRenderer _renderer;

  @override
  void add(covariant PerformanceEvent event) {
    try {
      final line = _renderer.render(event);
      if (line == null || line.isEmpty) {
        return;
      }
      writer.write('$line\n');
    } catch (error) {
      debugPrint('[PerfScope] sink error: $error');
    }
  }
}
