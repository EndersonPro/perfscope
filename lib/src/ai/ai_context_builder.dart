/// Pure rendering of a [PerformanceReport] into AI-ready context: one
/// token-optimized plain-text form and one compact structured form.
///
/// Both builders are PURE functions of the report plus config — no clock,
/// no IO, no engine. The only wall-clock value is `generated_at` in the
/// JSON shape, whose clock is injected via the `now` parameter so tests
/// stay deterministic.
///
/// Modeling limitations (deliberate, documented honesty over invention):
/// * Screen summaries carry no per-screen phase averages, so
///   `avg_build_ms` / `avg_raster_ms` lines are OMITTED from issue blocks
///   rather than approximated from session-wide numbers.
/// * Screen summaries carry no interaction attribution, so an
///   `interaction:` line is emitted for an issue only when an
///   [InteractionPerformanceSummary] with the SAME name as the screen
///   exists AND that interaction is the report's top-ranked interaction.
///   Anything smarter would require cross-attribution data the current
///   model does not hold.
library;

import '../frames/frame_classifier.dart' show FrameBottleneck;
import '../logging/format_session_duration.dart' show formatSessionDuration;
import '../reporting/interaction_summary.dart';
import '../reporting/performance_report.dart';
import '../reporting/screen_summary.dart';
import '../reporting/statistics.dart';
import 'ai_context_config.dart';

/// Schema version of the structured AI context output.
const int aiContextSchemaVersion = 1;

/// Marker appended when text output hits [AiContextConfig.maxChars].
const String _truncationMarker = '\n...[truncated]';

/// Renders [report] as compact, LLM-friendly plain text.
///
/// Shape (lines with absent data are omitted, never faked):
/// ```
/// PERFSCOPE_SESSION
///
/// name: checkout-performance
/// duration: 4m 32s
/// frames: 18421
/// slow_frames: 37
/// slow_frame_rate: 0.20%
///
/// p50_ms: 7.1
/// p95_ms: 14.4
/// p99_ms: 28.7
/// worst_frame_ms: 71.3
///
/// TOP_ISSUES:
///
/// 1:
/// screen: ProductList
/// anomalies: 12
/// worst_frame_ms: 46
/// p95_ms: 29
/// probable_bottleneck: UI
/// ```
///
/// Rates are percentages with two decimals; millisecond values use one
/// decimal but drop a trailing `.0` so whole numbers stay short. Output
/// never contains tabs or trailing whitespace and is hard-capped at
/// [AiContextConfig.maxChars] with a truncation marker.
String buildAiContextText(
  PerformanceReport report, {
  AiContextConfig config = const AiContextConfig(),
}) {
  final stats = report.statistics;
  final lines = <String>[
    'PERFSCOPE_SESSION',
    '',
    'name: ${report.session.name ?? '(unnamed)'}',
    if (report.session.endedAt != null)
      'duration: '
          '${formatSessionDuration(_sessionDuration(report))}',
    'frames: ${stats.totalFrames}',
    'slow_frames: ${stats.slowFrames + stats.severeFrames}',
    'slow_frame_rate: ${_formatPercent(stats.slowFrameRate)}',
    '',
    'p50_ms: ${_formatMs(stats.p50Ms)}',
    'p95_ms: ${_formatMs(stats.p95Ms)}',
    'p99_ms: ${_formatMs(stats.p99Ms)}',
    'worst_frame_ms: ${_formatMs(stats.worstFrameMs)}',
    '',
    'TOP_ISSUES:',
  ];

  if (config.includeScreens) {
    final topInteraction = _topInteraction(report,
        includeInteractions: config.includeInteractions);
    var rank = 0;
    for (final screen in report.screens) {
      if (rank >= config.maxTopIssues) break;
      rank++;
      lines
        ..add('')
        ..add('$rank:')
        ..add('screen: ${screen.name}');
      if (topInteraction != null && topInteraction.name == screen.name) {
        lines.add('interaction: ${screen.name}');
      }
      lines
        ..add('anomalies: ${screen.anomalyCount}')
        ..add('worst_frame_ms: ${_formatMs(screen.worstMs)}')
        ..add('p95_ms: ${_formatMs(screen.p95Ms)}')
        // avg_build_ms / avg_raster_ms intentionally omitted: per-screen
        // phase averages do not exist in the current model.
        ..add(
          'probable_bottleneck: ${_bottleneckLabel(screen.probableBottleneck)}',
        );
    }
  }

  return _capChars(lines.join('\n'), config.maxChars);
}

