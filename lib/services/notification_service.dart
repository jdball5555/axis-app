import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:async';
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final StreamController<String?> selectNotificationStream =
      StreamController<String?>.broadcast();

  Future<void> init() async {
    try {
      tz.initializeTimeZones();
      String timeZoneName;
      try {
        timeZoneName = await FlutterTimezone.getLocalTimezone();
      } catch (e) {
        timeZoneName = 'America/Chicago';
      }
      try {
        tz.setLocalLocation(tz.getLocation(timeZoneName));
      } catch (e) {
        tz.setLocalLocation(tz.getLocation('America/Chicago'));
      }

      // Use 'notification_icon' from res/drawable (User's custom icon)
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('notification_icon');

      const DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings(
            requestSoundPermission: true,
            requestBadgePermission: true,
            requestAlertPermission: true,
          );

      const InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsDarwin,
          );

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          selectNotificationStream.add(response.payload);
        },
      );
      debugPrint("✅ NotificationService: Initialized successfully");

      await requestPermissions();
    } catch (e) {
      debugPrint("❌ NotificationService Init Failed: $e");
    }
  }

  Future<void> requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint("❌ Permission Request Error: $e");
    }
  }

  // --- NIGHT DEBRIEF ---
  Future<void> scheduleDebrief(TimeOfDay time) async {
    try {
      final tz.TZDateTime nowLocal = tz.TZDateTime.now(tz.local);

      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        nowLocal.year,
        nowLocal.month,
        nowLocal.day,
        time.hour,
        time.minute,
      );

      if (scheduledDate.isBefore(nowLocal)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await flutterLocalNotificationsPlugin.zonedSchedule(
        0,
        'Axis Debrief',
        'Time to review your day.',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'axis_channel_v4',
            'Axis Notifications',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'notification_icon',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'night_debrief',
      );
      debugPrint("✅ Scheduled Daily Debrief for $scheduledDate");
    } catch (e) {
      debugPrint("❌ Failed to schedule debrief: $e");
    }
  }

  // --- SMART ALERTS ---
  Future<void> scheduleSmartAlert({
    required int id,
    required String title,
    required String body,
    required DateTime date,
    required TimeOfDay time,
    required String payload,
  }) async {
    try {
      final tz.TZDateTime nowLocal = tz.TZDateTime.now(tz.local);

      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      // PRODUCTION MODE: If time passed, move to tomorrow
      if (scheduledDate.isBefore(nowLocal)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'axis_channel_v4',
            'Axis Notifications',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'notification_icon',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );

      debugPrint("🔔 Scheduled '$title' for $scheduledDate (ID: $id)");
    } catch (e) {
      debugPrint("❌ Failed to schedule smart alert: $e");
    }
  }

  Future<void> cancelDebrief() async {
    await flutterLocalNotificationsPlugin.cancel(0);
    debugPrint("🚫 Cancelled daily debrief");
  }
}
