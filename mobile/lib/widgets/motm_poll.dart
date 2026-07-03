import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';
import 'player_avatar.dart';

class MotmPollCard extends StatelessWidget {
  final MotmPoll poll;
  final Fixture fixture;
  final void Function(String key) onVote;
  const MotmPollCard({super.key, required this.poll, required this.fixture, required this.onVote});

  Team _teamOf(MotmCandidate c) => c.teamCode == fixture.away.code ? fixture.away : fixture.home;

  @override
  Widget build(BuildContext context) {
    final total = poll.totalVotes <= 0 ? 1 : poll.totalVotes;
    final leaderKey = poll.candidates.isEmpty
        ? ''
        : poll.candidates.reduce((a, b) => a.votes >= b.votes ? a : b).key;
    final voted = poll.myVote != null;

    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Man of the match', style: display(18)),
          const Spacer(),
          Text('${poll.totalVotes} votes', style: body(color: AppColors.mut, size: 12)),
        ]),
        const SizedBox(height: 12),
        ...poll.candidates.map((c) {
          final frac = (c.votes / total).clamp(0.0, 1.0);
          final pct = (frac * 100).round();
          final mine = poll.myVote == c.key;
          final lead = c.key == leaderKey;
          final fill = mine ? AppColors.orange : (lead ? AppColors.orange.withValues(alpha: 0.85) : AppColors.ink.withValues(alpha: 0.18));
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Pressable(
              haptic: HapticFeedbackType.selection,
              onTap: voted ? null : () => onVote(c.key),
              child: Stack(children: [
                // animated fill bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 44,
                    color: AppColors.cardAlt,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: frac),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => FractionallySizedBox(widthFactor: v, child: Container(color: fill)),
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: mine ? AppColors.orange : AppColors.line)),
                  child: Row(children: [
                    PlayerAvatar(team: _teamOf(c), name: c.name, size: 30),
                    const SizedBox(width: 8),
                    Text(c.name, style: body(size: 14, weight: FontWeight.w800, color: (mine || lead) ? Colors.white : AppColors.ink)),
                    const SizedBox(width: 6),
                    Text(c.teamCode, style: label(color: (mine || lead) ? Colors.white70 : AppColors.mut, size: 9)),
                    if (mine) ...[const SizedBox(width: 6), const Icon(Icons.check_circle, color: Colors.white, size: 15)],
                    const Spacer(),
                    Text('$pct%', style: body(size: 13, weight: FontWeight.w800, color: (mine || lead) ? Colors.white : AppColors.ink)),
                  ]),
                ),
              ]),
            ),
          );
        }),
        if (!voted)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Tap to cast your vote', style: body(color: AppColors.mut, size: 11.5)),
          ),
      ]),
    );
  }
}
