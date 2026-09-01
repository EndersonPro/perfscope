import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

void main() {
  group('ScreenTracker initial state', () {
    test('current is unknown before any mutation', () {
      expect(ScreenTracker().current, unknownScreenName);
    });
  });

  group('ScreenTracker push', () {
    test('push named screen updates current with previous reported', () {
      final tracker = ScreenTracker();

      final change = tracker.push('home');

      expect(change.previous, 'unknown');
      expect(tracker.current, 'home');
      expect(change.changed, isTrue);
    });

    test('push unnamed screen normalizes to unknown', () {
      final tracker = ScreenTracker();

      tracker.push('home');
      final change = tracker.push(null);

      expect(change.previous, 'home');
      expect(tracker.current, 'unknown');
      expect(change.changed, isTrue);
    });

    test('push same name reports changed=false', () {
      final tracker = ScreenTracker()..push('home');

      final change = tracker.push('home');

      expect(change.changed, isFalse);
      expect(change.current, 'home');
    });
  });

  group('ScreenTracker pop', () {
    test('pop restores the previous screen', () {
      final tracker = ScreenTracker()
        ..push('home')
        ..push('details');

      final change = tracker.pop();

      expect(change.previous, 'details');
      expect(tracker.current, 'home');
      expect(change.changed, isTrue);
    });

    test('pop on empty stack is a safe no-op', () {
      final tracker = ScreenTracker();

      final change = tracker.pop();

      expect(change.changed, isFalse);
      expect(change.previous, isNull);
      expect(change.current, 'unknown');
      expect(tracker.current, 'unknown');
    });
  });

  group('ScreenTracker replace / remove', () {
    test('replace renames the top of the stack only', () {
      final tracker = ScreenTracker()
        ..push('home')
        ..push('settings');

      final change = tracker.replace('profile');

      expect(change.previous, 'settings');
      expect(tracker.current, 'profile');
      tracker.pop();
      expect(tracker.current, 'home');
    });

    test('replace on empty stack is a safe no-op', () {
      final tracker = ScreenTracker();

      final change = tracker.replace('anything');

      expect(change.changed, isFalse);
      expect(tracker.current, 'unknown');
    });

    test('remove acts like pop', () {
      final tracker = ScreenTracker()
        ..push('home')
        ..push('modal');

      final change = tracker.remove();

      expect(change.previous, 'modal');
      expect(tracker.current, 'home');
    });
  });

  group('ScreenTracker override', () {
    test('override replaces current until the next navigation mutation', () {
      final tracker = ScreenTracker()..push('home');

      final change = tracker.override('wizard_step_2');

      expect(change.changed, isTrue);
      expect(tracker.current, 'wizard_step_2');

      // Still in effect without navigation.
      expect(tracker.current, 'wizard_step_2');

      // Next effective navigation mutation discards it.
      tracker.pop();
      expect(tracker.current, 'unknown');
    });

    test('override then effective push resumes stack tracking', () {
      final tracker = ScreenTracker()..override('custom');

      final change = tracker.push('home');

      expect(change.previous, 'custom');
      expect(tracker.current, 'home');
      expect(change.changed, isTrue);
    });

    test('no-op pop does not discard an active override', () {
      final tracker = ScreenTracker()..override('custom');

      final change = tracker.pop(); // empty stack -> no-op

      expect(change.changed, isFalse);
      expect(tracker.current, 'custom');
    });

    test('override to the same name reports changed=false', () {
      final tracker = ScreenTracker()..override('same');

      final change = tracker.override('same');

      expect(change.changed, isFalse);
    });
  });
}
