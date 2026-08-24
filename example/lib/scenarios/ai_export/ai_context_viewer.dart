import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';
import '../../app/code_block.dart';

/// AI context scenario: renders `report.toAiContext()` from the last
/// finished session and copies it to the clipboard.
class AiContextViewerScreen extends StatefulWidget {
  const AiContextViewerScreen({super.key});

  @override
  State<AiContextViewerScreen> createState() => _AiContextViewerScreenState();
}

class _AiContextViewerScreenState extends State<AiContextViewerScreen> {
  String? _contextText;
  String? _error;

  void _renderContext() {
    // lastReport is null until some session has been stopped; the UI says
    // so instead of rendering an empty block.
    final PerformanceReport? report = PerfScope.lastReport;
    if (report == null) {
      setState(
        () => _error =
            'No finished session yet. Run Sessions > Session report first, '
            'then come back.',
      );
      return;
    }
    setState(() {
      _error = null;
      _contextText = report.toAiContext();
    });
  }

  Future<void> _copy() async {
    final text = _contextText;
    if (text != null) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'AI context viewer',
      categoryLabel: ScenarioCategory.aiAndExport.label,
      categoryColor: ScenarioCategory.aiAndExport.color,
      summary:
          'Turns a finished PerformanceReport into token-optimized text for '
          'LLM prompts. Output is hard-capped and never invents data it '
          'does not have.',
      captures:
          'The PERFSCOPE_SESSION context block: session identity, frame '
          'statistics, top issues with probable bottlenecks, and suggested '
          'next steps.',
      codeSnippet: '''
final report = PerfScope.lastReport;
if (report != null) {
  Clipboard.setData(ClipboardData(text: report.toAiContext()));
}''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                key: const ValueKey<String>('render-ai-context'),
                onPressed: _renderContext,
                child: const Text('Render AI context'),
              ),
              OutlinedButton(
                onPressed: _copy,
                child: const Text('Copy to clipboard'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!),
          if (_contextText != null)
            CodeBlock(code: _contextText!)
          else if (_error == null)
            const Text('Nothing rendered yet.'),
        ],
      ),
    );
  }
}
