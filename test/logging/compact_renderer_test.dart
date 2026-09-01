import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

import '../helpers/event_fixtures.dart';

void main() {
  group('CompactRenderer', () {
    const renderer = CompactRenderer();

    test('renders the exact canonical one-liner', () {
      final line = renderer.render(anomalyEvent(uiBoundAnomaly()));
      expect(
        line,
        'PERF ProductList | UI 27.4ms | Raster 4.8ms | Total 33.1ms '
        '| Budget 16.7ms | HIGH ui-bound',
      );
    });

    test('omits screen segment without leading separator when null', () {
      final anomaly = uiBoundAnomaly(sample: frameSample(screen: null));
      final line = renderer.render(anomalyEvent(anomaly));
      expect(
        line,
        'PERF UI 27.4ms | Raster 4.8ms | Total 33.1ms | Budget 16.7ms '
        '| HIGH ui-bound',
      );
    });

    test('LongTrace variant uses TRACE layout', () {
      final line = renderer.render(anomalyEvent(longTraceAnomaly()));
      expect(line, 'PERF TRACE calculate_prices | 127.0ms | HIGH');
    });

    test('severity text is uppercase for every tier', () {
      for (final severity in AnomalySeverity.values) {
        final line =
            renderer.render(anomalyEvent(uiBoundAnomaly(severity: severity)));
        expect(line, contains(severity.name.toUpperCase()));
      }
    });

    test('bottleneck slugs cover all phases', () {
      void slugFor(FrameBottleneck bottleneck, String expected) {
        final classification = FrameClassification(
          FrameSeverity.slow,
          bottleneck,
        );
        final anomaly = UiBoundFrameAnomaly(
          id: 'a',
          timestamp: fixedTime,
          severity: AnomalySeverity.high,
          sample: frameSample(),
          classification: classification,
          frameBudget: budget60,
        );
        // Rebuild through the concrete subclass matching the bottleneck.
        final rebuilt = switch (bottleneck) {
          FrameBottleneck.raster => RasterBoundFrameAnomaly(
              id: 'a',
              timestamp: fixedTime,
              severity: AnomalySeverity.high,
              sample: frameSample(),
              classification: classification,
              frameBudget: budget60,
            ),
          FrameBottleneck.mixed => MixedFrameAnomaly(
              id: 'a',
              timestamp: fixedTime,
              severity: AnomalySeverity.high,
              sample: frameSample(),
              classification: classification,
              frameBudget: budget60,
            ),
          FrameBottleneck.unknown => SlowFrameAnomaly(
              id: 'a',
              timestamp: fixedTime,
              severity: AnomalySeverity.high,
              sample: frameSample(),
              classification: classification,
              frameBudget: budget60,
            ),
          _ => anomaly,
        };
        final line = renderer.render(anomalyEvent(rebuilt));
        expect(line, endsWith(expected));
      }

      slugFor(FrameBottleneck.ui, 'HIGH ui-bound');
      slugFor(FrameBottleneck.raster, 'HIGH raster-bound');
      slugFor(FrameBottleneck.mixed, 'HIGH mixed');
      slugFor(FrameBottleneck.unknown, 'HIGH slow');
    });

    test('warning-tier frame events render with WARNING label', () {
      // 20 ms total on a 16.667 ms budget: warning tier (~1.2x); build and
      // raster are comparable, so the bottleneck resolves to mixed.
      final sample = frameSample(
        id: 9,
        build: const Duration(microseconds: 12000),
        raster: const Duration(microseconds: 8000),
        total: const Duration(microseconds: 20000),
        screen: 'Home',
        interactionId: null,
      );
      final event =
          FrameEvent(id: 'evt_w1', timestamp: fixedTime, sample: sample);
      expect(
        renderer.render(event),
        'PERF Home | MIXED 12.0ms | Raster 8.0ms | Total 20.0ms '
        '| Budget 16.7ms | WARNING mixed',
      );
    });

    test('non-warning frame events yield null (anomalies own slow/severe)', () {
      // Normal frame: well within budget.
      final normal = frameEvent(frameSample(
        id: 3,
        build: const Duration(milliseconds: 3),
        raster: const Duration(milliseconds: 5),
        total: const Duration(milliseconds: 8),
      ));
      expect(renderer.render(normal), isNull);
    });
  });
}
