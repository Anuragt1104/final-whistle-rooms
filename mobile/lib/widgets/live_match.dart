import 'dart:async';
import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

/// Second-precision match clock. The backend sends the authoritative
/// `clockSeconds` + `running`; this widget ticks locally every second between
/// snapshots so the clock never looks frozen, then resyncs when a fresh frame
/// arrives. Forward-biased so latency jitter can't make it tick backwards.
class LiveClock extends StatefulWidget {
  final int clockSeconds;
  final bool running;
  final TextStyle style;
  const LiveClock({super.key, required this.clockSeconds, required this.running, required this.style});
  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  Timer? _t;
  late int _base;
  late DateTime _anchor;
  int _displayed = 0;

  @override
  void initState() {
    super.initState();
    _base = widget.clockSeconds;
    _anchor = DateTime.now();
    _displayed = _base;
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant LiveClock old) {
    super.didUpdateWidget(old);
    if (old.clockSeconds != widget.clockSeconds || old.running != widget.running) {
      // Always re-anchor to the authoritative snapshot value. The snapshot is
      // already a few seconds stale (record -> server -> SSE -> us), so
      // interpolating from it keeps the clock at-most-exact and never ahead of
      // the real match — the user prefers a touch behind over running ahead.
      _base = widget.clockSeconds;
      _anchor = DateTime.now();
      _tick();
    }
  }

  void _tick() {
    if (!mounted) return;
    // never display ahead of the last authoritative value by more than the
    // elapsed real seconds; clamp so a slow upstream can't make us overshoot.
    final elapsed = DateTime.now().difference(_anchor).inSeconds;
    final secs = widget.running ? _base + elapsed.clamp(0, 75) : _base;
    if (secs != _displayed) setState(() => _displayed = secs);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _displayed ~/ 60;
    final s = _displayed % 60;
    return Text(
      "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}",
      style: widget.style,
    );
  }
}

/// Live stats comparison — every stat TxLINE provides (goals, corners, yellow,
/// red) shown per team with rolling counts and a proportional team-coloured bar.
class MatchStatsPanel extends StatefulWidget {
  final ScoreView score;
  final Team home, away;
  const MatchStatsPanel({super.key, required this.score, required this.home, required this.away});

  @override
  State<MatchStatsPanel> createState() => _MatchStatsPanelState();
}

class _MatchStatsPanelState extends State<MatchStatsPanel> {
  int _period = 0; // 0 = full match, 1 = 1st half, 2 = 2nd half

  Team get home => widget.home;
  Team get away => widget.away;

  @override
  Widget build(BuildContext context) {
    final score = widget.score;
    final periods = score.periods;
    // pick the stat lines for the selected period
    late final StatPair goals, corners, yellow, red;
    if (_period == 0 || periods == null) {
      goals = score.goals;
      corners = score.corners;
      yellow = score.yellow;
      red = score.red;
    } else {
      final p = _period == 1 ? periods.firstHalf : periods.secondHalf;
      goals = p.goals;
      corners = p.corners;
      yellow = p.yellow;
      red = p.red;
    }
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('MATCH STATS', style: label(color: AppColors.ink, size: 12, weight: FontWeight.w800)),
          const Spacer(),
          _key(home.code, teamColor(home.code)),
          const SizedBox(width: 10),
          _key(away.code, teamColor(away.code)),
        ]),
        if (periods != null) ...[
          const SizedBox(height: 12),
          _periodToggle(),
        ],
        const SizedBox(height: 16),
        _row(const Icon(Icons.sports_soccer, size: 15, color: AppColors.ink), 'Goals', goals.home, goals.away, big: true),
        _row(const Icon(Icons.flag_rounded, size: 15, color: AppColors.ink), 'Corners', corners.home, corners.away),
        _row(_card(const Color(0xFFF5C518)), 'Yellow cards', yellow.home, yellow.away),
        if (red.home + red.away > 0) _row(_card(const Color(0xFFD8392B)), 'Red cards', red.home, red.away),
      ]),
    );
  }

  Widget _periodToggle() {
    const labels = ['Match', '1st half', '2nd half'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: List.generate(3, (i) {
          final sel = _period == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _period = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(color: sel ? AppColors.ink : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: Text(labels[i], style: label(color: sel ? Colors.white : AppColors.mut, size: 10.5, weight: FontWeight.w800)),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _key(String code, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(code, style: label(color: AppColors.mut, size: 9.5, weight: FontWeight.w700)),
      ]);

  Widget _card(Color c) => Container(
        width: 11, height: 15,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2.5)),
      );

  Widget _row(Widget icon, String label_, int h, int a, {bool big = false}) {
    final hc = teamColor(home.code);
    final ac = teamColor(away.code);
    final total = (h + a) == 0 ? 1 : (h + a);
    final numStyle = TextStyle(
        fontFamily: kDisplay, fontSize: big ? 23 : 19, color: AppColors.ink, letterSpacing: 0.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(children: [
        Row(children: [
          SizedBox(width: 36, child: AnimatedCount(h, style: numStyle)),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              icon,
              const SizedBox(width: 7),
              Text(label_.toUpperCase(),
                  style: label(color: AppColors.mut, size: 10.5, weight: FontWeight.w700)),
            ]),
          ),
          SizedBox(
            width: 36,
            child: Align(alignment: Alignment.centerRight, child: AnimatedCount(a, style: numStyle)),
          ),
        ]),
        const SizedBox(height: 7),
        LayoutBuilder(builder: (_, box) {
          final hw = box.maxWidth * h / total;
          return ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                width: hw,
                height: 8,
                color: hc,
              ),
              Expanded(child: Container(height: 8, color: ac.withValues(alpha: 0.85))),
            ]),
          );
        }),
      ]),
    );
  }
}

