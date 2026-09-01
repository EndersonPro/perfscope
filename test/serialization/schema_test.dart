import 'package:flutter_test/flutter_test.dart';
import 'package:perfscope/perfscope.dart';

const _parser = SessionParser();

/// Minimal valid v1 document; every test mutates a fresh copy.
Map<String, Object?> _validDocument() => <String, Object?>{
      kKeySchemaVersion: 1,
      kKeyGenerator: <String, Object?>{
        kKeyName: 'perfscope',
        kKeyVersion: '0.1.0'
      },
      kKeySession: <String, Object?>{
        kKeyId: 'ses_1',
        kKeyName: 'release-check',
        kKeyStartedAt: '2026-01-01T00:00:00.000Z',
        kKeyEndedAt: '2026-01-01T00:01:00.000Z',
        kKeyMetadata: <String, Object?>{},
      },
      kKeyEnvironment: <String, Object?>{
        kKeyPlatform: 'test',
        kKeyFrameBudgetFps: 60.0,
        kKeyFrameBudgetMs: 16.667,
        kKeyFrameBudgetSource: 'fallback',
      },
      kKeySummary: <String, Object?>{
        kKeyTotalFrames: 10,
        kKeyNormalFrames: 8,
        kKeyWarningFrames: 0,
        kKeySlowFrames: 2,
        kKeySevereFrames: 0,
        kKeySlowFrameRate: 0.2,
        kKeyAverageBuildMs: 4.5,
        kKeyAverageRasterMs: 5.25,
        kKeyAverageTotalMs: 9.75,
        kKeyP50Ms: 8.0,
        kKeyP90Ms: 32.0,
        kKeyP95Ms: 32.0,
        kKeyP99Ms: 32.0,
        kKeyWorstFrameMs: 32.0,
      },
      kKeyScreens: <Object?>[],
      kKeyInteractions: <Object?>[],
      kKeyTraces: <Object?>[],
      kKeyAnomalies: <Object?>[],
    };

Matcher _parseFailsWith(Matcher messageMatcher) => throwsA(
      isA<FormatException>()
          .having((e) => e.message, 'message', messageMatcher),
    );

void main() {
  group('SessionParser schema guard', () {
    test('accepts a minimal valid document', () {
      final report = _parser.parse(_validDocument());

      expect(report.session.id, 'ses_1');
      expect(report.session.name, 'release-check');
      expect(report.screens, isEmpty);
      expect(report.anomalies, isEmpty);
    });

    test('unsupported version produces the EXACT contract message', () {
      final doc = _validDocument();
      doc[kKeySchemaVersion] = 4;

      expect(
        () => _parser.parse(doc),
        _parseFailsWith(equals(
          'Unsupported PerfScope schema version: 4. Supported versions: 1.',
        )),
      );
    });

    test('missing version fails with the path message', () {
      final doc = _validDocument()..remove(kKeySchemaVersion);

      expect(
        () => _parser.parse(doc),
        _parseFailsWith(contains("missing required field 'schema_version'")),
      );
    });

    test('non-int version fails with the path message', () {
      final doc = _validDocument();
      doc[kKeySchemaVersion] = '1'; // string, not int

      expect(
        () => _parser.parse(doc),
        _parseFailsWith(contains('schema_version must be an int')),
      );
    });

    test('missing session.id names the nested path', () {
      final doc = _validDocument();
      (doc[kKeySession]! as Map<String, Object?>).remove(kKeyId);

      expect(
        () => _parser.parse(doc),
        _parseFailsWith(contains("missing required field 'session.id'")),
      );
    });

    test('session.id of the wrong type names the nested path', () {
      final doc = _validDocument();
      (doc[kKeySession]! as Map<String, Object?>)[kKeyId] = 7;

      expect(
        () => _parser.parse(doc),
        _parseFailsWith(contains('session.id must be a string')),
      );
    });

    test('garbage timestamp produces a clear FormatException', () {
      final doc = _validDocument();
      (doc[kKeySession]! as Map<String, Object?>)[kKeyStartedAt] = 'not-a-date';

      expect(
        () => _parser.parse(doc),
        _parseFailsWith(allOf(
          contains('session.started_at'),
          contains('ISO-8601'),
        )),
      );
    });

    test('nested environment paths appear in messages', () {
      final doc = _validDocument();
      (doc[kKeyEnvironment]! as Map<String, Object?>).remove(kKeyPlatform);

      expect(
        () => _parser.parse(doc),
        _parseFailsWith(contains('environment.platform')),
      );

      (doc[kKeyEnvironment]! as Map<String, Object?>)[kKeyPlatform] = 'x';
      (doc[kKeyEnvironment]! as Map<String, Object?>)[kKeyFrameBudgetSource] =
          'telepathy';

      expect(
        () => _parser.parse(doc),
        _parseFailsWith(contains('environment.frame_budget_source')),
      );
    });

    test('summary and array-element paths appear in messages', () {
      final doc = _validDocument();
      (doc[kKeySummary]! as Map<String, Object?>)[kKeyP95Ms] = 'fast';

      expect(
        () => _parser.parse(doc),
        _parseFailsWith(contains('summary.p95_ms must be a number')),
      );

      doc[kKeySummary] = <String, Object?>{
        ...(doc[kKeySummary]! as Map<String, Object?>),
        kKeyP95Ms: 32.0,
      };
      doc[kKeyScreens] = <Object?>[
        <String, Object?>{
          kKeyName: 99,
          kKeyTotalFrames: 1,
          kKeySlowFrames: 0,
          kKeySevereFrames: 0,
          kKeyAnomalyCount: 0,
          kKeySlowFrameRate: 0.0,
          kKeyP95Ms: 1.0,
          kKeyWorstMs: 1.0,
          kKeyProbableBottleneck: 'unknown',
        }
      ];

      expect(
        () => _parser.parse(doc),
        _parseFailsWith(contains('screens[0].name must be a string')),
      );
    });

    test('malformed JSON text fails with FormatException', () {
      expect(
        () => _parser.parseString('{not json'),
        _parseFailsWith(contains('malformed JSON')),
      );
      expect(
        () => _parser.parseString('"just a string"'),
        _parseFailsWith(contains('top level must be an object')),
      );
    });
  });
}
