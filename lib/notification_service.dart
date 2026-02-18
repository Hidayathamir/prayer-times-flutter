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
    DateTime prayerTime,
  ) async {
    // 1. Calculate 15 minutes before
    final reminderTime = prayerTime.subtract(const Duration(minutes: 15));

    // 2. Safety Check: If time has already passed, don't schedule
    if (reminderTime.isBefore(DateTime.now())) {
      debugPrint("Skipping $prayerName - reminder time $reminderTime already passed");
      return;
    }

    // 3. Convert to "TZDateTime" (Required by the plugin)
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
      reminderTime,
      tz.local,
    );

    debugPrint("TZ scheduledDate: $scheduledDate (location: ${scheduledDate.location})");

    // 4. Define the expandable notification style (Android)
    final BigTextStyleInformation bigTextStyleInformation =
        BigTextStyleInformation(
          '$prayerName is in 15 minutes. Time to prepare!\n'
          'Here is a long text to test the expandability feature. '
          'If you can read this whole sentence, your expandable notification '
          'is working perfectly on Android!',
          contentTitle: '<b>$prayerName Warning</b>', // HTML-like styling
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
          styleInformation: bigTextStyleInformation, // <--- THIS IS KEY
        );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    // 5. Schedule it!
    try {
      await _notifications.zonedSchedule(
        id: id,
        title: 'Prayer Upcoming',
        body:
            '$prayerName is in 15 minutes (${DateFormat.Hm().format(prayerTime)})',
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint("Scheduled $prayerName reminder for $reminderTime");
    } catch (e, stackTrace) {
      debugPrint("ERROR scheduling $prayerName: $e");
      debugPrint("Stack trace: $stackTrace");
    }
  }
}
