import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

/// Exact-image-only portrait. Without a curated ID-bound image, render a
/// polished team-coloured illustration instead of guessing by surname.
class PlayerAvatar extends StatelessWidget {
  final Team team;
  final String name;
  final String? imageUrl;
  final double size;
  final Color? ringColor;
  const PlayerAvatar({
    super.key,
    required this.team,
    required this.name,
    this.imageUrl,
    this.size = 34,
    this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    final ring = ringColor ?? teamColor(team.code);
    final fallback = Container(
      color: Color.lerp(AppColors.ink, ring, .34),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -size * .16,
            top: -size * .16,
            child: Icon(
              Icons.sports_soccer_rounded,
              size: size * .8,
              color: Colors.white.withValues(alpha: .12),
            ),
          ),
          InitialAvatar(name: name, size: size),
        ],
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: size >= 40 ? 2 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null || imageUrl!.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            ),
    );
  }
}
