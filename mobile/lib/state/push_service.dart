import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import 'notifications.dart';
import 'room_presence.dart';

const _legacyGoalsTopic = 'goals_live';

/// Handles FCM goal pushes + a foreground rooms poller so alerts fire when the
/// user is elsewhere in the app (or the phone is locked, via FCM).
class PushService with WidgetsBindingObserver {
  PushService._();
  static final PushService instance = PushService._();

  bool _started = false;
  bool _fcmReady = false;
  FirebaseMessaging? _messaging;
  String? _token;
  final Set<String> _watchedFixtures = {};
  final ValueNotifier<String?> pendingFixtureId = ValueNotifier(null);
  final ValueNotifier<String?> pendingDuelId = ValueNotifier(null);
  Timer? _poll;
  final Set<String> _seenFingerprints = {};
  final Map<String, String> _lastScoreByRoom = {};

  Future<void> init() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await Notifications.init();
    await _initFcm();
    _startPoller();
  }

  Future<void> _initFcm() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      _messaging = messaging;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _token = token;
        final platform = defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android';
        await ApiClient.instance.registerDevice(token, platform);
      }
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleOpenedMessage(initial);
      _fcmReady = true;
    } catch (e) {
      debugPrint('PushService: FCM unavailable ($e) — using rooms poller');
      _fcmReady = false;
    }
  }

  /// Enable alerts only after the fan explicitly watches this Fixture. The
  /// fixture topic is the production contract; the legacy topic remains a
  /// compatibility subscription for the currently deployed match-night API.
  Future<void> watchFixture(String fixtureId) async {
    if (fixtureId.isEmpty || !_watchedFixtures.add(fixtureId)) return;
    try {
      final messaging = _messaging ?? FirebaseMessaging.instance;
      await messaging.subscribeToTopic('fixture_$fixtureId');
      await messaging.subscribeToTopic(_legacyGoalsTopic);
      final token = _token ?? await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _token = token;
        final platform = defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android';
        await ApiClient.instance.registerDevice(
          token,
          platform,
          fixtureIds: _watchedFixtures.toList(),
        );
      }
    } catch (e) {
      debugPrint('PushService: fixture subscription failed ($e)');
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final data = message.data;
    final duelId = data['duelId'] ?? _duelIdFromDeepLink(data['deepLink']);
    if (duelId != null && duelId.isNotEmpty) {
      pendingDuelId.value = duelId;
      return;
    }
    final fixtureId = data['fixtureId'];
    if (fixtureId != null && fixtureId.isNotEmpty) {
      pendingFixtureId.value = fixtureId;
    }
  }

  void consumePendingFixture() => pendingFixtureId.value = null;
  void consumePendingDuel() => pendingDuelId.value = null;

  String? _duelIdFromDeepLink(Object? raw) {
    final value = raw?.toString() ?? '';
    final match = RegExp(r'finalwhistle://duels/([^/?#]+)').firstMatch(value);
    return match?.group(1);
  }

  void _onForegroundMessage(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'duel_turn') {
      final duelId = data['duelId'] ?? _duelIdFromDeepLink(data['deepLink']);
      if (duelId != null && duelId.isNotEmpty) {
        Notifications.show(
          'Your Stadium turn',
          'A Friend Duel is waiting — tap to return to the pitch.',
        );
        pendingDuelId.value = duelId;
      }
      return;
    }
    final roomId = data['roomId'] ?? '';
    final fixtureId = data['fixtureId'] ?? '';
    if (fixtureId.isNotEmpty && !_watchedFixtures.contains(fixtureId)) return;
    if (roomId.isNotEmpty && RoomPresence.isViewingRoom(roomId)) return;
    if (fixtureId.isNotEmpty && RoomPresence.isViewingFixture(fixtureId)) {
      return;
    }
    final fp =
        data['fingerprint'] ??
        '${fixtureId}:${data['homeGoals']}-${data['awayGoals']}:${data['minute']}';
    if (!_remember(fp)) return;

    final title = data['title'] ?? message.notification?.title;
    final body = data['body'] ?? message.notification?.body;
    if (title != null && body != null) {
      Notifications.show(title, body, subText: data['subText']);
      return;
    }
    final team = data['teamName'] ?? 'GOAL';
    final scorer = data['scorer'] ?? team;
    Notifications.showGoal(
      teamName: team,
      scorer: scorer,
      homeName: data['homeName'] ?? '',
      awayName: data['awayName'] ?? '',
      homeGoals: int.tryParse(data['homeGoals'] ?? '') ?? 0,
      awayGoals: int.tryParse(data['awayGoals'] ?? '') ?? 0,
      minute: int.tryParse(data['minute'] ?? '') ?? 0,
      stage: data['stage'],
      roomName: data['roomName'],
    );
  }

  bool _remember(String fp) {
    if (_seenFingerprints.contains(fp)) return false;
    _seenFingerprints.add(fp);
    if (_seenFingerprints.length > 200) {
      _seenFingerprints.remove(_seenFingerprints.first);
    }
    return true;
  }

  void _startPoller() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _pollGoals());
    _pollGoals();
  }

  void _stopPoller() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _pollGoals() async {
    if (RoomPresence.isInRoom) return;
    try {
      final rooms = await ApiClient.instance.listRooms();
      for (final r in rooms) {
        if (r.status != 'live' || r.score == null) continue;
        if (RoomPresence.isViewingRoom(r.id)) continue;
        if (RoomPresence.isViewingFixture(r.fixture.id)) continue;
        final s = r.score!;
        final key = '${s.goals.home}-${s.goals.away}';
        final prev = _lastScoreByRoom[r.id];
        _lastScoreByRoom[r.id] = key;
        if (prev == null) continue;
        final parts = prev.split('-');
        final ph = int.tryParse(parts[0]) ?? 0;
        final pa = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        final dh = s.goals.home - ph;
        final da = s.goals.away - pa;
        if (dh <= 0 && da <= 0) continue;
        final homeScored = dh > 0;
        final team = homeScored ? r.fixture.home : r.fixture.away;
        final fp = '${r.fixture.id}:$key:${s.minute}:${homeScored ? "h" : "a"}';
        if (!_remember(fp)) continue;
        await Notifications.showGoal(
          teamName: team.name,
          scorer: team.name,
          homeName: r.fixture.home.name,
          awayName: r.fixture.away.name,
          homeGoals: s.goals.home,
          awayGoals: s.goals.away,
          minute: s.minute,
          stage: r.fixture.stage,
          roomName: r.name,
        );
      }
    } catch (_) {
      // best-effort
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    RoomPresence.setForeground(fg);
    if (fg) {
      _startPoller();
    } else {
      _stopPoller();
    }
  }

  bool get fcmReady => _fcmReady;
}

/// Background isolate entry — must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Notification+data payloads are shown by the OS when the app is killed.
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}
