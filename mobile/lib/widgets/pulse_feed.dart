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
        decoration: cardDecoration(),
        padding: const EdgeInsets.all(18),
        child: const Text(
          'The pulse feed lights up the moment the match kicks off — goals, cards, corners and odds swings, translated into plain English.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mut, fontSize: 13),
        ),
      );
    }
    return Column(
      children: cards
          .map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PulseTile(card: c),
              ))
          .toList(),
    );
  }
}

class _PulseTile extends StatelessWidget {
  final PulseCard card;
  const _PulseTile({required this.card});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardDecoration(leftAccent: accentColor(card.accent)),
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(card.emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(card.headline,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              Text("${card.minute}'", style: const TextStyle(fontSize: 10, color: AppColors.mut)),
            ]),
            const SizedBox(height: 2),
            Text(card.detail, style: const TextStyle(fontSize: 12.5, color: AppColors.mut, height: 1.3)),
          ]),
        ),
      ]),
    );
  }
}
