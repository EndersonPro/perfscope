import 'package:perfscope/perfscope.dart';
import 'package:perfscope/perfscope_live.dart';

/// PerfScope-only bootstrap module for the profile entry point.
///
/// Everything in this file exists to start and stop the observability
/// engine. It is imported by `main_profile.dart` (and by screens that want
/// to read RAW captured events back) and deliberately kept separate from
/// the application shell so the release entry point never initializes any
/// of it.
///
/// The shared [MemorySink] below is the reason this module exists as more
/// than a function: sinks are stateful runtime collaborators whose identity
/// belongs to the embedding app (see [PerfScope.initialize]), and several
/// showcase screens read the captured events directly from the same
/// instance that was handed to the engine.
///
/// Capacity is raised above the [defaultMemorySinkCapacity] default because
/// every observed frame becomes an event and the showcase wants a generous
/// inspection window on its diagnostics screens.
final MemorySink showcaseMemorySink = MemorySink(capacity: 5000);

/// Handle of the live-bridge server started by the profile entry point.
///
/// Assigned from the `serve()` future in `main_profile.dart` (serving
/// handles only); null until the bind completes or when the bridge is
/// disabled. The live event console reads it to render the bridge line; the
/// token itself is never exposed to the UI.
LiveServerHandle? liveBridgeHandle;

/// Formats the one-line live-bridge status for the event console.
///
/// Pure over its input (falling back to [liveBridgeHandle], then to
/// [LivePerfScope.current]): a serving handle renders its URL with the bound
/// port, anything else renders `off`. The Bearer token never appears here —
/// it lives in the console output and `.dart_tool/perfscope-live.json` only.
String liveBridgeLine([LiveServerHandle? handle]) {
  final LiveServerHandle? effective =
      handle ?? liveBridgeHandle ?? LivePerfScope.current;
  if (effective == null || !effective.isServing) {
    return 'Live bridge: off';
  }
  return 'Live bridge: http://127.0.0.1:${effective.port}/v1/status · token '
      'in console';
}

/// Initializes PerfScope and opens the named `'showcase'` session.
///
/// Call once from the profile entry point after
/// `WidgetsFlutterBinding.ensureInitialized()`.
///
/// * `printWarnings` is enabled so frame warnings appear in the console,
///   which is half of what this app demonstrates.
/// * The shared [showcaseMemorySink] is registered as a raw-event tap so
///   UI screens can render captured events without subscribing to the
///   broadcast stream.
/// * An explicitly named session replaces the automatic anonymous one
///   ([PerfScopeConfig.autoStartSession]): opening it auto-finalizes the
///   auto-started session, and reports produced later identify themselves
///   as coming from the showcase run.
///
/// Idempotent by delegation: a second call is ignored by
/// [PerfScope.initialize] with a log line.
void bootstrapPerfScope() {
  PerfScope.initialize(
    config: const PerfScopeConfig(printWarnings: true),
    sinks: <PerformanceEventSink>[showcaseMemorySink],
  );
  PerfScope.startSession('showcase');
}

/// Tears the engine down and resets singleton state (hot-restart friendly).
Future<void> shutdownPerfScope() => PerfScope.dispose();
