import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import 'code_block.dart';

/// Shared detail scaffold for every scenario screen.
///
/// Standardizes the teaching layout: category chip, summary paragraph, a
/// "what PerfScope captures here" section, the exact usage code on screen,
/// and then the scenario's own action row and results area below.
///
/// The widget receives plain values (title, labels, snippet) instead of a
/// [Scenario]-like model so screens never depend on the catalog that lists
/// them — the catalog imports the screens, not the other way around.
final class ScenarioScaffold extends StatelessWidget {
  /// Creates a scenario detail page shell.
  const ScenarioScaffold({
    super.key,
    required this.title,
    required this.categoryLabel,
    required this.categoryColor,
    required this.summary,
    required this.captures,
    required this.codeSnippet,
    required this.child,
  });

  /// AppBar title; also the human-readable scenario name.
  final String title;

  /// Short label for the category chip (for example `'Frames'`).
  final String categoryLabel;

  /// Accent color of the category chip.
  final Color categoryColor;

  /// One-paragraph explanation of what this screen demonstrates.
  final String summary;

  /// What PerfScope records while this scenario runs: event types,
  /// anomalies, report sections, or exports produced here.
  final String captures;

  /// Copy-paste-correct usage snippet rendered in a [CodeBlock].
  final String codeSnippet;

  /// Action row plus results area: buttons that trigger real API calls and
  /// the widgets rendering what PerfScope captured.
  ///
  /// LAYOUT CONTRACT: [child] is placed as a leaf of this scaffold's
  /// scrollable ([ListView]) and therefore receives UNBOUNDED height. It
  /// must size itself intrinsically or wrap any embedded viewport
  /// (ListView/GridView) in an explicit-height box (e.g. `SizedBox`) —
  /// `Expanded`/`Flexible` crash here, and unbounded inner viewports
  /// produce `Infinity or NaN toInt` layout exceptions on device.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: DefaultTextStyle.merge(
        style: textTheme.bodyMedium!,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Chip(
              avatar: CircleAvatar(backgroundColor: categoryColor),
              label: Text(categoryLabel),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(height: 8),
            Text(summary),
            const SizedBox(height: 16),
            Text('What PerfScope captures here', style: textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(captures),
            const SizedBox(height: 16),
            Text('Usage', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            CodeBlock(code: codeSnippet),
            const SizedBox(height: 20),
            // Degraded mode: the release entry point never initializes
            // PerfScope. Actions would run against an inert facade, so they
            // are replaced by an explicit notice instead of silently
            // showing empty results.
            if (!PerfScope.isEnabled)
              const _DisabledNotice()
            else ...<Widget>[
              Text('Run it', style: textTheme.titleSmall),
              const SizedBox(height: 8),
              child,
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

final class _DisabledNotice extends StatelessWidget {
  const _DisabledNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: colors.outline, width: 3)),
      ),
      child: const Text(
        'PerfScope is disabled in this entry point. Run the app with '
        '`flutter run --profile -t lib/main_profile.dart` to initialize '
        'the engine and see live results here.',
      ),
    );
  }
}
