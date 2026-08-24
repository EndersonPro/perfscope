import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import '../../app/scenario.dart';
import '../../app/scenario_scaffold.dart';

/// Raster-pressure scenario: expensive paint work loaded in bursts.
///
/// A grid of cards with stacked shadows, gradients, and rounded clips is
/// rebuilt repeatedly so several raster passes of the decorated tree happen
/// within one interaction. NOTE: qualitative stress example, NOT a
/// reproducible benchmark — absolute raster numbers depend on device,
/// resolution, and GPU; treat them as directional signals only.
class RasterPressureScreen extends StatefulWidget {
  const RasterPressureScreen({super.key});

  @override
  State<RasterPressureScreen> createState() => _RasterPressureScreenState();
}

class _RasterPressureScreenState extends State<RasterPressureScreen> {
  int _stormGeneration = 0;
  int _rasterAnomalyCount = 0;
  String? _lastAnomalyLine;

  void _rebuildStorm() {
    // Repeatedly invalidate the tree to force several raster passes of the
    // decorated grid within one interaction.
    for (int i = 0; i < 8; i++) {
      setState(() => _stormGeneration++);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshResults());
  }

  void _refreshResults() {
    final anomalies = PerfScope.anomalies
        .whereType<RasterBoundFrameAnomaly>()
        .toList();
    setState(() {
      _rasterAnomalyCount = anomalies.length;
      if (anomalies.isNotEmpty) {
        final latest = anomalies.last;
        _lastAnomalyLine =
            '${latest.sample.totalDuration.inMilliseconds}ms '
            'total, build ${latest.sample.buildDuration.inMilliseconds}ms, '
            'raster ${latest.sample.rasterDuration.inMilliseconds}ms, '
            'severity ${latest.severity.name}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'Raster pressure',
      categoryLabel: ScenarioCategory.frames.label,
      categoryColor: ScenarioCategory.frames.color,
      summary:
          'Forces repeated rebuild passes over 24 heavily decorated cards. '
          'When the raster phase dominates the frame budget, PerfScope '
          'flags the probable bottleneck as raster.',
      captures:
          'Frame anomalies classified RasterBoundFrameAnomaly, with build '
          'and raster durations attached per triggering frame.',
      codeSnippet: '''
// Layered shadows and gradients make paint expensive:
DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(colors: [base, base.withValues(alpha: .4)]),
    boxShadow: [BoxShadow(blurRadius: 18), BoxShadow(blurRadius: 10)],
  ),
);
// Watch raster_ms dominate build_ms in the captured anomalies.''',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton(
            key: const ValueKey<String>('rebuild-storm'),
            onPressed: _rebuildStorm,
            child: const Text('Rebuild storm (8 invalidations)'),
          ),
          const SizedBox(height: 16),
          Text('Raster-bound anomalies so far: $_rasterAnomalyCount'),
          if (_lastAnomalyLine != null)
            Text(_lastAnomalyLine!, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          // Fixed-height inner viewport: this child is a leaf of the
          // scaffold's ListView (unbounded height), so the grid MUST get an
          // explicit extent — Expanded would crash and an unbounded grid
          // inside a list item produces NaN layouts (Infinity toInt).
          SizedBox(height: 420, child: _buildGrid()),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      key: ValueKey<String>('grid-$_stormGeneration'),
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: 24,
      itemBuilder: (BuildContext context, int index) =>
          _HeavyCard(index: index, generation: _stormGeneration),
    );
  }
}

final class _HeavyCard extends StatelessWidget {
  const _HeavyCard({required this.index, required this.generation});

  final int index;
  final int generation;

  @override
  Widget build(BuildContext context) {
    final Color base = HSVColor.fromAHSV(
      1,
      (index * 37 % 360) / 360,
      0.7,
      0.85,
    ).toColor();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[base, base.withValues(alpha: 0.4)],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: base.withValues(alpha: 0.55),
              blurRadius: 18,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(4, 4),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.15),
              blurRadius: 4,
              offset: const Offset(-2, -2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '#$index g$generation',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
