import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

/// Deterministic fixed timestamp — no real clock involved.
final _capturedAt = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

FrameSample _sample(int id) {
  return FrameSample(
    id: id,
    frameNumber: id,
    capturedAt: _capturedAt,
    buildDuration: const Duration(milliseconds: 3),
    rasterDuration: const Duration(milliseconds: 5),
    totalDuration: const Duration(milliseconds: 8),
    vsyncOverhead: Duration.zero,
    frameBudget: const Duration(microseconds: 16667),
    screen: null,
    interactionId: null,
  );
}

FrameContextWindow _open(
  FrameContextWindowCollector collector,
  String anomalyId, {
  List<FrameSample> before = const [],
  int afterCount = 3,
}) {
  return collector.open(anomalyId, _sample(999), before, afterCount);
}

void main() {
  group('FrameContextWindow', () {
    test('before keeps exactly the given frames (no padding)', () {
      final window = _open(
        FrameContextWindowCollector(),
        'anm_1',
        before: [_sample(1)],
        afterCount: 5,
      );

      expect(window.before.map((s) => s.id).toList(), [1]);
      expect(window.isComplete, isFalse);
      expect(window.after, isEmpty);
    });

    test('offer fills the after-window incrementally', () {
      final window =
          _open(FrameContextWindowCollector(), 'anm_1', afterCount: 2);

      window.offer(_sample(10));
      expect(window.isComplete, isFalse);
      expect(window.after.map((s) => s.id).toList(), [10]);

      window.offer(_sample(11));
      expect(window.isComplete, isTrue);
      expect(window.after.map((s) => s.id).toList(), [10, 11]);
    });

    test('after never exceeds the requested count', () {
      final window =
          _open(FrameContextWindowCollector(), 'anm_1', afterCount: 2);

      for (final id in [10, 11, 12, 13]) {
        window.offer(_sample(id));
      }

      expect(window.after.length, 2);
      expect(window.after.map((s) => s.id).toList(), [10, 11]);
    });

    test('the anomaly frame is excluded from its own after-window', () {
      final anomalySample = _sample(7);
      final window = FrameContextWindow(
        anomalyId: 'anm_1',
        before: const [],
        anomaly: anomalySample,
        afterCount: 2,
      );

      // The engine offers every processed frame, including the anomaly
      // frame itself; the window must ignore it.
      window.offer(anomalySample);
      expect(window.after, isEmpty);
      expect(window.isComplete, isFalse);
    });

    test('after snapshot is unmodifiable', () {
      final window =
          _open(FrameContextWindowCollector(), 'anm_1', afterCount: 1);
      window.offer(_sample(10));

      expect(() => window.after.add(_sample(99)), throwsUnsupportedError);
    });

    test('zero afterCount completes immediately', () {
      final window =
          _open(FrameContextWindowCollector(), 'anm_1', afterCount: 0);

      expect(window.isComplete, isTrue);
    });
  });

  group('FrameContextWindowCollector', () {
    test('windowFor finds pending windows', () {
      final collector = FrameContextWindowCollector();

      final window = _open(collector, 'anm_1', afterCount: 3);

      expect(identical(collector.windowFor('anm_1'), window), isTrue);
      expect(collector.windowFor('anm_missing'), isNull);
    });

    test('windowFor finds completed windows', () {
      final collector = FrameContextWindowCollector();
      _open(collector, 'anm_1', afterCount: 1);

      collector.offer(_sample(10));

      final completed = collector.windowFor('anm_1');
      expect(completed, isNotNull);
      expect(completed!.isComplete, isTrue);
      expect(completed.after.map((s) => s.id).toList(), [10]);
    });

    test('offer feeds all open windows incrementally', () {
      final collector = FrameContextWindowCollector();
      _open(collector, 'anm_1', afterCount: 2);
      _open(collector, 'anm_2', afterCount: 2);

      collector.offer(_sample(10));
      expect(collector.windowFor('anm_1')!.isComplete, isFalse);
      expect(collector.windowFor('anm_2')!.isComplete, isFalse);

      collector.offer(_sample(11));
      expect(collector.windowFor('anm_1')!.isComplete, isTrue);
      expect(collector.windowFor('anm_2')!.isComplete, isTrue);
      expect(collector.windowFor('anm_1')!.after.map((s) => s.id).toList(),
          [10, 11]);
      expect(collector.windowFor('anm_2')!.after.map((s) => s.id).toList(),
          [10, 11]);
    });

    test('completed windows stop consuming further frames', () {
      final collector = FrameContextWindowCollector();
      _open(collector, 'anm_1', afterCount: 1);

      collector.offer(_sample(10));
      collector.offer(_sample(11));

      expect(
          collector.windowFor('anm_1')!.after.map((s) => s.id).toList(), [10]);
    });

    test('eviction drops the oldest tracked window when capacity is exceeded',
        () {
      final collector = FrameContextWindowCollector(pendingCapacity: 2);
      _open(collector, 'anm_1', afterCount: 5);
      _open(collector, 'anm_2', afterCount: 5);
      expect(collector.windowFor('anm_1'), isNotNull);

      _open(collector, 'anm_3', afterCount: 0); // completes instantly

      // Oldest (pending anm_1) was dropped entirely; newer ones survive —
      // including the completed anm_3, which stays resolvable.
      expect(collector.windowFor('anm_1'), isNull);
      expect(collector.windowFor('anm_2'), isNotNull);
      expect(collector.windowFor('anm_3'), isNotNull);
    });

    test('completed windows are bounded by the same capacity', () {
      final collector = FrameContextWindowCollector(pendingCapacity: 2);
      _open(collector, 'anm_1', afterCount: 0);
      _open(collector, 'anm_2', afterCount: 0);

      _open(collector, 'anm_3', afterCount: 0);

      expect(collector.windowFor('anm_1'), isNull);
      expect(collector.windowFor('anm_2'), isNotNull);
      expect(collector.windowFor('anm_3'), isNotNull);
    });
  });
}
