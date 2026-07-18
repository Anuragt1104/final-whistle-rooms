import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/cards.dart';
import '../data/player_portraits.dart';
import '../state/local_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gyro_card.dart';

class CardDetailScreen extends StatefulWidget {
  final MomentCard? moment;
  final PlayerCardModel? player;
  final SkillCardModel? skill;
  final VoidCallback? onVerify;
  final VoidCallback? onPrimary;
  final String? primaryLabel;

  const CardDetailScreen.moment(this.moment, {super.key, this.onVerify})
    : player = null,
      skill = null,
      onPrimary = null,
      primaryLabel = null;
  const CardDetailScreen.player(
    this.player, {
    super.key,
    this.onPrimary,
    this.primaryLabel,
  }) : moment = null,
       skill = null,
       onVerify = null;
  const CardDetailScreen.skill(this.skill, {super.key})
    : moment = null,
      player = null,
      onVerify = null,
      onPrimary = null,
      primaryLabel = null;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  final CardMotionController _motion = CardMotionController();
  bool _reduceParallax = false;
  bool _motionDiscovered = false;

  @override
  void initState() {
    super.initState();
    _motion.addListener(_onMotion);
    LocalStore.reducedMotion().then((v) {
      if (mounted) setState(() => _reduceParallax = v);
    });
  }

  void _onMotion() {
    if (!_motionDiscovered && _motion.hasMoved && mounted) {
      setState(() => _motionDiscovered = true);
    }
  }

  @override
  void dispose() {
    _motion.removeListener(_onMotion);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.moment;
    final p = widget.player;
    final s = widget.skill;
    final accent = m != null
        ? rarityBorder(m.rarity)
        : p != null
        ? teamColor(p.teamCode)
        : const Color(0xFFB8FF36);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.35),
                    radius: 1.05,
                    colors: [
                      accent.withValues(alpha: 0.32),
                      AppColors.ink,
                      const Color(0xFF090B11),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 16, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          m != null
                              ? '${m.rarity}★ MOMENT'
                              : s != null
                              ? 'SKILL RELIC'
                              : 'PLAYER COLLECTIBLE',
                          style: label(
                            color: accent,
                            size: 11,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: AspectRatio(
                          aspectRatio: 2.5 / 3.5,
                          child: GyroTiltCard(
                            motion: _motion,
                            borderColor: accent,
                            intensity: 1.0,
                            enableTilt: true,
                            rarity: m?.rarity ?? 3,
                            seed: cardSeed(
                              m != null
                                  ? '${m.id}|${m.artKey ?? m.kind}'
                                  : p != null
                                  ? '${p.id}|${p.teamCode}'
                                  : '${s!.id}|${s.name}',
                            ),
                            foilAccent: m != null
                                ? kindAccent(m.kind)
                                : p != null
                                ? teamColor(p.teamCode)
                                : const Color(0xFFB8FF36),
                            reduceParallax: _reduceParallax,
                            frameShape: p != null
                                ? CardFrameShape.stadiumCrown
                                : CardFrameShape.relic,
                            child: m != null
                                ? MomentCardFace(
                                    title: m.label,
                                    matchLabel: m.matchLabel,
                                    kind: m.kind,
                                    rarity: m.rarity,
                                    minute: m.minute,
                                    calledIt: m.calledIt,
                                    imageUrl: m.imageUrl,
                                    playerId: m.playerId,
                                    playerName: m.playerName,
                                    teamCode: m.teamCode,
                                    artKey: m.artKey,
                                  )
                                : p != null
                                ? PlayerCardFace(
                                    playerId: p.playerId,
                                    name: p.name,
                                    teamCode: p.teamCode,
                                    position: p.position,
                                    imageUrl: p.imageUrl,
                                    axes: p.axes,
                                    frameShape: CardFrameShape.stadiumCrown,
                                  )
                                : SkillCardFace(
                                    name: s!.name,
                                    description: s.description,
                                    effect: s.effect,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                    child: Column(
                      children: [
                        Text(
                          _motionDiscovered
                              ? '3D RELIC ACTIVE'
                              : _motion.snapshot.availability ==
                                    CardMotionAvailability.unavailable
                              ? 'DRAG TO EXPLORE'
                              : 'TILT YOUR PHONE · OR DRAG',
                          style: label(
                            color: AppColors.orangeBright,
                            size: 10,
                            weight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _motionDiscovered
                              ? 'The stadium, subject, crest and foil now move at independent depths.'
                              : 'Move the card to reveal its stadium layers, physical edge and foil light.',
                          textAlign: TextAlign.center,
                          style: body(color: AppColors.mutInk, size: 12),
                        ),
                        if (m != null && widget.onVerify != null) ...[
                          const SizedBox(height: 16),
                          GhostButton(
                            'Verify Merkle proof',
                            expand: true,
                            onTap: widget.onVerify,
                          ),
                        ],
                        if (p != null && widget.onPrimary != null) ...[
                          const SizedBox(height: 16),
                          PrimaryButton(
                            widget.primaryLabel ?? 'Mint NFT',
                            expand: true,
                            onTap: widget.onPrimary,
                          ),
                        ],
                        if (portraitForPlayerId(p?.playerId ?? m?.playerId) !=
                            null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () =>
                                _showPhotoCredit(p?.playerId ?? m!.playerId!),
                            icon: const Icon(Icons.photo_outlined, size: 16),
                            label: const Text('PHOTO CREDIT'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPhotoCredit(String playerId) async {
    final all = await loadPortraitAttributions();
    final credit = all.where((item) => item.playerId == playerId).firstOrNull;
    if (!mounted || credit == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(credit.name),
        content: Text(
          '${credit.license}\n${credit.author}\n\n${credit.modified}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(credit.sourcePage),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('ORIGINAL SOURCE'),
          ),
        ],
      ),
    );
  }
}
