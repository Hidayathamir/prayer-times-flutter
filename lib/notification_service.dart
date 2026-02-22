import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'settings_service.dart';

class NotificationService {
  // 1. Create the plugin instance
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Helper to format snooze duration into readable text (delegates to SettingsService)
  static String _formatSnoozeDuration(int seconds) {
    return SettingsService.formatSnoozeDuration(seconds);
  }

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

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

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

  // Handle notification tap actions
  static void _onNotificationTapped(NotificationResponse response) {
    if (response.actionId == 'snooze' || response.actionId == 'snooze_5min') {
      final payload = response.payload;
      if (payload != null) {
        _handleSnoozeAction(payload);
      }
    }
  }

  // Handle snooze action
  static void _handleSnoozeAction(String payload) {
    try {
      debugPrint('=== SNOOZE ACTION TRIGGERED ===');
      debugPrint('Payload: $payload');
      
      final snoozeSeconds = SettingsService.snoozeDurationSeconds;
      final newTime = DateTime.now().add(
        Duration(seconds: snoozeSeconds)
      );
      
      debugPrint('Scheduling snooze for $snoozeSeconds seconds');
      _scheduleBackupSnooze(payload, newTime);
    } catch (e) {
      debugPrint("Error handling snooze action: $e");
    }
  }

  static Future<void> _scheduleBackupSnooze(String prayerName, DateTime newTime) async {
    debugPrint('=== BACKUP SCHEDULED SNOOZE ===');
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
      newTime,
      tz.local,
    );

    debugPrint('Scheduled date: $scheduledDate');
    debugPrint('Local timezone: ${tz.local}');

    final snoozeSeconds = SettingsService.snoozeDurationSeconds;

    // Create custom notification details with vibration for snooze
    final NotificationDetails details = _getAlarmNotificationDetails(
      channelId: 'prayer_channel_alarm_2', // Use same channel as main notifications
      channelName: 'Prayer Alarms',
      channelDescription: 'Alarm reminders before prayer',
      styleInformation: null, // Use default style for snooze notifications
      enableSnooze: true, // Enable snooze for snooze notifications too
    );

