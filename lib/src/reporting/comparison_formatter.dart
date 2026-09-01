/// Fixed-width before/after comparison table for [SessionComparison]
/// values.
///
/// Pure string building: no IO, no clock, no locale. The BEFORE/AFTER/
/// DELTA columns are right-aligned with widths computed from the content
/// (minimum 8); the label column is left-aligned. Units: rates render as
/// percentage points with one decimal plus `%`, durations as rounded
/// integers plus `ms`; deltas always carry an explicit sign and one
/// decimal, or `n/a` when undefined.
library;

import 'session_comparison.dart';

const int _gap = 2;
const int _minColumnWidth = 8;

/// Renders [comparison] as a deterministic text report: overall metrics
/// first, then per-screen and per-interaction tables (each introduced by
/// its name), and finally the warnings section when non-empty.
String formatSessionComparison(SessionComparison comparison) {
  final buffer = StringBuffer();
  void renderMetrics(String title, List<MetricComparison> metrics) {
    if (title != 'Overall') {
      buffer.writeln(title);
    }
    _renderTable(buffer, [
      for (final metric in metrics) (_prettyLabel(metric.label), metric),
    ]);
  }

  renderMetrics('Overall', comparison.overall);

  if (comparison.screens.isNotEmpty) {
    buffer.writeln('By screen:');
    for (final screen in comparison.screens) {
      renderMetrics(screen.screen, screen.metrics);
    }
  }

  if (comparison.interactions.isNotEmpty) {
    buffer.writeln('By interaction:');
    for (final interaction in comparison.interactions) {
      renderMetrics(interaction.interaction, interaction.metrics);
    }
  }

  if (comparison.warnings.isNotEmpty) {
    buffer
      ..writeln('Warnings:')
      ..writeln(
        comparison.warnings.map((warning) => '  - $warning').join('\n'),
      );
  }
  return buffer.toString();
}

/// Snake_case metric labels → human-readable row names.
String _prettyLabel(String label) => switch (label) {
      'slow_frame_rate' => 'Slow frame rate',
      'worst_frame' => 'Worst frame',
      'average_build' => 'Avg build',
      'average_raster' => 'Avg raster',
      _ => label,
    };

void _renderTable(StringBuffer buffer, List<(String, MetricComparison)> rows) {
  const headerBefore = 'BEFORE';
  const headerAfter = 'AFTER';
  const headerDelta = 'DELTA';
  final cells = <(String, String, String)>[
    for (final (_, metric) in rows)
      (
        _formatValue(metric.before, metric.unit),
        _formatValue(metric.after, metric.unit),
        _formatDelta(metric.deltaPercent),
      ),
  ];

  var labelWidth = _minColumnWidth;
  var beforeWidth = _max(headerBefore.length, _minColumnWidth);
  var afterWidth = _max(headerAfter.length, _minColumnWidth);
  var deltaWidth = _max(headerDelta.length, _minColumnWidth);
  for (var i = 0; i < rows.length; i++) {
    labelWidth = _max(labelWidth, rows[i].$1.length);
    beforeWidth = _max(beforeWidth, cells[i].$1.length);
    afterWidth = _max(afterWidth, cells[i].$2.length);
    deltaWidth = _max(deltaWidth, cells[i].$3.length);
  }

  buffer.writeln(
    '${''.padRight(labelWidth)}'
    '${headerBefore.padLeft(beforeWidth + _gap)}'
    '${headerAfter.padLeft(afterWidth + _gap)}'
    '${headerDelta.padLeft(deltaWidth + _gap)}',
  );
  for (var i = 0; i < rows.length; i++) {
    final cell = cells[i];
    buffer.writeln(
      '${rows[i].$1.padRight(labelWidth)}'
      '${cell.$1.padLeft(beforeWidth + _gap)}'
      '${cell.$2.padLeft(afterWidth + _gap)}'
      '${cell.$3.padLeft(deltaWidth + _gap)}',
    );
  }
}

int _max(int a, int b) => a > b ? a : b;

/// Rates keep one decimal plus `%`; durations round to whole `ms`.
String _formatValue(double? value, String unit) {
  if (value == null) return 'n/a';
  return switch (unit) {
    '%' => '${value.toStringAsFixed(1)}%',
    _ => unit.isEmpty ? value.round().toString() : '${value.round()}$unit',
  };
}

/// Always-signed percent with one decimal; `n/a` when undefined.
String _formatDelta(double? deltaPercent) {
  if (deltaPercent == null) return 'n/a';
  final sign = deltaPercent > 0 ? '+' : '';
  return '$sign${deltaPercent.toStringAsFixed(1)}%';
}
