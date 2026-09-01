/// Parses PerfScope session files (schema version [kSchemaVersion]) back
/// into [PerformanceReport] values.
///
/// Contract:
/// * STRICT: every field the v1 serializer emits is required and type-
///   checked; failures throw [FormatException] whose message names the
///   offending dotted path (`session.environment.platform`,
///   `screens[0].name`, ...). No raw casts anywhere, so malformed input
///   can never surface as a [TypeError].
/// * Forward-compatible with unknown EXTRA keys: they are ignored on
///   purpose so files written by newer writers still load. Unknown
///   enum-like VALUES (anomaly types, bottleneck/severity/source names)
///   are NOT ignored — silently dropping an anomaly would corrupt the
///   report's meaning.
/// * Durations travel as millisecond doubles; reconstruction multiplies
///   by 1000 and rounds to whole microseconds, so round-trips carry a
///   documented tolerance of at most ±1 µs per duration.
/// * The returned report's session is an INERT snapshot copy: it holds no
///   live accumulators (statistics are frozen from the summary block),
///   and a document without `ended_at` parses fine but the resulting
///   session's `isActive` is meaningless — parsed snapshots never record.
library;

import 'dart:convert';

import '../anomalies/performance_anomaly.dart';
import '../context/metadata_validator.dart';
import '../frames/frame_budget.dart';
import '../frames/frame_classifier.dart'
    show FrameBottleneck, FrameClassification, FrameSeverity;
import '../frames/frame_sample.dart';
import '../reporting/interaction_summary.dart';
import '../reporting/performance_report.dart';
import '../reporting/screen_summary.dart';
import '../reporting/statistics.dart';
import '../sessions/performance_session.dart';
import '../traces/trace_tracker.dart';
import 'schema.dart';

/// Rebuilds a [PerformanceReport] (and its inert session snapshot) from
/// the PerfScope JSON session shape written by [SessionSerializer].
final class SessionParser {
  /// Creates a parser. Instances are stateless; a single const instance
  /// may be shared freely.
  const SessionParser();

