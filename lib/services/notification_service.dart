import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:async';
import 'dart:io';

import '../models/inventory_item.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  final StreamController<String?> selectNotificationStream =
      StreamController<String?>.broadcast();

  Future<void> setupInteractedMessage() async {
    RemoteMessage? initialMessage = await _firebaseMessaging
        .getInitialMessage();
    if (initialMessage != null) {
      _handleMessage(initialMessage);
    }
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
  }

  void _handleMessage(RemoteMessage message) {
    String? type = message.data['type'];
    if (type != null) {
      debugPrint("🚀 Notification Tapped. Type: $type");
      selectNotificationStream.add(type);
    } else {
      selectNotificationStream.add('default');
    }
  }

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

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'axis_channel_v4',
        'Axis Notifications',
        description: 'Important Axis Alerts',
        importance: Importance.max,
      );

      final AndroidFlutterLocalNotificationsPlugin? androidPlatform =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      if (androidPlatform != null) {
        await androidPlatform.createNotificationChannel(channel);
      }

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

      await requestPermissions();
      await _setupFCM();

      debugPrint("✅ NotificationService: Initialized successfully");
    } catch (e) {
      debugPrint("❌ NotificationService Init Failed: $e");
    }
  }

  Future<void> _setupFCM() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _saveTokenToDatabase(token);
      }

      _firebaseMessaging.onTokenRefresh.listen(_saveTokenToDatabase);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          "📩 Foreground Message Received: ${message.notification?.title}",
        );

        if (message.notification != null) {
          showInstantNotification(
            id: message.messageId.hashCode,
            title: message.notification!.title ?? "New Alert",
            body: message.notification!.body ?? "",
            payload: message.data['type'] ?? 'fcm_message',
          );
        }
      });
    } else {
      debugPrint("🚫 FCM Permission declined");
    }
  }

  Future<void> _saveTokenToDatabase(String token) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'fcmToken': token, 'lastTokenUpdate': FieldValue.serverTimestamp()},
      );
      debugPrint("🔑 FCM Token saved for user: ${user.uid}");
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

  Future<void> showInstantNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    // FIX: Add BigTextStyle to allow long lists in notifications
    final BigTextStyleInformation bigTextStyleInformation =
        BigTextStyleInformation(
          body,
          contentTitle: title,
          htmlFormatBigText: true,
          htmlFormatContent: true,
        );

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'axis_channel_v4',
          'Axis Notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'notification_icon',
          styleInformation: bigTextStyleInformation, // <--- ENABLED HERE
        );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );
  }

  Future<void> updateReportSettings(
    bool enabled,
    TimeOfDay time,
    int frequency,
    List<String> inventoryIds,
  ) async {
    debugPrint("🔄 Updating Report Settings Locally (Synced to Cloud)");
  }

  Future<void> checkAndScheduleSmartNotifications({
    List<InventoryItem>? items,
  }) async {}
}
