import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/cards.dart';
import '../api/models.dart';
import '../local/live_engine.dart';
import '../match_hub/controller.dart';
import '../match_hub/shell.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../state/room_controller.dart';
import '../state/room_presence.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gyro_card.dart';
import '../widgets/proof_sheet.dart';
import '../widgets/player_avatar.dart';
import '../widgets/ticket.dart';
import 'card_detail_screen.dart';
import 'team_sheet.dart';

class RoomScreen extends StatefulWidget {
  final String roomId;
  final LiveMatchEngine? engine;
  final bool autoStart;
  const RoomScreen({
    super.key,
    required this.roomId,
    this.engine,
    this.autoStart = false,
  });
  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  late final RoomController _c = widget.engine != null
      ? RoomController.local(widget.engine!)
      : RoomController(widget.roomId);
  late final MatchHubController _hub = MatchHubController(roomController: _c);
  Identity? _identity;
  bool _isPro = false;
  int _lifetimeBest = 0;
  bool _everConnected = false;
  int _lastGoals = 0;
  int _lastReds = 0;
  int _lastPoints = -1;
  int _lastCorrect = -1;
  String? _revealingDropId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RoomPresence.enter(widget.roomId);
    _c.init();
    _hub.init();
    _c.addListener(_onChange);
    _hub.addListener(_onHub);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _c.startMatch());
    }
    IdentityStore.getOrCreate().then((i) => _identity = i);
    LocalStore.streakBest().then(
      (b) => mounted ? setState(() => _lifetimeBest = b) : null,
    );
    LocalStore.isPro().then((p) => mounted ? setState(() => _isPro = p) : null);
    ApiClient.instance.config().then((_) {}).catchError((_) {});
    _markMatchWatched();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    RoomPresence.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed && mounted) {
      RoomPresence.enter(widget.roomId, fixtureId: _c.room?.fixture.id);
    }
  }

  bool _watchMarked = false;
  void _markMatchWatched() {
    if (_watchMarked) return;
    final fx = _c.room?.fixture;
    if (fx == null) return;
    _watchMarked = true;
    RoomPresence.enter(widget.roomId, fixtureId: fx.id);
    LocalStore.markWatched(fx.id);
  }

  void _onHub() {
    if (!mounted) return;
    final pending = _hub.state?.rewards.pendingReveal;
    if (pending != null && pending.id != _revealingDropId) {
      _revealingDropId = pending.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMomentDrop(pending);
      });
    }
    setState(() {});
  }

  void _onChange() {
    if (!mounted) return;
    if (_c.connected) _everConnected = true;
    final room = _c.room;
    _markMatchWatched();
    final myPoints = _c.me?.points ?? 0;
    if (_lastPoints >= 0 && myPoints > _lastPoints) {
      _pointsBurst(myPoints - _lastPoints);
      HapticFeedback.heavyImpact();
    }
    _lastPoints = myPoints;
    final st = _c.me?.streak ?? 0;
    if (st > _lifetimeBest) {
      _lifetimeBest = st;
      LocalStore.bumpStreakBest(st);
    }
    final correct = _c.me?.correct ?? 0;
    if (_lastCorrect >= 0 && correct > _lastCorrect) {
      for (var i = _lastCorrect; i < correct; i++) {
        LocalStore.bumpCallsCorrect();
      }
    }
    _lastCorrect = correct;
    final goalCards =
        room?.pulse.where((p) => p.kind == 'goal').toList() ?? const [];
    final redCards =
        room?.pulse.where((p) => p.kind == 'red').toList() ?? const [];
    if (goalCards.length > _lastGoals) {
      final isCatchUp = _lastGoals == 0 && goalCards.length > 1;
      _lastGoals = goalCards.length;
      if (!isCatchUp && room != null) {
        HapticFeedback.heavyImpact();
        final g = goalCards.last;
        final side = g.accent == 'away' ? 'away' : 'home';
        final team = side == 'away' ? room.fixture.away : room.fixture.home;
        _goalBanner(team, g.scorer ?? team.name, g.minute);
      }
    }
    if (redCards.length > _lastReds) {
      _lastReds = redCards.length;
    }
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RoomPresence.leave(widget.roomId);
    _hub.removeListener(_onHub);
    _c.removeListener(_onChange);
    _hub.dispose();
    _c.dispose();
    super.dispose();
  }

  Future<void> _shareScore(RoomView room) async {
    final me = _c.me;
    final best = ((me?.bestStreak ?? 0) > _lifetimeBest)
        ? (me?.bestStreak ?? 0)
        : _lifetimeBest;
    final text =
        '⚡ Live Calls on Final Whistle — best streak $best, ${me?.points ?? 0} pts '
        'on ${room.fixture.home.name} v ${room.fixture.away.name}. Think you can read the swings better? ⚽';
    try {
      await Share.share(text, subject: 'My Final Whistle streak');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Score copied — paste it anywhere to share 🔥'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _c.room;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: _build(room),
    );
  }

  Widget _build(RoomView? room) {
    if (_c.notFound) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          backgroundColor: AppColors.paper,
          foregroundColor: AppColors.ink,
          elevation: 0,
        ),
        body: Center(
          child: Text(
            'This room doesn\'t exist anymore.',
            style: body(color: AppColors.mut),
          ),
        ),
      );
    }
    if (_c.loadError != null && room == null) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          backgroundColor: AppColors.paper,
          foregroundColor: AppColors.ink,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _c.loadError!,
              textAlign: TextAlign.center,
              style: body(color: AppColors.mut),
            ),
          ),
        ),
      );
    }
    if (room == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0A08),
        body: Center(child: CircularProgressIndicator(color: AppColors.orange)),
      );
    }

    return Column(
      children: [
        _connectionBanner(),
        Expanded(
          child: MatchHubShell(
            hub: _hub,
            room: room,
            myPicks: _c.myPicks,
            meId: _c.memberId,
            meIsPro: _isPro,
            joined: _c.joined,
            reactionEmojis: packEmojis(_isPro ? 'pro' : room.reactionPack),
            onBack: () => Navigator.of(context).maybePop(),
            onTeamTap: (t) => showTeamSheet(context, t),
            onPickSide: _c.pickSide,
            onPredict: (promptId, key) {
              if (_hub.state?.callsPaused == true) return;
              // Answering a Call during replay pauses playback, then resumes.
              final replay = room.replayState;
              if (replay != null && replay.active && !replay.paused) {
                _hub.controlReplay(action: 'pause').then((_) {
                  _c.predict(promptId, key);
                  Future.delayed(const Duration(milliseconds: 400), () {
                    _hub.controlReplay(action: 'play');
                  });
                });
              } else {
                _c.predict(promptId, key);
              }
            },
            onReact: _c.react,
            onSendChat: _c.sendChat,
            onShare: () => _shareScore(room),
            onSourceTap: () => showProofSheet(
              context,
              room.id,
              _c.me?.isHost == true,
            ),
            joinOverlay: _c.joined
                ? null
                : _JoinGate(room: room, onJoin: _join),
          ),
        ),
      ],
    );
  }

  Widget _connectionBanner() {
    final dropped = !_c.isLocal && _everConnected && !_c.connected;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: dropped
          ? Container(
              width: double.infinity,
              color: const Color(0xFFB8860B),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'RECONNECTING TO LIVE FEED…',
                    style: label(
                      color: Colors.white,
                      size: 9.5,
                      weight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.orange,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '+$gained PTS 🔥',
                          style: display(26, color: Colors.white),
                        ),
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

  void _goalBanner(Team team, String scorer, int minute) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 8,
        left: 16,
        right: 16,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 2600),
            onEnd: () => entry.remove(),
            builder: (_, t, __) {
              final inT = Curves.easeOutBack.transform((t / 0.12).clamp(0, 1));
              final outT = t < 0.85
                  ? 0.0
                  : Curves.easeIn.transform(
                      ((t - 0.85) / 0.15).clamp(0.0, 1.0),
                    );
              return Opacity(
                opacity: (1 - outT).clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(0, -90 * (1 - inT) - 30 * outT),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(18),
                        border: Border(
                          left: BorderSide(
                            color: teamColor(team.code),
                            width: 5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          PlayerAvatar(
                            team: team,
                            name: scorer,
                            size: 46,
                            ringColor: AppColors.orangeBright,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'GOAL — ${team.name.toUpperCase()}',
                                  style: display(
                                    16,
                                    color: AppColors.orangeBright,
                                  ),
                                ),
                                Text(
                                  "$scorer · $minute'",
                                  style: body(
                                    color: AppColors.cream,
                                    size: 13,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text('⚽', style: TextStyle(fontSize: 24)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    overlay.insert(entry);
  }

  Future<void> _showMomentDrop(MomentDropView drop) async {
    HapticFeedback.heavyImpact();
    final view = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Moment earned',
      barrierColor: Colors.black.withValues(alpha: 0.82),
      transitionDuration: const Duration(milliseconds: 420),
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
      pageBuilder: (_, __, ___) => _MomentRevealDialog(drop: drop),
    );
    _hub.acknowledgeReward(drop.id);
    _hub.clearPendingReveal();
    _revealingDropId = null;
    if (view != true || !mounted) return;
    final moment = MomentCard(
      id: drop.id,
      fixtureId: _c.room?.fixture.id ?? '',
      matchLabel: drop.matchLabel,
      kind: drop.kind,
      label: drop.label,
      leafData: '',
      rarity: drop.rarity,
      minute: drop.minute,
      createdAt: drop.createdAt,
      calledIt: drop.calledIt,
      oddsSandwich: const {},
      roomId: widget.roomId,
      sourceEventId: drop.sourceEventId,
      playerId: drop.playerId,
      playerName: drop.playerName,
      teamCode: drop.teamCode,
      imageUrl: drop.imageUrl,
      artKey: drop.artworkKind,
    );
    Navigator.push(context, fwrRoute(CardDetailScreen.moment(moment)));
  }

  Future<void> _join(String name) async {
    final identity = _identity ?? await IdentityStore.getOrCreate();
    await IdentityStore.sign(
      'final-whistle-rooms:auth:$name:${identity.pubkey}',
    );
    await LocalStore.setDisplayName(name);
    await _c.join(name, identity.pubkey);
  }
}

class _MomentRevealDialog extends StatefulWidget {
  final MomentDropView drop;
  const _MomentRevealDialog({required this.drop});
  @override
  State<_MomentRevealDialog> createState() => _MomentRevealDialogState();
}

class _MomentRevealDialogState extends State<_MomentRevealDialog> {
  final CardMotionController _motion = CardMotionController();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.drop;
    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'MOMENT EARNED',
                style: display(30, color: AppColors.orangeBright),
              ),
              const SizedBox(height: 4),
              Text(
                '${d.rarity}★ COLLECTIBLE · ${d.minute}\'',
                style: label(
                  color: AppColors.cream,
                  size: 11,
                  weight: FontWeight.w800,
                ),
              ),
              if (d.calledIt) ...[
                const SizedBox(height: 7),
                Text(
                  'CALLED IT · ${d.answerLabel ?? 'Correct Call'}',
                  style: label(color: StadiumColors.mint, size: 10),
                ),
                if (d.promptQuestion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      d.promptQuestion!,
                      textAlign: TextAlign.center,
                      style: body(color: AppColors.mutInk, size: 11),
                    ),
                  ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: 270,
                height: 378,
                child: GyroTiltCard(
                  motion: _motion,
                  borderColor: rarityBorder(d.rarity),
                  intensity: 1.0,
                  enableTilt: true,
                  rarity: d.rarity,
                  seed: cardSeed('${d.id}|${d.artworkKind ?? d.kind}'),
                  foilAccent: kindAccent(d.kind),
                  child: MomentCardFace(
                    title: d.label,
                    matchLabel: d.matchLabel,
                    kind: d.kind,
                    rarity: d.rarity,
                    minute: d.minute,
                    calledIt: d.calledIt,
                    imageUrl: d.imageUrl,
                    playerId: d.playerId,
                    playerName: d.playerName,
                    teamCode: d.teamCode,
                    artKey: d.artworkKind,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                'View card',
                icon: Icons.view_in_ar_rounded,
                expand: true,
                onTap: () => Navigator.pop(context, true),
              ),
              const SizedBox(height: 8),
              GhostButton(
                'Keep watching',
                expand: true,
                onTap: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      ),
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
      await widget.onJoin(
        _ctrl.text.trim().isEmpty ? 'Fan' : _ctrl.text.trim(),
      );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TeamBadge(team: f.home, size: 44),
                const SizedBox(width: 10),
                Text('VS', style: display(20, color: AppColors.mut)),
                const SizedBox(width: 10),
                TeamBadge(team: f.away, size: 44),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.room.name,
              textAlign: TextAlign.center,
              style: display(20),
            ),
            const SizedBox(height: 2),
            Text(
              '${f.home.name} vs ${f.away.name}',
              textAlign: TextAlign.center,
              style: body(color: AppColors.mut, size: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: fwrInput('Your name e.g. Sam'),
            ),
            if (_err.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _err,
                  style: body(color: const Color(0xFFD8392B), size: 12),
                ),
              ),
            const SizedBox(height: 14),
            PrimaryButton(
              '◎ Continue with Solana & join',
              expand: true,
              busy: _busy,
              onTap: _join,
            ),
            const SizedBox(height: 8),
            Text(
              'No wallet or funds needed — a secure on-device identity is created for you.',
              textAlign: TextAlign.center,
              style: body(color: AppColors.mut, size: 11),
            ),
          ],
        ),
      ),
    );
  }
}
