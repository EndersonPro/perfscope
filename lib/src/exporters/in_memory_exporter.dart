/// [PerformanceExporter] that keeps serialized JSON in memory.
///
/// Intended for tests, debug screens, and short inspection windows;
/// exports accumulate unbounded by design — call [clear] when done.
library;

import 'dart:convert';

import '../anomalies/frame_context_window.dart' show FrameContextWindow;
import '../serialization/session_serializer.dart';
import '../sessions/performance_session.dart';
import 'performance_exporter.dart';

/// Stores every exported JSON string in insertion order and exposes the
/// most recent one through [lastJson].
final class InMemoryExporter implements PerformanceExporter {
  final List<String> _exports = <String>[];

  /// The JSON produced by the most recent export, null before the first.
  String? get lastJson => _exports.isEmpty ? null : _exports.last;

  /// How many exports have been captured so far.
  int get count => _exports.length;

  /// Chronological snapshot of every captured JSON string.
  List<String> get exports => List.unmodifiable(_exports);

  /// Drops all captured exports.
  void clear() => _exports.clear();

  @override
  Future<void> export(
    PerformanceSession session, {
    FrameContextWindow? Function(String anomalyId)? resolveContextWindow,
  }) async {
    _exports.add(
      jsonEncode(
        const SessionSerializer().serialize(
          reportForExport(session),
          resolveContextWindow: resolveContextWindow,
        ),
      ),
    );
  }
}
