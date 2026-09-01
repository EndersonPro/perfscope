import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/src/testing/fake_frame_source.dart';

/// Builds a REAL engine wired by hand — deliberately not the facade
/// singleton, so widget tests never depend on global state.
PerfScopeEngine _newEngine() {
  return PerfScopeEngine(
    frameSource: FakeFrameSource(),
    clock: const SystemClock(),
    logWriter: MemoryLogWriter(),
  );
}

Route<void> _namedPage(String? name) => MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => Text('page:$name'),
    );

/// Guard against lost events: widget tests cannot rely on draining the
/// whole event queue (it never settles under a live MaterialApp), so each
/// awaited event carries its own timeout instead.
const _eventTimeout = Duration(seconds: 10);

class _ThrowingPort implements ScreenContextPort {
  @override
  void onRoutePushed(String? name) => throw StateError('boom');

  @override
  void onRoutePopped() => throw StateError('boom');

  @override
  void onRouteReplaced(String? newName) => throw StateError('boom');

  @override
  void onRouteRemoved() => throw StateError('boom');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PerfScope.resetForTest(); // keep the singleton locator null.
  });

  group('PerfScopeNavigatorObserver against a real engine', () {
    final engines = <PerfScopeEngine>[];

    tearDown(() async {
      for (final engine in engines) {
        await engine.dispose();
      }
      engines.clear();
    });

    testWidgets('push named route emits push event and updates current',
        (tester) async {
      final engine = _newEngine();
      engines.add(engine);
      final pushed = engine.events
          .where((e) => e is ScreenEvent)
          .cast<ScreenEvent>()
          .where((e) => e.name == 'details')
          .first
          .timeout(_eventTimeout);

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [PerfScopeNavigatorObserver(port: engine)],
        home: const SizedBox(),
      ));
      expect(engine.currentScreen, '/'); // MaterialApp's initial route.

      Navigator.of(tester.element(find.byType(SizedBox)))
          .push(_namedPage('details'));
      await tester.pump();
      final event = await pushed;

      expect(event.reason, ScreenChangeReason.push);
      expect(event.previousName, '/');
      expect(engine.currentScreen, 'details');
    });

    testWidgets('push unnamed route normalizes to unknown', (tester) async {
      final engine = _newEngine();
      engines.add(engine);
      final pushed = engine.events
          .where((e) => e is ScreenEvent)
          .cast<ScreenEvent>()
          .where((e) => e.name == unknownScreenName)
          .first
          .timeout(_eventTimeout);

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [PerfScopeNavigatorObserver(port: engine)],
        home: const SizedBox(),
      ));

      Navigator.of(tester.element(find.byType(SizedBox)))
          .push(_namedPage(null));
      await tester.pump();
      final event = await pushed;

      expect(event.reason, ScreenChangeReason.push);
      expect(engine.currentScreen, unknownScreenName);
    });

    testWidgets('pop restores the previous screen', (tester) async {
      final engine = _newEngine();
      engines.add(engine);
      final poppedToHome = engine.events
          .where((e) => e is ScreenEvent)
          .cast<ScreenEvent>()
          .where((e) => e.name == 'home' && e.reason == ScreenChangeReason.pop)
          .first
          .timeout(_eventTimeout);

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [PerfScopeNavigatorObserver(port: engine)],
        home: const SizedBox(),
      ));
      final homeContext = tester.element(find.byType(SizedBox));

      Navigator.of(homeContext).push(_namedPage('home'));
      await tester.pump();
      expect(engine.currentScreen, 'home');

      Navigator.of(homeContext).push(_namedPage(null));
      await tester.pump();
      expect(engine.currentScreen, unknownScreenName);

      Navigator.of(homeContext).pop();
      await tester.pump();
      final event = await poppedToHome;

      expect(event.previousName, unknownScreenName);
      expect(engine.currentScreen, 'home');
    });

    testWidgets('replace reports the new route via named parameters',
        (tester) async {
      final engine = _newEngine();
      engines.add(engine);
      final replaced = engine.events
          .where((e) => e is ScreenEvent)
          .cast<ScreenEvent>()
          .where((e) => e.reason == ScreenChangeReason.replace)
          .first
          .timeout(_eventTimeout);

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [PerfScopeNavigatorObserver(port: engine)],
        home: const SizedBox(),
      ));
      final context = tester.element(find.byType(SizedBox));

      Navigator.of(context).push(_namedPage('old'));
      await tester.pump();
      Navigator.of(context).pushReplacement(_namedPage('new'));
      await tester.pump();
      final event = await replaced;

      expect(event.name, 'new');
      expect(event.previousName, 'old');
      expect(engine.currentScreen, 'new');
    });

    testWidgets('remove drops an arbitrary route from the stack',
        (tester) async {
      final engine = _newEngine();
      engines.add(engine);
      final removed = engine.events
          .where((e) => e is ScreenEvent)
          .cast<ScreenEvent>()
          .where((e) => e.reason == ScreenChangeReason.remove)
          .first
          .timeout(_eventTimeout);

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [PerfScopeNavigatorObserver(port: engine)],
        home: const SizedBox(),
      ));
      final context = tester.element(find.byType(SizedBox));

      Navigator.of(context).push(_namedPage('bottom'));
      await tester.pump();
      final doomed = _namedPage('doomed');
      Navigator.of(context).push(doomed);
      await tester.pump();
      expect(engine.currentScreen, 'doomed');

      Navigator.of(context).removeRoute(doomed);
      await tester.pump();
      final event = await removed;

      expect(event.previousName, 'doomed');
      expect(engine.currentScreen, 'bottom');
    });
  });

  group('PerfScopeNavigatorObserver without an engine', () {
    test('all four overrides are safe no-ops when nothing is initialized', () {
      expect(PerfScope.maybeEngine, isNull);
      final observer = PerfScopeNavigatorObserver();
      final route = PageRouteBuilder<void>(
        settings: const RouteSettings(name: 'any'),
        pageBuilder: (_, __, ___) => const SizedBox(),
      );

      expect(() {
        observer.didPush(route, route);
        observer.didPop(route, route);
        observer.didReplace(newRoute: route, oldRoute: route);
        observer.didRemove(route, route);
      }, returnsNormally);
    });

    test('a failing port implementation can never break navigation', () {
      final observer = PerfScopeNavigatorObserver(port: _ThrowingPort());
      final route = PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const SizedBox(),
      );

      expect(() {
        observer.didPush(route, null);
        observer.didPop(route, null);
        observer.didReplace(newRoute: route, oldRoute: null);
        observer.didRemove(route, null);
      }, returnsNormally);
    });
  });
}
