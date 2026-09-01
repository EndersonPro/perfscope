/// Before/after comparison of two [PerformanceReport] sessions.
///
/// Pure value computation: pairing is by NAME (screens pair with screens
/// of the same name, interactions likewise), unmatched names appear
/// single-sided, and every delta is a plain percentage the caller can
/// render or diff. Nothing here decides "good" or "bad" — sign and
/// magnitude are reported; judgment stays with the caller.
///
/// Units: rates are expressed in PERCENTAGE POINTS (a `slow_frame_rate`
/// of `0.002` becomes `0.2` with unit `'%'`) so the unit label is honest;
/// durations stay in milliseconds; frame counts are labeled `'frames'`.
///
/// Determinism: union lists (screens, interactions) are sorted by name,
/// and warnings are emitted in a fixed order, so identical inputs always
/// yield identically ordered comparisons.
library;

import 'interaction_summary.dart';
import 'performance_report.dart';
import 'screen_summary.dart';
import 'statistics.dart';

/// One compared metric between two sessions.
final class MetricComparison {
  /// Creates an immutable metric comparison.
  const MetricComparison({
    required this.label,
    required this.before,
    required this.after,
    required this.deltaPercent,
    required this.unit,
  });

  /// Stable snake_case metric name (`slow_frame_rate`, `p95`,
  /// `worst_frame`, ...).
  final String label;

  /// Value in the before session; null when the record exists only after.
  final double? before;

  /// Value in the after session; null when the record exists only before.
  final double? after;

  /// Relative change `(after - before) / before * 100`, rounded to one
  /// decimal. Null when `before` is zero (relative change undefined) or
  /// when either side is missing (single-sided entry).
  ///
  /// Sign convention: NEGATIVE means improvement for every metric listed
  /// here (all are "lower is better").
  final double? deltaPercent;

  /// Unit of [before] / [after]: `'%'` (percentage points) for rates,
  /// `'ms'` for durations, `'frames'` for counts.
  final String unit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetricComparison &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          before == other.before &&
          after == other.after &&
          deltaPercent == other.deltaPercent &&
          unit == other.unit;

  @override
  int get hashCode => Object.hash(label, before, after, deltaPercent, unit);

  @override
  String toString() => 'MetricComparison($label: $before -> $after $unit '
      '(delta ${deltaPercent ?? '-'}%))';
}

/// Paired comparison of one screen across two sessions.
final class ScreenComparison {
  /// Creates an immutable screen comparison over precomputed [metrics].
  const ScreenComparison({
    required this.screen,
    required this.before,
    required this.after,
    required this.metrics,
  });

  /// Screen name both sides were paired on.
  final String screen;

  /// Before-session summary; null when the screen exists only after.
  final ScreenPerformanceSummary? before;

  /// After-session summary; null when the screen exists only before.
  final ScreenPerformanceSummary? after;

  /// Every metric BOTH models carry: `slow_frame_rate` (%), `p95` (ms),
  /// `worst_frame` (ms). Single-sided entries still list all three
  /// metrics with the missing side null and no delta.
  final List<MetricComparison> metrics;
}

/// Paired comparison of one interaction across two sessions.
final class InteractionComparison {
  /// Creates an immutable interaction comparison over precomputed
  /// [metrics].
  const InteractionComparison({
    required this.interaction,
    required this.before,
    required this.after,
    required this.metrics,
  });

  /// Interaction name both sides were paired on.
  final String interaction;

  /// Before-session summary; null when it exists only after.
  final InteractionPerformanceSummary? before;

  /// After-session summary; null when it exists only before.
  final InteractionPerformanceSummary? after;

  /// Metrics the interaction model carries: `p95` (ms) and `worst_frame`
  /// (ms) — interaction summaries expose no rate, phase averages, or p99.
  final List<MetricComparison> metrics;
}

/// Full before/after comparison of two finished-session reports.
final class SessionComparison {
  /// Creates an immutable comparison.
  const SessionComparison({
    required this.before,
    required this.after,
    required this.overall,
    required this.screens,
    required this.interactions,
    required this.warnings,
  });

  /// Baseline session report.
  final PerformanceReport before;

