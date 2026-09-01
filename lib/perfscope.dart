/// PerfScope — local performance observability for Flutter.
///
/// PerfScope detects performance anomalies (jank, long interactions,
/// expensive traces), tracks screens and user interactions, records
/// sessions, compares regressions against baselines, and generates
/// AI-ready performance reports — all locally, on-device.
///
/// This barrel exposes the domain foundation plus the Flutter integration:
/// * [PerfScopeConfig] and [PerformanceThresholds] for configuration.
/// * [Clock] / [SystemClock] for injectable time.
/// * [FrameSample], [FrameBudgetProvider], [FixedFrameBudget],
///   [FrameClassifier] for frame analysis.
/// * [RingBuffer] as a general-purpose fixed-capacity utility.
/// * [PerfScope] facade, [PerfScopeEngine], [FlutterFrameSource], and the
///   [PerformanceEvent] hierarchy for runtime integration.
/// * Manual tracing ([CompletedTrace], [TraceTracker], timeline adapters)
///   and the [PerformanceAnomaly] family.
/// * Session lifecycle ([PerformanceSession], [SessionManager]) and the
///   reporting models ([SessionStatistics], [PerformanceReport],
///   [ScreenPerformanceSummary], [InteractionPerformanceSummary]).
/// * AI-ready context generation ([AiContextConfig],
///   [buildAiContextText], [buildAiContextJson], the `ReportAiContext`
///   extension) and session comparison ([SessionComparator],
///   [SessionComparison]).
library;

export 'src/ai/ai_context_builder.dart';
export 'src/ai/ai_context_config.dart';
export 'src/ai/report_ai_extensions.dart';
export 'src/anomalies/anomaly_detector.dart';
export 'src/anomalies/frame_context_window.dart';
export 'src/anomalies/performance_anomaly.dart';
export 'src/buffers/ring_buffer.dart';
export 'src/cli/perfscope_cli.dart';
export 'src/cli/system_probe.dart';
export 'src/context/interaction_tracker.dart';
export 'src/context/metadata_store.dart';
export 'src/context/screen_tracker.dart';
export 'src/core/clock.dart';
export 'src/core/frame_budget_resolver.dart';
export 'src/core/perfscope_config.dart';
export 'src/core/perfscope_engine.dart';
export 'src/events/performance_event.dart';
export 'src/exporters/callback_exporter.dart';
export 'src/exporters/in_memory_exporter.dart';
export 'src/exporters/performance_exporter.dart';
export 'src/exporters/text_exporter.dart';
export 'src/exporters/text_report_formatter.dart';
export 'src/frames/frame_budget.dart';
export 'src/frames/frame_classifier.dart';
export 'src/frames/frame_sample.dart';
export 'src/frames/frame_source.dart';
export 'src/frames/flutter_frame_source.dart';
export 'src/logging/compact_renderer.dart';
export 'src/logging/event_renderer.dart';
export 'src/logging/json_renderer.dart';
export 'src/logging/log_style.dart';
export 'src/logging/log_writer.dart';
export 'src/logging/performance_logger.dart';
export 'src/logging/pretty_renderer.dart';
export 'src/navigation/perfscope_navigator_observer.dart';
export 'src/navigation/screen_context_port.dart';
export 'src/perfscope_facade.dart';
export 'src/reporting/comparison_formatter.dart';
export 'src/reporting/interaction_summary.dart';
export 'src/reporting/performance_report.dart';
export 'src/reporting/report_builder.dart';
export 'src/reporting/screen_summary.dart';
export 'src/reporting/session_comparison.dart';
export 'src/reporting/statistics.dart';
export 'src/serialization/schema.dart';
export 'src/serialization/session_parser.dart';
export 'src/serialization/session_serializer.dart';
export 'src/sessions/performance_session.dart';
export 'src/sessions/session_manager.dart';
export 'src/sinks/console_sink.dart';
export 'src/sinks/json_sink.dart';
export 'src/sinks/memory_sink.dart';
export 'src/sinks/performance_event_sink.dart';
export 'src/traces/timeline_adapter.dart';
export 'src/traces/trace_tracker.dart';
