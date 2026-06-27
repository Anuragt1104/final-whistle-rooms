import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../state/room_controller.dart';
import '../local/live_engine.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ticket.dart';
import '../widgets/score_rail.dart';
import '../widgets/pulse_feed.dart';
import '../widgets/next_swing_card.dart';
import '../widgets/leaderboard.dart';
import '../widgets/chat_dock.dart';
import '../widgets/recap_card.dart';
import '../widgets/proof_sheet.dart';

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
  Identity? _identity;

  @override
  void initState() {
    super.initState();
    _c.init();
    _c.addListener(_onChange);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _c.startMatch());
    }
    IdentityStore.getOrCreate().then((i) => _identity = i);
    ApiClient.instance.config().then((c) => mounted ? setState(() => _aiOn = c.recapAI) : null).catchError((_) {});
  }

  int _lastGoals = 0;
  void _onChange() {
    if (!mounted) return;
    final goals = _c.room?.pulse.where((p) => p.kind == 'goal').length ?? 0;
    if (goals > _lastGoals) {
      _lastGoals = goals;
      HapticFeedback.heavyImpact();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  String? _scoreText(RoomView r) {
    final s = r.score;
    if (s == null || r.status == 'lobby') return null;
    return '${s.goals.home} - ${s.goals.away}';
  }

  String _minuteText(RoomView r) {
    final s = r.score;
    if (r.status == 'finished' || (s != null && s.phase == 4)) return 'FT';
    if (s == null) return r.status == 'lobby' ? 'LOBBY' : '';
    if (s.phase == 2) return 'HT';
    if (s.phase == 0) return 'KO SOON';
    return "${s.minute}'";
  }

  List<String> _scorers(RoomView r) =>
      r.pulse.where((c) => c.kind == 'goal').map((c) => "${c.accent == 'home' ? r.fixture.home.code : r.fixture.away.code} ${c.minute}'").toList();

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
              pill: room.status == 'live' ? 'LIVE' : 'LOBBY',
              watching: room.members.length,
              onBack: () => Navigator.of(context).maybePop(),
              topRadius: 0,
              topInset: MediaQuery.of(context).padding.top,
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
              _controls(room),
              const SizedBox(height: 12),
              _segmentBar(),
              const SizedBox(height: 12),
              if (_seg == 0) ...[
                if (room.status == 'lobby') ...[_lobbyBanner(room), const SizedBox(height: 12)],
                if (showDraft) ...[_sidePicker(room), const SizedBox(height: 12)],
                if (room.score != null) ...[WinBar(win: room.win, home: room.fixture.home, away: room.fixture.away), const SizedBox(height: 12)],
                if (showSwing) ...[NextSwingCard(prompts: room.prompts, myPicks: _c.myPicks, onPick: _c.predict), const SizedBox(height: 12)],
                if (latestRecap != null) ...[RecapCard(recap: latestRecap, aiOn: _aiOn), const SizedBox(height: 12)],
                PulseFeed(pulse: room.pulse),
                const SizedBox(height: 16),
                Row(children: [Text('THE TERRACE', style: label(color: AppColors.ink, size: 11.5, weight: FontWeight.w800)), const Spacer(), Text('${room.chat.where((c) => c.kind != "system").length} shouts', style: body(color: AppColors.mut, size: 11))]),
                const SizedBox(height: 8),
                ChatFeed(chat: room.chat),
              ] else ...[
                Leaderboard(room: room, meId: _c.memberId),
                if (room.recaps.isNotEmpty) const SizedBox(height: 12),
                ...room.recaps.reversed.map((r) => Padding(padding: const EdgeInsets.only(bottom: 10), child: RecapCard(recap: r, aiOn: _aiOn))),
              ],
            ]),
          ),
          ChatComposer(onSend: _c.sendChat, onReact: _c.react, disabled: !_c.joined),
        ]),
        if (!_c.joined) _JoinGate(room: room, onJoin: _join),
      ]),
    );
  }

  Widget _controls(RoomView room) {
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
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
        AppChip(room.proof.anchored ? '🛡 ⛓ on-chain' : '🛡 Verified · ${room.proof.leafCount}', color: AppColors.ink, onTap: () => showProofSheet(context, widget.roomId, _c.isHost)),
        if (_c.isHost && room.status == 'lobby') ...[
          const SizedBox(width: 8),
          PrimaryButton('Start', icon: Icons.play_arrow_rounded, onTap: _c.startMatch),
        ],
      ]),
    );
  }

  Widget _segmentBar() {
    Widget seg(String text, int i) {
      final on = _seg == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _seg = i),
          child: Container(
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
          child: GestureDetector(
            onTap: () => _c.pickSide(side),
            child: Container(
              decoration: cardBox(),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(children: [
                TeamBadge(team: t, size: 42),
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
              Expanded(child: GhostButton('Back to rooms', onTap: () => Navigator.of(context).maybePop())),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton('Share', icon: Icons.ios_share_rounded, onTap: () {
                  Clipboard.setData(ClipboardData(text: '${room.fixture.home.code} ${s?.goals.home ?? 0}-${s?.goals.away ?? 0} ${room.fixture.away.code} — full-time in our Final Whistle room!'));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Result copied')));
                }),
              ),
            ]),
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
