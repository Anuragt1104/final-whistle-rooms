import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/cards.dart';
import '../state/identity.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gyro_card.dart';

const _axes = ['finishing', 'chaos', 'clutch', 'marketShock', 'aura'];

class DuelScreen extends StatefulWidget {
  final List<PlayerCardModel> players;
  final List<MomentCard> moments;
  const DuelScreen({super.key, required this.players, required this.moments});
  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> {
  final _api = ApiClient.instance;
  final Set<String> _hand = {};
  final CardMotionController _motion = CardMotionController();
  TrumpDuelModel? _duel;
  String _axis = 'finishing';
  String? _playCardId;
  String? _seedMomentId;
  String? _err;
  bool _busy = false;
  Timer? _arenaTimer;
  int? _visibleArenaRounds;

  @override
  void initState() {
    super.initState();
    _motion.start();
    if (widget.moments.isNotEmpty) _seedMomentId = widget.moments.first.id;
  }

  @override
  void dispose() {
    _arenaTimer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  Future<String> _fanId() async => (await IdentityStore.getOrCreate()).pubkey;

  Future<void> _start({bool arena = false}) async {
    if (_hand.length != 3) {
      setState(() => _err = 'Lock exactly 3 Player Cards into your hand');
      return;
    }
    if (arena && _seedMomentId == null) {
      setState(() => _err = 'Choose a Moment to charge the arena');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final fanId = await _fanId();
      final hand = _hand.toList();
      final raw = arena
          ? await _api.createArena(
              fanId: fanId,
              seedMomentId: _seedMomentId!,
              hand: hand,
            )
          : await _api.createDuel(fanId: fanId, hand: hand, vsBot: true);
      if (!mounted) return;
      setState(() {
        _duel = TrumpDuelModel.fromJson(raw);
        _playCardId = hand.first;
        _busy = false;
        _visibleArenaRounds = arena ? 0 : null;
      });
      if (arena) _animateArenaRounds();
    } catch (e) {
      if (mounted)
        setState(() {
          _err = e.toString();
          _busy = false;
        });
    }
  }

  void _animateArenaRounds() {
    _arenaTimer?.cancel();
    _arenaTimer = Timer.periodic(const Duration(milliseconds: 850), (timer) {
      final total = _duel?.rounds.length ?? 0;
      if (!mounted || (_visibleArenaRounds ?? total) >= total) {
        timer.cancel();
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() => _visibleArenaRounds = (_visibleArenaRounds ?? 0) + 1);
    });
  }

  Future<void> _playRound() async {
    final d = _duel;
    if (d == null || _playCardId == null) return;
    setState(() => _busy = true);
    try {
      final fanId = await _fanId();
      final raw = await _api.playDuelRound(
        duelId: d.id,
        fanId: fanId,
        axis: _axis,
        cardId: _playCardId!,
      );
      if (!mounted) return;
      final next = TrumpDuelModel.fromJson(raw);
      final used = next.rounds
          .map((r) => (r as Map)['aCardId']?.toString())
          .whereType<String>()
          .toSet();
      final remaining = next.challengerHand
          .where((id) => !used.contains(id))
          .toList();
      HapticFeedback.heavyImpact();
      setState(() {
        _duel = next;
        _playCardId = remaining.isEmpty ? null : remaining.first;
        _busy = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _err = e.toString();
          _busy = false;
        });
    }
  }

  PlayerCardModel _player(String id) => widget.players.firstWhere(
    (p) => p.id == id,
    orElse: () => widget.players.first,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07130F),
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF07130F),
        title: Text(
          _duel == null ? 'BUILD YOUR HAND' : 'STADIUM DUEL',
          style: label(color: Colors.white, weight: FontWeight.w800),
        ),
      ),
      body: _duel == null ? _pickHand() : _arena(),
    );
  }

  Widget _pickHand() {
    return Column(
      children: [
        _stadiumHeader(
          'CHOOSE YOUR THREE',
          '${_hand.length}/3 locked · best of three',
        ),
        _handSlots(),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.5 / 3.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
            ),
            itemCount: widget.players.length,
            itemBuilder: (_, i) {
              final p = widget.players[i];
              final selected = _hand.contains(p.id);
              return GyroTiltCard(
                motion: _motion,
                selected: selected,
                borderColor: selected
                    ? AppColors.orangeBright
                    : teamColor(p.teamCode),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (selected)
                      _hand.remove(p.id);
                    else if (_hand.length < 3)
                      _hand.add(p.id);
                  });
                },
                child: PlayerCardFace(
                  name: p.name,
                  teamCode: p.teamCode,
                  position: p.position,
                  imageUrl: p.imageUrl,
                  axes: p.axes,
                ),
              );
            },
          ),
        ),
        if (widget.moments.isNotEmpty) _momentCharger(),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _err!,
              style: body(color: const Color(0xFFFF8A80), size: 12),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: GhostButton(
                    'Moment Arena',
                    expand: true,
                    onTap: _busy || _hand.length != 3 || _seedMomentId == null
                        ? null
                        : () => _start(arena: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    'Face the House',
                    expand: true,
                    busy: _busy,
                    onTap: _busy || _hand.length != 3 ? null : () => _start(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stadiumHeader(String title, String sub) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF153D2C), Color(0xFF07130F)]),
    ),
    child: Column(
      children: [
        Text(title, style: display(25, color: Colors.white)),
        const SizedBox(height: 3),
        Text(sub, style: body(color: const Color(0xFF93B9A8), size: 12)),
      ],
    ),
  );

  Widget _handSlots() {
    final ids = _hand.toList();
    return Container(
      height: 68,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2119),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF28563F)),
      ),
      child: Row(
        children: List.generate(3, (i) {
          final p = i < ids.length ? _player(ids[i]) : null;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == 2 ? 0 : 7),
              decoration: BoxDecoration(
                color: const Color(0xFF07130F),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: p == null
                      ? const Color(0xFF28563F)
                      : AppColors.orangeBright,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                p?.name.split(' ').last.toUpperCase() ?? 'EMPTY',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: label(
                  color: p == null ? const Color(0xFF587A6B) : Colors.white,
                  size: 9,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _momentCharger() => SizedBox(
    height: 58,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Center(
            child: Text(
              'ARENA CHARGE',
              style: label(
                color: const Color(0xFF93B9A8),
                size: 9,
                weight: FontWeight.w800,
              ),
            ),
          ),
        ),
        ...widget.moments.map((m) {
          final on = m.id == _seedMomentId;
          return GestureDetector(
            onTap: () => setState(() => _seedMomentId = m.id),
            child: Container(
              width: 112,
              margin: const EdgeInsets.only(right: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: on
                    ? rarityBorder(m.rarity).withValues(alpha: 0.28)
                    : const Color(0xFF0D2119),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: on ? rarityBorder(m.rarity) : const Color(0xFF28563F),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${kindGlyph(m.kind)} ${m.rarity}★ ${m.minute}\'',
                maxLines: 1,
                style: label(color: Colors.white, size: 9),
              ),
            ),
          );
        }),
      ],
    ),
  );

  Widget _arena() {
    final d = _duel!;
    final visibleRounds = d.mode == 'arena'
        ? d.rounds.take(_visibleArenaRounds ?? d.rounds.length).toList()
        : d.rounds;
    final arenaAnimating =
        d.mode == 'arena' && visibleRounds.length < d.rounds.length;
    final mine = visibleRounds
        .where((r) => (r as Map)['winnerId'] == d.challengerId)
        .length;
    final house = visibleRounds
        .where((r) => (r as Map)['winnerId'] == 'bot')
        .length;
    final used = visibleRounds
        .map((r) => (r as Map)['aCardId']?.toString())
        .whereType<String>()
        .toSet();
    final remaining = d.challengerHand
        .where((id) => !used.contains(id))
        .toList();
    final last = visibleRounds.isEmpty ? null : visibleRounds.last as Map;
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
        SafeArea(
          top: false,
          child: Column(
            children: [
              _scoreBoard(mine, house, visibleRounds.length),
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 520),
                    transitionBuilder: (child, a) => ScaleTransition(
                      scale: CurvedAnimation(
                        parent: a,
                        curve: Curves.easeOutBack,
                      ),
                      child: FadeTransition(opacity: a, child: child),
                    ),
                    child: Container(
                      key: ValueKey(visibleRounds.length),
                      width: 300,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xE60A1812),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppColors.orangeBright,
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Color(0x66000000), blurRadius: 28),
                        ],
                      ),
                      child: last == null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '🂠',
                                  style: TextStyle(fontSize: 54),
                                ),
                                Text(
                                  'THE HOUSE AWAITS',
                                  style: display(19, color: Colors.white),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${last['axis']}'.toUpperCase(),
                                  style: label(
                                    color: AppColors.orangeBright,
                                    size: 10,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _duelCard(_player('${last['aCardId']}')),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        'VS',
                                        style: display(
                                          20,
                                          color: AppColors.orangeBright,
                                        ),
                                      ),
                                    ),
                                    _houseCardBack(),
                                  ],
                                ),
                                const SizedBox(height: 9),
                                Text(
                                  '${last['aValue']}  VS  ${last['bValue']}',
                                  style: display(32, color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  last['winnerId'] == d.challengerId
                                      ? 'ROUND TO YOU 👑'
                                      : last['winnerId'] == 'bot'
                                      ? 'HOUSE TAKES IT'
                                      : 'DRAW',
                                  style: label(
                                    color: last['winnerId'] == d.challengerId
                                        ? const Color(0xFF6EF2A4)
                                        : const Color(0xFFFF8A80),
                                    size: 11,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              if (arenaAnimating) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  child: Column(
                    children: [
                      const LinearProgressIndicator(
                        color: AppColors.orangeBright,
                        backgroundColor: Color(0xFF28563F),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'REVEALING MOMENT ARENA · ${visibleRounds.length}/${d.rounds.length}',
                        style: label(color: const Color(0xFF93B9A8), size: 9),
                      ),
                    ],
                  ),
                ),
              ] else if (d.status == 'playing') ...[
                _axisRail(),
                SizedBox(
                  height: 178,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    itemCount: remaining.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final p = _player(remaining[i]);
                      final on = p.id == _playCardId;
                      return GestureDetector(
                        onTap: () => setState(() => _playCardId = p.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 112,
                          transform: Matrix4.translationValues(
                            0,
                            on ? -7 : 0,
                            0,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: on
                                  ? AppColors.orangeBright
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: PlayerCardFace(
                            name: p.name,
                            teamCode: p.teamCode,
                            position: p.position,
                            imageUrl: p.imageUrl,
                            axes: p.axes,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: PrimaryButton(
                    'PLAY ${_axis.toUpperCase()}',
                    icon: Icons.flash_on_rounded,
                    expand: true,
                    busy: _busy,
                    onTap: _busy || _playCardId == null ? null : _playRound,
                  ),
                ),
              ] else
                _finished(d, mine, house),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _err!,
                    style: body(color: const Color(0xFFFF8A80)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _duelCard(PlayerCardModel player) => Container(
    width: 78,
    height: 108,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: teamColor(player.teamCode), width: 1.5),
    ),
    child: PlayerCardFace(
      name: player.name,
      teamCode: player.teamCode,
      position: player.position,
      imageUrl: player.imageUrl,
      axes: const {},
    ),
  );

  Widget _houseCardBack() => Container(
    width: 78,
    height: 108,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF8B5CF6), Color(0xFF101B16)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFB8FF36), width: 1.5),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.shield_rounded, color: Color(0xFFB8FF36), size: 42),
        Positioned(
          bottom: 8,
          child: Text('HOUSE', style: label(color: Colors.white, size: 8)),
        ),
      ],
    ),
  );

  Widget _scoreBoard(int mine, int house, int round) => Container(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
    decoration: const BoxDecoration(
      color: Color(0xE607130F),
      border: Border(bottom: BorderSide(color: Color(0xFF28563F))),
    ),
    child: Row(
      children: [
        _scoreSide('YOU', mine, const Color(0xFF6EF2A4)),
        Expanded(
          child: Column(
            children: [
              Text(
                'ROUND ${math.min(round + 1, 3)}',
                style: label(color: const Color(0xFF93B9A8), size: 9),
              ),
              Text('⚔', style: display(25, color: AppColors.orangeBright)),
            ],
          ),
        ),
        _scoreSide('HOUSE', house, const Color(0xFFFF8A80)),
      ],
    ),
  );

  Widget _scoreSide(String name, int score, Color color) => Column(
    children: [
      Text(
        name,
        style: label(color: color, size: 10, weight: FontWeight.w800),
      ),
      const SizedBox(height: 3),
      Row(
        children: List.generate(
          2,
          (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              i < score
                  ? Icons.workspace_premium_rounded
                  : Icons.circle_outlined,
              size: 18,
              color: color,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _axisRail() => SizedBox(
    height: 42,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      children: _axes.map((a) {
        final on = a == _axis;
        return Padding(
          padding: const EdgeInsets.only(right: 7),
          child: ChoiceChip(
            label: Text(a == 'marketShock' ? 'MARKET' : a.toUpperCase()),
            selected: on,
            onSelected: (_) => setState(() => _axis = a),
            selectedColor: AppColors.orange,
            backgroundColor: const Color(0xFF0D2119),
            side: const BorderSide(color: Color(0xFF28563F)),
            labelStyle: label(
              color: on ? Colors.white : const Color(0xFF93B9A8),
              size: 9,
              weight: FontWeight.w800,
            ),
          ),
        );
      }).toList(),
    ),
  );

  Widget _finished(TrumpDuelModel d, int mine, int house) {
    final won = d.winnerId != 'bot';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
      child: Column(
        children: [
          Text(won ? '🏆' : '🛡️', style: const TextStyle(fontSize: 40)),
          Text(
            won ? 'ARENA CONQUERED' : 'THE HOUSE HOLDS',
            style: display(
              24,
              color: won ? const Color(0xFF6EF2A4) : const Color(0xFFFF8A80),
            ),
          ),
          Text(
            '$mine – $house · ${d.mode == 'arena' ? "Moment Arena" : "Trump Duel"}',
            style: body(color: const Color(0xFF93B9A8), size: 12),
          ),
          const SizedBox(height: 14),
          GhostButton(
            'Back to Album',
            expand: true,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0D2B1F);
    canvas.drawRect(Offset.zero & size, paint);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = const Color(0x334ED58A);
    final field = Rect.fromLTWH(14, 16, size.width - 28, size.height - 32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(field, const Radius.circular(18)),
      paint,
    );
    canvas.drawLine(
      Offset(14, size.height / 2),
      Offset(size.width - 14, size.height / 2),
      paint,
    );
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 54, paint);
    for (double y = 16; y < size.height; y += 72) {
      canvas.drawRect(
        Rect.fromLTWH(14, y, size.width - 28, 36),
        Paint()..color = const Color(0x0DFFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
