import 'dart:ui' show FlutterView, PlatformDispatcher;

import '../frames/frame_budget.dart';
import 'perfscope_config.dart';

/// Signature of the refresh-rate detection probe.
///
/// Returns a plausible display refresh rate in Hz, or null when no rate can
/// be trusted. Injectable so tests can exercise every resolution path
/// deterministically.
typedef RefreshRateProbe = double? Function();

/// Resolves the [FrameBudgetProvider] frames are judged against.
///
/// Resolution precedence:
///
/// 1. **Detected** — when a plausible refresh rate is detected AND the
///    config keeps the default [PerfScopeConfig.targetFrameRate] (60), the
///    detected rate wins ([FrameBudgetSource.detected]).
/// 2. **Configured** — when the config explicitly differs from 60, the
///    configured rate overrides detection ([FrameBudgetSource.configured]).
/// 3. **Fallback** — nothing detected and nothing configured beyond the
///    default yields the conservative 60Hz budget
///    ([FrameBudgetSource.fallback]).
///
/// TRADEOFF: because [PerfScopeConfig.targetFrameRate] defaults to 60 rather
/// than being nullable, an app on a 90Hz device that *explicitly* wants 60Hz
/// cannot express that intent; the detected 90Hz budget will be used.
/// TODO(v0.2): make targetFrameRate nullable so explicit configuration can be
/// distinguished from the default and always take priority over detection.
final class FrameBudgetResolver {
  /// Creates a resolver for [config], using [probeRefreshRate] to detect the
  /// device refresh rate (defaults to the real platform probe).
  FrameBudgetResolver({
    required this.config,
    this.probeRefreshRate = detectRefreshRate,
  });

  /// Configuration whose target frame rate participates in resolution.
  final PerfScopeConfig config;

  /// Detection probe; see [RefreshRateProbe].
  final RefreshRateProbe probeRefreshRate;

  static const int _defaultTargetFps = 60;

  /// Resolves the effective frame budget provider.
  FrameBudgetProvider resolve() {
    final detectedFps = detect();
    final targetFps = config.targetFrameRate.toDouble();

    if (detectedFps != null && config.targetFrameRate == _defaultTargetFps) {
      return _DetectedFrameBudget(FixedFrameBudget.fromFps(detectedFps));
    }
    if (config.targetFrameRate != _defaultTargetFps) {
      return FixedFrameBudget.fromFps(targetFps);
    }
    return const _FallbackFrameBudget();
  }

  /// Runs the probe, converting any failure into "nothing detected".
  ///
  /// Detection must never break initialization: exotic embedders may not
  /// expose displays at all, and probing must therefore be fail-safe.
  double? detect() {
    try {
      return probeRefreshRate();
    } catch (_) {
      return null;
    }
  }

  /// Real probe: returns the first view's refresh rate when it falls in a
  /// plausible range (>1 and <=1000 Hz), otherwise null.
  ///
  /// Plausibility filtering guards against headless/embedded views that
  /// report sentinel values such as 0.
  static double? detectRefreshRate() {
    try {
      for (final FlutterView view in PlatformDispatcher.instance.views) {
        final double rate = view.display.refreshRate;
        if (rate > 1 && rate <= 1000) {
          return rate;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

/// Provider reporting [FrameBudgetSource.detected] while reusing the fixed
/// budget math from [FixedFrameBudget.fromFps].
final class _DetectedFrameBudget implements FrameBudgetProvider {
  const _DetectedFrameBudget(this._delegate);

  final FixedFrameBudget _delegate;

  @override
  Duration get currentBudget => _delegate.currentBudget;

  @override
  FrameBudgetSource get source => FrameBudgetSource.detected;
}

/// Provider serving the conservative fallback budget.
final class _FallbackFrameBudget implements FrameBudgetProvider {
  const _FallbackFrameBudget();

  @override
  Duration get currentBudget => FixedFrameBudget.fallbackBudget;

  @override
  FrameBudgetSource get source => FrameBudgetSource.fallback;
}
