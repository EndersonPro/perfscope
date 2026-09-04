import 'dart:async';

import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../perf_bootstrap.dart';
import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';

/// Live event console scenario: the raw event stream made visible.
///
/// Subscribes to [PerfScope.events] (safe even before initialization: it is
/// an empty stream while disabled) AND can mirror the shared [MemorySink],
/// demonstrating both consumption seams side by side.
class LiveEventConsoleScreen extends StatefulWidget {
  const LiveEventConsoleScreen({super.key});

  @override
  State<LiveEventConsoleScreen> createState() => _LiveEventConsoleScreenState();
}

class _LiveEventConsoleScreenState extends State<LiveEventConsoleScreen> {
  static const int _maxEntries = 100;

  StreamSubscription<PerformanceEvent>? _subscription;
  final List<_Entry> _entries = <_Entry>[];

  @override
  void initState() {
    super.initState();
    _subscription = PerfScope.events.listen(
      (PerformanceEvent event) => _prepend(_Entry.fromEvent(event)),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _prepend(_Entry entry) {
    setState(() {
      _entries.insert(0, entry);
      if (_entries.length > _maxEntries) {
        _entries.removeLast();
      }
    });
  }

  void _loadFromSink() {
    // The MemorySink holds RAW events oldest-first; render newest-first.
    for (final PerformanceEvent event in showcaseMemorySink.events.reversed) {
      _entries.add(_Entry.fromEvent(event));
    }
    setState(() {
      if (_entries.length > _maxEntries) {
        _entries.removeRange(_maxEntries, _entries.length);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'Live event console',
      categoryLabel: ScenarioCategory.sessionsAndReports.label,
      categoryColor: ScenarioCategory.sessionsAndReports.color,
      summary:
          'Streams every raw event PerfScope produces. Run other scenarios, '
          'come back here, and read what their interactions emitted.',
      captures:
          'FrameEvent, ScreenEvent, InteractionEvent, TraceEvent, '
          'AnomalyEvent, and LifecycleEvent values - the same sealed '
          'hierarchy an in-app diagnostics panel would consume.',
      codeSnippet: '''
PerfScope.events.listen((PerformanceEvent event) {
  if (event is AnomalyEvent) {
    debugPrint(event.anomaly.severity.name); // low..critical
  }
});''',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                liveBridgeLine(),
                key: const ValueKey<String>('live-bridge-line'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
            key: const ValueKey<String>('load-from-sink'),
            onPressed: _loadFromSink,
            child: const Text('Load snapshot from shared MemorySink'),
          ),
          const SizedBox(height: 8),
          Text('${_entries.length} entries (newest first)'),
          const SizedBox(height: 8),
          for (final _Entry entry in _entries.take(30))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: '${entry.severityLabel} ',
                      style: TextStyle(
                        color: entry.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    TextSpan(text: entry.detail),
                  ],
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// One rendered console line: severity tag plus a one-line event description
/// built with an exhaustive switch over the sealed event hierarchy.
final class _Entry {
  const _Entry(this.severityLabel, this.color, this.detail);

  factory _Entry.fromEvent(PerformanceEvent event) => switch (event) {
    FrameEvent(:final sample) => _Entry(
      sample.totalDuration > sample.frameBudget ? 'SLOW' : 'OK',
      sample.totalDuration > sample.frameBudget
          ? const Color(0xFFB54F1E)
          : const Color(0xFF3A7A4A),
      'frame #${sample.frameNumber ?? sample.id} '
      '${sample.totalDuration.inMilliseconds}ms on ${sample.screen ?? '?'}',
    ),
    ScreenEvent(:final name, :final previousName, :final reason) => _Entry(
      'SCREEN',
      const Color(0xFF3F6FD8),
      '$previousName -> $name (${reason.name})',
    ),
    InteractionEvent(:final name, :final kind, :final duration) => _Entry(
      kind == InteractionEventKind.end ? 'IAX' : 'iax',
      const Color(0xFF9C6F1E),
      '$kind $name${duration == null ? '' : ' (${duration.inMilliseconds}ms)'}',
    ),
    TraceEvent(:final name, :final duration, :final didThrow) => _Entry(
      didThrow ? 'FAIL' : 'TRACE',
      didThrow ? const Color(0xFF8B1E1E) : const Color(0xFF2E8B6E),
      "$name took ${duration.inMilliseconds}ms",
    ),
    AnomalyEvent(:final anomaly) => _Entry(
      anomaly.severity.name.toUpperCase(),
      switch (anomaly.severity) {
        AnomalySeverity.low => const Color(0xFF5A5A5A),
        AnomalySeverity.medium => const Color(0xFF9C6F1E),
        AnomalySeverity.high => const Color(0xFFB54F1E),
        AnomalySeverity.critical => const Color(0xFF8B1E1E),
      },
      '${anomaly.runtimeType} on ${anomaly.screen ?? '?'}',
    ),
    LifecycleEvent(:final state) => _Entry(
      'LIFECYCLE',
      const Color(0xFF7A4FB5),
      state.name,
    ),
  };

  final String severityLabel;
  final Color color;
  final String detail;
}
