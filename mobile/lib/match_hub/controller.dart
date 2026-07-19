import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/live_data.dart';
import '../api/models.dart';
import '../state/room_controller.dart';
import 'freshness.dart';
import 'models.dart';
import 'timeline.dart';

/// Merges room SSE + match-data into an immutable [MatchHubViewState].
class MatchHubController extends ChangeNotifier {
  final RoomController roomController;
  final ApiClient api;
  final String? memberIdOverride;

  MatchHubSection _section = MatchHubSection.live;
  MatchData? _matchData;
  Timer? _poll;
  bool _followingLive = true;
  int _seenTimelineLen = 0;
  int _lastRevision = -1;
  final Set<String> _seenDropIds = {};
  bool _dropsPrimed = false;
  MomentDropView? _pendingReveal;
  int _lastChatLen = 0;
  int _fansUnread = 0;
  int _callsUnread = 0;
  int _rewardsUnread = 0;
  String? _lastOpenPromptId;
  bool _disposed = false;

  MatchHubController({
    required this.roomController,
    ApiClient? api,
    this.memberIdOverride,
  }) : api = api ?? ApiClient.instance;

  MatchHubViewState? get state {
    final room = roomController.room;
    if (room == null) return null;
    return _build(room);
  }

  Future<void> init() async {
    await _restoreSection();
    roomController.addListener(_onRoom);
    _onRoom();
    _schedulePoll();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    roomController.removeListener(_onRoom);
    super.dispose();
  }

  void selectSection(MatchHubSection section) {
    if (_section == section) return;
    _section = section;
    if (section == MatchHubSection.fans) _fansUnread = 0;
    if (section == MatchHubSection.calls) _callsUnread = 0;
    if (section == MatchHubSection.live) {
      _followingLive = true;
      _seenTimelineLen = state?.timeline.length ?? _seenTimelineLen;
    }
    _persistSection();
    notifyListeners();
  }

  void jumpToLive() {
    _followingLive = true;
    _seenTimelineLen = state?.timeline.length ?? 0;
    notifyListeners();
  }

  void markReadingOlder() {
    if (!_followingLive) return;
    _followingLive = false;
    notifyListeners();
  }

  void clearPendingReveal() {
    _pendingReveal = null;
    notifyListeners();
  }

  void acknowledgeReward(String dropId) {
    _seenDropIds.add(dropId);
    if (_pendingReveal?.id == dropId) _pendingReveal = null;
    _rewardsUnread = (_rewardsUnread - 1).clamp(0, 99);
    notifyListeners();
  }

  Future<void> controlReplay({
    required String action,
    int? minute,
    double? speed,
  }) async {
    final id = roomController.roomId;
    if (roomController.isLocal) return;
    await api.controlReplay(id, action: action, minute: minute, speed: speed);
  }

  void _onRoom() {
    if (_disposed) return;
    final room = roomController.room;
    if (room == null) {
      notifyListeners();
      return;
    }
    if (room.revision > 0 && room.revision < _lastRevision) {
      return; // out-of-order SSE
    }
    _lastRevision = room.revision;

    final open = room.prompts
        .where((p) => p.status == 'open' || p.status == 'locked')
        .toList();
    final openId = open.isNotEmpty ? open.first.id : null;
    if (openId != null &&
        openId != _lastOpenPromptId &&
        _section != MatchHubSection.calls) {
      _callsUnread += 1;
    }
    _lastOpenPromptId = openId;

    final chatLen = room.chat.length;
    if (chatLen > _lastChatLen && _section != MatchHubSection.fans) {
      _fansUnread += chatLen - _lastChatLen;
    }
    _lastChatLen = chatLen;

    final mid = memberIdOverride ?? roomController.memberId;
    if (mid != null) {
      final mine = room.momentDrops.where((d) => d.memberId == mid).toList();
      if (!_dropsPrimed) {
        _seenDropIds.addAll(mine.map((d) => d.id));
        _dropsPrimed = true;
      } else {
        for (final d in mine) {
          if (_seenDropIds.contains(d.id)) continue;
          _seenDropIds.add(d.id);
          _pendingReveal = d;
          _rewardsUnread += 1;
        }
      }
    }

    _schedulePoll();
    notifyListeners();
  }

  void _schedulePoll() {
    _poll?.cancel();
    final room = roomController.room;
    if (room == null || roomController.isLocal) return;
    if (room.status == 'finished' && _matchData != null) return;
    final live = room.status == 'live' || room.lifecycle == 'live';
    final delay = live ? const Duration(seconds: 15) : const Duration(seconds: 60);
    _poll = Timer(delay, () async {
      await _fetchMatchData();
      if (!_disposed) _schedulePoll();
    });
    // Kick immediately when empty.
    if (_matchData == null) {
      unawaited(_fetchMatchData());
    }
  }

