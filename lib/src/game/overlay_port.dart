/// Somewhere to put overlays, or not.
///
/// The coordinator is headless: it has no widgets, so every `overlays.add(...)`
/// in the shared game base was wrapped in `if (!isHeadlessMode)`. That put a
/// role check at eleven call sites to express one fact — this node has no UI.
///
/// A no-op implementation says it once instead.
///
/// Only overlay presentation goes through here. Guards that also cover
/// behaviour — starting a countdown, running its audio — deliberately keep
/// their explicit role check, because making those no-ops would silently
/// change what the coordinator simulates rather than what it displays.
abstract interface class OverlayPort {
  void add(String id);
  void remove(String id);
  bool isActive(String id);
}

/// Forwards to a live Flame overlay set.
///
/// Takes closures rather than the overlay manager itself: Flame does not
/// export that type from its public API, and reaching into `src/` for it would
/// couple this file to Flame's internals for no gain.
class FlameOverlayPort implements OverlayPort {
  const FlameOverlayPort({
    required this.addOverlay,
    required this.removeOverlay,
    required this.overlayIsActive,
  });

  final void Function(String id) addOverlay;
  final void Function(String id) removeOverlay;
  final bool Function(String id) overlayIsActive;

  @override
  void add(String id) => addOverlay(id);

  @override
  void remove(String id) => removeOverlay(id);

  @override
  bool isActive(String id) => overlayIsActive(id);
}

/// Accepts and discards everything. Held by the headless coordinator.
///
/// [isActive] always reports false, which is consistent: an overlay that was
/// never shown is not showing.
class NoOverlayPort implements OverlayPort {
  const NoOverlayPort();

  @override
  void add(String id) {}

  @override
  void remove(String id) {}

  @override
  bool isActive(String id) => false;
}
