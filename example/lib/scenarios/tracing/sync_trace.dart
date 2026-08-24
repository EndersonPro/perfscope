import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/busy_work.dart';
import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';

/// Synchronous trace scenario: wraps work in [PerfScope.trace] and inspects
/// the completed-trace window afterwards.
class SyncTraceScreen extends StatefulWidget {
  const SyncTraceScreen({super.key});

  @override
  State<SyncTraceScreen> createState() => _SyncTraceScreenState();
}

class _SyncTraceScreenState extends State<SyncTraceScreen> {
  String? _resultLine;
  List<CompletedTrace> _traces = const <CompletedTrace>[];

  void _runTracedWork() {
    // PerfScope.trace returns the body's result unchanged; while enabled it
    // also records a CompletedTrace, emits a TraceEvent, and feeds the
    // Timeline. Disabled, the same call just runs the body.
    final Duration spent = PerfScope.trace(
      'calculate_prices',
      () => busyWork(const Duration(milliseconds: 30)),
      metadata: <String, Object?>{'items': 12},
    );
    setState(() {
      _resultLine =
          "trace 'calculate_prices' returned after "
          '${spent.inMilliseconds} ms';
      _traces = PerfScope.recentTraces;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'Synchronous trace',
      categoryLabel: ScenarioCategory.tracing.label,
      categoryColor: ScenarioCategory.tracing.color,
      summary:
          'Times synchronous work with PerfScope.trace. The traced function '
          'keeps returning its result exactly as before; observability is '
          'purely additive around it.',
      captures:
          'One TraceEvent and one CompletedTrace per run (bounded window), '
          'with validated metadata attached. Traces longer than '
          'longTraceThreshold additionally raise LongTraceAnomaly.',
      codeSnippet: '''
final prices = PerfScope.trace(
  'calculate_prices',
  () => computePrices(cart),
  metadata: {'items': cart.length},
);
print(PerfScope.recentTraces.length); // bounded completed window''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton(
            key: const ValueKey<String>('run-sync-trace'),
            onPressed: _runTracedWork,
            child: const Text('Run sync trace (~30 ms)'),
          ),
          const SizedBox(height: 16),
          Text(_resultLine ?? 'No trace run yet.'),
          Text('Recent traces stored: ${_traces.length}'),
          if (_traces.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text('Latest: ${_describe(_traces.last)}'),
          ],
        ],
      ),
    );
  }

  static String _describe(CompletedTrace trace) =>
      '${trace.name} | ${trace.duration.inMilliseconds} ms | '
      'screen ${trace.screen}${trace.didThrow ? ' | threw' : ''}';
}
