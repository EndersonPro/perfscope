import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

class _NotSerializable {
  const _NotSerializable();
}

void main() {
  late MetadataStore store;

  setUp(() {
    store = MetadataStore();
  });

  group('MetadataStore.set accepts allowed types', () {
    test('null and scalar primitives', () {
      store
        ..set('n', null)
        ..set('b', true)
        ..set('i', 42)
        ..set('d', 3.14)
        ..set('s', 'value');

      final snapshot = store.snapshot();
      expect(snapshot['n'], isNull);
      expect(snapshot['b'], true);
      expect(snapshot['i'], 42);
      expect(snapshot['d'], 3.14);
      expect(snapshot['s'], 'value');
    });

    test('flat collections of primitives', () {
      store
        ..set('tags', <String>['a', 'b'])
        ..set('counts', <String, int>{'x': 1, 'y': 2});

      expect(store.snapshot()['tags'], ['a', 'b']);
      expect(store.snapshot()['counts'], {'x': 1, 'y': 2});
    });
  });

  group('MetadataStore.set rejects invalid values', () {
    test('nested collections (nesting depth must stay at 1)', () {
      expect(
        () => store.set('nested', [
          [1],
        ]),
        throwsArgumentError,
      );
      expect(
        () => store.set('nestedMap', <String, Object?>{
          'inner': <String>['x'],
        }),
        throwsArgumentError,
      );
    });

    test('arbitrary objects name the key and runtime type', () {
      expect(
        () => store.set('obj', const _NotSerializable()),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            contains('_NotSerializable'),
          ),
        ),
      );
    });

    test('oversized string', () {
      expect(
        () => store.set('long', 'x' * (MetadataStore.maxStringLength + 1)),
        throwsArgumentError,
      );
    });

    test('oversized collections', () {
      expect(
        () => store.set(
          'list',
          List<int>.generate(MetadataStore.maxItemsPerCollection + 1, (i) => i),
        ),
        throwsArgumentError,
      );
      expect(
        () => store.set(
          'map',
          <String, int>{
            for (final i in List<int>.generate(
                MetadataStore.maxItemsPerCollection + 1, (i) => i))
              'k$i': i,
          },
        ),
        throwsArgumentError,
      );
    });

    test('map with non-String keys', () {
      expect(
        () => store.set('badKeys', <int, String>{1: 'a'}),
        throwsArgumentError,
      );
    });

    test('more than maxEntries new keys', () {
      for (var i = 0; i < MetadataStore.maxEntries; i++) {
        store.set('k$i', i);
      }
      expect(() => store.set('overflow', 1), throwsArgumentError);
      // Replacing an existing key stays allowed at the limit.
      expect(() => store.set('k0', 'replaced'), returnsNormally);
    });
  });

  group('MetadataStore lifecycle', () {
    test('set replaces the previous value', () {
      store.set('k', 'first');

      store.set('k', 'second');

      expect(store.snapshot(), {'k': 'second'});
    });

    test('remove returns the old value and drops the entry', () {
      store.set('k', 'value');

      final removed = store.remove('k');

      expect(removed, 'value');
      expect(store.containsKey('k'), isFalse);
      expect(store.remove('missing'), isNull);
    });

    test('clear empties the store', () {
      store
        ..set('a', 1)
        ..set('b', 2);

      store.clear();

      expect(store.snapshot(), isEmpty);
      expect(store.containsKey('a'), isFalse);
    });

    test('snapshot is defensive in both directions', () {
      final list = <String>['original'];
      final map = <String, int>{'count': 1};
      store
        ..set('list', list)
        ..set('map', map);

      // Mutating caller-held collections after set must not leak in.
      list.add('mutated');
      map['count'] = 999;

      var snapshot = store.snapshot();
      expect(snapshot['list'], ['original']);

      // Mutating the returned snapshot must not leak into the store.
      (snapshot['list'] as List<Object?>).add('external');
      snapshot['newKey'] = 'nope';
      snapshot = store.snapshot();

      expect(snapshot.containsKey('newKey'), isFalse);
      expect(snapshot['list'], ['original']);
      expect(store.containsKey('newKey'), isFalse);
    });

    test('containsKey distinguishes stored null from absence', () {
      store.set('nothing', null);

      expect(store.containsKey('nothing'), isTrue);
      expect(store.containsKey('absent'), isFalse);
    });
  });
}
