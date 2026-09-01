import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

/// Deterministic fixed timestamp — no real clock involved.
final _startedAt = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

CompletedTrace _trace(String id,
    {bool didThrow = false, Duration duration = const Duration(seconds: 1)}) {
  return CompletedTrace(
    id: id,
    name: 'op_$id',
    startedAt: _startedAt,
    duration: duration,
    screen: 'home',
    didThrow: didThrow,
    metadata: <String, Object?>{'id': id},
  );
}

void main() {
  group('TraceTracker', () {
    test('default capacity matches the documented bound', () {
      expect(TraceTracker().capacity, maxStoredTraces);
      expect(maxStoredTraces, 500);
    });

    test('starts empty and preserves chronological order', () {
      final tracker = TraceTracker();

      expect(tracker.traces, isEmpty);

      tracker.record(_trace('trc_1'));
      tracker.record(_trace('trc_2'));

      expect(tracker.traces.length, 2);
      expect(tracker.traces.map((t) => t.id).toList(), ['trc_1', 'trc_2']);
    });

    test('overflow drops the oldest traces first (injected capacity)', () {
      final tracker = TraceTracker(capacity: 3);
      for (var i = 1; i <= 5; i++) {
        tracker.record(_trace('trc_$i'));
      }

      expect(tracker.capacity, 3);
      expect(tracker.traces.map((t) => t.id).toList(),
          ['trc_3', 'trc_4', 'trc_5']);
    });

    test('clear empties the store but keeps capacity', () {
      final tracker = TraceTracker(capacity: 2);
      tracker.record(_trace('trc_1'));

      tracker.clear();

      expect(tracker.traces, isEmpty);
      expect(tracker.capacity, 2);
    });

    test('stored records are immutable snapshots of what was recorded', () {
      final tracker = TraceTracker();
      final metadata = <String, Object?>{'k': 'v'};
      final trace = CompletedTrace(
        id: 'trc_1',
        name: 'op',
        startedAt: _startedAt,
        duration: const Duration(milliseconds: 10),
        screen: 'home',
        didThrow: true,
        metadata: metadata,
      );

      tracker.record(trace);
      metadata['k'] = 'mutated';

      // CompletedTrace copies caller maps defensively at construction.
      expect(tracker.traces.single.metadata, {'k': 'v'});
      expect(tracker.traces.single.didThrow, isTrue);
    });
  });
}
