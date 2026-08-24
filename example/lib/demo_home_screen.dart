import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import 'app/scenario.dart';
import 'app/scenario_card.dart';

/// Categorized showcase home: one section per [ScenarioCategory], one card
/// per scenario, plus an at-a-glance engine status line.
///
/// Uses NAMED routes so the navigator observer reports meaningful screen
/// names when PerfScope is initialized.
class DemoHomeScreen extends StatelessWidget {
  const DemoHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = ScenarioCategory.values;
    return Scaffold(
      appBar: AppBar(title: const Text('PerfScope Showcase')),
      body: ListView.builder(
        itemCount: _itemCount(categories),
        itemBuilder: (BuildContext context, int index) =>
            _itemFor(context, categories, index),
      ),
    );
  }

  /// Header status + one header and N cards per category.
  int _itemCount(List<ScenarioCategory> categories) {
    var count = 1; // status header
    for (final ScenarioCategory category in categories) {
      count += 1 + _scenariosIn(category).length;
    }
    return count;
  }

  Widget _itemFor(
    BuildContext context,
    List<ScenarioCategory> categories,
    int index,
  ) {
    if (index == 0) {
      return const _EngineStatusHeader();
    }
    var cursor = 1;
    for (final ScenarioCategory category in categories) {
      final scenarios = _scenariosIn(category);
      final sectionLength = 1 + scenarios.length;
      if (index < cursor + sectionLength) {
        final local = index - cursor;
        if (local == 0) {
          return _CategoryHeader(category: category);
        }
        return ScenarioCard(scenario: scenarios[local - 1]);
      }
      cursor += sectionLength;
    }
    // Unreachable by construction of _itemCount.
    return const SizedBox.shrink();
  }

  static List<Scenario> _scenariosIn(ScenarioCategory category) =>
      showcaseScenarios
          .where((Scenario scenario) => scenario.category == category)
          .toList(growable: false);
}

/// One-line engine status so it is obvious whether results on scenario
/// screens will be live or the degraded placeholder.
final class _EngineStatusHeader extends StatelessWidget {
  const _EngineStatusHeader();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = PerfScope.isEnabled;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled ? colors.secondaryContainer : colors.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        enabled
            ? 'PerfScope is running. Session: '
                  '${PerfScope.currentSession?.id ?? 'none'}.'
            : 'PerfScope is not initialized. Run with '
                  '`flutter run --profile -t lib/main_profile.dart`.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

final class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category});

  final ScenarioCategory category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: <Widget>[
          Icon(category.icon, size: 18, color: category.color),
          const SizedBox(width: 8),
          Text(
            category.label,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: category.color),
          ),
        ],
      ),
    );
  }
}
