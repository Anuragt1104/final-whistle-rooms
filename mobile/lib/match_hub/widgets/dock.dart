import 'package:flutter/material.dart';

import '../../theme.dart';
import '../models.dart';
import '../palette.dart';

class PersistentMatchDock extends StatelessWidget {
  final MatchHubUnreadCounts unread;
  final bool visible;
  final bool officialHub;
  final VoidCallback onReact;
  final VoidCallback onCalls;
  final VoidCallback onFans;
  final VoidCallback onRewards;
  final ValueChanged<String>? onSendChat;
  final List<String> reactionEmojis;

  const PersistentMatchDock({
    super.key,
    required this.unread,
    required this.visible,
    required this.officialHub,
    required this.onReact,
    required this.onCalls,
    required this.onFans,
    required this.onRewards,
    this.onSendChat,
    this.reactionEmojis = const ['🔥', '😱', '👏', '⚽'],
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1.2),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: Material(
        color: HubColors.stadiumLift,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68 + (officialHub ? 0 : 0),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, 6, 8, 4 + (bottom > 0 ? 0 : 4)),
              child: Row(
                children: [
                  _item(
                    icon: Icons.emoji_emotions_outlined,
                    label: 'React',
                    onTap: onReact,
                  ),
                  _item(
                    icon: Icons.bolt_rounded,
                    label: 'Calls',
                    badge: unread.calls,
                    accent: AppColors.orange,
                    onTap: onCalls,
                  ),
                  _item(
                    icon: Icons.groups_rounded,
                    label: 'Fans',
                    badge: unread.fans,
                    onTap: onFans,
                  ),
                  _item(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Rewards',
                    badge: unread.rewards,
                    accent: HubColors.lime,
                    onTap: onRewards,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int badge = 0,
    Color? accent,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: accent ?? AppColors.cream, size: 22),
                  if (badge > 0)
                    Positioned(
                      right: -10,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: accent ?? AppColors.orange,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          style: labelStyle(color: AppColors.cream, size: 8),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(label, style: labelStyle(color: AppColors.mutInk, size: 9)),
            ],
          ),
        ),
      ),
    );
  }

  // Avoid clashing with theme `label` helper name in scope.
  TextStyle labelStyle({required Color color, required double size}) => TextStyle(
    fontFamily: kBody,
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );
}
