import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';

/// Long async trace scenario: times a multi-hundred-millisecond future with
/// [PerfScope.traceAsync] until a [LongTraceAnomaly] fires.
///
/// The default `longTraceThreshold` is 50 ms; a ~150 ms operation lands in
/// the HIGH severity tier (>= 2x threshold, below the 5x critical tier).
class AsyncTraceLongOperationScreen extends StatefulWidget {
  const AsyncTraceLongOperationScreen({super.key});

  @override
  State<AsyncTraceLongOperationScreen> createState() =>
      _AsyncTraceLongOperationScreenState();
}

class _AsyncTraceLongOperationScreenState
    extends State<AsyncTraceLongOperationScreen> {
  bool _running = false;
  String? _resultLine;
  List<LongTraceAnomaly> _longTraces = const <LongTraceAnomaly>[];

  Future<void> _runTracedFetch() async {
    setState(() => _running = true);
    // A fake network call: awaits a real Future so traceAsync uses its
    // async-flavor Timeline spans and the event loop stays responsive.
    final String payload = await PerfScope.traceAsync<String>(
      'load_products',
      () async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return '42 products';
      },
      metadata: <String, Object?>{'endpoint': '/products'},
    );
    setState(() {
      _running = false;
      _resultLine = "traceAsync 'load_products' completed: $payload";
      _longTraces = PerfScope.anomalies.whereType<LongTraceAnomaly>().toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'Async trace: long operation',
      categoryLabel: ScenarioCategory.tracing.label,
      categoryColor: ScenarioCategory.tracing.color,
      summary:
          'Times an awaited future with PerfScope.traceAsync. When the '
          'operation exceeds longTraceThreshold, the TraceEvent is followed '
          'immediately by an AnomalyEvent carrying a LongTraceAnomaly.',
      captures:
          'A LongTraceAnomaly with name, duration, screen attribution, and a '
          'severity scaled against longTraceThreshold (>=2x high, >=5x '
          'critical, otherwise medium).',
      codeSnippet: '''
await PerfScope.traceAsync('load_products', () async {
  await api.loadProducts(); // > longTraceThreshold (default 50 ms)
});
final long = PerfScope.anomalies.whereType<LongTraceAnomaly>();''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton(
            key: const ValueKey<String>('run-async-trace'),
            onPressed: _running ? null : _runTracedFetch,
            child: Text(
              _running ? 'Fetching...' : 'Run traced fetch (~150 ms)',
            ),
          ),
          const SizedBox(height: 16),
          Text(_resultLine ?? 'No async trace run yet.'),
          Text('Long-trace anomalies stored: ${_longTraces.length}'),
          if (_longTraces.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            for (final LongTraceAnomaly anomaly in _longTraces.reversed.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${anomaly.name} | ${anomaly.duration.inMilliseconds} ms | '
                  'severity ${anomaly.severity.name}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
