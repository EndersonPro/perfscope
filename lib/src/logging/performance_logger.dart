import 'dart:convert';

import '../core/perfscope_config.dart';
import '../events/performance_event.dart';
import '../frames/frame_classifier.dart';
import '../reporting/performance_report.dart';
import 'compact_renderer.dart';
import 'event_renderer.dart';
import 'format_session_duration.dart' as duration_format;
import 'json_renderer.dart';
import 'log_box.dart';
import 'log_style.dart';
import 'log_writer.dart';
import 'pretty_renderer.dart';

/// Central output gate for PerfScope: turns engine events and session
/// reports into styled text and writes them through a single [LogWriter].
///
/// Responsibilities:
/// * Visibility policy per [PerfScopeLogStyle] plus the print flags:
///   - `silent` style suppresses everything unconditionally.
///   - Anomaly events require [printAnomalies] (or [verbose]).
///   - Frame events are tiered with a [FrameClassifier]: normal frames
///     follow [printNormalFrames], warning frames follow [printWarnings],
///     and slow/severe frames follow [printAnomalies] because those tiers
///     always surface again as anomaly events; [verbose] opens every gate.
///   - All other event types render only when [verbose].
/// * Delegates the actual text to the style-matching renderer; a null
///   render result suppresses the output.
/// * Newline contract: writers receive each rendered block WITHOUT a
///   trailing newline; [handleEvent] appends exactly one `\n` per block so
///   console/NDJSON consumers see clean line boundaries. Multi-line pretty
///   boxes therefore end with exactly one newline.
/// * Never throws into the caller: every failure inside logging is
///   swallowed by design.
final class PerformanceLogger {
  /// Creates a logger writing [style]-formatted text into [writer].
  PerformanceLogger({
    required PerfScopeLogStyle style,
    required LogWriter writer,
    this.printNormalFrames = false,
    this.printWarnings = false,
    this.printAnomalies = true,
    this.verbose = false,
    this.sessionIdResolver,
  })  : _style = style,
        _writer = writer,
        _classifier = const FrameClassifier(),
        _renderer = _buildRenderer(
          style: style,
          verbose: verbose,
          printNormalFrames: printNormalFrames,
          sessionIdResolver: sessionIdResolver,
        );

  final PerfScopeLogStyle _style;
  final LogWriter _writer;
  final FrameClassifier _classifier;
  final EventRenderer? _renderer;

  /// Whether frames classified as normal are printed.
  final bool printNormalFrames;

  /// Whether frames classified as warnings are printed.
  final bool printWarnings;

  /// Whether detected anomalies are printed.
  final bool printAnomalies;

  /// Whether verbose diagnostics are emitted (opens every visibility gate).
  final bool verbose;

  /// Returns the active session id for JSON envelopes, or null.
  final String? Function()? sessionIdResolver;

  static EventRenderer? _buildRenderer({
    required PerfScopeLogStyle style,
    required bool verbose,
    required bool printNormalFrames,
    required String? Function()? sessionIdResolver,
  }) {
    return switch (style) {
      PerfScopeLogStyle.silent => null,
      PerfScopeLogStyle.pretty => PrettyRenderer(verbose: verbose),
      PerfScopeLogStyle.compact => CompactRenderer(
          includeNormalFrames: printNormalFrames || verbose,
        ),
      PerfScopeLogStyle.json => JsonRenderer(
          sessionIdResolver: sessionIdResolver,
          printNormalEvents: printNormalFrames || verbose,
        ),
    };
  }

  /// Handles one event: decides visibility, renders it in the configured
  /// style, and writes the block plus one trailing newline. Never throws.
  void handleEvent(PerformanceEvent event) {
    try {
      if (_style == PerfScopeLogStyle.silent) {
        return;
      }
      if (!_isVisible(event)) {
        return;
      }
      final rendered = _renderer?.render(event);
      if (rendered == null || rendered.isEmpty) {
        return;
      }
      // Exactly one newline appended per rendered block; see class docs.
      _writer.write('$rendered\n');
    } catch (_) {
      // Logging must never break the host application.
    }
  }

  bool _isVisible(PerformanceEvent event) {
    if (verbose) {
      return true;
    }
    return switch (event) {
      AnomalyEvent() => printAnomalies,
      FrameEvent(:final sample) => switch (
            _classifier.classify(sample).severity) {
          FrameSeverity.normal => printNormalFrames,
          FrameSeverity.warning => printWarnings,
          FrameSeverity.slow || FrameSeverity.severe => printAnomalies,
        },
      _ => false,
    };
  }

