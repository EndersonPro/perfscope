import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';

/// Screen context scenario: manual screen override plus the metadata store.
///
/// For apps without a Navigator (custom shells, games, embedded views) the
/// navigator observer cannot help; [PerfScope.screen] takes over, and
/// [PerfScope.setMetadata] attaches free-form context to subsequent records.
class ScreenContextScreen extends StatefulWidget {
  const ScreenContextScreen({super.key});

  @override
  State<ScreenContextScreen> createState() => _ScreenContextScreenState();
}

class _ScreenContextScreenState extends State<ScreenContextScreen> {
  String _screen = PerfScope.currentScreen;

  void _overrideScreen() {
    // Emits a ScreenEvent with reason `manual` and re-attributes upcoming
    // frames/traces to 'checkout-step-2' until overridden again.
    PerfScope.screen(
      'checkout-step-2',
      metadata: <String, Object?>{'step': 'payment'},
    );
    setState(() => _screen = PerfScope.currentScreen);
  }

  void _restoreRouteName() {
    // Restoring the route name keeps reports honest after a temporary
    // manual override.
    PerfScope.screen('/context/screen-context');
    setState(() => _screen = PerfScope.currentScreen);
  }

  void _setMetadata() {
    PerfScope.setMetadata('cart_items', 3);
  }

  void _removeMetadata() {
    PerfScope.removeMetadata('cart_items');
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'Screen context override',
      categoryLabel: ScenarioCategory.context.label,
      categoryColor: ScenarioCategory.context.color,
      summary:
          'Overrides the current screen manually and stores session '
          'metadata. Metadata values must be primitives or flat maps of '
          'primitives; invalid values throw ArgumentError while enabled.',
      captures:
          'A ScreenEvent with reason manual on every override, and merged '
          'metadata embedded in frames, traces, and reports recorded while '
          'it is set.',
      codeSnippet: '''
PerfScope.screen('checkout', metadata: {'step': 'payment'});
PerfScope.setMetadata('cart_items', 3);
print(PerfScope.currentScreen); // 'checkout'
''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                key: const ValueKey<String>('override-screen'),
                onPressed: _overrideScreen,
                child: const Text("Override screen to 'checkout-step-2'"),
              ),
              OutlinedButton(
                onPressed: _restoreRouteName,
                child: const Text('Restore route name'),
              ),
              OutlinedButton(
                key: const ValueKey<String>('set-metadata'),
                onPressed: _setMetadata,
                child: const Text('Set cart_items = 3'),
              ),
              OutlinedButton(
                onPressed: _removeMetadata,
                child: const Text('Remove cart_items'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('currentScreen: $_screen'),
          const Text(
            'Open the Live event console scenario afterwards: the manual '
            'overrides appear there as ScreenEvent entries with reason '
            "'manual'.",
          ),
        ],
      ),
    );
  }
}
