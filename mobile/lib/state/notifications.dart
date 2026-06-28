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

  static Future<void> show(String title, String body) async {
    try {
      await init();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'match_events',
          'Match events',
          channelDescription: 'Goals, red cards and key live moments',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'GOAL',
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.show(id: _id++, title: title, body: body, notificationDetails: details);
    } catch (_) {
      // notifications are best-effort
    }
  }
}
