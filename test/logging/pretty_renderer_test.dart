import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

import '../helpers/event_fixtures.dart';

/// Rebuilds one content line from the DOCUMENTED box contract:
/// `'│ ' + content padded to 56 + ' │'` — inner width 58.
String _line(String content) => '│ ${content.padRight(56)} │';

/// Full pretty card assembled in the test from hand-written row literals,
/// independent of renderer internals.
final String _expectedUiBoundCard = [
  '╭${'─' * 58}╮',
  _line('PerfScope — Performance anomaly'),
  '├${'─' * 58}┤',
  _line('Screen        ProductList'),
  _line('Interaction   product_list_scroll'),
  _line(''),
  _line('Build         27.400 ms'),
  _line('Raster         4.800 ms'),
  _line('Total         33.100 ms'),
  _line('Budget        16.667 ms'),
  _line(''),
  _line('Severity      HIGH'),
  _line('Type          UiBoundFrame'),
  _line('Probable      UI'),
  '╰${'─' * 58}╯',
].join('\n');

void main() {
  group('PrettyRenderer', () {
    test('renders the exact canonical UI-bound anomaly card', () {
      const renderer = PrettyRenderer();
      final output = renderer.render(anomalyEvent(uiBoundAnomaly()))!;
      expect(output, _expectedUiBoundCard);
    });

    test('every line has identical length and correct borders', () {
      final lines = const PrettyRenderer()
          .render(anomalyEvent(uiBoundAnomaly()))!
          .split('\n');
      expect(lines, hasLength(15));
      expect(lines.first, '╭${'─' * 58}╮');
      expect(lines[2], '├${'─' * 58}┤');
      expect(lines.last, '╰${'─' * 58}╯');
      for (final line in lines) {
        expect(line.length, 60, reason: 'line: $line');
      }
    });

    test('ms values are right-aligned within their field', () {
      final lines = const PrettyRenderer()
          .render(anomalyEvent(uiBoundAnomaly()))!
          .split('\n');
      // Build value starts at column 16 (bar + space + 14-char label
      // column): '27.400 ms' fills the whole 9-char field with no leading
      // pad; Raster's shorter value gets one leading space so both END at
      // the same column.
      expect(lines[6].indexOf('27.400'), 16);
      expect(lines[7].indexOf('4.800'), 17);
      expect(lines[8].indexOf('33.100'), 16);
      expect(lines[9].indexOf('16.667'), 16);
    });

    test('omits Interaction row when interactionId is null', () {
      final anomaly = uiBoundAnomaly(
        sample: frameSample(interactionId: null),
      );
      final output = const PrettyRenderer().render(anomalyEvent(anomaly))!;
      expect(output, contains('Screen        ProductList'));
      expect(output, isNot(contains('Interaction')));
      expect(output.split('\n'), hasLength(14));
    });

    test('omits Screen row when screen is null', () {
      final anomaly = uiBoundAnomaly(sample: frameSample(screen: null));
      final output = const PrettyRenderer().render(anomalyEvent(anomaly))!;
      expect(output, isNot(contains('Screen')));
      expect(output.split('\n'), hasLength(14));
    });

    test('LongTrace layout replaces frame phases with Trace/Duration', () {
      final output =
          const PrettyRenderer().render(anomalyEvent(longTraceAnomaly()))!;
      final lines = output.split('\n');
      expect(output, contains('Trace         calculate_prices'));
      expect(output, contains('Duration      127.000 ms'));
      expect(
        lines.singleWhere((l) => l.contains('Type')),
        contains('LongTrace'),
      );
      expect(
        lines.singleWhere((l) => l.contains('Probable')),
        contains('trace'),
      );
      // No frame-phase rows on trace cards. The fixture carries a screen
      // but no interaction id, so the Interaction row is omitted.
      expect(output, isNot(contains('Build')));
      expect(output, isNot(contains('Raster ')));
      expect(lines, hasLength(12));
    });

    test('severity text maps to uppercase enum names', () {
      String severityLine(AnomalySeverity severity) {
        final output = const PrettyRenderer()
            .render(anomalyEvent(uiBoundAnomaly(severity: severity)))!;
        return output.split('\n').singleWhere((l) => l.contains('Severity'));
      }

      expect(severityLine(AnomalySeverity.high), contains('HIGH'));
      expect(severityLine(AnomalySeverity.critical), contains('CRITICAL'));
      expect(severityLine(AnomalySeverity.medium), contains('MEDIUM'));
      expect(severityLine(AnomalySeverity.low), contains('LOW'));
    });

    test('probable bottleneck mapping covers all four phases', () {
      String probableLine(FrameBottleneck bottleneck) {
        final classification = FrameClassification(
          FrameSeverity.slow,
          bottleneck,
        );
        final anomaly = switch (bottleneck) {
          FrameBottleneck.ui => UiBoundFrameAnomaly(
              id: 'a',
              timestamp: fixedTime,
              severity: AnomalySeverity.high,
              sample: frameSample(),
              classification: classification,
              frameBudget: budget60,
            ),
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
        };
        final output = const PrettyRenderer().render(anomalyEvent(anomaly))!;
        return output.split('\n').singleWhere((l) => l.contains('Probable'));
      }

      expect(probableLine(FrameBottleneck.ui), contains(' UI'));
      expect(probableLine(FrameBottleneck.raster), contains(' RASTER'));
      expect(probableLine(FrameBottleneck.mixed), contains(' MIXED'));
      expect(probableLine(FrameBottleneck.unknown), contains(' UNKNOWN'));
    });

    test('suppresses non-anomaly events unless verbose', () {
      const renderer = PrettyRenderer();
      expect(renderer.render(frameEvent(frameSample())), isNull);

      final verboseOutput =
          const PrettyRenderer(verbose: true).render(frameEvent(
        frameSample(),
      ));
      expect(verboseOutput, isNotNull);
      expect(verboseOutput, contains('Total         33.100 ms'));
    });
  });
}
