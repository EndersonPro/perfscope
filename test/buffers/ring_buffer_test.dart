import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

void main() {
  group('RingBuffer<int>', () {
    test('starts empty and not full', () {
      final buffer = RingBuffer<int>(3);

      expect(buffer.isEmpty, isTrue);
      expect(buffer.isFull, isFalse);
      expect(buffer.length, 0);
      expect(buffer.capacity, 3);
      expect(buffer.last, isNull);
    });

    test('filling under capacity preserves chronological order', () {
      final buffer = RingBuffer<int>(5);
      buffer.add(10);
      buffer.add(20);
      buffer.add(30);

      expect(buffer.toList(), [10, 20, 30]);
      expect(buffer[0], 10);
      expect(buffer[2], 30);
      expect(buffer.last, 30);
      expect(buffer.isFull, isFalse);
    });

    test('overflowing overwrites oldest entries in order', () {
      final buffer = RingBuffer<int>(3);
      for (var i = 1; i <= 5; i++) {
        buffer.add(i);
      }

      expect(buffer.toList(), [3, 4, 5]);
      expect(buffer.length, 3);
      expect(buffer.last, 5);
    });

    test('length never exceeds capacity and isFull flips', () {
      final buffer = RingBuffer<int>(3);
      expect(buffer.isFull, isFalse);

      buffer.add(1);
      buffer.add(2);
      expect(buffer.isFull, isFalse);

      buffer.add(3);
      expect(buffer.isFull, isTrue);
      expect(buffer.length, 3);

      buffer.add(4);
      buffer.add(5);
      expect(buffer.length, 3);
    });

    test('clear resets state but keeps capacity', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.clear();

      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, 0);
      expect(buffer.isFull, isFalse);
      expect(buffer.toList(), isEmpty);
      expect(buffer.capacity, 3);

      // Still usable after clearing.
      buffer.add(9);
      expect(buffer.toList(), [9]);
    });

    test('forEach visits elements in chronological order', () {
      final visited = <int>[];
      final buffer = RingBuffer<int>(4)
        ..add(1)
        ..add(2)
        ..add(3)
        ..add(4)
        ..add(5); // evicts 1

      buffer.forEach(visited.add);

      expect(visited, [2, 3, 4, 5]);
    });

    test('operator [] asserts out-of-bounds access', () {
      final buffer = RingBuffer<int>(3)
        ..add(1)
        ..add(2);

      expect(() => buffer[-1], throwsA(isA<AssertionError>()));
      expect(() => buffer[2], throwsA(isA<AssertionError>()));
    });
  });

  group('RingBuffer<String>', () {
    test('works with reference types too', () {
      final buffer = RingBuffer<String>(2)
        ..add('a')
        ..add('b')
        ..add('c');

      expect(buffer.toList(), ['b', 'c']);
      expect(buffer.last, 'c');
    });
  });

  group('RingBuffer stress', () {
    test('100000 adds into capacity-500 buffer keep the last 500', () {
      final buffer = RingBuffer<int>(500);
      const totalAdds = 100000;

      for (var i = 1; i <= totalAdds; i++) {
        buffer.add(i);
      }

      expect(buffer.length, 500);
      final contents = buffer.toList();
      expect(contents.first, totalAdds - 500 + 1);
      expect(contents.last, totalAdds);
      expect(contents.length, 500);
    });
  });
}
