/// Standalone deterministic text formatter for [PerformanceReport] values.
///
/// Mirrors the pretty session-summary box of [PerformanceLogger] without
/// depending on it, so exporters can produce human-readable output with no
/// logger/style configuration in scope. Pure string math: no clock, no IO.
library;

import '../logging/format_session_duration.dart' show formatSessionDuration;
import '../logging/log_box.dart';
import '../reporting/performance_report.dart';

/// Formats [report] as a fixed-width summary box (same layout contract as
/// the logging package's pretty renderer).
String formatReportText(PerformanceReport report) {
  final stats = report.statistics;
  final duration = (report.session.endedAt ?? report.session.startedAt)
      .difference(report.session.startedAt);
  String row(String label, String value) =>
      boxRow('${padRightTo(label, 20)}${value.padLeft(12)}');
  return joinLines(<String>[
    boxTop(),
    boxRow('PerfScope — Session Summary'),
    boxSeparator(),
    row('Session', report.session.id),
    row(
      'Duration',
      formatSessionDuration(duration),
    ),
    row('Frames', '${stats.totalFrames}'),
    row('Slow frames', '${stats.slowFrames}'),
    row('Severe frames', '${stats.severeFrames}'),
    row(
      'Slow-frame rate',
      '${(stats.slowFrameRate * 100).toStringAsFixed(2)}%',
    ),
    row('Worst frame', '${stats.worstFrameMs.toStringAsFixed(1)} ms'),
    boxRow(''),
    row('p50', '${stats.p50Ms.toStringAsFixed(1)} ms'),
    row('p90', '${stats.p90Ms.toStringAsFixed(1)} ms'),
    row('p95', '${stats.p95Ms.toStringAsFixed(1)} ms'),
    row('p99', '${stats.p99Ms.toStringAsFixed(1)} ms'),
    boxBottom(),
  ]);
}
