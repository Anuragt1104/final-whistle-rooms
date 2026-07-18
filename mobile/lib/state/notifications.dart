import 'dart:math';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for live match moments (goals, red cards).
/// Prefer [showGoal] for witty copy; [show] for generic alerts.
class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static int _id = 1000;
  static final _rng = Random();

  static const _goalTitles = [
    '⚽ NET BULGES',
    '⚽ THEY\'VE SCORED',
    '⚽ GOAL ALERT',
    '⚽ BACK OF THE NET',
    '⚽ IT\'S IN',
    '⚽ ABSOLUTE ROCKET',
  ];

  static Future<void> init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}
    _inited = true;
  }

  /// Witty goal tray notification — used when the user is NOT in that room.
  static Future<void> showGoal({
    required String teamName,
    required String scorer,
    required String homeName,
    required String awayName,
    required int homeGoals,
    required int awayGoals,
    required int minute,
    String? stage,
    String? roomName,
  }) async {
    final title = '${_goalTitles[_rng.nextInt(_goalTitles.length)]} — $teamName';
    final bodies = [
      '$scorer just ruined someone\'s evening. $homeName $homeGoals–$awayGoals $awayName · $minute\'',
      '$scorer finds the onion bag! $homeName $homeGoals–$awayGoals $awayName ($minute\')',
      'Cue the chaos — $scorer puts $teamName ahead of the night. $homeGoals–$awayGoals at $minute\'',
      '$teamName strike through $scorer. Scoreboard reads $homeGoals–$awayGoals · $minute\'',
      'Hold that thought — $scorer has spoken. $homeName $homeGoals–$awayGoals $awayName',
    ];
    final body = bodies[_rng.nextInt(bodies.length)];
    await show(
      title,
      body,
      subText: stage != null
          ? (roomName != null ? '$stage · $roomName' : stage)
          : (roomName ?? 'FINAL WHISTLE'),
    );
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
          icon: '@mipmap/ic_launcher',
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          color: const Color(0xFFE9531E),
          colorized: true,
          enableLights: true,
          ledColor: const Color(0xFFE9531E),
          ledOnMs: 600,
          ledOffMs: 200,
          styleInformation: BigTextStyleInformation(
            body,
            htmlFormatBigText: true,
            contentTitle: '<b>$title</b>',
            htmlFormatContentTitle: true,
            summaryText: subText ?? 'FINAL WHISTLE',
            htmlFormatSummaryText: true,
          ),
        ),
        iOS: DarwinNotificationDetails(
          subtitle: subText ?? 'Final Whistle',
          presentBanner: true,
          presentSound: true,
        ),
      );
      await _plugin.show(
        id: _id++,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {
      // notifications are best-effort
    }
  }
}
