import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/cards.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gyro_card.dart';

class CardDetailScreen extends StatefulWidget {
  final MomentCard? moment;
  final PlayerCardModel? player;
  final VoidCallback? onVerify;
  final VoidCallback? onPrimary;
  final String? primaryLabel;

  const CardDetailScreen.moment(this.moment, {super.key, this.onVerify})
    : player = null,
      onPrimary = null,
      primaryLabel = null;
  const CardDetailScreen.player(
    this.player, {
    super.key,
    this.onPrimary,
    this.primaryLabel,
  }) : moment = null,
       onVerify = null;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  final CardMotionController _motion = CardMotionController();

  @override
  void initState() {
    super.initState();
    _motion.start();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.moment;
    final p = widget.player;
    final accent = m != null
        ? rarityBorder(m.rarity)
        : teamColor(p?.teamCode ?? '');
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
                            child: m != null
                                ? MomentCardFace(
                                    title: m.label,
                                    matchLabel: m.matchLabel,
                                    kind: m.kind,
                                    rarity: m.rarity,
                                    minute: m.minute,
                                    calledIt: m.calledIt,
                                    imageUrl: m.imageUrl,
                                    playerName: m.playerName,
                                    teamCode: m.teamCode,
                                    artKey: m.artKey,
                                  )
                                : PlayerCardFace(
                                    name: p!.name,
                                    teamCode: p.teamCode,
                                    position: p.position,
                                    imageUrl: p.imageUrl,
                                    axes: p.axes,
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
                          'TILT YOUR PHONE',
                          style: label(
                            color: AppColors.orangeBright,
                            size: 10,
                            weight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Foil, depth and light move with the device. Drag the card in an emulator.',
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
}
