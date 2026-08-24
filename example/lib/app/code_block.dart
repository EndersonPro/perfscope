import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Monospace, selectable, light-on-dark container for the usage snippets
/// shown on every scenario screen.
///
/// The snippets ARE documentation: they must be copy-paste-correct usage of
/// the real PerfScope API, so they are rendered selectable and ship a
/// one-tap copy action to encourage pasting them into real code.
final class CodeBlock extends StatelessWidget {
  /// Creates a code block rendering [code] verbatim.
  const CodeBlock({super.key, required this.code});

  /// Snippet source text. Keep it short (5-15 lines): it is displayed on
  /// screen and read by humans, not compiled.
  final String code;

  void _copy() {
    Clipboard.setData(ClipboardData(text: code));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3A3450)),
      ),
      child: Stack(
        children: <Widget>[
          SelectionArea(
            child: Text(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
                color: Color(0xFFE6E1F5),
              ),
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              tooltip: 'Copy snippet',
              icon: const Icon(Icons.copy, size: 18),
              color: const Color(0xFF9C93C6),
              onPressed: _copy,
            ),
          ),
        ],
      ),
    );
  }
}