    try {
      await _notifications.zonedSchedule(
        id: prayerName.hashCode + 1000, // Different ID to avoid conflicts
        title: 'Reminder: $prayerName',
        body: 'This is your ${_formatSnoozeDuration(snoozeSeconds)} reminder for $prayerName.',
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: prayerName,
      );
      debugPrint("Scheduled snooze notification for $prayerName at ${DateFormat.Hm().format(newTime)}");
    } catch (e, stackTrace) {
      debugPrint("ERROR scheduling snooze for $prayerName: $e");
      debugPrint("Stack trace: $stackTrace");
    }
  }

  // Helper for consistent alarm notification details
  static NotificationDetails _getAlarmNotificationDetails({
    required String channelId,
    required String channelName,
    String? channelDescription,
    BigTextStyleInformation? styleInformation,
    bool enableSnooze = true,
  }) {
    final snoozeSeconds = SettingsService.snoozeDurationSeconds;
    final snoozeText = 'Remind me in ${_formatSnoozeDuration(snoozeSeconds)}';
    
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
      sound: const RawResourceAndroidNotificationSound('alarm'),
      additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT
      fullScreenIntent: true,
      styleInformation: styleInformation,
      actions: enableSnooze ? [
        AndroidNotificationAction(
          'snooze',
          snoozeText,
          showsUserInterface: false,
        ),
      ] : null,
    );

    return NotificationDetails(android: androidDetails);
  }

  // Unified prayer notification method (DRY approach)
  static Future<void> showPrayerNotification({
    required int id,
    required String prayerName,
    required String title,
    required String body,
    DateTime? scheduledTime,
    bool isInstant = false,
    bool enableSnooze = true,
  }) async {
    final now = DateTime.now();
    
    // Determine if we should show instantly or schedule
    bool showInstantly = isInstant;
    DateTime? effectiveScheduledTime = scheduledTime;
    
    if (!isInstant && scheduledTime != null) {
      // For scheduled notifications, check if the scheduled time has passed
      if (scheduledTime.isBefore(now)) {
        showInstantly = true;
        effectiveScheduledTime = null;
      }
    }

    // Create payload for snooze functionality
    final payload = '$prayerName|$title|$body|$id';

    final BigTextStyleInformation bigTextStyleInformation = BigTextStyleInformation(
      body,
      contentTitle: '<b>$title</b>',
      htmlFormatContentTitle: true,
      summaryText: '$prayerName Soon',
    );

    final NotificationDetails details = _getAlarmNotificationDetails(
      channelId: 'prayer_channel_alarm_2',
      channelName: 'Prayer Alarms',
      channelDescription: 'Alarm reminders 15m before prayer',
      styleInformation: bigTextStyleInformation,
      enableSnooze: enableSnooze, // Enable snooze for both instant and scheduled notifications
    );

    try {
      if (showInstantly) {
        debugPrint("Showing instant notification for $prayerName");
        await _notifications.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: details,
          payload: payload,
        );
      } else if (effectiveScheduledTime != null) {
        final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
          effectiveScheduledTime,
          tz.local,
        );
        
        debugPrint("Scheduling notification for $prayerName at ${DateFormat.Hm().format(effectiveScheduledTime)}");
        await _notifications.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: payload,
        );
      }
    } catch (e, stackTrace) {
      debugPrint("ERROR in showPrayerNotification for $prayerName: $e");
      debugPrint("Stack trace: $stackTrace");
    }
  }

  // 3. Simple Instant Notification (for testing) - now uses unified method
  static Future<void> showInstantNotification(String title, String body) async {
    await showPrayerNotification(
      id: 0,
      prayerName: 'Test',
      title: title,
      body: body,
      isInstant: true,
    );
  }

  // 4. Direct schedule test (no 15-minute subtraction)
  static Future<void> scheduleDirectTest(int id, Duration delay) async {
    final scheduledTime = tz.TZDateTime.now(tz.local).add(delay);

    debugPrint("TZ local location: ${tz.local}");
    debugPrint("TZ now: ${tz.TZDateTime.now(tz.local)}");
    debugPrint("Scheduling direct test for: $scheduledTime");

    final NotificationDetails details = _getAlarmNotificationDetails(
      channelId: 'prayer_channel_alarm_2',
      channelName: 'Prayer Alarms',
      channelDescription: 'Alarm reminders before prayer',
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
    final minutesBefore = SettingsService.notificationMinutesBefore;
    final reminderTime = prayerTime.subtract(Duration(minutes: minutesBefore));

    // Case 3: Prayer time itself already passed → skip entirely
    if (prayerTime.isBefore(now)) {
      debugPrint("Skipping $prayerName - prayer time ${DateFormat.Hm().format(prayerTime)} already passed");
      return;
    }

    // Case 2: Prayer is upcoming but reminder window already passed → notify instantly
    if (reminderTime.isBefore(now)) {
      final minutesLeft = prayerTime.difference(now).inMinutes;
      debugPrint("$prayerName is in $minutesLeft minutes - notifying instantly!");
      await showPrayerNotification(
        id: id,
        prayerName: prayerName,
        title: notifTitle ?? 'Prayer Upcoming',
        body: notifBody ?? '$prayerName is in $minutesLeft minutes! (${DateFormat.Hm().format(prayerTime)})',
        isInstant: true,
        enableSnooze: true, // Enable snooze for instant notifications too
      );
      return;
    }

    // Case 1: Both prayer time and reminder time are in the future → schedule normally
    debugPrint("Scheduling $prayerName reminder at ${DateFormat.Hm().format(reminderTime)} "
        "(prayer at ${DateFormat.Hm().format(prayerTime)})");

    await showPrayerNotification(
      id: id,
      prayerName: prayerName,
      title: notifTitle ?? 'Prayer Upcoming',
      body: notifBody ?? '$prayerName is in $minutesBefore minutes (${DateFormat.Hm().format(prayerTime)})',
      scheduledTime: reminderTime,
      isInstant: false,
    );
  }

  // Cancel all scheduled notifications
  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
    debugPrint("All scheduled notifications cancelled");
  }
}
