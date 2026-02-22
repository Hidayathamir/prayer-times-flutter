import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage app settings with persistence.
class SettingsService {
  static const String _keyNotificationMinutes = 'notification_minutes_before';
  static const String _keySnoozeSeconds = 'snooze_duration_seconds';
  static const String _keyTimezone = 'timezone';
  static const String _keyDailyScheduleHour = 'daily_schedule_hour';
  static const String _keyDailyScheduleMinute = 'daily_schedule_minute';

  // Default values
  static const int defaultNotificationMinutes = 15;
  static const int defaultSnoozeSeconds = 300; // 5 minutes
  static const String defaultTimezone = 'Asia/Jakarta';
  static const int defaultDailyScheduleHour = 0; // 12 AM
  static const int defaultDailyScheduleMinute = 5; // 12:05 AM

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

  /// Get timezone setting.
  static String get timezone {
    return _prefs?.getString(_keyTimezone) ?? defaultTimezone;
  }

  /// Set timezone setting.
  static Future<void> setTimezone(String timezone) async {
    await _prefs?.setString(_keyTimezone, timezone);
  }

  /// Get daily schedule hour.
  static int get dailyScheduleHour {
    return _prefs?.getInt(_keyDailyScheduleHour) ?? defaultDailyScheduleHour;
  }

  /// Set daily schedule hour.
  static Future<void> setDailyScheduleHour(int hour) async {
    await _prefs?.setInt(_keyDailyScheduleHour, hour);
  }

  /// Get daily schedule minute.
  static int get dailyScheduleMinute {
    return _prefs?.getInt(_keyDailyScheduleMinute) ?? defaultDailyScheduleMinute;
  }

  /// Set daily schedule minute.
  static Future<void> setDailyScheduleMinute(int minute) async {
    await _prefs?.setInt(_keyDailyScheduleMinute, minute);
  }

  /// Get daily schedule time as formatted string.
  static String get dailyScheduleTime {
    final hour = dailyScheduleHour;
    final minute = dailyScheduleMinute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final minuteStr = minute.toString().padLeft(2, '0');
    return '$displayHour:$minuteStr $period';
  }
}
