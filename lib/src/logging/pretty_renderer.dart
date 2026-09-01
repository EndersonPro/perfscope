/// Box-drawing renderer for anomaly events (pretty style).
///
/// Renders ONLY [AnomalyEvent]s as a fixed-width card; every other event
/// yields null unless constructed with [verbose], in which case frame
/// events additionally render as a compact frame card. All remaining
/// non-anomaly event types stay suppressed even when verbose.
///
/// Layout rules are defined in `log_box.dart`: 58-character inner width,
/// 14-character label column, `'X.XXX ms'` values right-aligned in a
/// 9-character field, and `Screen` / `Interaction` rows omitted entirely
/// when unknown.
///
/// [LongTraceAnomaly] replaces the frame-phase rows with a single
/// `Duration` row plus a `Trace` row carrying the trace name.
library;

import '../anomalies/performance_anomaly.dart';
import '../events/performance_event.dart';
import '../frames/frame_classifier.dart';
import 'event_renderer.dart';
import 'log_box.dart';

/// Renders anomalies as human-friendly box-drawing cards.
final class PrettyRenderer implements EventRenderer {
  /// Creates a renderer. [verbose] additionally lets [FrameEvent]s through
  /// as frame cards.
  const PrettyRenderer({this.verbose = false});

  /// Whether non-anomaly frame events are also rendered.
  final bool verbose;

  @override
  String? render(PerformanceEvent event) {
    return switch (event) {
      AnomalyEvent(:final anomaly) => _anomalyCard(anomaly),
      FrameEvent() when verbose => _frameCard(event),
      _ => null,
    };
  }

  // ---------------------------------------------------------------------------
  // Anomaly card
  // ---------------------------------------------------------------------------

  String _anomalyCard(PerformanceAnomaly anomaly) {
    final rows = <String>[
      ..._contextRows(anomaly),
      '',
      ...switch (anomaly) {
        LongTraceAnomaly(:final name, :final duration) => <String>[
            kvText('Trace', name),
            kvMs('Duration', duration),
          ],
        final FrameAnomaly frame => <String>[
            kvMs('Build', frame.sample.buildDuration),
            kvMs('Raster', frame.sample.rasterDuration),
            kvMs('Total', frame.sample.totalDuration),
            kvMs('Budget', frame.frameBudget),
          ],
      },
      '',
      kvText('Severity', anomaly.severity.name.toUpperCase()),
      kvText('Type', _typeName(anomaly)),
      kvText('Probable', _probable(anomaly)),
    ];
    return _card('PerfScope — Performance anomaly', rows);
  }

  /// Screen/interaction attribution rows; each omitted when unknown.
  List<String> _contextRows(PerformanceAnomaly anomaly) => [
        if (anomaly.screen != null) kvText('Screen', anomaly.screen!),
        if (anomaly.interactionId != null)
          kvText('Interaction', anomaly.interactionId!),
      ];

  String _typeName(PerformanceAnomaly anomaly) => switch (anomaly) {
        LongTraceAnomaly() => 'LongTrace',
        final FrameAnomaly frame => switch (frame) {
            SlowFrameAnomaly() => 'SlowFrame',
            UiBoundFrameAnomaly() => 'UiBoundFrame',
            RasterBoundFrameAnomaly() => 'RasterFrame',
            MixedFrameAnomaly() => 'MixedFrame',
            // Unreachable today; kept because FrameAnomaly is not sealed.
            _ => 'SlowFrame',
          },
      };

  String _probable(PerformanceAnomaly anomaly) => switch (anomaly) {
        LongTraceAnomaly() => 'trace',
        final FrameAnomaly frame => switch (frame.bottleneck) {
            FrameBottleneck.ui => 'UI',
            FrameBottleneck.raster => 'RASTER',
            FrameBottleneck.mixed => 'MIXED',
            FrameBottleneck.unknown => 'UNKNOWN',
          },
      };

  // ---------------------------------------------------------------------------
  // Verbose frame card
  // ---------------------------------------------------------------------------

  String _frameCard(FrameEvent event) {
    final sample = event.sample;
    final rows = <String>[
      if (sample.screen != null) kvText('Screen', sample.screen!),
      if (sample.interactionId != null)
        kvText('Interaction', sample.interactionId!),
      '',
      kvMs('Build', sample.buildDuration),
      kvMs('Raster', sample.rasterDuration),
      kvMs('Total', sample.totalDuration),
      kvMs('Budget', sample.frameBudget),
    ];
    return _card(
      'PerfScope — Frame #${sample.frameNumber ?? sample.id}',
      rows,
    );
  }

  // ---------------------------------------------------------------------------
  // Card assembly
  // ---------------------------------------------------------------------------

  /// Top border, title row, separator, content rows, bottom border — all
  /// joined with newlines, no trailing newline.
  String _card(String title, List<String> rows) => joinLines(<String>[
        boxTop(),
        boxRow(title),
        boxSeparator(),
        for (final row in rows) boxRow(row),
        boxBottom(),
      ]);
}
