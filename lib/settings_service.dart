import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage app settings with persistence.
class SettingsService {
  static const String _keyNotificationMinutes = 'notification_minutes_before';
  static const String _keySnoozeSeconds = 'snooze_duration_seconds';

  // Default values
  static const int defaultNotificationMinutes = 15;
  static const int defaultSnoozeSeconds = 300; // 5 minutes

  // Available options for notification time (minutes before prayer)
  static const List<int> notificationTimeOptions = [5, 10, 15, 20, 30, 45, 60];

  // Available options for snooze duration (in seconds)
  static const List<int> snoozeDurationOptions = [60, 120, 180, 300, 600, 900]; // 1, 2, 3, 5, 10, 15 min

  static SharedPreferences? _prefs;

  /// Initialize the settings service. Call this in main() before runApp.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get notification time in minutes before prayer.
  static int get notificationMinutesBefore {
    return _prefs?.getInt(_keyNotificationMinutes) ?? defaultNotificationMinutes;
  }

  /// Set notification time in minutes before prayer.
  static Future<void> setNotificationMinutesBefore(int minutes) async {
    await _prefs?.setInt(_keyNotificationMinutes, minutes);
  }

  /// Get snooze duration in seconds.
  static int get snoozeDurationSeconds {
    return _prefs?.getInt(_keySnoozeSeconds) ?? defaultSnoozeSeconds;
  }

  /// Set snooze duration in seconds.
  static Future<void> setSnoozeDurationSeconds(int seconds) async {
    await _prefs?.setInt(_keySnoozeSeconds, seconds);
  }

  /// Format snooze duration into readable text.
  static String formatSnoozeDuration(int seconds) {
    if (seconds < 60) {
      return '$seconds second${seconds == 1 ? '' : 's'}';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      if (remainingSeconds == 0) {
        return '$minutes minute${minutes == 1 ? '' : 's'}';
      } else {
        return '$minutes minute${minutes == 1 ? '' : 's'} $remainingSeconds second${remainingSeconds == 1 ? '' : 's'}';
      }
    } else {
      final hours = seconds ~/ 3600;
      final remainingMinutes = (seconds % 3600) ~/ 60;
      if (remainingMinutes == 0) {
        return '$hours hour${hours == 1 ? '' : 's'}';
      } else {
        return '$hours hour${hours == 1 ? '' : 's'} $remainingMinutes minute${remainingMinutes == 1 ? '' : 's'}';
      }
    }
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
}