  /// Renders [report] for the active style WITHOUT a trailing newline.
  ///
  /// Returns '' for the silent style; a full summary box for pretty; and a
  /// compact / JSON one-liner for the remaining styles.
  String renderReport(PerformanceReport report) {
    try {
      return switch (_style) {
        PerfScopeLogStyle.silent => '',
        PerfScopeLogStyle.pretty => _prettyReport(report),
        PerfScopeLogStyle.compact => _compactReport(report),
        PerfScopeLogStyle.json => jsonEncode(_reportMap(report)),
      };
    } catch (_) {
      // Report rendering failures stay contained like every other path.
      return '';
    }
  }

  Duration _reportDuration(PerformanceReport report) =>
      (report.session.endedAt ?? report.session.startedAt)
          .difference(report.session.startedAt);

  // ---------------------------------------------------------------------------
  // Pretty session summary
  // ---------------------------------------------------------------------------

  String _prettyReport(PerformanceReport report) {
    final stats = report.statistics;
    return joinLines(<String>[
      boxTop(),
      boxRow('PerfScope — Session Summary'),
      boxSeparator(),
      _summaryRow(
        'Duration',
        formatSessionDuration(_reportDuration(report)),
      ),
      _summaryRow('Frames', '${stats.totalFrames}'),
      _summaryRow('Slow frames', '${stats.slowFrames}'),
      _summaryRow('Severe frames', '${stats.severeFrames}'),
      _summaryRow(
        'Slow-frame rate',
        '${(stats.slowFrameRate * 100).toStringAsFixed(2)}%',
      ),
      _summaryRow(
        'Worst frame',
        '${stats.worstFrameMs.toStringAsFixed(1)} ms',
      ),
      boxRow(''),
      _summaryRow('p50', '${stats.p50Ms.toStringAsFixed(1)} ms'),
      _summaryRow('p90', '${stats.p90Ms.toStringAsFixed(1)} ms'),
      _summaryRow('p95', '${stats.p95Ms.toStringAsFixed(1)} ms'),
      _summaryRow('p99', '${stats.p99Ms.toStringAsFixed(1)} ms'),
      boxBottom(),
    ]);
  }

  /// Label left-aligned in a 20-character column, value right-aligned in
  /// the following 12 characters before the closing padding.
  String _summaryRow(String label, String value) =>
      boxRow('${padRightTo(label, 20)}${value.padLeft(12)}');

  // ---------------------------------------------------------------------------
  // Compact + JSON summaries
  // ---------------------------------------------------------------------------

  String _compactReport(PerformanceReport report) {
    final stats = report.statistics;
    return 'PERF SESSION '
        '${formatSessionDuration(_reportDuration(report))}'
        ' | frames ${stats.totalFrames}'
        ' | slow-rate ${(stats.slowFrameRate * 100).toStringAsFixed(2)}%'
        ' | worst ${stats.worstFrameMs.toStringAsFixed(1)}ms'
        ' | p95 ${stats.p95Ms.toStringAsFixed(1)}ms';
  }

  Map<String, Object?> _reportMap(PerformanceReport report) {
    final stats = report.statistics;
    return <String, Object?>{
      'schema_version': 1,
      'type': 'performance_summary',
      'session_id': report.session.id,
      'duration_ms': _reportDuration(report).inMicroseconds /
          Duration.microsecondsPerMillisecond,
      'frames': stats.totalFrames,
      'slow_frames': stats.slowFrames,
      'severe_frames': stats.severeFrames,
      'slow_frame_rate': stats.slowFrameRate,
      'worst_frame_ms': stats.worstFrameMs,
      'p50_ms': stats.p50Ms,
      'p90_ms': stats.p90Ms,
      'p95_ms': stats.p95Ms,
      'p99_ms': stats.p99Ms,
    };
  }

  // ---------------------------------------------------------------------------
  // Pure formatting helpers
  // ---------------------------------------------------------------------------

  /// Formats a session duration deterministically, delegating to the
  /// shared pure implementation in `format_session_duration.dart`
  /// (`'42ms'`, `'0.9s'`, `'4m 32s'`).
  static String formatSessionDuration(Duration duration) =>
      duration_format.formatSessionDuration(duration);
}
