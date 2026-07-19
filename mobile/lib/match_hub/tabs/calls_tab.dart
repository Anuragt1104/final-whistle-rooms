import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme.dart';
import '../../widgets/next_swing_card.dart';
import '../../widgets/ticket.dart';
import '../models.dart';
import '../palette.dart';

class CallsTab extends StatefulWidget {
  final MatchHubViewState state;
  final RoomView room;
  final Map<String, String> myPicks;
  final String? mySide;
  final bool showDraft;
  final void Function(String side)? onPickSide;
  final void Function(String promptId, String optionKey)? onPick;
  final VoidCallback? onShare;

  const CallsTab({
    super.key,
    required this.state,
    required this.room,
    required this.myPicks,
    this.mySide,
    this.showDraft = false,
    this.onPickSide,
    this.onPick,
    this.onShare,
  });

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = widget.state;
    final room = widget.room;
    final open = [
      if (s.activeCall != null) s.activeCall!,
      if (s.quickCall != null) s.quickCall!,
    ];

    return CustomScrollView(
      key: const PageStorageKey('hub_calls'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                'LIVE CALLS',
                style: label(color: AppColors.orange, size: 11, weight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'POINTS ONLY',
                style: label(color: AppColors.mutInk, size: 9),
              ),
              const SizedBox(height: 12),
              if (widget.showDraft && widget.onPickSide != null)
                _draftPicker(room)
              else if (widget.mySide != null)
                _draftLocked(room, widget.mySide!),
              if (s.callsPaused) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: HubColors.stadiumLift,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    s.callsPausedReason ??
                        'Calls paused while match data reconnects.',
                    style: body(color: HubColors.stale, size: 12.5),
                  ),
                ),
              ],
              if (room.modes.nextSwing && widget.onPick != null) ...[
                const SizedBox(height: 12),
                NextSwingCard(
                  prompts: open.isEmpty && s.settledCalls.isEmpty
                      ? room.prompts
                      : [...open, ...s.settledCalls.take(5)],
                  myPicks: widget.myPicks,
                  onPick: s.callsPaused ? (_, __) {} : widget.onPick!,
                  streak: s.myGame.streak,
                  bestStreak: s.myGame.bestStreak,
                  onShare: widget.onShare,
                ),
              ],
              const SizedBox(height: 16),
              _accuracy(s.myGame),
              if (s.activeCall?.reason != null ||
                  s.activeCall?.rewardPreview != null) ...[
                const SizedBox(height: 12),
                _callMeta(s.activeCall!),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _draftPicker(RoomView room) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HubColors.stadiumLift,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('TEAM DRAFT', style: label(color: AppColors.mutInk, size: 10)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _sideBtn(room.fixture.home, 'home')),
                const SizedBox(width: 10),
                Expanded(child: _sideBtn(room.fixture.away, 'away')),
              ],
            ),
          ],
        ),
      );

  Widget _sideBtn(Team team, String side) => InkWell(
        onTap: () => widget.onPickSide?.call(side),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lineInk),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              TeamBadge(team: team, size: 36),
              const SizedBox(height: 6),
              Text(team.code, style: display(16, color: AppColors.cream)),
            ],
          ),
        ),
      );

  Widget _draftLocked(RoomView room, String side) {
    final team = side == 'away' ? room.fixture.away : room.fixture.home;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HubColors.stadiumLift,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          TeamBadge(team: team, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TEAM DRAFT', style: label(color: AppColors.mutInk, size: 9)),
                Text(team.name, style: body(color: AppColors.cream, weight: FontWeight.w800)),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: AppColors.orange, size: 20),
        ],
      ),
    );
  }

  Widget _accuracy(MatchHubMyGameSummary g) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HubColors.stadiumLift,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ACCURACY', style: label(color: AppColors.mutInk, size: 9)),
                  Text(
                    g.answered == 0
                        ? '—'
                        : '${((g.correct / g.answered) * 100).round()}%',
                    style: display(28, color: AppColors.cream),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${g.streak} streak', style: body(color: AppColors.orange, size: 13)),
                Text('best ${g.bestStreak}', style: body(color: AppColors.mutInk, size: 12)),
              ],
            ),
          ],
        ),
      );

  Widget _callMeta(PromptView p) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HubColors.stadiumLift,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.reason != null)
              Text(p.reason!, style: body(color: AppColors.cream, size: 12.5)),
            if (p.rewardPreview != null) ...[
              const SizedBox(height: 6),
              Text(
                p.rewardPreview!,
                style: label(color: HubColors.lime, size: 10),
              ),
            ],
            if (p.answerClosesAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Closes at ${DateTime.fromMillisecondsSinceEpoch(p.answerClosesAt!).toLocal()}',
                style: body(color: AppColors.mutInk, size: 11),
              ),
            ],
          ],
        ),
      );
}
