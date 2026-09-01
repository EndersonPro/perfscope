import 'package:flutter/foundation.dart';

/// Destination for human- and machine-readable PerfScope output.
///
/// Abstracting output keeps PerfScope decoupled from any single sink: the
/// console, an in-memory buffer for tests, or a file logger are all valid
/// targets.
abstract interface class LogWriter {
  /// Writes one entry. Implementations must not throw under normal use;
  /// logging failures must never crash the host application.
  void write(String value);
}

/// [LogWriter] that forwards entries to [debugPrint].
///
/// [debugPrint] throttles long outputs instead of dropping them, which makes
/// it the right default console sink during development.
class ConsoleLogWriter implements LogWriter {
  /// Creates a constant console writer.
  const ConsoleLogWriter();

  @override
  void write(String value) => debugPrint(value);
}

/// [LogWriter] that accumulates entries in memory.
///
/// Intended for tests and golden-style assertions over what PerfScope wrote;
/// not meant for production retention since memory usage grows unbounded
/// until [clear] is called.
class MemoryLogWriter implements LogWriter {
  final List<String> _lines = <String>[];

  /// Unmodifiable view of every written line, oldest first.
  List<String> get lines => List.unmodifiable(_lines);

  /// Removes all accumulated lines without deallocating the list.
  void clear() => _lines.clear();

  @override
  void write(String value) => _lines.add(value);
}
