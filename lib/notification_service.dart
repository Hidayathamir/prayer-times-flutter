import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
}
