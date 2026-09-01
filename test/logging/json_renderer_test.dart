import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

import '../helpers/event_fixtures.dart';

void main() {
  group('JsonRenderer', () {
    test('emits the full anomaly envelope with session id', () {
      const renderer = JsonRenderer(sessionIdResolver: _fixedSession);
      final line = renderer.render(anomalyEvent(uiBoundAnomaly()))!;

      expect(line.contains('\n'), isFalse);
      final map = jsonDecode(line) as Map<String, dynamic>;
      // Key ORDER follows the documented envelope.
      expect(map.keys.toList(), <String>[
        'schema_version',
        'type',
        'anomaly_type',
        'event_id',
        'session_id',
        'timestamp',
        'screen',
        'interaction_id',
        'frame',
        'severity',
        'probable_bottleneck',
      ]);
      expect(map['schema_version'], 1);
      expect(map['type'], 'performance_anomaly');
      expect(map['anomaly_type'], 'ui_bound_frame');
      expect(map['event_id'], 'evt_1');
      expect(map['session_id'], 'ses_fixed');
      expect(
        map['timestamp'],
        fixedTime.toUtc().toIso8601String(),
      );
      expect(map['screen'], 'ProductList');
      expect(map['interaction_id'], 'product_list_scroll');
      expect(map['severity'], 'high');
      expect(map['probable_bottleneck'], 'ui');

      final frame = map['frame'] as Map<String, dynamic>;
      expect(frame.keys.toList(),
          <String>['build_ms', 'raster_ms', 'total_ms', 'budget_ms']);
      expect(frame['build_ms'], 27.4);
      expect(frame['raster_ms'], 4.8);
      expect(frame['total_ms'], 33.1);
      // Budget keeps raw double toString of the 2-decimal rounding.
      expect(frame['budget_ms'], 16.67);
    });

    test('anomaly_type mapping table is complete', () {
      const renderer = JsonRenderer();
      String anomalyType(PerformanceAnomaly anomaly) =>
          (jsonDecode(renderer.render(anomalyEvent(anomaly))!)
              as Map)['anomaly_type'] as String;

      expect(
        anomalyType(SlowFrameAnomaly(
          id: 'a',
          timestamp: fixedTime,
          severity: AnomalySeverity.high,
          sample: frameSample(screen: null, interactionId: null),
          classification: const FrameClassification(
            FrameSeverity.slow,
            FrameBottleneck.unknown,
          ),
          frameBudget: budget60,
        )),
        'slow_frame',
      );
      expect(anomalyType(uiBoundAnomaly()), 'ui_bound_frame');
      expect(
        anomalyType(RasterBoundFrameAnomaly(
          id: 'a',
          timestamp: fixedTime,
          severity: AnomalySeverity.high,
          sample: frameSample(screen: null, interactionId: null),
          classification: const FrameClassification(
            FrameSeverity.slow,
            FrameBottleneck.raster,
          ),
          frameBudget: budget60,
        )),
        'raster_bound_frame',
      );
      expect(
        anomalyType(MixedFrameAnomaly(
          id: 'a',
          timestamp: fixedTime,
          severity: AnomalySeverity.high,
          sample: frameSample(screen: null, interactionId: null),
          classification: const FrameClassification(
            FrameSeverity.slow,
            FrameBottleneck.mixed,
          ),
          frameBudget: budget60,
        )),
        'mixed_frame',
      );
      expect(anomalyType(longTraceAnomaly()), 'long_trace');
    });

    test('omits session_id when resolver absent or returns null', () {
      const noResolver = JsonRenderer();
      final without = jsonDecode(
        noResolver.render(anomalyEvent(uiBoundAnomaly()))!,
      ) as Map<String, dynamic>;
      expect(without.containsKey('session_id'), isFalse);

      const nullResolver = JsonRenderer(sessionIdResolver: _nullSession);
      final withNull = jsonDecode(
        nullResolver.render(anomalyEvent(uiBoundAnomaly()))!,
      ) as Map<String, dynamic>;
      expect(withNull.containsKey('session_id'), isFalse);
    });

    test('long trace envelope carries duration instead of frame phases', () {
      const renderer = JsonRenderer(sessionIdResolver: _fixedSession);
      final map = jsonDecode(
        renderer.render(anomalyEvent(longTraceAnomaly()))!,
      ) as Map<String, dynamic>;

      expect(map.containsKey('frame'), isFalse);
      expect(map.containsKey('probable_bottleneck'), isFalse);
      expect(map['duration_ms'], 127.0);
      expect(map['trace_name'], 'calculate_prices');
      expect(map['screen'], 'Checkout');
      // Severity/probable mapping still present for traces via severity.
      expect(map['severity'], 'high');
    });

    test('suppresses non-anomaly events unless printNormalEvents', () {
      const renderer = JsonRenderer();
      expect(renderer.render(frameEvent(frameSample())), isNull);

      const verboseNormal = JsonRenderer(
          printNormalEvents: true, sessionIdResolver: _fixedSession);
      final line = verboseNormal.render(frameEvent(frameSample()))!;
      expect(line.contains('\n'), isFalse);
      final map = jsonDecode(line) as Map<String, dynamic>;
      expect(map['type'], 'frame');
      expect((map['frame'] as Map)['total_ms'], 33.1);
    });
  });
}

String _fixedSession() => 'ses_fixed';

String? _nullSession() => null;
