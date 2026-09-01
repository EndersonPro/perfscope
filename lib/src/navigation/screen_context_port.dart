/// Navigation-side contract the PerfScope engine implements so framework
/// adapters (e.g. a [NavigatorObserver]) can report route changes without
/// depending on engine internals.
///
/// Kept in its own library to avoid an import cycle between the engine and
/// the observer, which resolves the live engine through the facade locator.
abstract interface class ScreenContextPort {
  /// Reports that [name] was pushed on top of the navigation stack
  /// (null for unnamed routes; normalized downstream).
  void onRoutePushed(String? name);

  /// Reports that the topmost route was popped.
  void onRoutePopped();

  /// Reports that the topmost route was replaced by one named [newName].
  void onRouteReplaced(String? newName);

  /// Reports that a route was removed from the stack by the framework.
  void onRouteRemoved();
}
