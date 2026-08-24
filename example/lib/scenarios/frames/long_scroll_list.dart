import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';

/// Long-scroll jank scenario: a 500-item list with a toggle between cheap
/// and expensive tiles.
///
/// The expensive tiles (nested shadows plus clipped paths) exist so the
/// toggle can be flipped mid-scroll and frame timings watched degrading in
/// profile mode. Mixed heights exercise variable-extent layout work too.
class LongScrollListScreen extends StatefulWidget {
  const LongScrollListScreen({super.key});

  @override
  State<LongScrollListScreen> createState() => _LongScrollListScreenState();
}

class _LongScrollListScreenState extends State<LongScrollListScreen> {
  bool _expensiveTiles = false;
  int _frameAnomalyCount = 0;

  void _toggleTiles() {
    setState(() => _expensiveTiles = !_expensiveTiles);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(
        () => _frameAnomalyCount = PerfScope.anomalies
            .whereType<FrameAnomaly>()
            .length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'Long scroll list',
      categoryLabel: ScenarioCategory.frames.label,
      categoryColor: ScenarioCategory.frames.color,
      summary:
          'A long list whose tiles can be switched between cheap containers '
          'and expensive decorated ones. Scroll with cheap tiles, flip the '
          'toggle, keep scrolling: the same screen produces two very '
          'different frame profiles.',
      captures:
          'Slow/severe FrameEvents attributed to this single named route, '
          'so per-screen summaries in a report isolate the degradation to '
          'one screen.',
      codeSnippet: '''
ListView.builder(
  itemCount: 500,
  itemBuilder: (_, i) => expensive ? ExpensiveTile(i) : CheapTile(i),
);
// Flip the toggle mid-scroll and watch slow_frame_rate climb.''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Expanded on the TEXT only: the button keeps its intrinsic
          // width while long counters wrap instead of overflowing.
          Row(
            children: <Widget>[
              FilledButton.tonal(
                key: const ValueKey<String>('toggle-tiles'),
                onPressed: _toggleTiles,
                child: Text(
                  _expensiveTiles
                      ? 'Switch to cheap tiles'
                      : 'Switch to expensive tiles',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Frame anomalies so far: $_frameAnomalyCount'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Fixed-height inner viewport: this child is a leaf of the
          // scaffold's ListView (unbounded height), so the scrollable MUST
          // be given an explicit extent — Expanded would crash and an
          // unbounded ListView inside a list item produces NaN layouts.
          SizedBox(
            height: 420,
            child: ListView.builder(
              itemCount: 500,
              itemBuilder: (BuildContext context, int index) => _expensiveTiles
                  ? _ExpensiveTile(index: index)
                  : _CheapTile(index: index),
            ),
          ),
        ],
      ),
    );
  }
}

Color _colorFor(int index) =>
    HSVColor.fromAHSV(1, (index * 53 % 360) / 360, 0.6, 0.9).toColor();

final class _CheapTile extends StatelessWidget {
  const _CheapTile({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: index.isEven ? 64 : 88,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: _colorFor(index),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(12),
      child: Text('Item $index (cheap)'),
    );
  }
}

final class _ExpensiveTile extends StatelessWidget {
  const _ExpensiveTile({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: index.isEven ? 72 : 104,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: _colorFor(index).withValues(alpha: 0.45),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipPath(
        clipper: _SlantClipper(),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[_colorFor(index), Colors.black87],
            ),
          ),
          alignment: Alignment.center,
          child: Text('Item $index (expensive)'),
        ),
      ),
    );
  }
}

final class _SlantClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - size.width * 0.08, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_SlantClipper oldClipper) => false;
}
