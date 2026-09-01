/// Exporter abstraction for PerfScope sessions.
///
/// An exporter turns one [PerformanceSession] into an external artifact
/// (a JSON string handed to a callback, an in-memory slot, a text block).
/// Core PerfScope deliberately ships NO filesystem exporter: storage
/// destinations are host concerns, while this interface gives embedders a
/// stable seam.
///
/// Serialization always flows through [reportForExport] +
/// [SessionSerializer], so every exporter emits byte-identical JSON for
/// identical inputs.
library;

import '../anomalies/frame_context_window.dart' show FrameContextWindow;
import '../reporting/interaction_summary.dart'
    show InteractionPerformanceSummary;
import '../reporting/performance_report.dart' show PerformanceReport;
import '../reporting/screen_summary.dart' show ScreenPerformanceSummary;
import '../serialization/session_serializer.dart';
import '../sessions/performance_session.dart' show PerformanceSession;

/// Destination for serialized PerfScope sessions.
///
/// The optional resolver parameter mirrors [SessionSerializer.serialize]:
/// when provided it answers context windows for frame-anomaly ids so
/// surrounding frames can be embedded; passing null keeps files compact.
abstract interface class PerformanceExporter {
  /// Exports [session]. Must not throw for valid sessions; failures to
  /// reach the destination may propagate to the caller.
  Future<void> export(
    PerformanceSession session, {
    FrameContextWindow? Function(String anomalyId)? resolveContextWindow,
  });
}

/// Returns the report backing an export of [session]: the report attached
/// by the session manager on stop/auto-finalize, or a minimal snapshot
/// built from the session's live aggregates when none was attached yet
/// (mid-session export).
///
/// The fallback contains session-wide statistics and attributed anomalies,
/// and no screen/interaction/trace breakdowns — exactly what the session
/// alone can answer.
PerformanceReport reportForExport(PerformanceSession session) {
  final attached = session.attachedReport;
  if (attached != null) {
    return attached;
  }
  return PerformanceReport(
    session: session,
    statistics: session.statistics(),
    screens: const <ScreenPerformanceSummary>[],
    interactions: const <InteractionPerformanceSummary>[],
    traces: const [],
    anomalies: session.anomalies,
    worstAnomalies: session.anomalies,
  );
}