  Future<void> _fetchMatchData() async {
    final room = roomController.room;
    if (room == null || roomController.isLocal) return;
    try {
      final data = await api.matchData(room.fixture.id);
      if (_disposed) return;
      _matchData = data;
      notifyListeners();
    } catch (_) {
      // Keep last good snapshot.
    }
  }

  MatchHubViewState _build(RoomView room) {
    final isReplay = room.replay || roomController.isLocal;
    final health = evaluateFeedHealth(room);
    final frameMinute = room.replayState?.active == true
        ? room.replayState!.currentMinute
        : null;
    final timeline = buildMatchTimeline(
      room: room,
      matchData: _matchData,
      frameMinute: frameMinute,
    );
    // Catch up the watermark only when actively following live (not while
    // reading older events). Mutation stays out of the public getter path by
    // happening here during rebuilds triggered by listeners.
    final following = _followingLive;
    if (following && timeline.length > _seenTimelineLen) {
      _seenTimelineLen = timeline.length;
    }
    final newCount =
        following ? 0 : (timeline.length - _seenTimelineLen).clamp(0, 999);

    final open = room.prompts
        .where((p) => p.status == 'open' || p.status == 'locked')
        .toList();
    PromptView? main;
    PromptView? quick;
    for (final p in open) {
      if (p.lane == 'quick' && quick == null) {
        quick = p;
      } else if (main == null) {
        main = p;
      } else {
        quick ??= p;
      }
    }
    if (quick != null && identical(quick, main)) quick = null;

    final settled = room.prompts
        .where(
          (p) =>
              p.status == 'settled' ||
              p.status == 'void' ||
              p.status == 'corrected',
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final me = roomController.me;
    final answered = roomController.myPicks.length;
    final ribbon = timeline.isEmpty
        ? null
        : '${timeline.last.artwork ?? '•'} ${timeline.last.title}';

    final spoilerHidden =
        room.spoilerSafe && room.status != 'finished'; // reveal handled by host

    return MatchHubViewState(
      header: MatchHubHeaderState(
        competition: room.fixture.stage,
        lifecycleBadge: lifecycleBadge(room, isReplay: isReplay),
        home: room.fixture.home,
        away: room.fixture.away,
        scoreText: scoreText(room, spoilerHidden: spoilerHidden) ?? 'v',
        clockText: formatClock(room, frozen: health.clockFrozen),
        clockFrozen: health.clockFrozen,
        freezeReason: health.reason,
        watching: room.members.length,
        feedFreshness: room.feedFreshness,
        notifyOn: true,
        replay: isReplay,
        latestEventRibbon: ribbon,
      ),
      lifecycle: room.lifecycle,
      freshness: room.feedFreshness,
      selectedSection: _section,
      activeCall: main,
      quickCall: quick,
      settledCalls: settled,
      timeline: timeline,
      lineup: _matchData,
      supportedStats: room.score,
      matchPulse: buildMatchPulse(timeline),
      presence: room.members,
      reactionTally: room.reactionTally,
      partyChat: room.chat,
      officialHub: room.kind == 'official',
      callsPaused: health.callsPaused,
      callsPausedReason: health.callsPaused
          ? 'Calls paused while match data reconnects.'
          : null,
      myGame: MatchHubMyGameSummary(
        points: me?.points ?? 0,
        streak: me?.streak ?? 0,
        bestStreak: me?.bestStreak ?? 0,
        correct: me?.correct ?? 0,
        answered: answered,
        side: me?.side,
      ),
      unread: MatchHubUnreadCounts(
        calls: _callsUnread,
        fans: _fansUnread,
        rewards: _rewardsUnread,
      ),
      rewards: MatchHubRewardState(
        recentDrops: room.momentDrops
            .where((d) => d.memberId == (memberIdOverride ?? roomController.memberId))
            .toList(),
        seenDropIds: Set.unmodifiable(_seenDropIds),
        pendingReveal: _pendingReveal,
      ),
      replayState: room.replayState,
      newTimelineCount: newCount,
      followingLive: _followingLive,
      latestRecap: room.recaps.isNotEmpty ? room.recaps.last : null,
      revision: room.revision,
    );
  }

  Future<void> _restoreSection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'hub_section_${roomController.roomId}';
      final raw = prefs.getString(key);
      if (raw == null) return;
      _section = MatchHubSection.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => MatchHubSection.live,
      );
    } catch (_) {}
  }

  Future<void> _persistSection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'hub_section_${roomController.roomId}',
        _section.name,
      );
    } catch (_) {}
  }
}
