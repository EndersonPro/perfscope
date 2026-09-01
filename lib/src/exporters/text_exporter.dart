/// [PerformanceExporter] producing human-readable summary text.
///
/// Uses the standalone [formatReportText] box formatter (same layout as
/// the pretty logger) so no logging configuration is required.
library;

import '../anomalies/frame_context_window.dart' show FrameContextWindow;
import '../sessions/performance_session.dart';
import 'performance_exporter.dart';
import 'text_report_formatter.dart';

/// Formats the session's report and passes the text block to [onText].
final class TextExporter implements PerformanceExporter {
  /// Creates an exporter invoking [onText] once per export call.
  TextExporter({required void Function(String text) onText}) : _onText = onText;

  final void Function(String text) _onText;

  @override
  Future<void> export(
    PerformanceSession session, {
    FrameContextWindow? Function(String anomalyId)? resolveContextWindow,
  }) async {
    // Context windows are a JSON-schema feature; the text box has no
    // section for them, so the resolver is intentionally unused here.
    _onText(formatReportText(reportForExport(session)));
  }
}
