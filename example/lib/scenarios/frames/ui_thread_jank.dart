import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/busy_work.dart';
import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';

/// UI-thread jank scenario: heavy synchronous work runs inside `build`.
///
/// Blocking the UI thread past the frame budget is the canonical jank
/// recipe. No PerfScope API is needed to trigger it — the engine observes
/// every frame and classifies the blown ones on its own, which is exactly
/// what this scenario demonstrates.
class UiThreadJankScreen extends StatefulWidget {
  const UiThreadJankScreen({super.key});

  @override
  State<UiThreadJankScreen> createState() => _UiThreadJankScreenState();
}

class _UiThreadJankScreenState extends State<UiThreadJankScreen> {
  /// Non-null while the NEXT build must spin the CPU. Cleared immediately
  /// after use so ordinary rebuilds (theme changes, keyboard, navigation)
  /// stay cheap and only deliberate triggers jank.
  Duration? _pendingSpin;

  Duration? _lastSpent;
  int _anomalyCount = 0;
  String? _lastAnomalyLine;

  void _trigger() {
    setState(() => _pendingSpin = const Duration(milliseconds: 60));
  }

  void _refreshResults() {
    final frameAnomalies = PerfScope.anomalies.whereType<FrameAnomaly>().toList(
      growable: false,
    );
    setState(() {
      _anomalyCount = frameAnomalies.length;
      if (frameAnomalies.isNotEmpty) {
        final latest = frameAnomalies.last;
        _lastAnomalyLine =
            '${latest.runtimeType}: '
            '${latest.sample.totalDuration.inMilliseconds}ms total '
            '(budget ${latest.frameBudget.inMilliseconds}ms), severity '
            '${latest.severity.name}, probable bottleneck '
            '${latest.bottleneck.name}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The jank happens HERE: synchronous busy work inside build blocks the
    // UI thread for this frame's entire build phase.
    final pending = _pendingSpin;
    if (pending != null) {
      _lastSpent = busyWork(pending);
      _pendingSpin = null;
    }
    return ScenarioScaffold(
      title: 'UI-thread jank',
      categoryLabel: ScenarioCategory.frames.label,
      categoryColor: ScenarioCategory.frames.color,
      summary:
          'Runs an adaptive ~60 ms busy loop synchronously inside '
          'build(), blowing the frame budget without calling any PerfScope '
          'API.',
      captures:
          'Slow/severe FrameEvents and frame anomalies whose probable '
          'bottleneck is UI (UiBoundFrameAnomaly), attributed to this named '
          'route.',
      codeSnippet: '''
// Synchronous work inside build blocks the UI thread:
Widget build(BuildContext context) {
  spinFor(const Duration(milliseconds: 60)); // janks this frame
  return const HeavyTree();
}
// PerfScope classifies the blown frame automatically - no API calls.''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton(
            key: const ValueKey<String>('trigger-cpu-work'),
            onPressed: () {
              _trigger();
              // Results are read after the janked frame settles so the
              // anomaly list already contains it.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _refreshResults();
              });
            },
            child: const Text('Block the UI thread (~60 ms)'),
          ),
          const SizedBox(height: 16),
          Text(
            'Busy-loop duration: '
            '${_lastSpent?.inMilliseconds ?? '-'} ms',
          ),
          Text('Frame anomalies so far (whole session): $_anomalyCount'),
          if (_lastAnomalyLine != null) Text(_lastAnomalyLine!),
          const SizedBox(height: 8),
          const Text(
            'Never copy the blocking pattern into real code: move heavy work '
            'to isolates or chunk it across frames. This screen exists to '
            'give PerfScope something to detect.',
          ),
        ],
      ),
    );
  }
}