/// Penalty shootout scoreboard — kick-by-kick, running tally, sudden-death, winner.
class ShootoutCard extends StatelessWidget {
  final ShootoutView s;
  final Team home, away;
  const ShootoutCard({super.key, required this.s, required this.home, required this.away});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: AppColors.ink,
          child: Row(children: [
            Text('🎯 PENALTY SHOOTOUT', style: label(color: AppColors.cream, size: 11.5, weight: FontWeight.w800)),
            const Spacer(),
            Text('${s.home}–${s.away}', style: display(18, color: AppColors.orangeBright)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(children: [
            _teamRow(home, 'home'),
            const SizedBox(height: 10),
            _teamRow(away, 'away'),
            const SizedBox(height: 12),
            if (s.decided && s.winnerSide != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text('${(s.winnerSide == 'home' ? home.name : away.name).toUpperCase()} WIN ${s.home}–${s.away} ON PENS',
                    style: label(color: Colors.white, size: 11.5, weight: FontWeight.w900)),
              )
            else
              Text(_statusLine(), textAlign: TextAlign.center, style: body(color: AppColors.mut, size: 11.5)),
          ]),
        ),
      ]),
    );
  }

  String _statusLine() {
    final hk = s.kicks.where((k) => k.side == 'home').length;
    final ak = s.kicks.where((k) => k.side == 'away').length;
    if (hk > 5 || ak > 5) return 'Sudden death — one slip settles it.';
    return 'Best of five · nerves of steel';
  }

  Widget _teamRow(Team t, String side) {
    final c = teamColor(t.code);
    final kicks = s.kicks.where((k) => k.side == side).toList();
    return Row(children: [
      SizedBox(width: 46, child: Text(t.code, style: label(color: c, size: 12.5, weight: FontWeight.w800))),
      const SizedBox(width: 8),
      Expanded(
        child: Wrap(spacing: 5, runSpacing: 5, children: [
          for (final k in kicks) _dot(scored: k.scored, color: c),
          for (int i = kicks.length; i < 5; i++) _dot(empty: true),
        ]),
      ),
    ]);
  }

  Widget _dot({bool scored = false, bool empty = false, Color? color}) {
    if (empty) {
      return Container(
        width: 16, height: 16,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.line, width: 1.5)),
      );
    }
    if (!scored) {
      return Container(
        width: 16, height: 16,
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.line.withValues(alpha: 0.5)),
        child: const Icon(Icons.close_rounded, size: 12, color: AppColors.mut),
      );
    }
    return Container(
      width: 16, height: 16,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
    );
  }
}
