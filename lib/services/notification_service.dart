import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final StreamController<String?> selectNotificationStream =
      StreamController<String?>.broadcast();

  Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('notification_icon');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse:
          (NotificationResponse notificationResponse) {
            selectNotificationStream.add(notificationResponse.payload);
          },
    );
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      await androidImplementation?.requestNotificationsPermission();
      await androidImplementation?.requestExactAlarmsPermission();
    }
  }

  Future<void> showInstant(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'instant_channel_id',
          'Instant Notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'notification_icon',
          color: Color(0xFF00C897),
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );
    await flutterLocalNotificationsPlugin.show(0, title, body, details);
  }

  // NEW: Generic Daily Scheduler
  Future<void> scheduleDaily(
    int id,
    String title,
    String body,
    TimeOfDay time,
  ) async {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_channel_id',
          'Daily Notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'notification_icon',
          color: Color(0xFF00C897),
        ),
      ),
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> scheduleDebrief(TimeOfDay time) async {
    // Reusing the logic above, but keeping this method for specific Settings usage
    // logic (like the UTC conversion if needed) or just redirecting to scheduleDaily
    // For now, we keep the specific implementation for Debrief to avoid regression
    try {
      final DateTime now = DateTime.now();
      DateTime scheduledLocal = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );

      if (scheduledLocal.isBefore(now)) {
        scheduledLocal = scheduledLocal.add(const Duration(days: 1));
      }

      tz.TZDateTime nextTimeUtc = tz.TZDateTime.from(
        scheduledLocal.toUtc(),
        tz.UTC,
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        888,
        'Debrief Waiting',
        'Your nightly debrief is ready.',
        nextTimeUtc,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'debrief_channel_v5',
            'Debrief Notifications',
            channelDescription: 'Daily reminder for nightly debrief',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'notification_icon',
            color: Color(0xFF00C897),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'night_debrief',
      );
    } catch (e) {
      debugPrint("Error scheduling debrief: $e");
    }
  }

  Future<void> sendTestNotification() async {
    await showInstant(
      "Test Notification",
      "If you see this, notifications are working!",
    );
  }

  Future<void> cancelDebrief() async {
    await flutterLocalNotificationsPlugin.cancel(888);
  }

  Future<void> cancelAll() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}
