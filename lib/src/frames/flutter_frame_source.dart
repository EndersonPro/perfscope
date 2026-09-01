import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart';

import '../core/clock.dart';
import '../core/ids.dart';
import 'frame_budget.dart';
import 'frame_sample.dart';
import 'frame_source.dart';

/// [FrameSource] backed by the Flutter engine's frame timing reports.
///
/// Registers with [SchedulerBinding.addTimingsCallback] on [start] and
/// converts every reported [FrameTiming] batch into [FrameSample] values
/// pushed onto [frames].
///
/// Lifecycle contract:
/// * Calling [start] while already running throws [StateError] — the bug is
///   in the caller and must surface loudly instead of silently double-
///   registering engine callbacks.
/// * Calling [stop] when not running is an idempotent no-op.
/// * After [stop], the [frames] stream is closed and this instance cannot
///   be restarted; create a new source instead (engine lifetime matches).
final class FlutterFrameSource implements FrameSource {
  /// Creates a source converting engine timings using [frameBudgetProvider]
  /// for each sample's budget and [clock] for capture timestamps.
  FlutterFrameSource({
    required FrameBudgetProvider frameBudgetProvider,
    Clock clock = const SystemClock(),
  })  : _frameBudgetProvider = frameBudgetProvider,
        _clock = clock,
        _frameIds = IntIdGenerator();

  final FrameBudgetProvider _frameBudgetProvider;
  final Clock _clock;
  final IntIdGenerator _frameIds;

  late final StreamController<FrameSample> _controller =
      StreamController<FrameSample>.broadcast(sync: false);

  bool _running = false;

  @override
  Stream<FrameSample> get frames => _controller.stream;

  @override
  Future<void> start() async {
    if (_running) {
      throw StateError('FlutterFrameSource.start() called while running; '
          'stop() it first or create a new instance');
    }
    _running = true;
    SchedulerBinding.instance.addTimingsCallback(onTimings);
  }

  @override
  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    await _controller.close();
  }

  /// Raw entry point for engine timing batches; exposed for tests to drive
  /// the full conversion path deterministically without real frames.
  ///
  /// PERF: this runs on the UI thread for every reported frame batch. It
  /// MUST stay cheap — pure conversion only. No IO, no serialization, no
  /// heavy allocation. Expensive work belongs in downstream subscribers of
  /// [frames].
  @visibleForTesting
  void onTimings(List<FrameTiming> timings) {
    // A timing batch may still arrive while/after stopping; dropping it
    // beats adding to an already-closed controller.
    if (!_running) {
      return;
    }
    for (final timing in timings) {
      // The engine reports -1 when no frame number is available; such
      // timings carry no correlation value, so they are dropped.
      if (timing.frameNumber < 0) {
        continue;
      }
      _controller.add(convertTiming(timing));
    }
  }

  /// Converts a single [FrameTiming] into an immutable [FrameSample].
  ///
  /// Screen and interaction attribution are intentionally null here; later
  /// phases enrich samples inside the engine where routing context exists.
  @visibleForTesting
  FrameSample convertTiming(FrameTiming timing) {
    return FrameSample(
      id: _frameIds.next(),
      frameNumber: timing.frameNumber,
      capturedAt: _clock.now(),
      buildDuration: timing.buildDuration,
      rasterDuration: timing.rasterDuration,
      totalDuration: timing.totalSpan,
      vsyncOverhead: timing.vsyncOverhead,
      frameBudget: _frameBudgetProvider.currentBudget,
      screen: null,
      interactionId: null,
    );
  }
}
