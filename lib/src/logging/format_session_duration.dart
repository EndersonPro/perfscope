/// Pure session-duration rendering shared by the logging package and
/// the offline CLI.
///
/// Kept free of Flutter imports on purpose: `text_report_formatter` and
/// the CLI compile graph must stay importable without the framework.
library;

/// Formats a session [duration] for compact display:
///
/// * below 100 ms → whole milliseconds (`'450ms'` style, e.g. `'42ms'`);
/// * below 1 s → one-decimal seconds (`'0.9s'`);
/// * otherwise → `'Xm YYs'` with zero-padded seconds (`'0m 05s'`,
///   `'4m 32s'`).
String formatSessionDuration(Duration duration) {
  if (duration.inMilliseconds < 100) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inMilliseconds < Duration.millisecondsPerSecond) {
    return '${(duration.inMilliseconds / Duration.millisecondsPerSecond).toStringAsFixed(1)}s';
  }
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % Duration.secondsPerMinute;
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}
