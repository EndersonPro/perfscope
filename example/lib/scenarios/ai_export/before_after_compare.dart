import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/busy_work.dart';
import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';
import '../../app/code_block.dart';

/// Before/after comparison scenario: records the SAME workload twice (a
/// slow baseline, then an optimized variant) and diffs the two reports.
///
/// The toy deltas are deterministic in shape, not magnitude: both runs
/// record few frames, so SessionComparator's low-sample warnings are part
/// of the lesson - comparisons over tiny sessions deserve skepticism.
class BeforeAfterCompareScreen extends StatefulWidget {
  const BeforeAfterCompareScreen({super.key});

  @override
  State<BeforeAfterCompareScreen> createState() =>
      _BeforeAfterCompareScreenState();
}

class _BeforeAfterCompareScreenState extends State<BeforeAfterCompareScreen> {
  PerformanceReport? _baseline;
  String? _comparisonText;
  String _status =
      'Step 1: capture the slow baseline. Step 2: capture the optimized run.';

  Future<void> _captureBaseline() async {
    PerfScope.startSession('compare-baseline');
    for (int i = 0; i < 4; i++) {
      // "Unoptimized": four ~40 ms synchronous operations.
      PerfScope.trace(
        'process_page',
        () => busyWork(const Duration(milliseconds: 40)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final PerformanceReport report = await PerfScope.stopSession();
    setState(() {
      _baseline = report;
      _status =
          'Baseline captured (${report.statistics.totalFrames} frames). '
          'Now capture the optimized run.';
    });
  }

  Future<void> _captureOptimizedAndCompare() async {
    final PerformanceReport? baseline = _baseline;
    if (baseline == null) {
      setState(() => _status = 'Capture the baseline first.');
      return;
    }
    PerfScope.startSession('compare-optimized');
    for (int i = 0; i < 4; i++) {
      // "Optimized": same workload, cheaper per operation.
      PerfScope.trace(
        'process_page',
        () => busyWork(const Duration(milliseconds: 8)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final PerformanceReport after = await PerfScope.stopSession();
    // Pure comparison: works without any engine involvement; sign
    // convention is NEGATIVE delta = improvement for every metric here.
    final SessionComparison comparison = PerfScope.compareSessions(
      baseline,
      after,
    );
    setState(() {
      _comparisonText = formatSessionComparison(comparison);
      _status =
          'Comparison ready. Warnings below the table are expected '
          'with this few frames.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'Before / after compare',
      categoryLabel: ScenarioCategory.aiAndExport.label,
      categoryColor: ScenarioCategory.aiAndExport.color,
      summary:
          'Runs one workload as a slow baseline and again as a faster '
          '"optimized" variant, then compares the two reports. Pairing is '
          'by name: screens pair with screens, interactions with '
          'interactions.',
      captures:
          'Signed percentage deltas for overall metrics (slow frame rate, '
          'p95/p99, worst frame, averages) plus per-screen tables and '
          'comparability warnings.',
      codeSnippet: '''
final before = await PerfScope.stopSession();
PerfScope.startSession('after');
await runSameWorkload();
final after = await PerfScope.stopSession();
print(formatSessionComparison(PerfScope.compareSessions(before, after)));''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                key: const ValueKey<String>('capture-baseline'),
                onPressed: _captureBaseline,
                child: const Text('1. Capture baseline (~340 ms)'),
              ),
              FilledButton.tonal(
                key: const ValueKey<String>('capture-optimized'),
                onPressed: _captureOptimizedAndCompare,
                child: const Text('2. Capture optimized & compare'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(_status),
          if (_comparisonText != null) ...<Widget>[
            const SizedBox(height: 12),
            CodeBlock(code: _comparisonText!),
          ],
        ],
      ),
    );
  }
}
