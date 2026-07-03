import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../data/player_images.dart';
import '../theme.dart';
import 'common.dart';

/// The one player face used everywhere: circular official photo (disk-cached)
/// with a team-color ring, degrading to an initials avatar. Self-warming — if
/// the team's photo index isn't built yet it kicks off the fetch and re-renders
/// the moment it lands, so surfaces can use it fire-and-forget.
class PlayerAvatar extends StatefulWidget {
  final Team team;
  final String name;
  final double size;
  final Color? ringColor;
  const PlayerAvatar({super.key, required this.team, required this.name, this.size = 34, this.ringColor});

  @override
  State<PlayerAvatar> createState() => _PlayerAvatarState();
}

class _PlayerAvatarState extends State<PlayerAvatar> {
  @override
  void initState() {
    super.initState();
    PlayerImages.addListener(_onWarm);
    PlayerImages.warm(widget.team.name);
  }

  @override
  void dispose() {
    PlayerImages.removeListener(_onWarm);
    super.dispose();
  }

  void _onWarm() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final url = PlayerImages.photoFor(widget.team.name, widget.name);
    final ring = widget.ringColor ?? teamColor(widget.team.code);
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: widget.size >= 40 ? 2 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? InitialAvatar(name: widget.name, size: widget.size)
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              placeholder: (_, _) => InitialAvatar(name: widget.name, size: widget.size),
              errorWidget: (_, _, _) => InitialAvatar(name: widget.name, size: widget.size),
            ),
    );
  }
}
