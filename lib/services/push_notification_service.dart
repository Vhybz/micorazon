import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'offline_sync_service.dart';

class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // Web does not support local notifications via this plugin reliably
    if (kIsWeb) return;

    try {
      // 1. Check local settings first
      final box = Hive.box(OfflineSyncService.settingsBoxName);
      final bool enabled = box.get('push_notifications', defaultValue: true);
      
      if (!enabled) return;

      // 2. Request permission (Guard for mobile)
      await Permission.notification.request();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle when user taps the notification
        },
      );
    } catch (e) {
      debugPrint('Push Notification initialization failed (Expected on Web/Desktop): $e');
    }
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    // Check if user has disabled notifications in settings
    final box = Hive.box(OfflineSyncService.settingsBoxName);
    final bool enabled = box.get('push_notifications', defaultValue: true);
    
    if (!enabled) {
      debugPrint('PushNotificationService: Suppressing notification because user disabled it in settings.');
      return;
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'ms_critical_alerts',
      'Important System Alerts',
      channelDescription: 'Used for critical meat shop operations and reports',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: Color(0xFF6B1111),
      enableLights: true,
      ledColor: Color(0xFF6B1111),
      ledOnMs: 1000,
      ledOffMs: 500,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
    );
  }
}
