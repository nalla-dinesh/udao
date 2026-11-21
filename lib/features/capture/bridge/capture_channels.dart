// phase-03
// Channel + method names for the native capture surface. LOCKED by
// test/features/capture/bridge_contract_test.dart, which asserts
// string parity against the Kotlin sources — a rename on either side
// fails the build's test stage by design.
abstract final class CaptureChannels {
  /// Live posted-notification events (EventChannel).
  static const String stream = 'udao/capture/stream';

  /// Control surface (MethodChannel).
  static const String control = 'udao/capture/control';

  // Methods on [control] — must match CaptureBridge.kt verbatim.
  static const String methodGetWAL = 'getWAL';
  static const String methodAckWAL = 'ackWAL';
  static const String methodListenerStatus = 'listenerStatus';
  static const String methodRequestRebind = 'requestRebind';
  static const String methodOpenListenerSettings = 'openListenerSettings';
  static const String methodRebindViaToggle = 'rebindViaToggle';
  static const String methodPushAllowlist = 'pushAllowlist';

  // Status payload keys — must match the Kotlin mapOf keys.
  static const String keyConnected = 'connected';
  static const String keyLastEventAt = 'lastEventAt';
  static const String keyComponentEnabled = 'componentEnabled';
}
