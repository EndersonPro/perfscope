import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../perf_bootstrap.dart';
import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';

/// Interaction context scenario: span-style and marker-style attributions
/// during one simulated task.
class InteractionSpansScreen extends StatefulWidget {
  const InteractionSpansScreen({super.key});

  @override
  State<InteractionSpansScreen> createState() => _InteractionSpansScreenState();
}

class _InteractionSpansScreenState extends State<InteractionSpansScreen> {
  InteractionHandle? _openSpan;
  List<InteractionEvent> _events = const <InteractionEvent>[];

  void _startSpan() {
    _openSpan = PerfScope.startInteraction('checkout_flow');
    _refresh();
  }

  void _dropMarker() {
    // One-shot attribution for the very next observed frame; nothing to
    // close, last mark before a frame wins.
    PerfScope.interaction('add_to_cart');
    _refresh();
  }

  void _endSpan() {
    // end() is safe to call repeatedly; out-of-order endings are supported.
    _openSpan?.end();
    _openSpan = null;
    _refresh();
  }

  void _refresh() {
    setState(() {
      _events = showcaseMemorySink.events.whereType<InteractionEvent>().toList(
        growable: false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final openSpan = _openSpan;
    return ScenarioScaffold(
      title: 'Interaction spans',
      categoryLabel: ScenarioCategory.context.label,
      categoryColor: ScenarioCategory.context.color,
      summary:
          'Opens an interaction span around a simulated flow, drops quick '
          'markers inside it, then ends the span. Frames rendered while a '
          'span is open are attributed to it.',
      captures:
          'InteractionEvents of kind start/end (end carries wall-clock '
          'duration) and marker events attributed to the next observed '
          'frame. Nesting is guarded at maxInteractionDepth.',
      codeSnippet: '''
final handle = PerfScope.startInteraction('checkout');
await pay();
handle.end(); // repeated calls are safe no-ops

PerfScope.interaction('add_to_cart'); // quick marker''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                key: const ValueKey<String>('start-span'),
                onPressed: openSpan == null ? _startSpan : null,
                child: const Text("Start span 'checkout_flow'"),
              ),
              OutlinedButton(
                key: const ValueKey<String>('quick-marker'),
                onPressed: openSpan == null ? null : _dropMarker,
                child: const Text("Quick marker 'add_to_cart'"),
              ),
              FilledButton.tonal(
                key: const ValueKey<String>('end-span'),
                onPressed: openSpan == null ? null : _endSpan,
                child: const Text('End span'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Open span: ${openSpan?.name ?? 'none'}'),
          Text('Interaction events captured: ${_events.length}'),
          const SizedBox(height: 8),
          for (final InteractionEvent event in _events.reversed.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${event.kind.name.toUpperCase()} ${event.name}'
                '${event.duration == null ? '' : ' | ${event.duration!.inMilliseconds} ms'}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
