import 'package:flutter/foundation.dart' show debugPrint;

import '../events/performance_event.dart';
import '../logging/event_renderer.dart';
import '../logging/log_writer.dart';
import '../logging/pretty_renderer.dart';
import 'performance_event_sink.dart';

/// Sink that renders events with an [EventRenderer] and writes each
/// non-null block to a [LogWriter].
///
/// Defaults match the pretty console experience: [PrettyRenderer] plus
/// [ConsoleLogWriter]. Rendering failures are contained and reported via
/// [debugPrint].
final class ConsoleSink
    with SinkAcceptsAllMixin
    implements PerformanceEventSink {
  /// Creates a console sink over an optional custom renderer/writer pair.
  ConsoleSink({EventRenderer? renderer, LogWriter? writer})
      : _renderer = renderer ?? const PrettyRenderer(),
        _writer = writer ?? const ConsoleLogWriter();

  final EventRenderer _renderer;
  final LogWriter _writer;

  @override
  void add(covariant PerformanceEvent event) {
    try {
      final rendered = _renderer.render(event);
      if (rendered == null || rendered.isEmpty) {
        return;
      }
      // One trailing newline per rendered block; see PerformanceLogger's
      // newline contract.
      _writer.write('$rendered\n');
    } catch (error) {
      debugPrint('[PerfScope] sink error: $error');
    }
  }
}
