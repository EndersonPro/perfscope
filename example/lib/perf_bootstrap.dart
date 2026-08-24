import 'package:perfscope/perfscope.dart';

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
