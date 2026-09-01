/// Base type for every event emitted on PerfScope's public event stream.
///
/// [PerformanceEvent] is `sealed` so consumers get exhaustive pattern
/// matching over the full, compile-time-known set of events. Dart restricts
/// `sealed` subtypes to their defining library, therefore [FrameEvent],
/// [LifecycleEvent], [ScreenEvent], [InteractionEvent], [TraceEvent], and
/// [AnomalyEvent] are declared in `part` files of this library instead of
/// standalone libraries.
library;

import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../anomalies/performance_anomaly.dart';
import '../frames/frame_sample.dart';

part 'anomaly_event.dart';
part 'frame_event.dart';
part 'interaction_event.dart';
part 'lifecycle_event.dart';
part 'screen_event.dart';
part 'trace_event.dart';

sealed class PerformanceEvent {
  /// Creates an event carrying a correlation [id] and wall-clock [timestamp].
  ///
  /// The constructor is const-capable for symmetry; because [DateTime]
  /// cannot be a const value in practice, instances are created normally at
  /// runtime and treated as immutable afterwards.
  const PerformanceEvent({required this.id, required this.timestamp});

  /// Local correlation identifier unique within this PerfScope session.
  final String id;

  /// Wall-clock time at which the event was produced.
  final DateTime timestamp;
}
