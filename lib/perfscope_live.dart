/// `perfscope_live` — loopback-only live bridge for PerfScope.
///
/// One opt-in call ([LivePerfScope.serve]) in a profile entrypoint serves a
/// read-only view of the in-memory session for agents/`curl`. Slice 1 ships
/// the lifecycle, token gate, `GET /v1/status` and `GET /v1/ai-context`.
///
/// Opt-in library: import `package:perfscope/perfscope_live.dart` explicitly.
/// The main barrel (`package:perfscope/perfscope.dart`) never exports live
/// symbols, so release builds stay free of socket code unless opted in.
library;

export 'src/live/live_server.dart';
export 'src/live/snapshot/live_snapshot.dart';
