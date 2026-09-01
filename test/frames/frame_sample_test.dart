import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

final _capturedAt = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);

FrameSample _sample({
  int id = 7,
  int? frameNumber = 3,
  DateTime? capturedAt,
  Duration buildDuration = const Duration(milliseconds: 27),
  Duration rasterDuration = const Duration(milliseconds: 4),
  Duration totalDuration = const Duration(milliseconds: 33, microseconds: 100),
  Duration vsyncOverhead = const Duration(microseconds: 500),
  Duration frameBudget = const Duration(microseconds: 16667),
  String? screen = 'home',
  String? interactionId = 'evt_1',
}) {
  return FrameSample(
    id: id,
    frameNumber: frameNumber,
    capturedAt: capturedAt ?? _capturedAt,
    buildDuration: buildDuration,
    rasterDuration: rasterDuration,
    totalDuration: totalDuration,
    vsyncOverhead: vsyncOverhead,
    frameBudget: frameBudget,
    screen: screen,
    interactionId: interactionId,
  );
}

void main() {
  group('FrameSample equality', () {
    test('identical values are equal with matching hashCodes', () {
      expect(_sample(), equals(_sample()));
      expect(_sample().hashCode, equals(_sample().hashCode));
    });

    test('different id breaks equality', () {
      final base = _sample();
      final other = _sample(id: 8);

      expect(base, isNot(equals(other)));
    });

    test('different frameNumber breaks equality', () {
      final other = _sample(frameNumber: 4);
      expect(_sample(), isNot(equals(other)));
    });

    test('different capturedAt breaks equality', () {
      final other = _sample(
        capturedAt: _capturedAt.add(const Duration(microseconds: 1)),
      );
      expect(_sample(), isNot(equals(other)));
    });

    test('different durations break equality', () {
      expect(
        _sample(),
        isNot(equals(_sample(buildDuration: const Duration(milliseconds: 28)))),
      );
      expect(
        _sample(),
        isNot(equals(_sample(rasterDuration: const Duration(milliseconds: 5)))),
      );
      expect(
        _sample(),
        isNot(equals(_sample(totalDuration: const Duration(seconds: 1)))),
      );
      expect(
        _sample(),
        isNot(equals(_sample(vsyncOverhead: Duration.zero))),
      );
      expect(
        _sample(),
        isNot(
            equals(_sample(frameBudget: const Duration(microseconds: 11111)))),
      );
    });

    test('different screen breaks equality', () {
      final other = _sample(screen: 'settings');
      expect(_sample(), isNot(equals(other)));

      // Null vs non-null also differs.
      expect(_sample(screen: null), isNot(equals(_sample())));
    });

    test('different interactionId breaks equality', () {
      final other = _sample(interactionId: 'evt_2');
      expect(_sample(), isNot(equals(other)));

      expect(
        _sample(interactionId: null),
        isNot(equals(_sample())),
      );
    });
  });

  group('FrameSample toString', () {
    test('renders a compact one-line summary', () {
      final text = _sample().toString();

      expect(text, startsWith('FrameSample(#3'));
      expect(text, contains('total=33.1ms'));
      expect(text, contains('build=27.0ms'));
      expect(text, contains('raster=4.0ms'));
    });

    test('falls back to id when frameNumber is null', () {
      final text = _sample(frameNumber: null).toString();

      expect(text, startsWith('FrameSample(#7'));
    });
  });
}