  /// Decodes [raw] JSON text and parses it.
  ///
  /// Throws [FormatException] for syntactically invalid JSON as well as
  /// for every schema violation [parse] reports.
  PerformanceReport parseString(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw FormatException(
        'Invalid PerfScope session file: malformed JSON (${error.message}).',
      );
    }
    if (decoded is! Map) {
      _fail('top level must be an object.');
    }
    // Copy with validated string keys — no casts, so a hostile payload
    // can only ever produce FormatExceptions.
    final root = <String, Object?>{};
    for (final key in decoded.keys) {
      if (key is! String) _fail('top level must be an object.');
      root[key] = decoded[key];
    }
    return parse(root);
  }

  /// Parses an already-decoded JSON object into a [PerformanceReport].
  ///
  /// Unknown extra keys anywhere in the document are ignored (forward
  /// compatibility); everything else is strictly validated.
  PerformanceReport parse(Map<String, Object?> json) {
    // Working view of the incoming map: keys are statically String here,
    // widening to Object? via a plain copy cannot fail at runtime.
    final root = Map<Object?, Object?>.of(json);

    _guardVersion(root);

    // --- Generator block: informational, validated when present. -------
    if (root.containsKey(kKeyGenerator)) {
      final generatorPath = kKeyGenerator;
      if (root[kKeyGenerator] is! Map<Object?, Object?>) {
        _fail('$generatorPath must be an object.');
      }
    }

    // --- Session --------------------------------------------------------
    final sessionMap = _requireMapField(root, kKeySession, kKeySession);
    final sessionId = _requireString(sessionMap, kKeyId, 'session.id');
    final sessionName = _optionalString(sessionMap, kKeyName, 'session.name');
    final startedAt = _requireTimestamp(
      sessionMap,
      kKeyStartedAt,
      'session.started_at',
    );
    final endedAt =
        _optionalTimestamp(sessionMap, kKeyEndedAt, 'session.ended_at');
    final metadata = _requireMetadata(
      sessionMap,
      kKeyMetadata,
      'session.metadata',
    );

    // --- Environment ----------------------------------------------------
    final environmentMap = _requireMapField(
      root,
      kKeyEnvironment,
      kKeyEnvironment,
    );
    final platform = _requireString(
      environmentMap,
      kKeyPlatform,
      'environment.platform',
    );
    final frameBudgetFps = _requireNumber(
      environmentMap,
      kKeyFrameBudgetFps,
      'environment.frame_budget_fps',
    );
    final frameBudgetMs = _requireNumber(
      environmentMap,
      kKeyFrameBudgetMs,
      'environment.frame_budget_ms',
    );
    final frameBudgetSource = _enumByName(
      FrameBudgetSource.values,
      _requireString(
        environmentMap,
        kKeyFrameBudgetSource,
        'environment.frame_budget_source',
      ),
      'environment.frame_budget_source',
    );
    final environment = PerformanceEnvironment(
      frameBudgetFps: frameBudgetFps,
      frameBudgetMs: frameBudgetMs,
      frameBudgetSource: frameBudgetSource,
      platform: platform,
    );

    // --- Summary --------------------------------------------------------
    final summaryMap = _requireMapField(root, kKeySummary, kKeySummary);
    final statistics = SessionStatistics(
      totalFrames:
          _requireInt(summaryMap, kKeyTotalFrames, 'summary.total_frames'),
      normalFrames:
          _requireInt(summaryMap, kKeyNormalFrames, 'summary.normal_frames'),
      warningFrames: _requireInt(
        summaryMap,
        kKeyWarningFrames,
        'summary.warning_frames',
      ),
      slowFrames:
          _requireInt(summaryMap, kKeySlowFrames, 'summary.slow_frames'),
      severeFrames:
          _requireInt(summaryMap, kKeySevereFrames, 'summary.severe_frames'),
      slowFrameRate: _requireNumber(
        summaryMap,
        kKeySlowFrameRate,
        'summary.slow_frame_rate',
      ),
      averageBuildMs: _requireNumber(
        summaryMap,
        kKeyAverageBuildMs,
        'summary.average_build_ms',
      ),
      averageRasterMs: _requireNumber(
        summaryMap,
        kKeyAverageRasterMs,
        'summary.average_raster_ms',
      ),
      averageTotalMs: _requireNumber(
        summaryMap,
        kKeyAverageTotalMs,
        'summary.average_total_ms',
      ),
      p50Ms: _requireNumber(summaryMap, kKeyP50Ms, 'summary.p50_ms'),
      p90Ms: _requireNumber(summaryMap, kKeyP90Ms, 'summary.p90_ms'),
      p95Ms: _requireNumber(summaryMap, kKeyP95Ms, 'summary.p95_ms'),
      p99Ms: _requireNumber(summaryMap, kKeyP99Ms, 'summary.p99_ms'),
      worstFrameMs: _requireNumber(
        summaryMap,
        kKeyWorstFrameMs,
        'summary.worst_frame_ms',
      ),
    );

    // --- Screens / interactions / traces --------------------------------
    final screens = _parseScreens(root);
    final interactions = _parseInteractions(root);
    final traces = _parseTraces(root);

    // --- Anomalies ------------------------------------------------------
    final anomalyList = _requireListField(root, kKeyAnomalies, kKeyAnomalies);
    final anomalies = <PerformanceAnomaly>[];
    for (var i = 0; i < anomalyList.length; i++) {
      anomalies.add(_parseAnomaly(anomalyList[i], 'anomalies[$i]'));
    }

    // The parsed session is an inert snapshot: fresh empty accumulators
    // plus the frozen statistics from the summary block. Parsed anomalies
    // are attached so `session.anomalies` mirrors the document too. A
    // document without `ended_at` yields a session whose `isActive` is
    // true — meaningless by design, since parsed snapshots never record.
    final session = PerformanceSession(
      id: sessionId,
      name: sessionName,
      startedAt: startedAt,
      environment: environment,
      metadata: metadata,
      calculator: StatisticsCalculator(),
      anomalies: List<PerformanceAnomaly>.of(anomalies),
    )
      ..endedAt = endedAt
      ..freezeStatistics(statistics);

    // worstAnomalies is a derived ranking (not serialized); rebuild it
    // with exactly the same ordering rule as the report builder.
    final worstAnomalies = anomalies.toList()..sort(_compareWorstAnomalies);

    final report = PerformanceReport(
      session: session,
      statistics: statistics,
      screens: screens,
      interactions: interactions,
      traces: traces,
      anomalies: anomalies,
      worstAnomalies: worstAnomalies.take(10).toList(),
    );
    session.attachReport(report);
    return report;
  }

  // ---------------------------------------------------------------------------
  // Version guard
  // ---------------------------------------------------------------------------

  void _guardVersion(Map<Object?, Object?> root) {
    if (!root.containsKey(kKeySchemaVersion)) {
      _fail("missing required field '$kKeySchemaVersion'.");
    }
    final version = root[kKeySchemaVersion];
    if (version is! int) {
      _fail('$kKeySchemaVersion must be an int.');
    }
    if (version != kSchemaVersion) {
      // Exact message contract — do not reword or prefix.
      throw FormatException(
        'Unsupported PerfScope schema version: $version. '
        'Supported versions: $kSchemaVersion.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Screens / interactions / traces
  // ---------------------------------------------------------------------------

  List<ScreenPerformanceSummary> _parseScreens(Map<Object?, Object?> root) {
    final list = _requireListField(root, kKeyScreens, kKeyScreens);
    final result = <ScreenPerformanceSummary>[];
    for (var i = 0; i < list.length; i++) {
      final path = '$kKeyScreens[$i]';
      final entry = _requireMap(list[i], path);
      result.add(ScreenPerformanceSummary(
        name: _requireString(entry, kKeyName, '$path.name'),
        totalFrames: _requireInt(entry, kKeyTotalFrames, '$path.total_frames'),
        slowFrames: _requireInt(entry, kKeySlowFrames, '$path.slow_frames'),
        severeFrames:
            _requireInt(entry, kKeySevereFrames, '$path.severe_frames'),
        anomalyCount:
            _requireInt(entry, kKeyAnomalyCount, '$path.anomaly_count'),
        slowFrameRate:
            _requireNumber(entry, kKeySlowFrameRate, '$path.slow_frame_rate'),
        p95Ms: _requireNumber(entry, kKeyP95Ms, '$path.p95_ms'),
        worstMs: _requireNumber(entry, kKeyWorstMs, '$path.worst_ms'),
        probableBottleneck: _enumByName(
          FrameBottleneck.values,
          _requireString(entry, kKeyProbableBottleneck, '$path.bottleneck'),
          '$path.probable_bottleneck',
        ),
      ));
    }
    return result;
  }

  List<InteractionPerformanceSummary> _parseInteractions(
    Map<Object?, Object?> root,
  ) {
    final list = _requireListField(root, kKeyInteractions, kKeyInteractions);
    final result = <InteractionPerformanceSummary>[];
    for (var i = 0; i < list.length; i++) {
      final path = '$kKeyInteractions[$i]';
      final entry = _requireMap(list[i], path);
      result.add(InteractionPerformanceSummary(
        name: _requireString(entry, kKeyName, '$path.name'),
        mostRecentInteractionId: _optionalString(
          entry,
          kKeyMostRecentInteractionId,
          '$path.most_recent_interaction_id',
        ),
        spanCount: _requireInt(entry, kKeySpanCount, '$path.span_count'),
        frameCount: _requireInt(entry, kKeyFrameCount, '$path.frame_count'),
        anomalyCount:
            _requireInt(entry, kKeyAnomalyCount, '$path.anomaly_count'),
        totalSpanDuration: _durationFromMs(
          _requireNumber(
            entry,
            kKeyTotalSpanDurationMs,
            '$path.total_span_duration_ms',
          ),
        ),
        p95Ms: _requireNumber(entry, kKeyP95Ms, '$path.p95_ms'),
        worstMs: _requireNumber(entry, kKeyWorstMs, '$path.worst_ms'),
        probableBottleneck: _enumByName(
          FrameBottleneck.values,
          _requireString(entry, kKeyProbableBottleneck, '$path.bottleneck'),
          '$path.probable_bottleneck',
        ),
      ));
    }
    return result;
  }

  List<CompletedTrace> _parseTraces(Map<Object?, Object?> root) {
    final list = _requireListField(root, kKeyTraces, kKeyTraces);
    final result = <CompletedTrace>[];
    for (var i = 0; i < list.length; i++) {
      final path = '$kKeyTraces[$i]';
      final entry = _requireMap(list[i], path);
      result.add(CompletedTrace(
        id: _requireString(entry, kKeyId, '$path.id'),
        name: _requireString(entry, kKeyName, '$path.name'),
        startedAt: _requireTimestamp(entry, kKeyStartedAt, '$path.started_at'),
        duration: _durationFromMs(
          _requireNumber(entry, kKeyDurationMs, '$path.duration_ms'),
        ),
        screen: _requireString(entry, kKeyScreen, '$path.screen'),
        didThrow: _requireBool(entry, kKeyDidThrow, '$path.did_throw'),
      ));
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Anomalies
  // ---------------------------------------------------------------------------

  PerformanceAnomaly _parseAnomaly(Object? value, String path) {
    final entry = _requireMap(value, path);
    final id = _requireString(entry, kKeyId, '$path.id');
    final type = _requireString(entry, kKeyType, '$path.type');
    final severity = _enumByName(
      AnomalySeverity.values,
      _requireString(entry, kKeySeverity, '$path.severity'),
      '$path.severity',
    );
    final timestamp =
        _requireTimestamp(entry, kKeyTimestamp, '$path.timestamp');
    final screen = _optionalString(entry, kKeyScreen, '$path.screen');
    final interactionId =
        _optionalString(entry, kKeyInteractionId, '$path.interaction_id');
    final metadata = _requireMetadata(entry, kKeyMetadata, '$path.metadata');

    switch (type) {
      case kAnomalyTypeLongTrace:
        return LongTraceAnomaly(
          id: id,
          timestamp: timestamp,
          severity: severity,
          traceId: _requireString(entry, kKeyTraceId, '$path.trace_id'),
          name: _requireString(entry, kKeyName, '$path.name'),
          duration: _durationFromMs(
            _requireNumber(entry, kKeyDurationMs, '$path.duration_ms'),
          ),
          screen: screen,
          interactionId: interactionId,
          metadata: metadata,
        );
      case kAnomalyTypeSlowFrame:
      case kAnomalyTypeUiBoundFrame:
      case kAnomalyTypeRasterBoundFrame:
      case kAnomalyTypeMixedFrame:
        return _parseFrameAnomaly(
          entry,
          path: path,
          type: type,
          id: id,
          severity: severity,
          timestamp: timestamp,
          screen: screen,
          interactionId: interactionId,
          metadata: metadata,
        );
      default:
        _fail(
          "$path.type must be one of ${kKnownAnomalyTypes.join(', ')} "
          "(got '$type').",
        );
    }
  }

  FrameAnomaly _parseFrameAnomaly(
    Map<Object?, Object?> entry, {
    required String path,
    required String type,
    required String id,
    required AnomalySeverity severity,
    required DateTime timestamp,
    required String? screen,
    required String? interactionId,
    required Map<String, Object?> metadata,
  }) {
    // Inverse of FrameAnomaly.severityFor: only high/critical frames ever
    // became anomalies upstream.
    final frameSeverity = switch (severity) {
      AnomalySeverity.high => FrameSeverity.slow,
      AnomalySeverity.critical => FrameSeverity.severe,
      _ => _fail("$path.severity must be 'high' or 'critical' for a frame "
          "anomaly (got '${severity.name}')."),
    };
    final frameEntry = _requireMapField(entry, kKeyFrame, '$path.frame');
    final buildDuration = _durationFromMs(
      _requireNumber(frameEntry, kKeyBuildMs, '$path.frame.build_ms'),
    );
    final rasterDuration = _durationFromMs(
      _requireNumber(frameEntry, kKeyRasterMs, '$path.frame.raster_ms'),
    );
    final totalDuration = _durationFromMs(
      _requireNumber(frameEntry, kKeyTotalMs, '$path.frame.total_ms'),
    );
    final frameBudget = _durationFromMs(
      _requireNumber(frameEntry, kKeyBudgetMs, '$path.frame.budget_ms'),
    );
    final classification = FrameClassification(
      frameSeverity,
      _enumByName(
        FrameBottleneck.values,
        _requireString(
          entry,
          kKeyProbableBottleneck,
          '$path.probable_bottleneck',
        ),
        '$path.probable_bottleneck',
      ),
    );
    // Fields the wire format does not carry (frame ids, vsync overhead,
    // engine frame numbers) get inert defaults; they take part in no
    // correlation after parsing.
    final sample = FrameSample(
      id: 0,
      frameNumber: null,
      capturedAt: timestamp,
      buildDuration: buildDuration,
      rasterDuration: rasterDuration,
      totalDuration: totalDuration,
      vsyncOverhead: Duration.zero,
      frameBudget: frameBudget,
      screen: screen,
      interactionId: interactionId,
    );
    return switch (type) {
      kAnomalyTypeSlowFrame => SlowFrameAnomaly(
          id: id,
          timestamp: timestamp,
          severity: severity,
          sample: sample,
          classification: classification,
          frameBudget: frameBudget,
          screen: screen,
          interactionId: interactionId,
          metadata: metadata,
        ),
      kAnomalyTypeUiBoundFrame => UiBoundFrameAnomaly(
          id: id,
          timestamp: timestamp,
          severity: severity,
          sample: sample,
          classification: classification,
          frameBudget: frameBudget,
          screen: screen,
          interactionId: interactionId,
          metadata: metadata,
        ),
      kAnomalyTypeRasterBoundFrame => RasterBoundFrameAnomaly(
          id: id,
          timestamp: timestamp,
          severity: severity,
          sample: sample,
          classification: classification,
          frameBudget: frameBudget,
          screen: screen,
          interactionId: interactionId,
          metadata: metadata,
        ),
      _ => MixedFrameAnomaly(
          id: id,
          timestamp: timestamp,
          severity: severity,
          sample: sample,
          classification: classification,
          frameBudget: frameBudget,
          screen: screen,
          interactionId: interactionId,
          metadata: metadata,
        ),
    };
  }

  // ---------------------------------------------------------------------------
  // Validation helpers
  // ---------------------------------------------------------------------------

  /// Fails with the canonical message prefix. Every validation error in
  /// this library funnels through here.
  Never _fail(String detail) =>
      throw FormatException('Invalid PerfScope session file: $detail');

  Map<Object?, Object?> _requireMap(Object? value, String path) {
    if (value is! Map<Object?, Object?>) {
      _fail('$path must be an object.');
    }
    return value;
  }

  Object? _fieldValue(Map<Object?, Object?> map, String key, String path) {
    if (!map.containsKey(key)) {
      _fail("missing required field '$path'.");
    }
    return map[key];
  }

  Map<Object?, Object?> _requireMapField(
    Map<Object?, Object?> map,
    String key,
    String path,
  ) =>
      _requireMap(_fieldValue(map, key, path), path);

  List<Object?> _requireListField(
    Map<Object?, Object?> map,
    String key,
    String path,
  ) {
    final value = _fieldValue(map, key, path);
    if (value is! List<Object?>) {
      _fail('$path must be an array.');
    }
    return value;
  }

  String _requireString(
    Map<Object?, Object?> map,
    String key,
    String path,
  ) {
    final value = _fieldValue(map, key, path);
    if (value is! String) {
      _fail('$path must be a string.');
    }
    return value;
  }

  String? _optionalString(
    Map<Object?, Object?> map,
    String key,
    String path,
  ) {
    if (!map.containsKey(key)) return null;
    final value = map[key];
    if (value == null) return null;
    if (value is! String) _fail('$path must be a string.');
    return value;
  }

  int _requireInt(Map<Object?, Object?> map, String key, String path) {
    final value = _fieldValue(map, key, path);
    if (value is! int) {
      _fail('$path must be an int.');
    }
    return value;
  }

  double _requireNumber(
    Map<Object?, Object?> map,
    String key,
    String path,
  ) {
    final value = _fieldValue(map, key, path);
    if (value is! num) {
      _fail('$path must be a number.');
    }
    return value.toDouble();
  }

  bool _requireBool(Map<Object?, Object?> map, String key, String path) {
    final value = _fieldValue(map, key, path);
    if (value is! bool) {
      _fail('$path must be a boolean.');
    }
    return value;
  }

  DateTime _requireTimestamp(
    Map<Object?, Object?> map,
    String key,
    String path,
  ) {
    final value = _requireString(map, key, path);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      _fail("$path must be an ISO-8601 timestamp (got '$value').");
    }
    return parsed;
  }

  DateTime? _optionalTimestamp(
    Map<Object?, Object?> map,
    String key,
    String path,
  ) {
    if (!map.containsKey(key)) return null;
    final value = map[key];
    if (value == null) return null;
    if (value is! String) _fail('$path must be a string.');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      _fail("$path must be an ISO-8601 timestamp (got '$value').");
    }
    return parsed;
  }

  /// Validates and defensively copies a metadata block through the SAME
  /// allow-list rules used everywhere else in PerfScope. Violations become
  /// [FormatException]s, never [ArgumentError]/[TypeError].
  Map<String, Object?> _requireMetadata(
    Map<Object?, Object?> map,
    String key,
    String path,
  ) {
    final entries = _requireMapField(map, key, path);
    final result = <String, Object?>{};
    entries.forEach((entryKey, value) {
      if (entryKey is! String) {
        _fail('$path keys must be strings.');
      }
      try {
        MetadataValidator.validate(entryKey, value);
      } on ArgumentError catch (error) {
        _fail('$path has invalid metadata: ${error.message ?? error}');
      }
      result[entryKey] = MetadataValidator.defensiveCopy(value);
    });
    return result;
  }

  T _enumByName<T extends Enum>(List<T> values, String name, String path) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    _fail(
      "$path must be one of ${values.map((v) => v.name).join(', ')} "
      "(got '$name').",
    );
  }
}

// ---------------------------------------------------------------------------
// File-level helpers
// ---------------------------------------------------------------------------

/// Milliseconds → [Duration]: multiply by 1000 and round to whole
/// microseconds. Round-trip tolerance versus the original integer-
/// microsecond duration is at most ±1 µs (documented contract).
Duration _durationFromMs(double ms) => Duration(
      microseconds: (ms * Duration.microsecondsPerMillisecond).round(),
    );

/// Ordering duration used for worst-anomaly ranking; matches the report
/// builder's rule (trace duration, else the frame's total).
Duration _orderingDurationOf(PerformanceAnomaly anomaly) => switch (anomaly) {
      LongTraceAnomaly(:final duration) => duration,
      FrameAnomaly(:final sample) => sample.totalDuration,
    };

int _compareWorstAnomalies(PerformanceAnomaly a, PerformanceAnomaly b) {
  final bySeverity = b.severity.index.compareTo(a.severity.index);
  if (bySeverity != 0) return bySeverity;
  final byDuration = _orderingDurationOf(b).compareTo(_orderingDurationOf(a));
  if (byDuration != 0) return byDuration;
  return a.id.compareTo(b.id);
}
