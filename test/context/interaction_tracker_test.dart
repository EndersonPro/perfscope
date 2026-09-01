import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

/// Deterministic fixed timestamps — no real clock involved.
final _t0 = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);
final _t1 = _t0.add(const Duration(milliseconds: 10));

void main() {
  late List<String> warnings;
  late InteractionTracker tracker;

  setUp(() {
    warnings = <String>[];
    tracker = InteractionTracker(onWarning: warnings.add);
  });

  group('InteractionHandle lifecycle', () {
    test('start/end flips hasEnded and notifies onSpanEnded', () {
      var ended = false;
      tracker.onSpanEnded = (_) => ended = true;

      final handle = tracker.start('checkout', _t0);
      expect(handle.hasEnded, isFalse);
      expect(tracker.activeInteractionId, handle.id);

      handle.end();
      expect(handle.hasEnded, isTrue);
      expect(ended, isTrue);
      expect(tracker.activeInteractionId, noActiveInteractionId);
    });

    test('end is idempotent', () {
      final handle = tracker.start('checkout', _t0);

      handle.end();
      handle.end();

      expect(handle.hasEnded, isTrue);
      expect(tracker.depth, 0);
    });
  });

  group('nested interactions', () {
    test(
        'innermost active span wins and parent ids chain checkout → '
        'calculate_total → load_discount', () {
      final checkout = tracker.start('checkout', _t0);
      final calculateTotal = tracker.start('calculate_total', _t1);
      final loadDiscount = tracker.start('load_discount', _t1);

      expect(checkout.parentInteractionId, isNull);
      expect(calculateTotal.parentInteractionId, checkout.id);
      expect(loadDiscount.parentInteractionId, calculateTotal.id);
      expect(tracker.activeInteractionId, loadDiscount.id);

      loadDiscount.end();
      expect(tracker.activeInteractionId, calculateTotal.id);

      calculateTotal.end();
      expect(tracker.activeInteractionId, checkout.id);

      checkout.end();
      expect(tracker.activeInteractionId, noActiveInteractionId);
    });

    test('out-of-order end removes the middle span only', () {
      final outer = tracker.start('outer', _t0);
      final middle = tracker.start('middle', _t0);
      final inner = tracker.start('inner', _t0);

      middle.end(); // ends before its child

      expect(middle.hasEnded, isTrue);
      expect(tracker.activeInteractionId, inner.id);

      inner.end();
      expect(tracker.activeInteractionId, outer.id);
      expect(tracker.depth, 1);
    });
  });

  group('quick markers', () {
    test('markOnce is consumed exactly once', () {
      final markerId = tracker.markOnce('tap_pay', _t0);

      expect(tracker.consumePendingMarker(), markerId);
      expect(tracker.consumePendingMarker(), isNull);
    });

    test('last mark wins when marked twice before consumption', () {
      tracker.markOnce('first', _t0);
      final secondId = tracker.markOnce('second', _t0);

      expect(tracker.consumePendingMarker(), secondId);
    });
  });

  group('depth guard', () {
    test(
        'start beyond maxInteractionDepth is ignored with one warning '
        'and an inert handle', () {
      final handles = <InteractionHandle>[
        for (var i = 0; i < maxInteractionDepth; i++)
          tracker.start('span_$i', _t0),
      ];
      expect(handles.every((h) => h.id.isNotEmpty), isTrue);

      final overflow = tracker.start('overflow', _t0);

      expect(overflow.id, isEmpty); // inert marker
      expect(overflow.hasEnded, isTrue);
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('[PerfScope]'));
      expect(tracker.depth, maxInteractionDepth);
      expect(tracker.activeInteractionId, handles.last.id);

      // Further starts stay silent: the warning fires once per process.
      tracker.start('overflow_2', _t0);
      expect(warnings, hasLength(1));
      expect(() => overflow.end(), returnsNormally);
    });

    test('depth frees up after endings', () {
      for (var i = 0; i < maxInteractionDepth; i++) {
        tracker.start('span_$i', _t0).end();
      }

      final handle = tracker.start('fresh', _t0);
      expect(handle.id, isNotEmpty);
      expect(warnings, isEmpty);
    });
  });
}