/// Renders [report] as a compact JSON-encodable map for AI consumption.
///
/// Top-level keys: `schema_version`, `kind`, `session`, `summary`,
/// `top_issues`, `traces`, `generated_at`. List lengths are capped by
/// [AiContextConfig.maxTopIssues] (issues) and
/// [AiContextConfig.maxAnomaliesListed] (traces). Null-valued optional
/// session fields (name, end time) are omitted instead of emitted as
/// nulls to keep payloads dense.
Map<String, Object?> buildAiContextJson(
  PerformanceReport report, {
  AiContextConfig config = const AiContextConfig(),
  DateTime Function()? now,
}) {
  final timestamp = (now ?? DateTime.now)().toUtc().toIso8601String();
  final session = report.session;
  final endedAt = session.endedAt;

  return <String, Object?>{
    'schema_version': aiContextSchemaVersion,
    'kind': 'ai_context',
    'session': <String, Object?>{
      'id': session.id,
      if (session.name != null) 'name': session.name,
      'started_at': session.startedAt.toUtc().toIso8601String(),
      if (endedAt != null) 'ended_at': endedAt.toUtc().toIso8601String(),
      if (endedAt != null)
        'duration_ms': _sessionDuration(report).inMilliseconds,
    },
    'summary': _statisticsJson(report.statistics),
    'top_issues': [
      if (config.includeScreens)
        for (final screen in report.screens.take(config.maxTopIssues))
          _screenIssueJson(screen, report,
              includeInteractions: config.includeInteractions),
    ],
    'traces': [
      if (config.includeTraces)
        for (final trace in report.traces.take(config.maxAnomaliesListed))
          <String, Object?>{
            'name': trace.name,
            'duration_ms': trace.duration.inMilliseconds,
            'screen': trace.screen,
            'did_throw': trace.didThrow,
          },
    ],
    'generated_at': timestamp,
  };
}

// -----------------------------------------------------------------------------
// Shared helpers (pure formatting; deterministic across runs).
// -----------------------------------------------------------------------------

Duration _sessionDuration(PerformanceReport report) {
  final endedAt = report.session.endedAt;
  if (endedAt == null) {
    return Duration.zero;
  }
  final duration = endedAt.difference(report.session.startedAt);
  return duration.isNegative ? Duration.zero : duration;
}

InteractionPerformanceSummary? _topInteraction(
  PerformanceReport report, {
  required bool includeInteractions,
}) {
  if (!includeInteractions || report.interactions.isEmpty) {
    return null;
  }
  // Limitation documented in the library docs: an interaction line is
  // merged into an issue ONLY on an exact name match with the single
  // top-ranked interaction — no richer attribution exists in the model.
  return report.interactions.first;
}

Map<String, Object?> _statisticsJson(SessionStatistics stats) =>
    <String, Object?>{
      'total_frames': stats.totalFrames,
      'normal_frames': stats.normalFrames,
      'warning_frames': stats.warningFrames,
      'slow_frames': stats.slowFrames,
      'severe_frames': stats.severeFrames,
      'slow_frame_rate': stats.slowFrameRate,
      'average_build_ms': stats.averageBuildMs,
      'average_raster_ms': stats.averageRasterMs,
      'average_total_ms': stats.averageTotalMs,
      'p50_ms': stats.p50Ms,
      'p90_ms': stats.p90Ms,
      'p95_ms': stats.p95Ms,
      'p99_ms': stats.p99Ms,
      'worst_frame_ms': stats.worstFrameMs,
    };

Map<String, Object?> _screenIssueJson(
  ScreenPerformanceSummary screen,
  PerformanceReport report, {
  required bool includeInteractions,
}) {
  final topInteraction = _topInteraction(
    report,
    includeInteractions: includeInteractions,
  );
  return <String, Object?>{
    'screen': screen.name,
    if (topInteraction != null && topInteraction.name == screen.name)
      'interaction': screen.name,
    'total_frames': screen.totalFrames,
    'slow_frames': screen.slowFrames,
    'severe_frames': screen.severeFrames,
    'anomaly_count': screen.anomalyCount,
    'slow_frame_rate': screen.slowFrameRate,
    'p95_ms': screen.p95Ms,
    'worst_ms': screen.worstMs,
    'probable_bottleneck': screen.probableBottleneck.name,
  };
}

/// Percentage with exactly two decimals (`0.0020086` → `'0.20%'`).
String _formatPercent(double fraction) =>
    '${(fraction * 100).toStringAsFixed(2)}%';

/// Milliseconds with one decimal, trailing `.0` stripped (`46.0` → `'46'`,
/// `71.34` → `'71.3'`).
String _formatMs(double ms) {
  final fixed = ms.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

/// Uppercase bottleneck label for the text format (`ui` → `'UI'`,
/// `unknown` → `'UNKNOWN'`).
String _bottleneckLabel(FrameBottleneck bottleneck) =>
    bottleneck.name.toUpperCase();

/// Hard cap with a graceful, visible truncation marker. Cuts back to the
/// last complete line inside the budget so the marker starts at column 0.
String _capChars(String text, int maxChars) {
  if (text.length <= maxChars) {
    return text;
  }
  final keep = maxChars - _truncationMarker.length;
  if (keep <= 0) {
    return _truncationMarker.trimLeft();
  }
  final cut = text.substring(0, keep);
  final lastNewline = cut.lastIndexOf('\n');
  final trimmed = lastNewline > 0 ? cut.substring(0, lastNewline) : cut;
  return '$trimmed$_truncationMarker';
}
