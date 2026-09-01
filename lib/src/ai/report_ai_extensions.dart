/// Convenience extension exposing AI-ready context directly on
/// [PerformanceReport].
///
/// Thin delegation to the pure builders in `ai_context_builder.dart` —
/// all semantics (caps, omission rules, truncation) live there.
library;

import '../reporting/performance_report.dart';
import 'ai_context_builder.dart';
import 'ai_context_config.dart';

/// AI-ready context generation on every [PerformanceReport].
extension ReportAiContext on PerformanceReport {
  /// Plain-text, token-optimized context for LLM prompts.
  String toAiContext({AiContextConfig config = const AiContextConfig()}) =>
      buildAiContextText(this, config: config);

  /// Compact structured context for programmatic/JSON consumption.
  ///
  /// [now] injects the clock used for `generated_at`; defaults to the
  /// real wall clock so production callers need no setup.
  Map<String, Object?> toAiJson({
    AiContextConfig config = const AiContextConfig(),
    DateTime Function()? now,
  }) =>
      buildAiContextJson(this, config: config, now: now);
}
