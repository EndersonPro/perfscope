import 'package:flutter/widgets.dart';

import '../perfscope_facade.dart';
import 'screen_context_port.dart';

/// [NavigatorObserver] that feeds route changes into PerfScope's screen
/// context.
///
/// Attach it to the root `MaterialApp.navigatorObservers` (or to any
/// `Navigator.observers`) and every push/pop/replace/remove updates the
/// current screen and emits a [ScreenEvent]-worthy mutation through the
/// active engine.
///
/// Construction modes:
/// * Default: resolves the live engine singleton lazily on every callback,
///   so attaching before `PerfScope.initialize()` is safe. Without an
///   engine every method is a no-op — this observer must never throw when
///   the host app runs without initialization.
/// * `port:` injection for tests and advanced embeddings that own their
///   engine instance.
///
/// Nested navigators caveat: each [Navigator] only reports through the
/// observers registered on *itself*. A nested navigator (bottom tabs,
/// modal flows) without this observer attached will not update the screen
/// context; attach a separate observer per navigator that should count as
/// screen navigation, and be aware overlapping reports can occur when the
/// same logical screen change bubbles through two navigators.
final class PerfScopeNavigatorObserver extends NavigatorObserver {
  /// Creates an observer. Pass [port] to bypass the facade locator (tests,
  /// custom engines); omit it to bind to the live engine automatically.
  PerfScopeNavigatorObserver({ScreenContextPort? port}) : _injectedPort = port;

  final ScreenContextPort? _injectedPort;

  ScreenContextPort? get _target {
    final injected = _injectedPort;
    if (injected != null) {
      return injected;
    }
    return PerfScope.maybeEngine;
  }

  void _withTarget(void Function(ScreenContextPort target) action) {
    // Never let observability break navigation: failures are swallowed by
    // design here, while the engine guards and logs its own internals.
    try {
      final target = _target;
      if (target != null) {
        action(target);
      }
    } catch (_) {
      // Swallowed on purpose: see class doc ("must never throw").
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _withTarget((port) => port.onRoutePushed(route.settings.name));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _withTarget((port) => port.onRoutePopped());
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _withTarget((port) => port.onRouteReplaced(newRoute?.settings.name));
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _withTarget((port) => port.onRouteRemoved());
  }
}
