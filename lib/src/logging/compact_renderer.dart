/// Terse single-line renderer (compact style).
///
/// Renders anomalies and warning-tier frame events only; everything else
/// yields null. Visibility gating for normal frames lives in
/// [PerformanceLogger], not here.
///
/// Format (1-decimal milliseconds, ` | ` separators):
/// ```
/// PERF ProductList | UI 27.4ms | Raster 4.8ms | Total 33.1ms | Budget 16.7ms | HIGH ui-bound
/// ```
/// The screen segment is omitted entirely — including its separator — when
/// unknown. Long-trace anomaly variant:
/// ```
/// PERF TRACE calculate_prices | 127.0ms | HIGH
/// ```
library;

import '../anomalies/performance_anomaly.dart';
import '../events/performance_event.dart';
import '../frames/frame_classifier.dart';
import '../frames/frame_sample.dart';
import 'event_renderer.dart';

/// Renders anomalies and warnings as one-liners.
final class CompactRenderer implements EventRenderer {
  /// Creates a renderer.
  ///
  /// [classifier] re-derives the tier of raw frame events so warnings can
  /// be rendered without carrying extra state on the event itself.
  /// [includeNormalFrames] additionally lets NORMAL-tier frame events
  /// through as `'NORMAL'` lines — wired by [PerformanceLogger] from its
  /// `printNormalFrames`/`verbose` flags; slow/severe frames always stay
  /// suppressed because their anomaly events own them.
  const CompactRenderer({
    this.classifier = const FrameClassifier(),
    this.includeNormalFrames = false,
  });

  /// Classifier used to tier [FrameEvent]s.
  final FrameClassifier classifier;

  /// Whether normal-tier frame events also render.
  final bool includeNormalFrames;

  @override
  String? render(PerformanceEvent event) {
    return switch (event) {
      AnomalyEvent(:final anomaly) => switch (anomaly) {
          LongTraceAnomaly() => _traceLine(anomaly),
          final FrameAnomaly frame => _frameLine(
              sample: frame.sample,
              severityLabel: anomaly.severity.name.toUpperCase(),
              bottleneck: frame.bottleneck,
            ),
        },
      final FrameEvent frameEvent => _frameEventLine(frameEvent),
      _ => null,
    };
  }

  String? _frameEventLine(FrameEvent event) {
    final classification = classifier.classify(event.sample);
    switch (classification.severity) {
      case FrameSeverity.warning:
      case FrameSeverity.normal:
        break;
      case FrameSeverity.slow:
      case FrameSeverity.severe:
        // Slow and severe frames surface through their own AnomalyEvents;
        // raw frame events never double-report them.
        return null;
    }
    if (classification.severity == FrameSeverity.normal &&
        !includeNormalFrames) {
      return null;
    }
    return _frameLine(
      sample: event.sample,
      severityLabel: classification.severity == FrameSeverity.warning
          ? 'WARNING'
          : 'NORMAL',
      bottleneck: classification.bottleneck,
    );
  }

  String _frameLine({
    required FrameSample sample,
    required String severityLabel,
    required FrameBottleneck bottleneck,
  }) {
    final segments = <String>[
      if (sample.screen != null) sample.screen!,
      '${_bottleneckToken(bottleneck)} '
          '${_ms(sample.buildDuration)}ms',
      'Raster ${_ms(sample.rasterDuration)}ms',
      'Total ${_ms(sample.totalDuration)}ms',
      'Budget ${_ms(sample.frameBudget)}ms',
      '$severityLabel ${_bottleneckSlug(bottleneck)}',
    ];
    return 'PERF ${segments.join(' | ')}';
  }

  String _traceLine(LongTraceAnomaly anomaly) =>
      'PERF TRACE ${anomaly.name} | ${_ms(anomaly.duration)}ms | '
      '${anomaly.severity.name.toUpperCase()}';

  /// Short uppercase token naming the probable phase.
  String _bottleneckToken(FrameBottleneck bottleneck) => switch (bottleneck) {
        FrameBottleneck.ui => 'UI',
        FrameBottleneck.raster => 'RASTER',
        FrameBottleneck.mixed => 'MIXED',
        FrameBottleneck.unknown => 'SLOW',
      };

  /// Lowercase slug appended after the severity label.
  String _bottleneckSlug(FrameBottleneck bottleneck) => switch (bottleneck) {
        FrameBottleneck.ui => 'ui-bound',
        FrameBottleneck.raster => 'raster-bound',
        FrameBottleneck.mixed => 'mixed',
        FrameBottleneck.unknown => 'slow',
      };

  /// Milliseconds with exactly 1 decimal place.
  String _ms(Duration duration) =>
      (duration.inMicroseconds / Duration.microsecondsPerMillisecond)
          .toStringAsFixed(1);
}
