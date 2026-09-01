import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

void main() {
  group('SystemClock', () {
    test('now() is non-decreasing across consecutive calls', () {
      final clock = const SystemClock();
      final first = clock.now();
      final second = clock.now();

      expect(second.isBefore(first), isFalse);
    });

    test('returns wall-clock time close to DateTime.now()', () {
      final before = DateTime.now();
      final now = const SystemClock().now();
      final after = DateTime.now();

      expect(now.isBefore(before) || now.isAfter(after), isFalse);
    });
  });
}
