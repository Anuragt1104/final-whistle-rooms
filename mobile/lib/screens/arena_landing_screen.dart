import 'package:flutter/material.dart';

import '../api/cards.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gyro_card.dart';

class ArenaLandingScreen extends StatefulWidget {
  final List<PlayerCardModel> players;
  final List<MomentCard> moments;
  final List<SkillCardModel> skills;
  final ValueChanged<int> onStartMode;
  final VoidCallback onOpenCards;

  const ArenaLandingScreen({
    super.key,
    required this.players,
    required this.moments,
    required this.skills,
    required this.onStartMode,
    required this.onOpenCards,
  });

  @override
  State<ArenaLandingScreen> createState() => _ArenaLandingScreenState();
}

class _ArenaLandingScreenState extends State<ArenaLandingScreen> {
  final CardMotionController _motion = CardMotionController();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  bool get _ready => widget.players.length >= 3;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: CustomScrollView(
      key: const PageStorageKey('arena-scroll'),
      slivers: [
        SliverToBoxAdapter(child: _hero()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          sliver: SliverToBoxAdapter(child: _hand()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              'CHOOSE YOUR ARENA',
              style: label(
                color: StadiumColors.text,
                size: 12,
                weight: FontWeight.w900,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          sliver: SliverList.list(
            children: [
              _mode(
                mode: 0,
                eyebrow: 'SOLO · FAST',
                title: 'HOUSE DUEL',
                description:
                    'Challenge the committed House hand. Pick the Axis when you attack.',
                accent: StadiumColors.orange,
                icon: Icons.stadium_rounded,
              ),
              const SizedBox(height: 10),
              _mode(
                mode: 1,
                eyebrow: 'PRIVATE · LIVE',
                title: 'FRIEND DUEL',
                description:
                    'Share an invite and play three tactical Rounds against a friend.',
                accent: StadiumColors.violet,
                icon: Icons.group_rounded,
              ),
              const SizedBox(height: 10),
              _mode(
                mode: 2,
                eyebrow: 'FEATURED · VERIFIED',
                title: 'MOMENT ARENA',
                description: widget.moments.isEmpty
                    ? 'Earn a Moment in a Match Hub to unlock its verified Arena.'
                    : 'Seed the Duel with one of your Moments and prove its Lineage.',
                accent: StadiumColors.lime,
                icon: Icons.bolt_rounded,
              ),
              const SizedBox(height: 18),
              _rules(),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _hero() => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    height: 208,
    clipBehavior: Clip.antiAlias,
    decoration: stadiumGradientPanel(accent: StadiumColors.lime),
    child: Stack(
      children: [
        const Positioned.fill(child: _PitchPainter()),
        Positioned(
          top: -56,
          right: -32,
          child: Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  StadiumColors.violet.withValues(alpha: .35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _statusPill(_ready ? 'HAND READY' : 'BUILD YOUR HAND'),
                  const Spacer(),
                  Text(
                    'BEST OF 3',
                    style: label(color: StadiumColors.muted, size: 9),
                  ),
                ],
              ),
              const Spacer(),
              Text('THE ARENA', style: display(36, color: StadiumColors.text)),
              const SizedBox(height: 7),
              SizedBox(
                width: 270,
                child: Text(
                  'Your Moments built the Hand. Now make the right call when the floodlights hit.',
                  style: body(color: StadiumColors.textSoft, size: 12.5),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _statusPill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: (_ready ? StadiumColors.lime : StadiumColors.amber).withValues(
        alpha: .14,
      ),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(
        color: (_ready ? StadiumColors.lime : StadiumColors.amber).withValues(
          alpha: .55,
        ),
      ),
    ),
    child: Text(
      text,
      style: label(
        color: _ready ? StadiumColors.lime : StadiumColors.amber,
        size: 8.5,
        weight: FontWeight.w900,
      ),
    ),
  );

  Widget _hand() => Container(
    padding: const EdgeInsets.all(16),
    decoration: stadiumPanel(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR HAND',
                    style: label(
                      color: StadiumColors.text,
                      size: 11,
                      weight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _ready
                        ? 'Three Player Cards ready for the tunnel.'
                        : 'Build your hand with three Player Cards.',
                    style: body(color: StadiumColors.muted, size: 11.5),
                  ),
                ],
              ),
            ),
            if (!_ready)
              TextButton(
                onPressed: widget.onOpenCards,
                child: const Text('Open Cards'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final player = index < widget.players.length
                ? widget.players[index]
                : null;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
                child: AspectRatio(
                  aspectRatio: 2.5 / 3.5,
                  child: player == null
                      ? _emptySlot(index)
                      : GyroTiltCard(
                          motion: _motion,
                          intensity: 0,
                          enableTilt: false,
                          rarity: 3,
                          seed: cardSeed('${player.id}|arena-hand'),
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
              ),
            );
          }),
        ),
        if (widget.skills.isNotEmpty) ...[
          const SizedBox(height: 11),
          Text(
            '${widget.skills.take(3).map((skill) => skill.name).join(' · ')} equipped',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: label(color: StadiumColors.violet, size: 8.5),
          ),
        ],
      ],
    ),
  );

  Widget _emptySlot(int index) => InkWell(
    onTap: widget.onOpenCards,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      decoration: BoxDecoration(
        color: StadiumColors.canvasRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StadiumColors.hairline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '0${index + 1}',
            style: display(20, color: StadiumColors.hairline),
          ),
          const SizedBox(height: 5),
          const Icon(Icons.add_rounded, color: StadiumColors.muted, size: 20),
        ],
      ),
    ),
  );

  Widget _mode({
    required int mode,
    required String eyebrow,
    required String title,
    required String description,
    required Color accent,
    required IconData icon,
  }) {
    final unlocked = _ready && (mode != 2 || widget.moments.isNotEmpty);
    return Pressable(
      haptic: HapticFeedbackType.medium,
      onTap: unlocked ? () => widget.onStartMode(mode) : widget.onOpenCards,
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(15),
        decoration: stadiumGradientPanel(accent: accent, radius: 18),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 64,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: accent.withValues(alpha: .42)),
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow, style: label(color: accent, size: 8.5)),
                  const SizedBox(height: 4),
                  Text(title, style: display(20, color: StadiumColors.text)),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: body(color: StadiumColors.muted, size: 11),
                  ),
                ],
              ),
            ),
            Icon(
              unlocked ? Icons.arrow_forward_rounded : Icons.lock_outline,
              color: unlocked ? accent : StadiumColors.muted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _rules() => Container(
    padding: const EdgeInsets.all(15),
    decoration: stadiumPanel(color: StadiumColors.canvasRaised),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HOW A DUEL FLOWS',
          style: label(
            color: StadiumColors.text,
            size: 10,
            weight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        _rule('01', 'Lock a Hand of three Player Cards.'),
        _rule('02', 'The Attacker chooses the Axis.'),
        _rule('03', 'Cards reveal, modifiers land, higher score wins.'),
        _rule('04', 'First Fan to two Round wins takes the Duel.'),
      ],
    ),
  );

  Widget _rule(String number, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text(number, style: display(13, color: StadiumColors.orange)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: body(color: StadiumColors.textSoft)),
        ),
      ],
    ),
  );
}

class _PitchPainter extends StatelessWidget {
  const _PitchPainter();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PitchLines());
}

class _PitchLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = StadiumColors.lime.withValues(alpha: .07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rect = Rect.fromLTWH(18, 18, size.width - 36, size.height - 36);
    canvas.drawRect(rect, paint);
    canvas.drawLine(
      Offset(size.width / 2, rect.top),
      Offset(size.width / 2, rect.bottom),
      paint,
    );
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 34, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
