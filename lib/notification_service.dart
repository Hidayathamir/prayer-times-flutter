import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  // 1. Create the plugin instance
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // 2. Initialize settings for Android, iOS, and Linux
  static Future<void> init() async {
    // Android Setup
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Linux Setup (standard icon)
    const LinuxInitializationSettings linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    // Initialization Wrapper
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
    );

    await _notifications.initialize(settings: settings);

    // Request notification permission (required on Android 13+)
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();

      // Check and request exact alarm permission (required on Android 14+)
      final canSchedule = await androidPlugin.canScheduleExactNotifications();
      debugPrint("Can schedule exact alarms: $canSchedule");
      if (canSchedule != true) {
        debugPrint("Exact alarm permission NOT granted! Requesting...");
        await androidPlugin.requestExactAlarmsPermission();
      }
    }
  }

  // 3. Simple Instant Notification (for testing)
  static Future<void> showInstantNotification(String title, String body) async {
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'channel_id_1',
        'High Importance Notifications',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    await _notifications.show(
      id: 0, // ID (unique for every notification)
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  // 4. Direct schedule test (no 15-minute subtraction)
  static Future<void> scheduleDirectTest(int id, Duration delay) async {
    final scheduledTime = tz.TZDateTime.now(tz.local).add(delay);

    debugPrint("TZ local location: ${tz.local}");
    debugPrint("TZ now: ${tz.TZDateTime.now(tz.local)}");
    debugPrint("Scheduling direct test for: $scheduledTime");

    final NotificationDetails details = const NotificationDetails(
      android: AndroidNotificationDetails(
        'prayer_channel',
        'Prayer Reminders',
        channelDescription: 'Reminders 15m before prayer',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    try {
      await _notifications.zonedSchedule(
        id: id,
        title: 'Direct Test',
        body: 'This was scheduled $delay ago',
        scheduledDate: scheduledTime,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint("zonedSchedule completed successfully for id=$id");
    } catch (e, stackTrace) {
      debugPrint("ERROR in zonedSchedule: $e");
      debugPrint("Stack trace: $stackTrace");
    }
  }

  static Future<void> schedulePrayerReminder(
    int id,
    String prayerName,
    DateTime prayerTime, {
    String? notifTitle,
    String? notifBody,
  }) async {
    final now = DateTime.now();
    final reminderTime = prayerTime.subtract(const Duration(minutes: 15));

    // Case 3: Prayer time itself already passed → skip entirely
    if (prayerTime.isBefore(now)) {
      debugPrint("Skipping $prayerName - prayer time ${DateFormat.Hm().format(prayerTime)} already passed");
      return;
    }

    // Case 2: Prayer is upcoming but 15-min window already passed → notify instantly
    if (reminderTime.isBefore(now)) {
      final minutesLeft = prayerTime.difference(now).inMinutes;
      debugPrint("$prayerName is in $minutesLeft minutes - notifying instantly!");
      await showInstantNotification(
        notifTitle ?? 'Prayer Upcoming',
        notifBody ?? '$prayerName is in $minutesLeft minutes! (${DateFormat.Hm().format(prayerTime)})',
      );
      return;
    }

    // Case 1: Both prayer time and reminder time are in the future → schedule normally
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
      reminderTime,
      tz.local,
    );

    debugPrint("Scheduling $prayerName reminder at ${DateFormat.Hm().format(reminderTime)} "
        "(prayer at ${DateFormat.Hm().format(prayerTime)})");

    final BigTextStyleInformation bigTextStyleInformation =
        BigTextStyleInformation(
          notifBody ?? '$prayerName is in 15 minutes. Time to prepare!',
          contentTitle: '<b>${notifTitle ?? '$prayerName Reminder'}</b>',
          htmlFormatContentTitle: true,
          summaryText: '$prayerName Soon',
        );

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'prayer_channel',
          'Prayer Reminders',
          channelDescription: 'Reminders 15m before prayer',
          importance: Importance.max,
          priority: Priority.high,
          styleInformation: bigTextStyleInformation,
        );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _notifications.zonedSchedule(
        id: id,
        title: notifTitle ?? 'Prayer Upcoming',
        body: notifBody ?? '$prayerName is in 15 minutes (${DateFormat.Hm().format(prayerTime)})',
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint("Scheduled $prayerName reminder for ${DateFormat.Hm().format(reminderTime)}");
    } catch (e, stackTrace) {
      debugPrint("ERROR scheduling $prayerName: $e");
      debugPrint("Stack trace: $stackTrace");
    }
  }

  // Cancel all scheduled notifications
  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
    debugPrint("All scheduled notifications cancelled");
  }
}
