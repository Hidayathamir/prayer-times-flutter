/// App-wide configuration.
/// Toggle `devMode` to enable/disable developer features.
class AppConfig {
  /// Set to `true` during development to show debug tools (e.g. notification preview FAB).
  /// Set to `false` before building for production/release.
  static const bool devMode = false;

  /// Snooze duration for notifications (in seconds).
  /// In production, this will be 300 (5 minutes).
  /// In development, you can set this to any value for testing.
  static const int snoozeDurationSeconds = devMode ? 10 : 300;
}
