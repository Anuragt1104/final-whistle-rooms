import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../state/room_controller.dart';
import '../state/notifications.dart';
import '../local/live_engine.dart';
import '../theme.dart';
import 'team_sheet.dart';
import '../widgets/common.dart';
import '../widgets/ticket.dart';
import '../widgets/live_match.dart';
import '../widgets/score_rail.dart';
import '../widgets/pulse_feed.dart';
import '../widgets/next_swing_card.dart';
import '../widgets/leaderboard.dart';
import '../widgets/chat_dock.dart';
import '../widgets/recap_card.dart';
import '../widgets/proof_sheet.dart';
import '../widgets/motm_poll.dart';

class RoomScreen extends StatefulWidget {
  final String roomId;
  final LiveMatchEngine? engine; // non-null = local solo room
  final bool autoStart;
  const RoomScreen({super.key, required this.roomId, this.engine, this.autoStart = false});
  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final RoomController _c = widget.engine != null ? RoomController.local(widget.engine) : RoomController(widget.roomId);
  int _seg = 0;
  bool _aiOn = false;
  bool _revealed = false; // spoiler-safe reveal
  Identity? _identity;
  final ScrollController _scroll = ScrollController();
  bool _showComposer = false; // revealed only when scrolled to the chat

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    // near the bottom (where the terrace chat lives), or content too short to scroll
    final near = p.maxScrollExtent <= 4 || p.pixels >= p.maxScrollExtent - 90;
    if (near != _showComposer) setState(() => _showComposer = near);
  }

  void _scrollToChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _c.init();
    _c.addListener(_onChange);
    _scroll.addListener(_onScroll);
    // re-evaluate composer visibility once content has laid out (covers short
    // rooms that don't scroll)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _c.startMatch());
    }
    IdentityStore.getOrCreate().then((i) => _identity = i);
    LocalStore.streakBest().then((b) => mounted ? setState(() => _lifetimeBest = b) : null);
    ApiClient.instance.config().then((c) => mounted ? setState(() => _aiOn = c.recapAI) : null).catchError((_) {});
  }

  Future<void> _shareScore(RoomView room) async {
    final me = _c.me;
    final best = ((me?.bestStreak ?? 0) > _lifetimeBest) ? (me?.bestStreak ?? 0) : _lifetimeBest;
    final text =
        '🔥 Higher or Lower on Final Whistle Rooms — best streak $best, ${me?.points ?? 0} pts '
        'on ${room.fixture.home.name} v ${room.fixture.away.name}. Think you can read the swings better? ⚽';
    try {
      await Share.share(text, subject: 'My Final Whistle Rooms streak');
    } catch (_) {
      // fall back to clipboard if the platform share sheet is unavailable
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Score copied — paste it anywhere to share 🔥')),
        );
      }
    }
  }

  int _lastGoals = 0;
  int _lastReds = 0;
  int _lastPoints = -1;
  int _lifetimeBest = 0; // best Higher-or-Lower streak across all matches
  void _onChange() {
    if (!mounted) return;
    final room = _c.room;
    // celebrate when the user's Next Swing points go up
    final myPoints = _c.me?.points ?? 0;
    if (_lastPoints >= 0 && myPoints > _lastPoints) {
      _pointsBurst(myPoints - _lastPoints);
      HapticFeedback.heavyImpact();
    }
    _lastPoints = myPoints;
    // keep a lifetime-best streak across rooms (replayable across 104 games)
    final st = _c.me?.streak ?? 0;
    if (st > _lifetimeBest) {
      _lifetimeBest = st;
      LocalStore.bumpStreakBest(st);
    }
    final goalCards = room?.pulse.where((p) => p.kind == 'goal').toList() ?? const [];
    final redCards = room?.pulse.where((p) => p.kind == 'red').toList() ?? const [];
    if (goalCards.length > _lastGoals) {
      _lastGoals = goalCards.length;
      HapticFeedback.heavyImpact();
      // notify only for real (live TxLINE) rooms, not the on-device sim
      if (!_c.isLocal && room != null && room.score != null) {
        final g = goalCards.last;
        final s = room.score!;
        final team = g.accent == 'away' ? room.fixture.away : room.fixture.home;
        Notifications.show(
          '⚽ GOAL — ${team.name}${g.scorer != null ? " · ${g.scorer}" : ""}',
          "${room.fixture.home.name} ${s.goals.home}–${s.goals.away} ${room.fixture.away.name}   ·   ${s.minute}'",
          subText: '${room.fixture.stage} · ${room.name}',
        );
      }
    }
    if (redCards.length > _lastReds) {
      _lastReds = redCards.length;
      if (!_c.isLocal && room != null) {
        final r = redCards.last;
        Notifications.show('🟥 RED CARD', r.detail.isNotEmpty ? r.detail : r.headline,
            subText: '${room.fixture.home.name} v ${room.fixture.away.name}');
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _scroll.dispose();
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  bool _hidden(RoomView r) => r.spoilerSafe && !_revealed && r.status != 'finished';

  String? _scoreText(RoomView r) {
    if (_hidden(r)) return null;
    final s = r.score;
    if (s == null || r.status == 'lobby') return null;
    return '${s.goals.home} - ${s.goals.away}';
  }

  String _minuteText(RoomView r) {
    if (_hidden(r)) return '🙈 HIDDEN';
    final s = r.score;
    if (r.status == 'finished' || (s != null && s.phase == 4)) return 'FT';
    if (s == null) return r.status == 'lobby' ? 'LOBBY' : '';
    if (s.phase == 2) return 'HT';
    if (s.phase == 0) return 'KO SOON';
    return "${s.minute}'";
  }

  /// Pill text reflects the actual MATCH state, not just the room status — a
  /// not-yet-kicked-off match must not read "LIVE".
  String _pillText(RoomView r) {
    if (r.status == 'finished') return 'FULL TIME';
    if (r.status == 'lobby') return 'LOBBY';
    final s = r.score;
    if (s == null || s.phase == 0) return 'KO SOON';
    switch (s.phase) {
      case 2:
        return 'HALF-TIME';
      case 4:
      case 9:
        return 'FULL TIME';
      case 5:
      case 7:
        return 'EXTRA TIME';
      case 6:
        return 'ET BREAK';
      case 8:
        return 'PENALTIES';
      default:
        return 'LIVE';
    }
  }

  List<String> _scorers(RoomView r) => r.pulse
      .where((c) => c.kind == 'goal')
      .map((c) => "${c.scorer ?? (c.accent == 'home' ? r.fixture.home.code : r.fixture.away.code)} ${c.minute}'")
      .toList();

  @override
  Widget build(BuildContext context) {
    final room = _c.room;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: _build(room),
    );
  }

  Widget _build(RoomView? room) {
    if (_c.notFound) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(backgroundColor: AppColors.paper, foregroundColor: AppColors.ink, elevation: 0),
        body: Center(child: Text('This room doesn\'t exist anymore.', style: body(color: AppColors.mut))),
      );
    }
    if (room == null) {
      return const Scaffold(backgroundColor: AppColors.paper, body: Center(child: CircularProgressIndicator(color: AppColors.orange)));
    }
    if (room.status == 'finished') return _finalWhistle(room);
    return _liveRoom(room);
  }

  // ---------------- LIVE / LOBBY ----------------
  Widget _liveRoom(RoomView room) {
    final me = _c.me;
    final showSwing = room.modes.nextSwing && (room.status == 'live' || room.prompts.isNotEmpty);
    final showDraft = room.modes.draft && _c.joined && me?.side == null;
    final latestRecap = room.recaps.isNotEmpty ? room.recaps.last : null;

    return Scaffold(
      backgroundColor: AppColors.paper,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Column(children: [
          Container(
            color: AppColors.ink,
            child: TicketScoreboard(
              home: room.fixture.home,
              away: room.fixture.away,
              league: room.fixture.stage,
              score: _scoreText(room),
              minute: _minuteText(room),
              clockSeconds: room.score?.clockSeconds,
              clockRunning: (room.score?.running ?? false) && room.status == 'live' && !_hidden(room) && (room.score?.phase ?? 0) != 0,
              onTeamTap: (t) => showTeamSheet(context, t),
              pill: _pillText(room),
              pillColor: const {'LIVE', 'EXTRA TIME', 'PENALTIES'}.contains(_pillText(room)) ? AppColors.orange : AppColors.inkSoft,
              watching: room.members.length,
              onBack: () => Navigator.of(context).maybePop(),
              topRadius: 0,
              topInset: MediaQuery.of(context).padding.top,
            ),
          ),
          Expanded(
            child: ListView(controller: _scroll, padding: EdgeInsets.fromLTRB(16, 12, 16, _seg == 0 ? 88 : 16), children: [
              _controls(room),
              const SizedBox(height: 12),
              _segmentBar(),
              const SizedBox(height: 12),
              if (_seg == 0) ...[
                _presenceRow(room),
                const SizedBox(height: 12),
                if (room.score?.statusNote != null) ...[_statusBanner(room.score!.statusNote!), const SizedBox(height: 12)],
                if (room.status == 'lobby') ...[_lobbyBanner(room), const SizedBox(height: 12)],
                if (showDraft) ...[_sidePicker(room), const SizedBox(height: 12)],
                if (room.shootout != null && !_hidden(room)) ...[
                  ShootoutCard(s: room.shootout!, home: room.fixture.home, away: room.fixture.away),
                  const SizedBox(height: 12),
                ],
                if (room.score != null && !_hidden(room)) ...[WinBar(win: room.win, home: room.fixture.home, away: room.fixture.away), const SizedBox(height: 12)],
                if (room.score != null && !_hidden(room) && room.winHistory.length >= 3) ...[
                  WinTimeline(history: room.winHistory, home: room.fixture.home, away: room.fixture.away),
                  const SizedBox(height: 12),
                ],
                if (room.score != null && room.status != 'lobby' && !_hidden(room)) ...[
                  MatchStatsPanel(score: room.score!, home: room.fixture.home, away: room.fixture.away),
                  const SizedBox(height: 12),
                ],
                if (showSwing) ...[
                  NextSwingCard(
                    prompts: room.prompts,
                    myPicks: _c.myPicks,
                    onPick: _c.predict,
                    streak: _c.me?.streak ?? 0,
                    bestStreak: ((_c.me?.bestStreak ?? 0) > _lifetimeBest) ? (_c.me?.bestStreak ?? 0) : _lifetimeBest,
                    onShare: () => _shareScore(room),
                  ),
                  const SizedBox(height: 12),
                ],
                if (latestRecap != null) ...[RecapCard(recap: latestRecap, aiOn: _aiOn), const SizedBox(height: 12)],
                PulseFeed(pulse: room.pulse),
                const SizedBox(height: 16),
                Row(children: [Text('THE TERRACE', style: label(color: AppColors.ink, size: 11.5, weight: FontWeight.w800)), const Spacer(), Text('${room.chat.where((c) => c.kind != "system").length} shouts', style: body(color: AppColors.mut, size: 11))]),
                const SizedBox(height: 8),
                ChatFeed(chat: room.chat, hostId: room.hostId),
              ] else ...[
                Leaderboard(room: room, meId: _c.memberId),
                if (room.recaps.isNotEmpty) const SizedBox(height: 12),
                ...room.recaps.reversed.map((r) => Padding(padding: const EdgeInsets.only(bottom: 10), child: RecapCard(recap: r, aiOn: _aiOn))),
              ],
            ]),
          ),
        ]),
        // The "Shout it out" composer is hidden until you scroll to the terrace
        // chat, then slides up from the bottom (Terrace tab only).
        if (_seg == 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: _showComposer ? Offset.zero : const Offset(0, 1.25),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: ChatComposer(
                onSend: (t) {
                  _c.sendChat(t);
                  _scrollToChat(); // jump to the terrace so you see it land
                },
                onTap: _scrollToChat,
                onReact: _c.react,
                disabled: !_c.joined,
                emojis: packEmojis(room.reactionPack),
              ),
            ),
          ),
        if (!_c.joined) _JoinGate(room: room, onJoin: _join),
      ]),
    );
  }

  Widget _controls(RoomView room) {
    final extras = <Widget>[];
    if (room.voice) {
      extras.add(AppChip('🎙 Voice room on', color: AppColors.orange, bg: const Color(0x14E9531E)));
    }
    if (_hidden(room)) {
      extras.add(AppChip('🙈 Tap to reveal score', color: AppColors.ink, onTap: () => setState(() => _revealed = true)));
    }
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: 'Join my World Cup room — code ${room.code}'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite copied')));
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('INVITE CODE', style: label(color: AppColors.mut, size: 9)),
              Text(room.code, style: display(20, color: AppColors.orange, spacing: 2)),
            ]),
          ),
          const Spacer(),
          AppChip(room.proof.anchored ? '🛡 ⛓ on-chain' : '🛡 Verified · ${room.proof.leafCount}', color: AppColors.ink, onTap: () => showProofSheet(context, widget.roomId, _c.isHost, localProof: _c.localProof())),
          if (_c.isHost && room.status == 'lobby') ...[
            const SizedBox(width: 8),
            PrimaryButton('Start', icon: Icons.play_arrow_rounded, onTap: _c.startMatch),
          ],
        ]),
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: extras),
        ],
      ]),
    );
  }

  Widget _presenceRow(RoomView room) {
    final shown = room.members.take(4).toList();
    final hostName = room.members.where((m) => m.isHost).isNotEmpty ? room.members.firstWhere((m) => m.isHost).name : 'Host';
    final others = room.members.length - 1;
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        SizedBox(
          width: 18.0 * shown.length + 14,
          height: 32,
          child: Stack(
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(left: i * 18.0, child: Container(decoration: const BoxDecoration(color: AppColors.card, shape: BoxShape.circle), padding: const EdgeInsets.all(1.5), child: InitialAvatar(name: shown[i].name, size: 29))),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            others > 0 ? '$hostName & $others ${others == 1 ? "fan" : "fans"}' : '$hostName',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: body(weight: FontWeight.w700, size: 13),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(99)),
          child: Text('★ HOST', style: label(color: AppColors.cream, size: 9)),
        ),
      ]),
    );
  }

  Widget _statusBanner(String note) {
    final emoji = note.contains('Cooling')
        ? '💧'
        : note.contains('Half')
            ? '⏸️'
            : note.contains('Interrup')
                ? '⚠️'
                : note.contains('Penal')
                    ? '🥅'
                    : '⏱️';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(child: Text(note.toUpperCase(), style: display(18, color: AppColors.cream))),
          const LiveDot(color: AppColors.orange),
        ]),
      ),
    );
  }

  Widget _segmentBar() {
    Widget seg(String text, int i) {
      final on = _seg == i;
      return Expanded(
        child: Pressable(
          haptic: HapticFeedbackType.selection,
          onTap: () => setState(() => _seg = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? AppColors.ink : Colors.transparent, borderRadius: BorderRadius.circular(10)),
            child: Text(text.toUpperCase(), style: label(color: on ? AppColors.cream : AppColors.mut, size: 11.5, weight: FontWeight.w800)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.line)),
      child: Row(children: [seg('Terrace', 0), seg('Standings', 1)]),
    );
  }

  Widget _lobbyBanner(RoomView room) {
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(14),
      child: Text(
        _c.isHost ? "You're the host. Share the code, draft a side, then kick off ▶" : 'Waiting for the host to kick off. Draft your side while you wait 👇',
        textAlign: TextAlign.center,
        style: body(color: AppColors.mut, size: 13),
      ),
    );
  }

  Widget _sidePicker(RoomView room) {
    Widget card(String side, Team t) => Expanded(
          child: Pressable(
            haptic: HapticFeedbackType.medium,
            onTap: () => _c.pickSide(side),
            child: Container(
              decoration: cardBox(),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(children: [
                TeamBadge(team: t, size: 50),
                const SizedBox(height: 8),
                Text(t.name, textAlign: TextAlign.center, style: body(weight: FontWeight.w800, size: 13)),
              ]),
            ),
          ),
        );
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🏆 DRAFT YOUR SIDE', style: label(color: AppColors.ink, size: 11.5, weight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Earn points when your team scores, wins corners, or finishes ahead.', style: body(color: AppColors.mut, size: 11.5)),
        const SizedBox(height: 12),
        Row(children: [card('home', room.fixture.home), const SizedBox(width: 10), card('away', room.fixture.away)]),
      ]),
    );
  }

  // ---------------- FINAL WHISTLE ----------------
  Widget _finalWhistle(RoomView room) {
    final s = room.score;
    final msgs = room.chat.where((c) => c.kind == 'chat').length;
    final reacts = room.chat.where((c) => c.kind == 'reaction').length;
    final recap = room.recaps.isNotEmpty ? room.recaps.last : null;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: ListView(padding: EdgeInsets.zero, children: [
        ClipPath(
          clipper: TicketClipper(radius: 0, tooth: 10),
          child: Container(
            color: AppColors.ink,
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 28),
            child: Column(children: [
              Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.inkSoft, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.chevron_left, color: AppColors.cream, size: 20)),
                ),
                const Spacer(),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(border: Border.all(color: AppColors.lineInk), borderRadius: BorderRadius.circular(99)), child: Text('FULL TIME', style: label(color: AppColors.cream, size: 10))),
                const Spacer(),
                SizedBox(width: 30, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [const Icon(Icons.visibility_outlined, size: 13, color: AppColors.mutInk), const SizedBox(width: 3), Text(compactNum(room.members.length), style: label(color: AppColors.mutInk, size: 10))])),
              ]),
              const SizedBox(height: 14),
              RichText(text: TextSpan(children: [
                TextSpan(text: 'FINAL ', style: display(36, color: AppColors.cream, spacing: 1)),
                TextSpan(text: 'WHISTLE', style: display(36, color: AppColors.orangeBright, spacing: 1)),
              ])),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Column(children: [TeamBadge(team: room.fixture.home, size: 44), const SizedBox(height: 6), Text(room.fixture.home.code, style: display(14, color: AppColors.cream))])),
                Text('${s?.goals.home ?? 0} - ${s?.goals.away ?? 0}', style: display(44, color: AppColors.orangeBright, spacing: 1)),
                Expanded(child: Column(children: [TeamBadge(team: room.fixture.away, size: 44), const SizedBox(height: 6), Text(room.fixture.away.code, style: display(14, color: AppColors.cream))])),
              ]),
              if (_scorers(room).isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 2, children: _scorers(room).map((x) => Text(x, style: body(color: AppColors.mutInk, size: 11.5, weight: FontWeight.w600))).toList()),
              ],
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(children: [
            if (room.shootout != null) ...[ShootoutCard(s: room.shootout!, home: room.fixture.home, away: room.fixture.away), const SizedBox(height: 14)],
            if (room.motm != null) ...[MotmPollCard(poll: room.motm!, onVote: (k) => _c.voteMotm(k)), const SizedBox(height: 14)],
            if (recap != null) ...[RecapCard(recap: recap, aiOn: _aiOn), const SizedBox(height: 14)],
            Leaderboard(room: room, meId: _c.memberId),
            const SizedBox(height: 14),
            Row(children: [
              _statTile(compactNum(room.members.length), 'Peak in room'),
              const SizedBox(width: 10),
              _statTile(compactNum(msgs), 'Messages'),
              const SizedBox(width: 10),
              _statTile(compactNum(reacts), 'Reactions'),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: GhostButton('★ Rate match', onTap: _rateMatch)),
              const SizedBox(width: 10),
              Expanded(child: PrimaryButton('Highlights', icon: Icons.play_arrow_rounded, onTap: () => _showHighlights(room))),
            ]),
            const SizedBox(height: 10),
            GhostButton('Back to rooms', expand: true, onTap: () => Navigator.of(context).maybePop()),
          ]),
        ),
      ]),
    );
  }

  Widget _statTile(String value, String label_) {
    return Expanded(
      child: Container(
        decoration: cardBox(),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(children: [
          Text(value, style: display(22)),
          const SizedBox(height: 2),
          Text(label_.toUpperCase(), textAlign: TextAlign.center, style: label(color: AppColors.mut, size: 8.5)),
        ]),
      ),
    );
  }

  void _rateMatch() {
    showDialog(
      context: context,
      builder: (_) {
        int rating = 0;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text('RATE THE MATCH', style: display(18)),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                return IconButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setLocal(() => rating = i + 1);
                  },
                  icon: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, color: AppColors.orange, size: 32),
                );
              }),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(rating > 0 ? 'Thanks — rated $rating★' : 'Maybe next time')));
                },
                child: Text('Done', style: body(color: AppColors.orange, weight: FontWeight.w800)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHighlights(RoomView room) {
    const kinds = ['goal', 'red', 'half-time', 'full-time', 'chaos', 'corner-storm'];
    final events = room.pulse.where((p) => kinds.contains(p.kind)).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 14),
          Text('HIGHLIGHTS', style: display(20)),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Text('No standout moments this match.', style: body(color: AppColors.mut))
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: events
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: 40, child: Text("${e.minute}'", style: display(15, color: AppColors.orange))),
                            Text(e.emoji, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(e.scorer != null ? '${e.scorer} scores — ${e.detail}' : e.headline, style: body(size: 13.5, weight: FontWeight.w600))),
                          ]),
                        ))
                    .toList(),
              ),
            ),
        ]),
      ),
    );
  }

  /// A celebratory "+N PTS" burst when the user's Next Swing call pays off.
  void _pointsBurst(int gained) {
    if (gained <= 0) return;
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).size.height * 0.30,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeOut,
              onEnd: () => entry.remove(),
              builder: (_, t, __) {
                final pop = Curves.elasticOut.transform((t / 0.25).clamp(0, 1));
                final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3);
                return Opacity(
                  opacity: opacity.clamp(0, 1),
                  child: Transform.translate(
                    offset: Offset(0, -50 * t),
                    child: Transform.scale(
                      scale: 0.5 + 0.5 * pop,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.orange,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [BoxShadow(color: Color(0x55E9531E), blurRadius: 26, offset: Offset(0, 10))],
                        ),
                        child: Text('+$gained PTS 🔥', style: display(26, color: Colors.white)),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
  }

  Future<void> _join(String name) async {
    final identity = _identity ?? await IdentityStore.getOrCreate();
    await IdentityStore.sign('final-whistle-rooms:auth:$name:${identity.pubkey}');
    await LocalStore.setDisplayName(name);
    await _c.join(name, identity.pubkey);
  }
}

