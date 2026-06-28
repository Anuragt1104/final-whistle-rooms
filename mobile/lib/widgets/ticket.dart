import 'package:flutter/material.dart';
import '../api/models.dart';
import '../data/flags.dart';
import '../theme.dart';
import 'common.dart';
import 'live_match.dart';

/// Torn-ticket bottom edge (rounded top corners + sawtooth bottom).
class TicketClipper extends CustomClipper<Path> {
  final double radius;
  final double tooth;
  TicketClipper({this.radius = 18, this.tooth = 9});

  @override
  Path getClip(Size s) {
    final p = Path();
    p.moveTo(0, radius);
    p.quadraticBezierTo(0, 0, radius, 0);
    p.lineTo(s.width - radius, 0);
    p.quadraticBezierTo(s.width, 0, s.width, radius);
    p.lineTo(s.width, s.height - tooth);
    final n = (s.width / 18).round().clamp(6, 40);
    final step = s.width / n;
    double x = s.width;
    for (var i = 0; i < n; i++) {
      p.lineTo(x - step / 2, s.height);
      p.lineTo(x - step, s.height - tooth);
      x -= step;
    }
    p.lineTo(0, radius);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Real country flag (circular) with a colored-badge fallback for unknown nations.
class TeamBadge extends StatelessWidget {
  final Team team;
  final double size;
  const TeamBadge({super.key, required this.team, this.size = 46});
  @override
  Widget build(BuildContext context) => CircleFlag(team: team, size: size);
}

class TicketScoreboard extends StatelessWidget {
  final Team home, away;
  final String? score; // "2 - 1" ; null => VS
  final String? minute; // "67'" under score (fallback when no live clock)
  final int? clockSeconds; // live match clock — ticks every second when running
  final bool clockRunning;
  final String league;
  final String? pill; // "LIVE" / "FULL TIME"
  final Color pillColor;
  final int? watching;
  final VoidCallback? onBack;
  final void Function(Team team)? onTeamTap; // tap a badge -> team/squad sheet
  final List<String> scorers; // optional under score
  final bool tall;
  final double topRadius;
  final double topInset;

  const TicketScoreboard({
    super.key,
    required this.home,
    required this.away,
    required this.league,
    this.score,
    this.minute,
    this.clockSeconds,
    this.clockRunning = false,
    this.onTeamTap,
    this.pill,
    this.pillColor = AppColors.orange,
    this.watching,
    this.onBack,
    this.scorers = const [],
    this.tall = false,
    this.topRadius = 18,
    this.topInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: TicketClipper(radius: topRadius),
      child: Container(
        color: AppColors.ink,
        padding: EdgeInsets.fromLTRB(16, 14 + topInset, 16, tall ? 30 : 22),
        child: Column(children: [
          Row(children: [
            if (onBack != null)
              Pressable(
                haptic: HapticFeedbackType.selection,
                onTap: onBack,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: AppColors.inkSoft, borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.chevron_left, color: AppColors.cream, size: 20),
                ),
              )
            else
              const SizedBox(width: 30),
            const Spacer(),
            if (pill != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: pillColor, borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (pill == 'LIVE')
                    Container(
                      width: 6, height: 6,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    ),
                  Text(pill!, style: label(color: Colors.white, size: 10.5, weight: FontWeight.w800)),
                ]),
              ),
            const Spacer(),
            SizedBox(
              width: 44,
              child: watching != null
                  ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      const Icon(Icons.visibility_outlined, size: 13, color: AppColors.mutInk),
                      const SizedBox(width: 3),
                      Text(_compact(watching!), style: label(color: AppColors.mutInk, size: 10.5)),
                    ])
                  : const SizedBox(),
            ),
          ]),
          const SizedBox(height: 12),
          Text(league.toUpperCase(),
              textAlign: TextAlign.center, style: label(color: AppColors.mutInk, size: 10.5)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: _side(home)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              // score pops with an elastic bounce whenever it changes (a goal!)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Text(score ?? 'VS',
                    key: ValueKey(score ?? 'VS'),
                    style: display(score != null ? 46 : 30, color: AppColors.orangeBright, spacing: 1)),
              ),
              if (clockRunning && clockSeconds != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppColors.orange, borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 5, height: 5,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    ),
                    LiveClock(
                      clockSeconds: clockSeconds!,
                      running: clockRunning,
                      style: label(color: Colors.white, size: 11, weight: FontWeight.w800),
                    ),
                  ]),
                ),
              ] else if (minute != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppColors.inkSoft, borderRadius: BorderRadius.circular(99)),
                  child: Text(minute!, style: label(color: AppColors.cream, size: 10)),
                ),
              ],
            ]),
            Expanded(child: _side(away)),
          ]),
          if (scorers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 2,
              children: scorers
                  .map((s) => Text(s, style: body(color: AppColors.mutInk, size: 11.5, weight: FontWeight.w600)))
                  .toList(),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _side(Team t) {
    final col = Column(children: [
      TeamBadge(team: t, size: 48),
      const SizedBox(height: 8),
      Text(t.name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: display(15, color: AppColors.cream, spacing: 0.4)),
      if (onTeamTap != null)
        Text('squad ›', style: label(color: AppColors.mutInk, size: 8)),
    ]);
    if (onTeamTap == null) return col;
    return Pressable(haptic: HapticFeedbackType.selection, onTap: () => onTeamTap!(t), child: col);
  }

  static String _compact(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    return '$n';
  }
}

/// Small "mini scoreboard" badge used in room/fixture list rows.
class MiniScore extends StatelessWidget {
  final String top; // score "2-1" or time "20:00"
  final String bottom; // minute "67'" or "UCL"
  const MiniScore({super.key, required this.top, required this.bottom});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(top, style: display(17, color: AppColors.orangeBright)),
        const SizedBox(height: 2),
        Text(bottom, style: label(color: AppColors.mutInk, size: 8)),
      ]),
    );
  }
}

String compactNum(int n) {
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
  return '$n';
}
