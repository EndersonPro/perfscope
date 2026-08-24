import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/busy_work.dart';
import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';
import '../../app/code_block.dart';

/// Session lifecycle scenario: start a named session, feed it work, stop it,
/// and render the deterministic text report on screen.
class SessionReportScreen extends StatefulWidget {
  const SessionReportScreen({super.key});

  @override
  State<SessionReportScreen> createState() => _SessionReportScreenState();
}

class _SessionReportScreenState extends State<SessionReportScreen> {
  String _status = 'No session started from this screen yet.';
  String? _reportText;

  void _startSession() {
    // startSession auto-finalizes an already-active session first, so this
    // is always safe; the auto-started 'showcase' session simply ends here
    // and its data stays reachable through PerfScope.lastFinishedSession
    // internals. Throws StateError only when PerfScope was never
    // initialized - which the scaffold's disabled notice prevents.
    final PerformanceSession session = PerfScope.startSession('report-demo');
    setState(
      () => _status =
          "Session '${session.name}' (${session.id}) is "
          'open. Run some workload, then stop it.',
    );
  }

  void _runWorkload() {
    PerfScope.trace(
      'report_demo_work',
      () => busyWork(const Duration(milliseconds: 25)),
    );
    setState(
      () => _status =
          'One traced workload recorded into the open session (if any).',
    );
  }

  Future<void> _stopSession() async {
    try {
      final PerformanceReport report = await PerfScope.stopSession();
      // Reports are pure models; formatReportText turns one into the fixed
      // summary box. There is deliberately NO report.toText().
      setState(() {
        _reportText = formatReportText(report);
        _status = 'Session stopped. Report below.';
      });
    } on StateError catch (error) {
      setState(() => _status = 'Could not stop a session: ${error.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'Session report',
      categoryLabel: ScenarioCategory.sessionsAndReports.label,
      categoryColor: ScenarioCategory.sessionsAndReports.color,
      summary:
          'Controls session boundaries explicitly. Opening a session while '
          'another is active auto-finalizes the previous one; stopping '
          'produces the full PerformanceReport.',
      captures:
          'Exact counters (frames, slow/severe tiers), percentile estimates '
          'over the bounded window, per-screen and per-interaction '
          'summaries, completed traces, and anomalies ranked worst-first.',
      codeSnippet: '''
PerfScope.startSession('release-check'); // auto-finalizes previous
await runWorkload();
final report = await PerfScope.stopSession();
final text = formatReportText(report); // reports have NO toText()''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                key: const ValueKey<String>('start-session'),
                onPressed: _startSession,
                child: const Text("Start 'report-demo'"),
              ),
              OutlinedButton(
                key: const ValueKey<String>('run-workload'),
                onPressed: _runWorkload,
                child: const Text('Run traced workload'),
              ),
              FilledButton.tonal(
                key: const ValueKey<String>('stop-session'),
                onPressed: _stopSession,
                child: const Text('Stop & render report'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(_status),
          if (_reportText != null) ...<Widget>[
            const SizedBox(height: 12),
            CodeBlock(code: _reportText!),
          ],
        ],
      ),
    );
  }
}
