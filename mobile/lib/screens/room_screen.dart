import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../state/room_controller.dart';
import '../theme.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import '../widgets/score_rail.dart';
import '../widgets/pulse_feed.dart';
import '../widgets/next_swing_card.dart';
import '../widgets/leaderboard.dart';
import '../widgets/chat_dock.dart';
import '../widgets/recap_card.dart';
import '../widgets/proof_sheet.dart';

class RoomScreen extends StatefulWidget {
  final String roomId;
  const RoomScreen({super.key, required this.roomId});
  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final RoomController _c = RoomController(widget.roomId);
  int _tab = 0;
  bool _aiOn = false;
  Identity? _identity;

  @override
  void initState() {
    super.initState();
    _c.init();
    _c.addListener(_onChange);
    IdentityStore.getOrCreate().then((i) => _identity = i);
    ApiClient.instance.config().then((cfg) => mounted ? setState(() => _aiOn = cfg.recapAI) : null).catchError((_) {});
  }

  void _onChange() => mounted ? setState(() {}) : null;

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _c.room;

    if (_c.notFound) {
      return Scaffold(
        body: Column(children: [
          FwrHeader(small: true, showBack: true, identityLabel: 'Solana', onIdentityTap: () {}),
          const Expanded(
            child: Center(child: Text('This room doesn\'t exist anymore.', style: TextStyle(color: AppColors.mut))),
          ),
        ]),
      );
    }
    if (room == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(children: [
        Column(children: [
          FwrHeader(small: true, showBack: true, identityLabel: 'Solana', onIdentityTap: () {}),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
              _titleRow(room),
              const SizedBox(height: 12),
              _hostBar(room),
              const SizedBox(height: 12),
              ScoreRail(room: room),
              const SizedBox(height: 12),
              if (room.status == 'lobby') _lobbyBanner(room),
              if (room.status == 'lobby') const SizedBox(height: 12),
              _tabs(),
              const SizedBox(height: 12),
              ..._tabContent(room),
            ]),
          ),
        ]),
        if (!_c.joined) _JoinGate(room: room, onJoin: _join),
      ]),
    );
  }

  Widget _titleRow(RoomView room) {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(room.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(room.fixture.stage, style: const TextStyle(fontSize: 11, color: AppColors.mut)),
        ]),
      ),
      AppChip(
        room.proof.anchored ? '🛡️ Verified · ⛓ on-chain' : '🛡️ Verified · ${room.proof.leafCount}',
        color: AppColors.lime,
        onTap: () => showProofSheet(context, widget.roomId, _c.isHost),
      ),
    ]);
  }

  Widget _hostBar(RoomView room) {
    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('INVITE CODE', style: TextStyle(fontSize: 9, letterSpacing: 1, color: AppColors.mut)),
          Text(room.code,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 3, color: AppColors.lime)),
        ]),
        const Spacer(),
        GhostButton('Share', onTap: () {
          Clipboard.setData(ClipboardData(text: 'Join my World Cup room — code ${room.code}'));
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Invite copied to clipboard')));
        }),
        if (_c.isHost && room.status == 'lobby') ...[
          const SizedBox(width: 8),
          PrimaryButton('▶ Start', onTap: () => _c.startMatch()),
        ],
      ]),
    );
  }

  Widget _lobbyBanner(RoomView room) {
    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Text(
        _c.isHost
            ? 'You\'re the host. Share the code, draft a side, then start the match.'
            : 'Waiting for the host to kick things off. Draft your side while you wait 👇',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.mut, fontSize: 13),
      ),
    );
  }

  Widget _tabs() {
    final labels = ['⚡ Watch', '🏆 Board', '💬 Chat'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0x4D000000), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: List.generate(3, (i) {
          final sel = _tab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                    color: sel ? AppColors.pitch700 : Colors.transparent,
                    borderRadius: BorderRadius.circular(9)),
                child: Text(labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : AppColors.mut)),
              ),
            ),
          );
        }),
      ),
    );
  }

  List<Widget> _tabContent(RoomView room) {
    final me = _c.me;
    final latestRecap = room.recaps.isNotEmpty ? room.recaps.last : null;
    final showSwing = room.modes.nextSwing && (room.status == 'live' || room.prompts.isNotEmpty);
    final showDraft = room.modes.draft && _c.joined && me?.side == null && room.status != 'finished';

    if (_tab == 0) {
      return [
        if (latestRecap != null) ...[RecapCard(recap: latestRecap, aiOn: _aiOn), const SizedBox(height: 12)],
        if (showDraft) ...[_SidePicker(fixture: room.fixture, onPick: (s) => _c.pickSide(s)), const SizedBox(height: 12)],
        if (showSwing) ...[
          NextSwingCard(prompts: room.prompts, myPicks: _c.myPicks, onPick: (p, k) => _c.predict(p, k)),
          const SizedBox(height: 12),
        ],
        PulseFeed(pulse: room.pulse),
      ];
    }
    if (_tab == 1) {
      return [
        Leaderboard(room: room, meId: _c.memberId),
        if (room.recaps.isNotEmpty) const SizedBox(height: 12),
        ...room.recaps.reversed.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecapCard(recap: r, aiOn: _aiOn),
            )),
      ];
    }
    return [
      ChatDock(
        chat: room.chat,
        disabled: !_c.joined,
        onSend: (t) => _c.sendChat(t),
        onReact: (e) => _c.react(e),
      ),
    ];
  }

  Future<void> _join(String name) async {
    final identity = _identity ?? await IdentityStore.getOrCreate();
    await IdentityStore.sign('final-whistle-rooms:auth:$name:${identity.pubkey}');
    await LocalStore.setDisplayName(name);
    await _c.join(name, identity.pubkey);
  }
}

class _SidePicker extends StatelessWidget {
  final Fixture fixture;
  final void Function(String side) onPick;
  const _SidePicker({required this.fixture, required this.onPick});
  @override
  Widget build(BuildContext context) {
    Widget card(String side, Team t) => Expanded(
          child: GestureDetector(
            onTap: () => onPick(side),
            child: Container(
              decoration: cardDecoration(),
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Text(t.flag, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 4),
                Text(t.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
          ),
        );
    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const AppChip('🏆 Tournament Draft', color: AppColors.gold),
        const SizedBox(height: 8),
        const Text('Draft your side', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const Text('Earn points whenever your team scores, wins corners, or finishes ahead.',
            style: TextStyle(fontSize: 11, color: AppColors.mut)),
        const SizedBox(height: 12),
        Row(children: [card('home', fixture.home), const SizedBox(width: 8), card('away', fixture.away)]),
      ]),
    );
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
      color: Colors.black.withValues(alpha: 0.72),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: cardDecoration(),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${f.home.flag} vs ${f.away.flag}', style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 6),
          Text(widget.room.name,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('${f.home.name} vs ${f.away.name}',
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mut, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(controller: _ctrl, autofocus: true, decoration: fwrInput('Your name e.g. Sam')),
          if (_err.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_err, style: const TextStyle(color: AppColors.away, fontSize: 12)),
            ),
          const SizedBox(height: 14),
          PrimaryButton('◎ Continue with Solana & join', expand: true, busy: _busy, onTap: _join),
          const SizedBox(height: 8),
          const Text('No wallet or funds needed — a secure on-device identity is created for you.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.mut)),
        ]),
      ),
    );
  }
}