  /// Compared-against session report.
  final PerformanceReport after;

  /// Session-wide metrics, always the complete set: `slow_frame_rate`
  /// (%), `p95` (ms), `p99` (ms), `worst_frame` (ms), `average_build`
  /// (ms), `average_raster` (ms).
  final List<MetricComparison> overall;

  /// Per-screen comparisons: union of both reports' screen names sorted
  /// alphabetically; names present in only one report appear once with
  /// the other side null.
  final List<ScreenComparison> screens;

  /// Per-interaction comparisons: same union pattern as [screens].
  final List<InteractionComparison> interactions;

  /// Human-readable comparability caveats (see [SessionComparator] for
  /// the exact rules and their rationale).
  final List<String> warnings;
}

/// Pure comparator producing a [SessionComparison] from two reports.
abstract final class SessionComparator {
  /// Minimum frame count under which a session's percentiles are treated
  /// as statistically noisy.
  static const int lowSampleFrameThreshold = 100;

  /// Frame-count ratio above which sessions are considered incomparable
  /// in scale.
  static const int scaleMismatchRatio = 10;

  /// Compares [before] against [after].
  ///
  /// Warning rules, emitted in this fixed order:
  ///
  /// 1. DISJOINT SCREENS — both reports contain screens but share none.
  ///    Every screen entry ends up single-sided, so screen-level numbers
  ///    cannot be read as regressions or improvements.
  /// 2. LOW SAMPLE — a session recorded fewer than
  ///    [lowSampleFrameThreshold] frames; small samples make percentile
  ///    swings statistically meaningless. One warning per offending side.
  /// 3. SCALE MISMATCH — both sessions have frames and the larger count
  ///    exceeds the smaller by more than [scaleMismatchRatio]x; aggregate
  ///    shifts may reflect session LENGTH rather than real changes. (A
  ///    zero-frame side is already covered by the low-sample rule.)
  static SessionComparison compare(
    PerformanceReport before,
    PerformanceReport after,
  ) {
    return SessionComparison(
      before: before,
      after: after,
      overall: _overallMetrics(before.statistics, after.statistics),
      screens: _pairedScreens(before, after),
      interactions: _pairedInteractions(before, after),
      warnings: _warnings(before, after),
    );
  }

  // ---------------------------------------------------------------------------
  // Overall metrics (complete six-metric set from SessionStatistics).
  // ---------------------------------------------------------------------------

  static List<MetricComparison> _overallMetrics(
    SessionStatistics before,
    SessionStatistics after,
  ) {
    return [
      _metric(
        'slow_frame_rate',
        '%',
        _asPercentPoints(before.slowFrameRate),
        _asPercentPoints(after.slowFrameRate),
      ),
      _metric('p95', 'ms', before.p95Ms, after.p95Ms),
      _metric('p99', 'ms', before.p99Ms, after.p99Ms),
      _metric('worst_frame', 'ms', before.worstFrameMs, after.worstFrameMs),
      _metric(
          'average_build', 'ms', before.averageBuildMs, after.averageBuildMs),
      _metric('average_raster', 'ms', before.averageRasterMs,
          after.averageRasterMs),
    ];
  }

  // ---------------------------------------------------------------------------
  // Pairing helpers (union by name, alphabetical, single-sided allowed).
  // ---------------------------------------------------------------------------

  static List<ScreenComparison> _pairedScreens(
    PerformanceReport before,
    PerformanceReport after,
  ) {
    final beforeByName = <String, ScreenPerformanceSummary>{
      for (final screen in before.screens) screen.name: screen,
    };
    final afterByName = <String, ScreenPerformanceSummary>{
      for (final screen in after.screens) screen.name: screen,
    };
    final names = <String>{...beforeByName.keys, ...afterByName.keys}.toList()
      ..sort();
    return [
      for (final name in names)
        _screenComparison(name, beforeByName[name], afterByName[name]),
    ];
  }

