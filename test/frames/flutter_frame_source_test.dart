import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

/// Deterministic fixed timestamp — no real clock involved.
final _capturedAt = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

class _FakeClock implements Clock {
  @override
  DateTime now() => _capturedAt;
}

/// Raw timestamps in microseconds chosen for clean getter math:
/// build 3000us, raster 13000us, vsyncOverhead 100us, totalSpan 17000us.
FrameTiming _timing({int frameNumber = 7}) {
  return FrameTiming(
    vsyncStart: 0,
    buildStart: 100,
    buildFinish: 3100,
    rasterStart: 4000,
    rasterFinish: 17000,
    rasterFinishWallTime: 18000,
    frameNumber: frameNumber,
  );
}

FlutterFrameSource _source() {
  return FlutterFrameSource(
    frameBudgetProvider: FixedFrameBudget.fromFps(120),
    clock: _FakeClock(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('start/stop lifecycle', () {
    test('double start throws StateError (documented contract)', () async {
      final source = _source();
      await source.start();

      await expectLater(source.start(), throwsStateError);

      await source.stop();
    });

    test('stop before start is an idempotent no-op', () async {
      final source = _source();

      await expectLater(source.stop(), completes);
      await expectLater(source.stop(), completes);
    });

    test('stop closes the frames stream; second stop is a no-op', () async {
      final source = _source();
      final done = Completer<void>();
      source.frames.listen((_) {}, onDone: done.complete);

      await source.start();
      await source.stop();
      await done.future;

      await expectLater(source.stop(), completes);
    });
  });

  group('convertTiming', () {
    test('maps engine timings onto FrameSample fields', () {
      final sample = _source().convertTiming(_timing());

      // buildFinish - buildStart
      expect(sample.buildDuration, const Duration(microseconds: 3000));
      // rasterFinish - rasterStart
      expect(sample.rasterDuration, const Duration(microseconds: 13000));
      // buildStart - vsyncStart
      expect(sample.vsyncOverhead, const Duration(microseconds: 100));
      // rasterFinish - vsyncStart
      expect(sample.totalDuration, const Duration(microseconds: 17000));
    });

    test('carries budget, clock timestamp and null attribution', () {
      final sample = _source().convertTiming(_timing());

      expect(sample.frameBudget, FixedFrameBudget.fromFps(120).currentBudget);
      expect(sample.capturedAt, _capturedAt);
      expect(sample.frameNumber, 7);
      expect(sample.screen, isNull);
      expect(sample.interactionId, isNull);
    });

    test('assigns sequential integer ids across conversions', () {
      final source = _source();
      final first = source.convertTiming(_timing());
      final second = source.convertTiming(_timing());

      expect(second.id, first.id + 1);
    });
  });

  group('onTimings stream delivery', () {
    test('delivers converted samples in order', () async {
      final source = _source();
      final received = <FrameSample>[];
      source.frames.listen(received.add);

      // Production path: callbacks only fire while running.
      await source.start();
      source.onTimings([_timing(frameNumber: 1), _timing(frameNumber: 2)]);
      await pumpEventQueue();

      expect(received.length, 2);
      expect(received[0].frameNumber, 1);
      expect(received[1].frameNumber, 2);
      await source.stop();
    });

    test('skips timings with negative frame numbers', () async {
      final source = _source();
      final received = <FrameSample>[];
      source.frames.listen(received.add);

      await source.start();
      source.onTimings([
        _timing(frameNumber: -1), // default sentinel: dropped
        _timing(frameNumber: -5),
        _timing(frameNumber: 3),
      ]);
      await pumpEventQueue();

      expect(received.length, 1);
      expect(received.single.frameNumber, 3);
      await source.stop();
    });

    test('no deliveries after stop', () async {
      final source = _source();
      final received = <FrameSample>[];
      source.frames.listen(received.add);

      await source.start();
      await source.stop();
      // Post-stop callback invocation must not crash nor deliver.
      source.onTimings([_timing()]);
      await pumpEventQueue();

      expect(received, isEmpty);
    });
  });
}
