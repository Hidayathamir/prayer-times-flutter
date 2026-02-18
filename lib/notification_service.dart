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
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
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

  static Future<void> schedulePrayerReminder(
    int id,
    String prayerName,
    DateTime prayerTime,
  ) async {
    // 1. Calculate 15 minutes before
    final reminderTime = prayerTime.subtract(const Duration(minutes: 15));

    // 2. Safety Check: If time has already passed, don't schedule
    if (reminderTime.isBefore(DateTime.now())) {
      return;
    }

    // 3. Convert to "TZDateTime" (Required by the plugin)
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
      reminderTime,
      tz.local,
    );

    // 4. Define the expandable notification style (Android)
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'prayer_channel',
          'Prayer Reminders',
          channelDescription: 'Reminders 15m before prayer',
          importance: Importance.max,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(''), // Makes it expandable
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    // 5. Schedule it!
    await _notifications.zonedSchedule(
      id: id,
      title: 'Prayer Upcoming',
      body: '$prayerName is in 15 minutes (${DateFormat.Hm().format(prayerTime)})',
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    debugPrint("Scheduled $prayerName reminder for $reminderTime");
  }
}
