/// Test utilities for PerfScope consumers.
///
/// Exports deterministic fakes that make golden-style assertions over
/// PerfScope behavior possible without real frame timings or wall clocks:
///
/// * [FakeFrameSource] — push synthetic samples on demand.
/// * [MemoryLogWriter] — capture everything PerfScope writes.
library;

export 'src/logging/log_writer.dart' show MemoryLogWriter;
export 'src/testing/fake_frame_source.dart';
