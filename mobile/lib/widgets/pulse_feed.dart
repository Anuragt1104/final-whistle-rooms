import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

class PulseFeed extends StatelessWidget {
  final List<PulseCard> pulse;
  const PulseFeed({super.key, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final cards = pulse.reversed.toList();
    if (cards.isEmpty) {
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
    return Column(
      children: cards.map((c) => _PulseEntry(key: ValueKey(c.id), card: c)).toList(),
    );
  }
}

/// Each card slides + fades in once when it first appears (keyed by id).
class _PulseEntry extends StatefulWidget {
  final PulseCard card;
  const _PulseEntry({super.key, required this.card});
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

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: SizeTransition(
        sizeFactor: _a,
        axisAlignment: -1,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(_a),
          child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _tile(widget.card)),
        ),
      ),
    );
  }

  Widget _tile(PulseCard c) {
    if (c.kind == 'goal') {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('GOAL', style: display(20, color: AppColors.orangeBright)),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text('${c.headline}  ${c.detail}', style: body(color: AppColors.cream, size: 13.5, weight: FontWeight.w600)),
            ),
          ),
          Text("${c.minute}'", style: label(color: AppColors.mutInk, size: 10)),
        ]),
      );
    }
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
