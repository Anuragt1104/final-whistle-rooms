import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/ticket.dart';
import '../models.dart';
import '../palette.dart';

class MatchHubHeader extends StatelessWidget {
  final MatchHubHeaderState header;
  final TeamPalette palette;
  final bool expanded;
  final VoidCallback? onBack;
  final void Function(Team team)? onTeamTap;
  final VoidCallback? onNotifyTap;
  final VoidCallback? onSourceTap;

  const MatchHubHeader({
    super.key,
    required this.header,
    required this.palette,
    required this.expanded,
    this.onBack,
    this.onTeamTap,
    this.onNotifyTap,
    this.onSourceTap,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: (expanded ? 240.0 : 72.0) + top,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.lerp(palette.home, HubColors.stadium, 0.35)!,
            HubColors.stadium,
            Color.lerp(palette.away, HubColors.stadium, 0.35)!,
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
      child: expanded ? _expanded(top) : _collapsed(top),
    );
  }

  Widget _collapsed(double top) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, top + 4, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.cream),
          ),
          _pill(header.lifecycleBadge),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${header.home.code} ${header.scoreText} ${header.away.code}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: display(18, color: AppColors.cream),
              textAlign: TextAlign.center,
            ),
          ),
          Text(
            header.clockText,
            style: label(color: AppColors.mutInk, size: 10),
          ),
        ],
      ),
    );
  }

  Widget _expanded(double top) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, top + 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.cream),
              ),
              Expanded(
                child: Text(
                  header.competition.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: label(color: AppColors.mutInk, size: 10),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: onNotifyTap,
                icon: Icon(
                  header.notifyOn
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  color: AppColors.cream,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: _team(header.home, palette.home, onTap: () => onTeamTap?.call(header.home))),
              Column(
                children: [
                  _pill(header.lifecycleBadge),
                  const SizedBox(height: 6),
                  Text(
                    header.scoreText,
                    style: display(36, color: AppColors.orangeBright),
                  ),
                  Text(
                    header.clockText,
                    style: label(
                      color: header.clockFrozen ? HubColors.stale : AppColors.mutInk,
                      size: 11,
                    ),
                  ),
                  const SizedBox(height: 5),
                  GestureDetector(
                    onTap: onSourceTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: StadiumColors.mint.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: StadiumColors.mint.withValues(alpha: .32),
                        ),
                      ),
                      child: Text(
                        'VERIFIED BY TxLINE',
                        style: label(color: StadiumColors.mint, size: 7.5),
                      ),
                    ),
                  ),
                  if (header.freezeReason != null)
                    Text(
                      header.freezeReason!,
                      style: body(color: HubColors.stale, size: 10),
                    ),
                ],
              ),
              Expanded(child: _team(header.away, palette.away, onTap: () => onTeamTap?.call(header.away))),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Icon(Icons.visibility_rounded, size: 14, color: AppColors.mutInk),
              const SizedBox(width: 4),
              Text(
                '${header.watching} watching',
                style: body(color: AppColors.mutInk, size: 11),
              ),
              const Spacer(),
              if (header.latestEventRibbon != null)
                Flexible(
                  child: Text(
                    header.latestEventRibbon!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(color: AppColors.cream, size: 11),
                    textAlign: TextAlign.right,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _team(Team team, Color flood, {VoidCallback? onTap}) {
    return Pressable(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: flood.withValues(alpha: 0.28),
              shape: BoxShape.circle,
            ),
            child: TeamBadge(team: team, size: 40),
          ),
          const SizedBox(height: 6),
          Text(
            team.code,
            style: display(16, color: AppColors.cream),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    final live = const {'LIVE', 'EXTRA TIME', 'PENALTIES'}.contains(text);
    final replay = text == 'REPLAY';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: live
            ? AppColors.orange
            : (replay ? AppColors.gold : AppColors.inkSoft),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: label(color: AppColors.cream, size: 9, weight: FontWeight.w800),
      ),
    );
  }
}
