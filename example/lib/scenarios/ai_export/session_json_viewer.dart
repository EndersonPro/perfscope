import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';
import '../../app/code_block.dart';

/// JSON export scenario: serializes the open (or last finished) session to
/// the schema-v1 JSON string and previews it.
class SessionJsonViewerScreen extends StatefulWidget {
  const SessionJsonViewerScreen({super.key});

  @override
  State<SessionJsonViewerScreen> createState() =>
      _SessionJsonViewerScreenState();
}

class _SessionJsonViewerScreenState extends State<SessionJsonViewerScreen> {
  static const int _previewLimit = 4000;

  String? _json;
  bool _truncated = false;
  String? _error;

  void _export() {
    // Export target priority: the OPEN session (minimal live snapshot), or
    // after stopSession the last finished session's attached report. Null
    // only when PerfScope is disabled or nothing was ever recorded.
    final String? json = PerfScope.exportCurrentSessionAsJson();
    if (json == null) {
      setState(
        () => _error =
            'Nothing to export yet: no open or finished session exists.',
      );
      return;
    }
    setState(() {
      _error = null;
      _truncated = json.length > _previewLimit;
      _json = _truncated ? json.substring(0, _previewLimit) : json;
    });
  }

  Future<void> _copyFull() async {
    final String? json = PerfScope.exportCurrentSessionAsJson();
    if (json != null) {
      await Clipboard.setData(ClipboardData(text: json));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'Session JSON export',
      categoryLabel: ScenarioCategory.aiAndExport.label,
      categoryColor: ScenarioCategory.aiAndExport.color,
      summary:
          'Serializes a session to deterministic single-line JSON (schema '
          'v1). With context windows enabled, surrounding frames are '
          'embedded per frame anomaly.',
      captures:
          'The full wire format: session environment, statistics summary, '
          'anomalies, and context windows - round-trip safe through '
          'SessionParser.',
      codeSnippet: '''
final json = PerfScope.exportCurrentSessionAsJson(
  includeContextWindows: true,
);
// Works mid-session (live snapshot) AND after stopSession().''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                key: const ValueKey<String>('export-json'),
                onPressed: _export,
                child: const Text('Export JSON'),
              ),
              OutlinedButton(
                onPressed: _copyFull,
                child: const Text('Copy full JSON'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!),
          if (_json != null) ...<Widget>[
            CodeBlock(
              code: '${_json!}${_truncated ? '\n... (preview truncated)' : ''}',
            ),
            const SizedBox(height: 4),
            Text(
              _truncated
                  ? 'Preview shows the first $_previewLimit characters.'
                  : 'Complete document.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else if (_error == null)
            const Text('Nothing exported yet.'),
        ],
      ),
    );
  }
}
