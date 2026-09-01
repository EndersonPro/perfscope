/// PerfScope session-file schema, version 1.
///
/// Single source of truth for every constant used by BOTH the serializer
/// ([SessionSerializer]) and the parser ([SessionParser]): the schema
/// version, generator identity, JSON key names, and anomaly type strings.
/// Neither side may hard-code a literal that exists here.
///
/// Forward compatibility contract:
/// * The parser MUST ignore unknown top-level and nested keys so files
///   written by newer minor versions still load.
/// * New enum-like string values (anomaly types, bottleneck/severity/
///   budget-source names) are NOT forward compatible: encountering an
///   unknown one is a hard parse error, because silently dropping an
///   anomaly would corrupt the report's meaning.
library;

/// Schema version this package writes and accepts.
const int kSchemaVersion = 1;

/// Value written under the `generator.name` key.
const String kGeneratorName = 'perfscope';

/// Value written under the `generator.version` key.
///
/// MUST be kept in sync manually with `version:` in pubspec.yaml — there
/// is deliberately no codegen step in this package.
const String kGeneratorVersion = '0.1.0';

// ---------------------------------------------------------------------------
// Top-level document keys
// ---------------------------------------------------------------------------

const String kKeySchemaVersion = 'schema_version';
const String kKeyGenerator = 'generator';
const String kKeySession = 'session';
const String kKeyEnvironment = 'environment';
const String kKeySummary = 'summary';
const String kKeyScreens = 'screens';
const String kKeyInteractions = 'interactions';
const String kKeyTraces = 'traces';
const String kKeyAnomalies = 'anomalies';

// ---------------------------------------------------------------------------
// Generator block
// ---------------------------------------------------------------------------

const String kKeyName = 'name';
const String kKeyVersion = 'version';

// ---------------------------------------------------------------------------
// Session / environment blocks
// ---------------------------------------------------------------------------

const String kKeyId = 'id';
const String kKeyStartedAt = 'started_at';
const String kKeyEndedAt = 'ended_at';
const String kKeyMetadata = 'metadata';
const String kKeyPlatform = 'platform';
const String kKeyFrameBudgetFps = 'frame_budget_fps';
const String kKeyFrameBudgetMs = 'frame_budget_ms';
const String kKeyFrameBudgetSource = 'frame_budget_source';

// ---------------------------------------------------------------------------
// Summary block
// ---------------------------------------------------------------------------

const String kKeyTotalFrames = 'total_frames';
const String kKeyNormalFrames = 'normal_frames';
const String kKeyWarningFrames = 'warning_frames';
const String kKeySlowFrames = 'slow_frames';
const String kKeySevereFrames = 'severe_frames';
const String kKeySlowFrameRate = 'slow_frame_rate';
const String kKeyAverageBuildMs = 'average_build_ms';
const String kKeyAverageRasterMs = 'average_raster_ms';
const String kKeyAverageTotalMs = 'average_total_ms';
const String kKeyP50Ms = 'p50_ms';
const String kKeyP90Ms = 'p90_ms';
const String kKeyP95Ms = 'p95_ms';
const String kKeyP99Ms = 'p99_ms';
const String kKeyWorstFrameMs = 'worst_frame_ms';

// ---------------------------------------------------------------------------
// Screen / interaction summary entries
// ---------------------------------------------------------------------------

const String kKeyAnomalyCount = 'anomaly_count';
const String kKeyMostRecentInteractionId = 'most_recent_interaction_id';
const String kKeySpanCount = 'span_count';
const String kKeyFrameCount = 'frame_count';
const String kKeyTotalSpanDurationMs = 'total_span_duration_ms';
const String kKeyWorstMs = 'worst_ms';
const String kKeyProbableBottleneck = 'probable_bottleneck';

// ---------------------------------------------------------------------------
// Trace entries
// ---------------------------------------------------------------------------

const String kKeyDurationMs = 'duration_ms';
const String kKeyScreen = 'screen';
const String kKeyDidThrow = 'did_throw';

// ---------------------------------------------------------------------------
// Anomaly entries
// ---------------------------------------------------------------------------

const String kKeyType = 'type';
const String kKeySeverity = 'severity';
const String kKeyTimestamp = 'timestamp';
const String kKeyInteractionId = 'interaction_id';
const String kKeyFrame = 'frame';
const String kKeyBuildMs = 'build_ms';
const String kKeyRasterMs = 'raster_ms';
const String kKeyTotalMs = 'total_ms';
const String kKeyBudgetMs = 'budget_ms';
const String kKeyTraceId = 'trace_id';
const String kKeyContextWindow = 'context_window';
const String kKeyBefore = 'before';
const String kKeyAfter = 'after';

// ---------------------------------------------------------------------------
// Anomaly type discriminator strings ([PerformanceAnomaly] family)
// ---------------------------------------------------------------------------

const String kAnomalyTypeSlowFrame = 'slow_frame';
const String kAnomalyTypeUiBoundFrame = 'ui_bound_frame';
const String kAnomalyTypeRasterBoundFrame = 'raster_bound_frame';
const String kAnomalyTypeMixedFrame = 'mixed_frame';
const String kAnomalyTypeLongTrace = 'long_trace';

/// Every anomaly type string a v1 writer may emit, for error messages.
const List<String> kKnownAnomalyTypes = <String>[
  kAnomalyTypeSlowFrame,
  kAnomalyTypeUiBoundFrame,
  kAnomalyTypeRasterBoundFrame,
  kAnomalyTypeMixedFrame,
  kAnomalyTypeLongTrace,
];
