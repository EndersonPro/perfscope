import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

import '../helpers/event_fixtures.dart';

/// Sink accepting only anomaly events — proves CompositeSink honors
/// per-sink filtering.
class AnomaliesOnlySink
    with SinkAcceptsAllMixin
    implements PerformanceEventSink {
  final List<PerformanceEvent> received = <PerformanceEvent>[];

  @override
  bool accepts(covariant PerformanceEvent event) => event is AnomalyEvent;

  @override
  void add(covariant PerformanceEvent event) => received.add(event);
}

/// Sink that always throws — proves CompositeSink isolates failures.
class ExplodingSink with SinkAcceptsAllMixin implements PerformanceEventSink {
  @override
  bool accepts(covariant PerformanceEvent event) => true;

  @override
  void add(covariant PerformanceEvent event) =>
      throw StateError('sink exploded');
}

/// Plain recording sink.
class RecordingSink with SinkAcceptsAllMixin implements PerformanceEventSink {
  final List<PerformanceEvent> received = <PerformanceEvent>[];

  @override
  void add(covariant PerformanceEvent event) => received.add(event);
}

void main() {
  group('MemorySink', () {
    test('stores raw events chronologically and drops oldest when full', () {
      final sink = MemorySink(capacity: 3);
      expect(sink.capacity, 3);

      for (var i = 1; i <= 5; i++) {
        sink.add(anomalyEvent(uiBoundAnomaly(id: 'anm_$i'), id: 'evt_$i'));
      }

      expect(sink.length, 3);
      expect(
        sink.events.map((e) => e.id).toList(),
        <String>['evt_3', 'evt_4', 'evt_5'],
      );
    });

    test('clear() empties the buffer', () {
      final sink = MemorySink();
      sink.add(anomalyEvent(uiBoundAnomaly()));
      expect(sink.events, isNotEmpty);

      sink.clear();
      expect(sink.events, isEmpty);
      expect(sink.length, 0);
    });

    test('default capacity is bounded', () {
      expect(MemorySink().capacity, defaultMemorySinkCapacity);
    });
  });

  group('CompositeSink', () {
    test('honors accepts() filters per child', () {
      final filtered = AnomaliesOnlySink();
      final all = RecordingSink();
      final composite = CompositeSink(<PerformanceEventSink>[filtered, all]);

      composite.add(frameEvent(frameSample()));
      composite.add(anomalyEvent(uiBoundAnomaly()));

      // Filtered child only saw the anomaly.
      expect(filtered.received, hasLength(1));
      expect(filtered.received.single, isA<AnomalyEvent>());
      // Accept-all child saw both.
      expect(all.received, hasLength(2));
    });

    test('isolates a throwing sink so siblings still receive events', () {
      final recorder = RecordingSink();
      final composite = CompositeSink(<PerformanceEventSink>[
        ExplodingSink(),
        recorder,
      ]);

      expect(
        () => composite.add(anomalyEvent(uiBoundAnomaly())),
        returnsNormally,
      );
      expect(recorder.received, hasLength(1));
    });
  });

  group('JsonSink', () {
    test('produces NDJSON lines in the injected writer', () {
      final writer = MemoryLogWriter();
      final sink = JsonSink(
        writer: writer,
        sessionIdResolver: () => 'ses_ndjson',
      );

      sink.add(anomalyEvent(uiBoundAnomaly()));
      sink.add(anomalyEvent(longTraceAnomaly()));

      expect(writer.lines, hasLength(2));
      for (final line in writer.lines) {
        expect(line.endsWith('\n'), isTrue);
        final body = line.substring(0, line.length - 1);
        expect(body.contains('\n'), isFalse);
        expect(body.startsWith('{"schema_version":1'), isTrue);
      }
      expect(writer.lines.first, contains('"performance_anomaly"'));
    });

    test('suppresses non-anomaly events by default', () {
      final writer = MemoryLogWriter();
      JsonSink(writer: writer).add(frameEvent(frameSample()));
      expect(writer.lines, isEmpty);
    });
  });

  group('ConsoleSink', () {
    test('renders through injected renderer into injected writer', () {
      final writer = MemoryLogWriter();
      final sink = ConsoleSink(
        renderer: const CompactRenderer(),
        writer: writer,
      );

      sink.add(anomalyEvent(uiBoundAnomaly()));
      expect(writer.lines, hasLength(1));
      expect(writer.lines.single, contains('PERF ProductList'));
    });
  });
}
