// phase-03
// Snapshot of the native listener's health, as surfaced by
// `listenerStatus` on the control channel.
class ListenerStatus {
  const ListenerStatus({
    required this.connected,
    required this.lastEventAt,
    required this.componentEnabled,
  });

  /// Is the system binding live right now?
  final bool connected;

  /// Epoch ms of the last captured event (0 = nothing yet).
  final int lastEventAt;

  /// Is the service component enabled (not disabled via the toggle
  /// workaround or by the system)?
  final bool componentEnabled;

  /// True when the user has granted notification access at the OS
  /// level (component enabled AND bound at least once — the binding
  /// only exists for granted listeners).
  bool get granted => componentEnabled && connected;

  static ListenerStatus fromMap(Map<Object?, Object?> map) {
    return ListenerStatus(
      connected: map['connected'] as bool? ?? false,
      lastEventAt: map['lastEventAt'] as int? ?? 0,
      componentEnabled: map['componentEnabled'] as bool? ?? false,
    );
  }
}
