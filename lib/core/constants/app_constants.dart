// App-wide constants. Keep this file SMALL — it is not a dumping
// ground; feature-specific constants live in their feature folders.
abstract final class AppConstants {
  /// Product name.
  static const String appName = 'UDAO';

  /// Keep in sync with `version:` in pubspec.yaml.
  static const String appVersion = '0.1.0';

  /// Native bridge hosted by `MainActivity.UdaoChannel` (android/).
  static const String platformChannelName = 'udao/platform';

  /// Method on [platformChannelName] returning the read-only device
  /// facts map: `appFlavor`, `manufacturer`, `brand`, `sdkInt`.
  static const String platformDeviceInfoMethod = 'getDeviceInfo';

  /// UdaoLogger ring buffer capacity (in-memory entries).
  static const int logRingCapacity = 500;
}
