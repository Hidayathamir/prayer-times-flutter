import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:adhan/adhan.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'settings_service.dart';
import 'prayer_data_service.dart';

class AlarmService {
  // Base alarm IDs for each prayer.
  // Day offset is encoded as: id = base + dayOffset * 10
  // So Fajr day0=1001, day1=1011, day2=1021 … day6=1061
  static const int _fajrBase    = 1001;
  static const int _dhuhrBase   = 1002;
  static const int _asrBase     = 1003;
  static const int _maghribBase = 1004;
  static const int _ishaBase    = 1005;

  /// How many days ahead to schedule alarms.
  static const int scheduleDays = 7;

  static const String _alarmAsset = 'assets/alarm.wav';

  static int _baseIdForPrayer(String name) {
    switch (name) {
      case 'Fajr':    return _fajrBase;
      case 'Dhuhr':   return _dhuhrBase;
      case 'Asr':     return _asrBase;
      case 'Maghrib': return _maghribBase;
      case 'Isha':    return _ishaBase;
      default:        return name.hashCode.abs() % 10 + 2000;
    }
  }

  /// Alarm ID for a given prayer + day offset (0 = today, 1 = tomorrow, …)
  static int _idForPrayerDay(String name, int dayOffset) =>
      _baseIdForPrayer(name) + dayOffset * 10;

  /// Must be called once from main() BEFORE runApp()
  static Future<void> init() async {
    await Alarm.init();

    if (Platform.isAndroid) {
      // Request exact alarm permission (Android 12+)
      final status = await Permission.scheduleExactAlarm.status;
      debugPrint('[AlarmService] scheduleExactAlarm status: $status');
      if (!status.isGranted) {
        final result = await Permission.scheduleExactAlarm.request();
        debugPrint('[AlarmService] scheduleExactAlarm after request: $result');
      }

      // Request POST_NOTIFICATIONS (Android 13+)
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        await Permission.notification.request();
      }
    }
  }

  /// Schedule alarms for all 5 prayers across the next [scheduleDays] days.
  /// Cancels any existing prayer alarms first.
  ///
  /// Pass the saved [coordinates] and [params] so prayer times can be
  /// recalculated for each future day without opening the app again.
  static Future<void> scheduleAllPrayerAlarms({
    required Coordinates coordinates,
    required CalculationParameters params,
  }) async {
    await cancelAll();

    final minutesBefore = SettingsService.notificationMinutesBefore;
    final now = DateTime.now();
    int scheduled = 0;

    for (int dayOffset = 0; dayOffset < scheduleDays; dayOffset++) {
      final targetDate = now.add(Duration(days: dayOffset));
      final dateComponents = DateComponents.from(targetDate);
      final prayerTimes = PrayerTimes(coordinates, dateComponents, params);

      final prayers = <String, DateTime>{
        'Fajr':    prayerTimes.fajr,
        'Dhuhr':   prayerTimes.dhuhr,
        'Asr':     prayerTimes.asr,
        'Maghrib': prayerTimes.maghrib,
        'Isha':    prayerTimes.isha,
      };

      for (final entry in prayers.entries) {
        final prayerName = entry.key;
        final prayerTime = entry.value;
        final alarmTime  = prayerTime.subtract(Duration(minutes: minutesBefore));

        // Skip if alarm time has already passed
        if (alarmTime.isBefore(now)) {
          debugPrint('[AlarmService] Skipping $prayerName day+$dayOffset — already passed');
          continue;
        }

        final msg = PrayerDataService.getMessageForDate(prayerName, targetDate);
        final title = msg?.title ?? '$prayerName – $minutesBefore min';
        final body  = msg?.body  ?? '$prayerName prayer is in $minutesBefore minutes.';

        await _setAlarm(
          id:        _idForPrayerDay(prayerName, dayOffset),
          dateTime:  alarmTime,
          title:     title,
          body:      body,
          stopLabel: 'Stop ($prayerName)',
        );

        debugPrint('[AlarmService] Scheduled $prayerName day+$dayOffset at $alarmTime');
        scheduled++;
      }
    }

    debugPrint('[AlarmService] Total alarms scheduled: $scheduled (across $scheduleDays days)');
  }

  /// Schedule a single alarm that fires [delay] from now. Useful for testing.
  static Future<void> scheduleTestAlarm({
    int id = 9999,
    Duration delay = const Duration(seconds: 5),
    String prayerName = 'Test',
  }) async {
    final alarmTime = DateTime.now().add(delay);
    debugPrint('[AlarmService] Scheduling TEST alarm at $alarmTime');

    // Use today's CSV message if available (same as real alarms)
    final msg = PrayerDataService.getMessageForToday(prayerName);
    await _setAlarm(
      id:        id,
      dateTime:  alarmTime,
      title:     msg?.title ?? '🕌 $prayerName – Test Alarm',
      body:      msg?.body  ?? 'This is a test alarm. It works!',
      stopLabel: 'Stop',
    );
  }

  static Future<void> _setAlarm({
    required int id,
    required DateTime dateTime,
    required String title,
    required String body,
    required String stopLabel,
  }) async {
    final settings = AlarmSettings(
      id:             id,
      dateTime:       dateTime,
      assetAudioPath: _alarmAsset,
      loopAudio:      true,
      vibrate:        true,
      warningNotificationOnKill: Platform.isIOS,
      androidFullScreenIntent:   true,
      volumeSettings: VolumeSettings.fade(
        volume:       0.9,
        fadeDuration: const Duration(seconds: 5),
        volumeEnforced: true,
      ),
      notificationSettings: NotificationSettings(
        title:      title,
        body:       body,
        stopButton: stopLabel,
        icon:       'mipmap/launcher_icon',
      ),
    );

    try {
      await Alarm.set(alarmSettings: settings);
    } catch (e, st) {
      debugPrint('[AlarmService] ERROR setting alarm id=$id: $e');
      debugPrint('[AlarmService] $st');
    }
  }

  /// Cancel a single alarm by its prayer name (today's alarm only)
  static Future<void> cancelPrayer(String prayerName) async {
    await Alarm.stop(_idForPrayerDay(prayerName, 0));
  }

  /// Snooze a ringing alarm: stop it and re-schedule N minutes from now.
  /// Special case: minutes == 0 means 5 seconds (dev mode).
  static Future<void> snooze({
    required int id,
    required int minutes,
    required String prayerName,
  }) async {
    await Alarm.stop(id);
    final duration = minutes == 0
        ? const Duration(seconds: 5)
        : Duration(minutes: minutes);
    final snoozeTime = DateTime.now().add(duration);
    debugPrint('[AlarmService] Snoozing alarm id=$id for $duration → $snoozeTime');
    await _setAlarm(
      id: id,
      dateTime: snoozeTime,
      title: '⏰ $prayerName – Snoozed Reminder',
      body: 'Your snoozed $prayerName reminder.',
      stopLabel: 'Stop ($prayerName)',
    );
  }

  /// Cancel ALL prayer alarms across all scheduled days
  static Future<void> cancelAll() async {
    const prayerNames = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    for (final name in prayerNames) {
      for (int day = 0; day < scheduleDays; day++) {
        await Alarm.stop(_idForPrayerDay(name, day));
      }
    }
    debugPrint('[AlarmService] All prayer alarms cancelled (${scheduleDays} days)');
  }

  /// Stream of alarms ringing (from the alarm package)
  static Stream<AlarmSettings> get onAlarmRing => Alarm.ringStream.stream;
}
