/// Provenance of the frame budget currently in effect.
enum FrameBudgetSource {
  /// Detected from the device's actual display refresh rate.
  detected,

  /// Explicitly configured by the application (e.g. from a target FPS).
  configured,

  /// Safe default used when detection and configuration are unavailable.
  fallback,
}

/// Provides the frame duration budget frames are judged against.
///
/// A budget corresponds to the display refresh interval: 16.667ms at 60Hz,
/// 11.111ms at 90Hz, 8.333ms at 120Hz, and 6.944ms at 144Hz.
abstract interface class FrameBudgetProvider {
  /// The current per-frame time budget.
  Duration get currentBudget;

  /// Where the current budget came from.
  FrameBudgetSource get source;
}

/// [FrameBudgetProvider] backed by a fixed, pre-computed budget.
final class FixedFrameBudget implements FrameBudgetProvider {
  const FixedFrameBudget._(this._budget);

  /// Creates a fixed budget for the given refresh rate [fps].
  ///
  /// Examples: 60Hz -> 16.667ms, 90Hz -> 11.111ms, 120Hz -> 8.333ms,
  /// 144Hz -> 6.944ms.
  factory FixedFrameBudget.fromFps(double fps) => FixedFrameBudget._(
        Duration(microseconds: (Duration.microsecondsPerSecond / fps).round()),
      );

  final Duration _budget;

  /// Conservative default budget used when nothing better is known
  /// (equivalent to a 60Hz display).
  static const Duration fallbackBudget = Duration(microseconds: 16667);

  @override
  Duration get currentBudget => _budget;

  @override
  FrameBudgetSource get source => FrameBudgetSource.configured;
}
