import 'package:flutter_test/flutter_test.dart';
// IdGenerator is an internal primitive; it is intentionally not part of
// the public barrel, so this test targets its source directly.
import 'package:perfscope/src/core/ids.dart';

void main() {
  group('IdGenerator', () {
    test('produces sequential ids starting at 1', () {
      final gen = IdGenerator('ses');

      expect(gen.next(), 'ses_1');
      expect(gen.next(), 'ses_2');
      expect(gen.next(), 'ses_3');
    });

    test('generators keep independent counters', () {
      final a = IdGenerator('a');
      final b = IdGenerator('b');
      a.next();
      a.next();

      expect(b.next(), 'b_1');
      expect(a.next(), 'a_3');
    });

    test('supports arbitrary prefixes', () {
      expect(IdGenerator('frm').next(), 'frm_1');
      expect(IdGenerator('evt').next(), 'evt_1');
    });
  });
}
