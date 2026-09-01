/// Tuning knobs for AI-ready context generation.
///
/// [AiContextConfig] bounds the SIZE of generated context so an LLM prompt
/// never explodes on a long session: it caps the number of issues listed,
/// the number of secondary records (anomalies, traces) embedded, and the
/// hard character budget of the plain-text rendering.
///
/// Instances are immutable and const-constructible; embed one as a const
/// default wherever context is generated.
library;

/// Configuration for [buildAiContextText] / [buildAiContextJson] (and the
/// `PerformanceReport.toAiContext` / `toAiJson` extension methods).
final class AiContextConfig {
  /// Creates an immutable configuration.
  ///
  /// All bounds must be positive; [maxChars] is a HARD cap on the text
  /// output length including its truncation marker.
  const AiContextConfig({
    this.maxTopIssues = 10,
    this.maxAnomaliesListed = 20,
    this.includeTraces = true,
    this.includeScreens = true,
    this.includeInteractions = true,
    this.maxChars = 12000,
  })  : assert(maxTopIssues > 0, 'maxTopIssues must be positive'),
        assert(maxAnomaliesListed > 0, 'maxAnomaliesListed must be positive'),
        assert(maxChars > 0, 'maxChars must be positive');

  /// Maximum number of top issues (ranked screens) emitted.
  final int maxTopIssues;

  /// Budget for secondary bounded lists (anomaly entries, trace entries)
  /// in structured output; also caps the trace list length in JSON.
  final int maxAnomaliesListed;

  /// Whether completed traces are embedded at all.
  final bool includeTraces;

  /// Whether per-screen summaries feed the top-issues section.
  final bool includeScreens;

  /// Whether interaction data may be merged into issue blocks.
  final bool includeInteractions;

  /// Hard cap, in characters, on the plain-text output. Longer output is
  /// truncated gracefully with a visible `...[truncated]` marker.
  final int maxChars;

  /// Copies this config, replacing only the given fields.
  AiContextConfig copyWith({
    int? maxTopIssues,
    int? maxAnomaliesListed,
    bool? includeTraces,
    bool? includeScreens,
    bool? includeInteractions,
    int? maxChars,
  }) {
    return AiContextConfig(
      maxTopIssues: maxTopIssues ?? this.maxTopIssues,
      maxAnomaliesListed: maxAnomaliesListed ?? this.maxAnomaliesListed,
      includeTraces: includeTraces ?? this.includeTraces,
      includeScreens: includeScreens ?? this.includeScreens,
      includeInteractions: includeInteractions ?? this.includeInteractions,
      maxChars: maxChars ?? this.maxChars,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiContextConfig &&
          runtimeType == other.runtimeType &&
          maxTopIssues == other.maxTopIssues &&
          maxAnomaliesListed == other.maxAnomaliesListed &&
          includeTraces == other.includeTraces &&
          includeScreens == other.includeScreens &&
          includeInteractions == other.includeInteractions &&
          maxChars == other.maxChars;

  @override
  int get hashCode => Object.hash(maxTopIssues, maxAnomaliesListed,
      includeTraces, includeScreens, includeInteractions, maxChars);

  @override
  String toString() => 'AiContextConfig('
      'maxTopIssues: $maxTopIssues, '
      'maxAnomaliesListed: $maxAnomaliesListed, '
      'includeTraces: $includeTraces, '
      'includeScreens: $includeScreens, '
      'includeInteractions: $includeInteractions, '
      'maxChars: $maxChars)';
}
