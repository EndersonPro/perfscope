import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';

/// Baseline scenario: healthy navigation between two lightweight subroutes.
///
/// Everything here is deliberately cheap so the frame budget is met and the
/// only visible PerfScope activity is screen bookkeeping: this is the
/// "everything is fine" reference the jank scenarios are contrasted against.
class SmoothNavigationScreen extends StatefulWidget {
  const SmoothNavigationScreen({super.key});

  @override
  State<SmoothNavigationScreen> createState() => _SmoothNavigationScreenState();
}

class _SmoothNavigationScreenState extends State<SmoothNavigationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.2,
    end: 1,
  ).animate(_controller);

  String _lastScreen = PerfScope.currentScreen;

  Future<void> _openDetail() async {
    await Navigator.of(context).pushNamed(routeSmoothNavigationDetail);
    // Refresh after popping back so the reported screen name stays honest.
    setState(() => _lastScreen = PerfScope.currentScreen);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'Smooth navigation baseline',
      categoryLabel: ScenarioCategory.frames.label,
      categoryColor: ScenarioCategory.frames.color,
      summary:
          'Pushes a second lightweight subroute and returns. Both routes '
          'render a trivial animation that should stay inside the frame '
          'budget, producing a clean baseline.',
      captures:
          'A ScreenEvent for every push/pop carrying both route names, and '
          'one normal-tier FrameEvent per rendered frame while animating.',
      codeSnippet: '''
MaterialApp(
  navigatorObservers: [PerfScopeNavigatorObserver()],
  routes: {'/products': (_) => const ProductsScreen()},
);
// Named routes become PerfScope screen names automatically.''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton(
            key: const ValueKey<String>('open-detail'),
            onPressed: _openDetail,
            child: const Text('Open detail subroute'),
          ),
          const SizedBox(height: 12),
          FadeTransition(
            opacity: _opacity,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                'Current screen: $_lastScreen',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Expected console output in profile mode: no anomalies at all. '
            'If this baseline janks, the device is under external load; '
            're-run before drawing conclusions from other scenarios.',
          ),
        ],
      ),
    );
  }
}

/// Second subroute of the smooth-navigation flow.
///
/// Exists mainly to give the navigator observer another named screen to
/// report; kept minimal on purpose.
final class SmoothNavigationDetailScreen extends StatelessWidget {
  const SmoothNavigationDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detail subroute')),
      body: const Center(
        child: Text(
          'Lightweight detail route.\n'
          'PerfScope attributed every frame here to this named route.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
