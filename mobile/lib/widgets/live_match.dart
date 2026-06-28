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
      final incoming = widget.clockSeconds;
      // trust forward moves and large jumps (new period / reset); hold tiny
      // backward moves that are just network latency.
      if (incoming >= _displayed || (_displayed - incoming) > 90) {
        _base = incoming;
      } else {
        _base = _displayed;
      }
      _anchor = DateTime.now();
      _tick();
    }
  }

  void _tick() {
    if (!mounted) return;
    final secs = widget.running ? _base + DateTime.now().difference(_anchor).inSeconds : _base;
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
class MatchStatsPanel extends StatelessWidget {
  final ScoreView score;
  final Team home, away;
  const MatchStatsPanel({super.key, required this.score, required this.home, required this.away});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('MATCH STATS', style: label(color: AppColors.ink, size: 12, weight: FontWeight.w800)),
          const Spacer(),
          // tiny team key
          _key(home.code, teamColor(home.code)),
          const SizedBox(width: 10),
          _key(away.code, teamColor(away.code)),
        ]),
        const SizedBox(height: 16),
        _row(const Icon(Icons.sports_soccer, size: 15, color: AppColors.ink), 'Goals', score.goals.home, score.goals.away, big: true),
        _row(const Icon(Icons.flag_rounded, size: 15, color: AppColors.ink), 'Corners', score.corners.home, score.corners.away),
        _row(_card(const Color(0xFFF5C518)), 'Yellow cards', score.yellow.home, score.yellow.away),
        if (score.red.home + score.red.away > 0) _row(_card(const Color(0xFFD8392B)), 'Red cards', score.red.home, score.red.away),
      ]),
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
