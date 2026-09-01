import '../events/performance_event.dart';

/// Turns one [PerformanceEvent] into its textual representation.
///
/// Contract:
/// * Returns `null` to suppress the event entirely (wrong style, filtered
///   tier, disabled verbosity).
/// * Implementations are PURE: no IO, no clock access, no global state.
/// * Returned text never ends with a newline; the caller owns line/block
///   termination.
abstract interface class EventRenderer {
  /// Renders [event], or returns null when this renderer does not apply.
  String? render(PerformanceEvent event);
}
