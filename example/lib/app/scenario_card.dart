import 'package:flutter/material.dart';

import 'scenario.dart';

/// Home-list card for one scenario: title, summary, category icon, and a
/// stable `menu-tile<route>` key used by the integration test to drive
/// navigation.
final class ScenarioCard extends StatelessWidget {
  /// Creates a card for [scenario].
  const ScenarioCard({super.key, required this.scenario});

  /// Scenario this card opens when tapped.
  final Scenario scenario;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('menu-tile${scenario.route}'),
      leading: Icon(scenario.category.icon, color: scenario.category.color),
      title: Text(scenario.title),
      subtitle: Text(
        scenario.summary,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).pushNamed(scenario.route),
    );
  }
}
