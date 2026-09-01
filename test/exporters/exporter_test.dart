import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

PerformanceSession _session({String id = 'ses_export'}) {
  final session = PerformanceSession(
    id: id,
    name: 'export-check',
    startedAt: DateTime.fromMicrosecondsSinceEpoch(1700000000000000),
    environment: PerformanceEnvironment(
      frameBudgetFps: 60.0,
      frameBudgetMs: 16.667,
      frameBudgetSource: FrameBudgetSource.fallback,
      platform: 'test',
    ),
    calculator: StatisticsCalculator(),
    anomalies: <PerformanceAnomaly>[],
  );
  // Attach a real report so exporters exercise the attached-report path.
  session.attachReport(buildPerformanceReport(
    session: session
      ..endedAt = DateTime.fromMicrosecondsSinceEpoch(1700000060000000),
    statistics: SessionStatistics.zero,
    screenAccumulators: const [],
    interactionAccumulators: const [],
    traces: const [],
    anomalies: const [],
  ));
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PerfScope.resetForTest();
  });

  tearDown(() {
    PerfScope.resetForTest();
  });

  group('CallbackExporter', () {
    test('hands parseable schema-v1 JSON to the callback', () async {
      String? captured;
      final exporter = CallbackExporter(
        onJson: (json) => captured = json,
        pretty: false,
      );

      await exporter.export(_session());

      expect(captured, isNotNull);
      expect(captured!.contains('\n'), isFalse); // single line
      final doc = jsonDecode(captured!) as Map<Object?, Object?>;
      expect(doc[kKeySchemaVersion], 1);
      expect(
          (doc[kKeySession]! as Map<Object?, Object?>)[kKeyId], 'ses_export');
    });

    test('pretty mode indents but stays deterministic', () async {
      var count = 0;
      String? first;
      String? second;
      Future<void> run() => CallbackExporter(
            onJson: (json) => count++ == 0 ? first = json : second = json,
            pretty: true,
          ).export(_session());

      await run();
      await run();

      expect(first, contains('"\n')); // multi-line output
      expect(first, second);
    });
  });

  group('InMemoryExporter', () {
    test('accumulates exports and exposes lastJson', () async {
      final exporter = InMemoryExporter();
      expect(exporter.lastJson, isNull);
      expect(exporter.count, 0);

      await exporter.export(_session(id: 'ses_1'));
      await exporter.export(_session(id: 'ses_2'));

      expect(exporter.count, 2);
      final doc = jsonDecode(exporter.lastJson!) as Map<Object?, Object?>;
      expect((doc[kKeySession]! as Map<Object?, Object?>)[kKeyId], 'ses_2');
      expect(exporter.exports, hasLength(2));
      exporter.clear();
      expect(exporter.count, 0);
      expect(exporter.lastJson, isNull);
    });
  });

  group('TextExporter', () {
    test('renders the PerfScope summary box with a p95 line', () async {
      String? captured;
      final exporter = TextExporter(onText: (text) => captured = text);

      await exporter.export(_session());

      expect(captured, isNotNull);
      expect(captured, contains('PerfScope'));
      expect(captured, contains('Session Summary'));
      expect(captured, matches(RegExp(r'^.*p95.*$', multiLine: true)));
      // Fixed-width box layout: every line has identical length.
      final lines = captured!.split('\n');
      expect(lines.map((l) => l.length).toSet(), hasLength(1));
    });
  });

  group('facade export entry points (disabled / no-session safety)', () {
    test('null-safe and StateError-safe while disabled', () async {
      expect(PerfScope.exportCurrentSessionAsJson(), isNull);
      await expectLater(
        PerfScope.export(exporter: InMemoryExporter()),
        throwsStateError,
      );
      await pumpEventQueue();
    });

    test('after stopSession, export falls back to the finished session',
        () async {
      PerfScope.initialize(logWriter: MemoryLogWriter());
      await pumpEventQueue(); // auto-start fires
      final stopped = await PerfScope.stopSession(); // leaves no active session

      // The JSON entry point falls back to the last finished session's
      // attached report instead of returning null.
      final json = PerfScope.exportCurrentSessionAsJson();
      expect(json, isNotNull);
      expect(
        (jsonDecode(json!) as Map<Object?, Object?>)[kKeySchemaVersion],
        1,
      );
      expect(SessionParser().parseString(json).session.id, stopped.session.id);

      // The throwing entry point keeps its contract: with no OPEN session
      // an explicit export still fails loudly.
      await expectLater(
        PerfScope.export(exporter: InMemoryExporter()),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'No performance session available to export.',
        )),
      );
    });
  });
}
