import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for live match moments (goals, red cards). Fired while
/// the app is watching a live TxLINE room.
class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static int _id = 1000;

  static Future<void> init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(settings: const InitializationSettings(android: android, iOS: ios));
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}
    _inited = true;
  }

  static Future<void> show(String title, String body, {String? subText}) async {
    try {
      await init();
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'match_events',
          'Match events',
          channelDescription: 'Goals, red cards and key live moments',
          importance: Importance.max,
          priority: Priority.high,
          ticker: title,
          // brand the notification with the app logo + orange accent
          icon: '@mipmap/ic_launcher',
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          color: const Color(0xFFE9531E),
          colorized: true,
          enableLights: true,
          ledColor: const Color(0xFFE9531E),
          ledOnMs: 600,
          ledOffMs: 200,
          // expandable, detailed body with a Final Whistle footer
          styleInformation: BigTextStyleInformation(
            body,
            htmlFormatBigText: true,
            contentTitle: '<b>$title</b>',
            htmlFormatContentTitle: true,
            summaryText: subText ?? 'FINAL WHISTLE ROOMS',
            htmlFormatSummaryText: true,
          ),
        ),
        iOS: DarwinNotificationDetails(
          subtitle: subText ?? 'Final Whistle Rooms',
          presentBanner: true,
          presentSound: true,
        ),
      );
      await _plugin.show(id: _id++, title: title, body: body, notificationDetails: details);
    } catch (_) {
      // notifications are best-effort
    }
  }
}
