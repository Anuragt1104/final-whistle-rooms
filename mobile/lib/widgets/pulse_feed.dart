import 'package:flutter/material.dart';
import '../api/models.dart';
import '../local/players.dart';
import '../theme.dart';
import 'common.dart';
import 'player_avatar.dart';

class PulseFeed extends StatelessWidget {
  final List<PulseCard> pulse;
  final Fixture fixture;
  const PulseFeed({super.key, required this.pulse, required this.fixture});

  @override
  Widget build(BuildContext context) {
    if (pulse.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: cardBox(),
        child: Text(
          'The terrace lights up the moment the match kicks off — goals, cards, corners and odds swings, called out in plain English.',
          textAlign: TextAlign.center,
          style: body(color: AppColors.mut, size: 13),
        ),
      );
    }
    // Attribute team-level goal cards (backend live rooms carry no player) to a
    // real squad player, deterministically by goal index per side — so every
    // rebuild and every surface names the same scorer.
    final actorFor = <String, String>{};
    final goalCount = {'home': 0, 'away': 0};
    for (final c in pulse) {
      if (c.kind != 'goal') continue;
      final side = c.accent == 'away' ? 'away' : 'home';
      actorFor[c.id] = c.scorer ?? scorerName(fixture, side, goalCount[side]!);
      goalCount[side] = goalCount[side]! + 1;
    }
    final cards = pulse.reversed.toList();
    return Column(
      children: cards
          .map((c) => _PulseEntry(key: ValueKey(c.id), card: c, fixture: fixture, actor: actorFor[c.id] ?? c.scorer))
          .toList(),
    );
  }
}

/// Each card slides + fades in once when it first appears (keyed by id).
class _PulseEntry extends StatefulWidget {
  final PulseCard card;
  final Fixture fixture;
  final String? actor;
  const _PulseEntry({super.key, required this.card, required this.fixture, this.actor});
  @override
  State<_PulseEntry> createState() => _PulseEntryState();
}

class _PulseEntryState extends State<_PulseEntry> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 360))..forward();
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Team _sideTeam(PulseCard c) => c.accent == 'away' ? widget.fixture.away : widget.fixture.home;

  @override
  Widget build(BuildContext context) {
    // NOTE: no SizeTransition here — it measures children with unbounded height,
    // which breaks Columns/stretch rows in the tiles. Fade + slide are paint-only.
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(_a),
        child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _tile(widget.card)),
      ),
    );
  }

  Widget _tile(PulseCard c) {
    if (c.kind == 'goal') {
      final scorer = widget.actor ?? c.scorer;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          if (scorer != null) ...[
            PlayerAvatar(team: _sideTeam(c), name: scorer, size: 44, ringColor: AppColors.orangeBright),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('GOAL', style: display(19, color: AppColors.orangeBright)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scorer != null ? "$scorer  ${c.minute}'" : c.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(color: AppColors.cream, size: 14, weight: FontWeight.w800),
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              Text(c.detail, style: body(color: AppColors.mutInk, size: 12.5, weight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(width: 6),
          Text("${c.minute}'", style: label(color: AppColors.mutInk, size: 10)),
        ]),
      );
    }
    final actor = widget.actor ?? c.scorer;
    return Container(
      decoration: cardBox(),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 5,
          decoration: BoxDecoration(
            color: accentColor(c.accent),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), bottomLeft: Radius.circular(18)),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // the face makes the event — avatar with a tiny emoji badge when
              // we know who's involved; plain emoji otherwise
              if (actor != null && (c.accent == 'home' || c.accent == 'away'))
                SizedBox(
                  width: 36,
                  height: 34,
                  child: Stack(clipBehavior: Clip.none, children: [
                    PlayerAvatar(team: _sideTeam(c), name: actor, size: 32),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Text(c.emoji, style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
                )
              else
                Text(c.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(c.headline, style: body(weight: FontWeight.w800, size: 13.5))),
                    Text("${c.minute}'", style: label(color: AppColors.mut, size: 10)),
                  ]),
                  const SizedBox(height: 2),
                  Text(c.detail, style: body(color: AppColors.mut, size: 12.5)),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
