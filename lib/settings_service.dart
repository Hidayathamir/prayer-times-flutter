import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';

/// Service to manage app settings with persistence.
class SettingsService {
  static const String _keyNotificationMinutes = 'notification_minutes_before';
  static const String _keySnoozeMins = 'snooze_duration_minutes';
  static const String _keyTimezone = 'timezone';

  // Default values
  static const int defaultNotificationMinutes = 15;
  static const int defaultSnoozeDurationMinutes = 5;
  static const String defaultTimezone = 'Asia/Jakarta';

  // Available options for alarm time (minutes before prayer)
  static const List<int> notificationTimeOptions = [5, 10, 15, 20, 30, 45, 60];

  // Available snooze duration options (in minutes). 0 = 5 seconds (dev only).
  static List<int> get snoozeDurationOptions {
    final opts = [3, 5, 10, 15, 20];
    if (AppConfig.devMode) return [0, ...opts];
    return opts;
  }

  static SharedPreferences? _prefs;

  /// Initialize the settings service. Call this in main() before runApp.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get alarm time in minutes before prayer.
  static int get notificationMinutesBefore {
    return _prefs?.getInt(_keyNotificationMinutes) ?? defaultNotificationMinutes;
  }

  /// Set alarm time in minutes before prayer.
  static Future<void> setNotificationMinutesBefore(int minutes) async {
    await _prefs?.setInt(_keyNotificationMinutes, minutes);
  }

  /// Get snooze duration in minutes.
  static int get snoozeDurationMinutes {
    return _prefs?.getInt(_keySnoozeMins) ?? defaultSnoozeDurationMinutes;
  }

  /// Set snooze duration in minutes.
  static Future<void> setSnoozeDurationMinutes(int minutes) async {
    await _prefs?.setInt(_keySnoozeMins, minutes);
  }

  /// Format notification time into readable text.
  static String formatNotificationTime(int minutes) {
    if (minutes < 60) {
      return '$minutes minute${minutes == 1 ? '' : 's'} before';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '$hours hour${hours == 1 ? '' : 's'} before';
      } else {
        return '$hours hour${hours == 1 ? '' : 's'} $remainingMinutes min before';
      }
    }
  }

  /// Format snooze minutes into readable text.
  static String formatSnoozeDuration(int minutes) {
    if (minutes == 0) return '5 sec (dev)';
    return '$minutes minute${minutes == 1 ? '' : 's'}';
  }

  /// Get timezone setting.
  static String get timezone {
    return _prefs?.getString(_keyTimezone) ?? defaultTimezone;
  }

  /// Set timezone setting.
  static Future<void> setTimezone(String timezone) async {
    await _prefs?.setString(_keyTimezone, timezone);
  }
}
