import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/cards.dart';
import '../duel/duel_controller.dart';
import '../duel/duel_models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/duel/duel_stadium.dart';
import '../widgets/gyro_card.dart';

const _axes = ['finishing', 'chaos', 'clutch', 'marketShock', 'aura'];

class DuelScreen extends StatefulWidget {
  final List<PlayerCardModel> players;
  final List<MomentCard> moments;
  final List<SkillCardModel> skills;
  final String? resumeDuelId;

  /// 0 House · 1 Friend · 2 Moment Arena
  final int initialSetupMode;

  const DuelScreen({
    super.key,
    required this.players,
    required this.moments,
    this.skills = const [],
    this.resumeDuelId,
    this.initialSetupMode = 2,
  });

  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> {
  late final DuelController _controller = DuelController(
    players: widget.players,
    moments: widget.moments,
    skills: widget.skills,
  );
  final CardMotionController _motion = CardMotionController();
  final TextEditingController _code = TextEditingController();
  late int _setupMode; // House, Friend, Moment Arena
  bool _showJoin = false;

  bool get _showDemoControls =>
      ApiClient.instance.cachedConfig?.mode == 'simulation';

  @override
  void initState() {
    super.initState();
    _setupMode = widget.initialSetupMode.clamp(0, 2);
    _controller.addListener(_onChange);
    _motion.start();
    _controller.init(resumeDuelId: widget.resumeDuelId);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller.dispose();
    _code.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duel = _controller.view;
    return PopScope(
      canPop: !_controller.presentation.busy,
      child: Scaffold(
        backgroundColor: const Color(0xFF03110C),
        body: duel == null ? _setup() : _stadium(duel),
      ),
    );
  }

  Widget _setup() => SafeArea(
    child: Column(
      children: [
        _topBar('BUILD YOUR DUEL'),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(
            children: [
              _modeButton('HOUSE', 0, Icons.stadium_rounded),
              const SizedBox(width: 7),
              _modeButton('FRIEND', 1, Icons.group_rounded),
              const SizedBox(width: 7),
              _modeButton('MOMENT', 2, Icons.bolt_rounded),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            children: [
              if (_controller.players.length < 3) ...[
                _messageCard(
                  _showDemoControls
                      ? 'Need 3 Player Cards to duel. Load the explicit demo set.'
                      : 'Need 3 Player Cards to duel. Earn Moments, open Packs, then return with a complete Hand.',
                ),
                if (_showDemoControls) ...[
                  const SizedBox(height: 10),
                  PrimaryButton(
                    'Load explicit demo cards',
                    icon: Icons.auto_awesome_rounded,
                    expand: true,
                    busy: _controller.seeding,
                    onTap: _controller.loadDemoCards,
                  ),
                ],
                const SizedBox(height: 18),
              ] else if (_showDemoControls) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _controller.seeding
                        ? null
                        : _controller.loadDemoCards,
                    child: Text(
                      _controller.seeding
                          ? 'Loading…'
                          : 'Reload explicit demo cards',
                      style: label(color: AppColors.orangeBright, size: 10),
                    ),
                  ),
                ),
              ],
              _sectionTitle(
                'LOCK YOUR THREE',
                '${_controller.selectedHand.length}/3 selected',
              ),
              const SizedBox(height: 9),
              if (_controller.players.isEmpty)
                _messageCard(
                  _showDemoControls
                      ? 'No Player Cards yet — load the explicit demo set.'
                      : 'No Player Cards yet — open a Pack from Cards.',
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: .70,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _controller.players.length,
                  itemBuilder: (_, index) =>
                      _setupCard(_controller.players[index]),
                ),
              if (_controller.skills.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sectionTitle(
                  'OPTIONAL SKILLS',
                  '${_controller.selectedSkills.length}/3 equipped',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _controller.skills
                      .map(
                        (skill) => FilterChip(
                          selected: _controller.selectedSkills.contains(
                            skill.id,
                          ),
                          onSelected: (_) => _controller.toggleSkill(skill.id),
                          label: Text(skill.name),
                          selectedColor: AppColors.orange,
                          backgroundColor: const Color(0xFF10251C),
                          checkmarkColor: Colors.white,
                          labelStyle: label(color: Colors.white, size: 9),
                          side: const BorderSide(color: Color(0xFF315C48)),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (_setupMode == 2) ...[
                const SizedBox(height: 18),
                _sectionTitle(
                  'CHARGE WITH A VERIFIED MOMENT',
                  'Choose one explicitly',
                ),
                const SizedBox(height: 8),
                if (_controller.moments.isEmpty)
                  _messageCard(
                    _showDemoControls
                        ? 'Load explicit demo cards or earn a live Moment to charge Arena.'
                        : 'Earn a verified Moment in a Match Hub to charge Arena.',
                  )
                else
                  ..._controller.moments.map(_momentChoice),
              ],
              if (_setupMode == 1) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        _showJoin ? 'Create Invite' : 'Join Invite',
                        expand: true,
                        onTap: () => setState(() => _showJoin = !_showJoin),
                      ),
                    ),
                  ],
                ),
                if (_showJoin) ...[
                  const SizedBox(height: 9),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    style: display(22, color: Colors.white),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '6-CHARACTER CODE',
                      hintStyle: label(color: AppColors.mutInk, size: 10),
                      filled: true,
                      fillColor: const Color(0xFF10251C),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF315C48)),
                      ),
                    ),
                  ),
                ],
              ],
              if (_controller.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _controller.error!,
                  style: body(color: const Color(0xFFFF8A80), size: 12),
                ),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                _setupMode == 2
                    ? 'Enter Moment Arena'
                    : _setupMode == 1 && _showJoin
                    ? 'Join Stadium Duel'
                    : _setupMode == 1
                    ? 'Create Friend Duel'
                    : 'Face the House',
                icon: _setupMode == 2
                    ? Icons.bolt_rounded
                    : Icons.sports_mma_rounded,
                expand: true,
                busy: _controller.busy,
                onTap: _startSelectedMode,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _startSelectedMode() async {
    HapticFeedback.mediumImpact();
    if (_setupMode == 2) {
      await _controller.createArena();
    } else if (_setupMode == 1 && _showJoin) {
      await _controller.joinFriend(_code.text);
    } else {
      await _controller.createStadium(
        _setupMode == 1 ? DuelOpponent.friend : DuelOpponent.house,
      );
    }
  }

  Widget _setupCard(PlayerCardModel player) {
    final selected = _controller.selectedHand.contains(player.id);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _controller.toggleHand(player.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, selected ? -5 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.orangeBright : Colors.transparent,
            width: 3,
          ),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x55F05223), blurRadius: 14)]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: GyroTiltCard(
          motion: _motion,
          intensity: 0,
          enableTilt: false,
          selected: selected,
          rarity: 3,
          seed: cardSeed('${player.id}|duel-setup'),
          borderColor: teamColor(player.teamCode),
          frameShape: CardFrameShape.stadiumCrown,
          child: DuelPlayerCardFace(
            playerId: player.playerId,
            name: player.name,
            teamCode: player.teamCode,
            position: player.position,
            imageUrl: player.imageUrl,
            axes: player.axes,
          ),
        ),
      ),
    );
  }

  Widget _momentChoice(MomentCard moment) {
    final selected = _controller.selectedMomentId == moment.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        haptic: HapticFeedbackType.selection,
        onTap: () => _controller.selectMoment(moment.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.orange.withValues(alpha: .2)
                : const Color(0xFF10251C),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? AppColors.orangeBright
                  : const Color(0xFF315C48),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kindAccent(moment.kind),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  kindGlyph(moment.kind),
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      moment.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(
                        color: Colors.white,
                        size: 12.5,
                        weight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      "${moment.matchLabel} · ${moment.minute}' · ${moment.rarity}★",
                      style: body(color: AppColors.mutInk, size: 10),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? AppColors.orangeBright : AppColors.mutInk,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        Expanded(
          child: Text(
            title,
            style: label(
              color: AppColors.cream,
              size: 12,
              weight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _modeButton(String labelText, int mode, IconData icon) {
    final selected = _setupMode == mode;
    return Expanded(
      child: Pressable(
        haptic: HapticFeedbackType.selection,
        onTap: () => setState(() {
          _setupMode = mode;
          _showJoin = false;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.orange : const Color(0xFF10251C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.orangeBright
                  : const Color(0xFF315C48),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(height: 4),
              Text(
                labelText,
                style: label(
                  color: Colors.white,
                  size: 9,
                  weight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String detail) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: label(
            color: AppColors.cream,
            size: 11,
            weight: FontWeight.w900,
          ),
        ),
      ),
      Text(detail, style: body(color: AppColors.mutInk, size: 11)),
    ],
  );

  Widget _messageCard(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF10251C),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF315C48)),
    ),
    child: Text(text, style: body(color: AppColors.mutInk, size: 12)),
  );

  Widget _stadium(DuelViewModel duel) {
    final presentation = _controller.presentation;
    final dimmed =
        presentation.phase == DuelPresentationPhase.floodlights ||
        presentation.phase == DuelPresentationPhase.flipping;
    return DuelStadiumBackdrop(
      dimmed: dimmed,
      child: SafeArea(
        child: Column(
          children: [
            _liveTopBar(duel),
            const SizedBox(height: 8),
            DuelConditionRibbon(duel: duel),
            const SizedBox(height: 10),
            Expanded(child: _arenaBody(duel)),
            if (duel.phase == DuelPhase.finished)
              _finishedPanel(duel)
            else
              _controls(duel),
          ],
        ),
      ),
    );
  }

  Widget _liveTopBar(DuelViewModel duel) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 2, 12, 0),
    child: Row(
      children: [
        IconButton(
          onPressed: _controller.presentation.busy
              ? null
              : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
        _crown(duel.yourScore, 'YOU'),
        const SizedBox(width: 8),
        Text('VS', style: label(color: AppColors.mutInk, size: 10)),
        const SizedBox(width: 8),
        _crown(
          duel.opponentScore,
          duel.opponent == DuelOpponent.house ? 'HOUSE' : 'FOE',
        ),
        const Spacer(),
        if (duel.attackerId == duel.fanId)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'ATTACKER',
              style: label(
                color: AppColors.orangeBright,
                size: 9,
                weight: FontWeight.w900,
              ),
            ),
          ),
        Icon(
          _controller.connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          size: 16,
          color: _controller.connected
              ? const Color(0xFF4ED58A)
              : AppColors.mutInk,
        ),
        const SizedBox(width: 8),
        DuelTurnClock(deadline: duel.deadlineAt),
      ],
    ),
  );

  Widget _crown(int score, String who) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFF173C2C),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: const Color(0xFF315C48)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.workspace_premium_rounded,
          size: 13,
          color: AppColors.orangeBright,
        ),
        const SizedBox(width: 4),
        Text(
          '$who $score',
          style: label(color: Colors.white, size: 9, weight: FontWeight.w900),
        ),
      ],
    ),
  );

  Widget _arenaBody(DuelViewModel duel) {
    if (duel.phase == DuelPhase.waitingForOpponent) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('WAITING FOR FRIEND', style: display(22, color: Colors.white)),
            const SizedBox(height: 10),
            Text('Invite code', style: body(color: AppColors.mutInk, size: 12)),
            const SizedBox(height: 6),
            Text(duel.code, style: display(36, color: AppColors.orangeBright)),
            const SizedBox(height: 14),
            GhostButton(
              'Share invite',
              onTap: () => Share.share(
                'Join my Final Whistle Stadium Duel: ${duel.code}\nfinalwhistle://duels/${duel.id}',
              ),
            ),
          ],
        ),
      );
    }

    final presentation = _controller.presentation;
    final visible =
        presentation.visibleRound ??
        (presentation.busy ? null : duel.latestRound);
    final showOpp = presentation.busy
        ? presentation.showOpponentCard
        : visible != null;
    final showScores = presentation.busy
        ? presentation.showScores
        : visible != null;
    final showMods = presentation.busy
        ? presentation.showModifiers
        : visible != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: _combatCard(
                title: duel.opponent == DuelOpponent.house
                    ? 'HOUSE'
                    : 'OPPONENT',
                card: showOpp ? visible?.opponentCard : null,
                score: showScores ? visible?.opponentScore : null,
                modifiers: showMods
                    ? visible?.opponentModifiers ?? const []
                    : const [],
                locked:
                    !showOpp &&
                    (duel.opponentSubmitted ||
                        duel.opponent == DuelOpponent.house),
                faceDown: !showOpp,
              ),
            ),
          ),
          if (visible != null && showScores) ...[
            Text(
              visible.axis.toUpperCase(),
              style: label(
                color: AppColors.cream,
                size: 11,
                weight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              showScores
                  ? '${visible.yourScore ?? '—'}  ·  ${visible.opponentScore ?? '—'}'
                  : '—  ·  —',
              style: display(28, color: Colors.white),
            ),
            if (presentation.showResult || !presentation.busy) ...[
              const SizedBox(height: 4),
              Text(
                visible.winnerId == null
                    ? 'DRAW'
                    : visible.winnerId == duel.fanId
                    ? 'YOU TAKE THE ROUND'
                    : 'OPPONENT TAKES THE ROUND',
                style: label(
                  color: AppColors.orangeBright,
                  size: 10,
                  weight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 10),
          ] else
            const SizedBox(height: 18),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _combatCard(
                title: 'YOU',
                card:
                    visible?.yourCard ??
                    (duel.yourHand
                        .where((c) => c.id == _controller.selectedCardId)
                        .firstOrNull),
                score: showScores ? visible?.yourScore : null,
                modifiers: showMods
                    ? visible?.yourModifiers ?? const []
                    : const [],
                locked: false,
                faceDown: false,
                prominent: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _combatCard({
    required String title,
    required DuelCardSnapshot? card,
    required int? score,
    required List<DuelModifierModel> modifiers,
    required bool locked,
    required bool faceDown,
    bool prominent = false,
  }) {
    final width = prominent ? 148.0 : 118.0;
    final height = prominent ? 198.0 : 158.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: label(color: AppColors.mutInk, size: 9)),
        const SizedBox(height: 6),
        faceDown || card == null
            ? Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A3A2C), Color(0xFF0B1F16)],
                  ),
                  border: Border.all(color: const Color(0xFF3C6B54)),
                ),
                alignment: Alignment.center,
                child: Text(
                  locked ? 'LOCKED' : 'WAITING',
                  style: label(
                    color: Colors.white54,
                    size: 11,
                    weight: FontWeight.w900,
                  ),
                ),
              )
            : GyroTiltCard(
                width: width,
                height: height,
                motion: _motion,
                intensity: prominent ? 1 : 0.35,
                enableTilt: prominent,
                rarity: 4,
                seed: cardSeed('${card.id}|duel-live'),
                borderColor: teamColor(card.teamCode),
                frameShape: CardFrameShape.stadiumCrown,
                child: DuelPlayerCardFace(
                  playerId: card.playerId ?? '',
                  name: card.name,
                  teamCode: card.teamCode,
                  position: card.position,
                  imageUrl: card.imageUrl,
                  axes: card.axes,
                ),
              ),
        if (score != null) ...[
          const SizedBox(height: 6),
          Text('$score', style: display(22, color: Colors.white)),
        ],
        if (modifiers.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: modifiers
                .map(
                  (m) => Text(
                    '${m.label} +${m.value}',
                    style: label(color: AppColors.orangeBright, size: 8),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _controls(DuelViewModel duel) {
    if (_controller.presentation.busy) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(14, 8, 14, 16),
        child: Text(
          'Reveal in progress…',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF9BB7A8), fontSize: 12),
        ),
      );
    }
    if (duel.phase == DuelPhase.roundComplete) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
        child: PrimaryButton(
          'Next round',
          expand: true,
          busy: _controller.busy,
          onTap: _controller.acknowledgeRound,
        ),
      );
    }
    if (duel.phase == DuelPhase.axisSelection && duel.yourTurn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _axes
                  .map(
                    (axis) => ChoiceChip(
                      selected: _controller.selectedAxis == axis,
                      label: Text(axis.toUpperCase()),
                      onSelected: (_) => _controller.chooseLocalAxis(axis),
                      selectedColor: AppColors.orange,
                      labelStyle: label(color: Colors.white, size: 9),
                      backgroundColor: const Color(0xFF10251C),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              'Lock attribute',
              expand: true,
              busy: _controller.busy,
              onTap: _controller.chooseAxis,
            ),
          ],
        ),
      );
    }
    if (duel.phase == DuelPhase.cardSelection) {
      final available = duel.yourHand
          .where((card) => !duel.usedCardIds.contains(card.id))
          .toList();
      final skills = widget.skills
          .where((skill) => !duel.usedSkillIds.contains(skill.id))
          .toList();
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
        child: Column(
          children: [
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: available.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final card = available[index];
                  final selected = _controller.selectedCardId == card.id;
                  return GestureDetector(
                    onTap: () => _controller.selectCard(card.id),
                    child: SizedBox(
                      width: 84,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppColors.orangeBright
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: GyroTiltCard(
                          motion: _motion,
                          intensity: 0,
                          enableTilt: false,
                          rarity: 3,
                          seed: cardSeed('${card.id}|hand'),
                          borderColor: teamColor(card.teamCode),
                          child: DuelPlayerCardFace(
                            playerId: card.playerId ?? '',
                            name: card.name,
                            teamCode: card.teamCode,
                            position: card.position,
                            imageUrl: card.imageUrl,
                            axes: card.axes,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (skills.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ChoiceChip(
                      selected: _controller.selectedSkillId == null,
                      label: const Text('No skill'),
                      onSelected: (_) => _controller.selectSkill(null),
                      selectedColor: AppColors.orange,
                      labelStyle: label(color: Colors.white, size: 9),
                      backgroundColor: const Color(0xFF10251C),
                    ),
                    ...skills.map(
                      (skill) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          selected: _controller.selectedSkillId == skill.id,
                          label: Text(skill.name),
                          onSelected: (_) => _controller.selectSkill(skill.id),
                          selectedColor: AppColors.orange,
                          labelStyle: label(color: Colors.white, size: 9),
                          backgroundColor: const Color(0xFF10251C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (duel.youSubmitted)
              Text(
                'Card locked — waiting for opponent',
                style: body(color: AppColors.mutInk, size: 12),
              )
            else
              PrimaryButton(
                'Play card',
                expand: true,
                busy: _controller.busy,
                onTap: _controller.selectedCardId == null
                    ? null
                    : _controller.submitCard,
              ),
            if (_controller.error != null) ...[
              const SizedBox(height: 6),
              Text(
                _controller.error!,
                style: body(color: const Color(0xFFFF8A80), size: 11),
              ),
            ],
          ],
        ),
      );
    }
    return const SizedBox(height: 16);
  }

  Widget _finishedPanel(DuelViewModel duel) {
    final won = duel.winnerId == duel.fanId;
    final draw = duel.winnerId == null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xF216251F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF315C48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            draw
                ? 'HONEST DRAW'
                : won
                ? 'VICTORY'
                : 'DEFEAT',
            textAlign: TextAlign.center,
            style: display(26, color: Colors.white),
          ),
          const SizedBox(height: 8),
          ...duel.rounds.map(
            (round) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'R${round.round} ${round.axis} · ${round.yourScore ?? '—'}–${round.opponentScore ?? '—'}'
                '${round.autoPlayed ? ' · auto' : ''}',
                style: body(color: AppColors.mutInk, size: 11),
              ),
            ),
          ),
          if (duel.houseCommitment != null) ...[
            const SizedBox(height: 6),
            Text(
              'House commitment ${duel.houseCommitment!.substring(0, duel.houseCommitment!.length.clamp(0, 12))}…',
              style: label(color: AppColors.cream, size: 8),
            ),
          ],
          if (duel.arena?.proof != null) ...[
            const SizedBox(height: 4),
            Text(
              'Moment proof verified',
              style: label(color: const Color(0xFF4ED58A), size: 9),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  'Share',
                  expand: true,
                  onTap: () => Share.share(
                    'Final Whistle ${duel.mode.name} duel ${draw
                        ? 'drew'
                        : won
                        ? 'won'
                        : 'lost'} ${duel.yourScore}-${duel.opponentScore}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  'Rematch',
                  expand: true,
                  busy: _controller.busy,
                  onTap: _controller.rematch,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GhostButton(
            'Back to Arena',
            expand: true,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