class _JoinGate extends StatefulWidget {
  final RoomView room;
  final Future<void> Function(String name) onJoin;
  const _JoinGate({required this.room, required this.onJoin});
  @override
  State<_JoinGate> createState() => _JoinGateState();
}

class _JoinGateState extends State<_JoinGate> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String _err = '';

  @override
  void initState() {
    super.initState();
    LocalStore.displayName().then((n) => _ctrl.text = n);
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      await widget.onJoin(_ctrl.text.trim().isEmpty ? 'Fan' : _ctrl.text.trim());
    } catch (e) {
      setState(() {
        _err = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.room.fixture;
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: cardBox(),
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TeamBadge(team: f.home, size: 44),
            const SizedBox(width: 10),
            Text('VS', style: display(20, color: AppColors.mut)),
            const SizedBox(width: 10),
            TeamBadge(team: f.away, size: 44),
          ]),
          const SizedBox(height: 14),
          Text(widget.room.name, textAlign: TextAlign.center, style: display(20)),
          const SizedBox(height: 2),
          Text('${f.home.name} vs ${f.away.name}', textAlign: TextAlign.center, style: body(color: AppColors.mut, size: 13)),
          const SizedBox(height: 16),
          TextField(controller: _ctrl, autofocus: true, decoration: fwrInput('Your name e.g. Sam')),
          if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err, style: body(color: const Color(0xFFD8392B), size: 12))),
          const SizedBox(height: 14),
          PrimaryButton('◎ Continue with Solana & join', expand: true, busy: _busy, onTap: _join),
          const SizedBox(height: 8),
          Text('No wallet or funds needed — a secure on-device identity is created for you.', textAlign: TextAlign.center, style: body(color: AppColors.mut, size: 11)),
        ]),
      ),
    );
  }
}
