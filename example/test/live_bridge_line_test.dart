import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';
import 'package:perfscope/perfscope_live.dart';
import 'package:perfscope_example/app/scenario.dart';
import 'package:perfscope_example/app/showcase_app.dart';
import 'package:perfscope_example/perf_bootstrap.dart';

/// Coverage for the live-bridge line shown on the event console.
///
/// The line renders the bound port but never the token; a disabled bridge
/// renders `off`. Pure formatter cases use fake handles (no sockets); the
/// widget case pumps the real console screen with no server serving.
final class _FakeHandle implements LiveServerHandle {
  const _FakeHandle({required this.isServing, this.port = 0, this.token = ''});

  @override
  final bool isServing;

  @override
  final int port;

  @override
  final String token;

  @override
  Future<void> close() async {}
}

void main() {
  tearDown(() {
    liveBridgeHandle = null;
  });

  test('disabled bridge renders off', () {
    expect(liveBridgeLine(const _FakeHandle(isServing: false)), 'Live bridge: off');
  });

  test('no handle renders off', () {
    expect(liveBridgeLine(), 'Live bridge: off');
  });

  test('serving handle renders URL with port and never the token', () {
    const handle = _FakeHandle(
      isServing: true,
      port: 4567,
      token: 'secret-token',
    );
    final line = liveBridgeLine(handle);
    expect(line, contains('http://127.0.0.1:4567/v1/status'));
    expect(line, isNot(contains('secret-token')));
  });

  test('stored bootstrap handle is used when no argument is given', () {
    liveBridgeHandle = const _FakeHandle(isServing: true, port: 9876);
    expect(liveBridgeLine(), contains('9876'));
  });

  testWidgets('console screen shows the bridge line while disabled', (
    tester,
  ) async {
    PerfScope.initialize(
      config: const PerfScopeConfig(logStyle: PerfScopeLogStyle.silent),
    );
    addTearDown(PerfScope.dispose);
    await tester.pumpWidget(
      const ShowcaseApp(initialRoute: routeLiveEventConsole),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('live-bridge-line')),
      findsOneWidget,
    );
    expect(find.text('Live bridge: off'), findsOneWidget);
  });
}