  static ScreenComparison _screenComparison(
    String name,
    ScreenPerformanceSummary? b,
    ScreenPerformanceSummary? a,
  ) {
    return ScreenComparison(
      screen: name,
      before: b,
      after: a,
      metrics: [
        _metric(
          'slow_frame_rate',
          '%',
          b == null ? null : _asPercentPoints(b.slowFrameRate),
          a == null ? null : _asPercentPoints(a.slowFrameRate),
        ),
        _metric('p95', 'ms', b?.p95Ms, a?.p95Ms),
        _metric('worst_frame', 'ms', b?.worstMs, a?.worstMs),
      ],
    );
  }

  static List<InteractionComparison> _pairedInteractions(
    PerformanceReport before,
    PerformanceReport after,
  ) {
    final beforeByName = <String, InteractionPerformanceSummary>{
      for (final interaction in before.interactions)
        interaction.name: interaction,
    };
    final afterByName = <String, InteractionPerformanceSummary>{
      for (final interaction in after.interactions)
        interaction.name: interaction,
    };
    final names = <String>{...beforeByName.keys, ...afterByName.keys}.toList()
      ..sort();
    return [
      for (final name in names)
        _interactionComparison(name, beforeByName[name], afterByName[name]),
    ];
  }

  static InteractionComparison _interactionComparison(
    String name,
    InteractionPerformanceSummary? b,
    InteractionPerformanceSummary? a,
  ) {
    return InteractionComparison(
      interaction: name,
      before: b,
      after: a,
      metrics: [
        _metric('p95', 'ms', b?.p95Ms, a?.p95Ms),
        _metric('worst_frame', 'ms', b?.worstMs, a?.worstMs),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Warnings (fixed emission order; each rule documented above).
  // ---------------------------------------------------------------------------

  static List<String> _warnings(
    PerformanceReport before,
    PerformanceReport after,
  ) {
    final warnings = <String>[];

    final beforeScreens = before.screens.map((s) => s.name).toSet();
    final afterScreens = after.screens.map((s) => s.name).toSet();
    if (beforeScreens.isNotEmpty &&
        afterScreens.isNotEmpty &&
        beforeScreens.intersection(afterScreens).isEmpty) {
      warnings.add('No screens are shared between the two sessions; '
          'every screen entry is single-sided and cannot be read as a '
          'regression or an improvement.');
    }

    if (before.statistics.totalFrames < lowSampleFrameThreshold) {
      warnings.add('Low sample: the \'before\' session recorded '
          '${before.statistics.totalFrames} frames '
          '(<$lowSampleFrameThreshold); percentile shifts may be noise.');
    }
    if (after.statistics.totalFrames < lowSampleFrameThreshold) {
      warnings.add('Low sample: the \'after\' session recorded '
          '${after.statistics.totalFrames} frames '
          '(<$lowSampleFrameThreshold); percentile shifts may be noise.');
    }

    final beforeFrames = before.statistics.totalFrames;
    final afterFrames = after.statistics.totalFrames;
    final smaller = beforeFrames <= afterFrames ? beforeFrames : afterFrames;
    final larger = beforeFrames <= afterFrames ? afterFrames : beforeFrames;
    if (smaller > 0 && larger / smaller > scaleMismatchRatio) {
      warnings.add('Frame counts differ by more than '
          '${scaleMismatchRatio}x ($beforeFrames vs $afterFrames): '
          'aggregate shifts may reflect session length rather than real '
          'changes.');
    }

    return warnings;
  }

  // ---------------------------------------------------------------------------
  // Formatting helpers.
  // ---------------------------------------------------------------------------

  static MetricComparison _metric(
    String label,
    String unit,
    double? before,
    double? after,
  ) {
    return MetricComparison(
      label: label,
      before: before,
      after: after,
      deltaPercent: _deltaPercent(before, after),
      unit: unit,
    );
  }

  /// `(after - before) / before * 100` rounded to ONE decimal; null when
  /// the baseline is zero or either side is missing.
  static double? _deltaPercent(double? before, double? after) {
    if (before == null || after == null || before == 0) {
      return null;
    }
    return _round1((after - before) / before * 100);
  }

  static double _asPercentPoints(double fraction) => fraction * 100;

  /// Rounds half away from zero, matching `toStringAsFixed` behavior.
  static double _round1(double value) => (value * 10).roundToDouble() / 10;
}
