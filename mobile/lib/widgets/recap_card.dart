import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

class RecapCard extends StatelessWidget {
  final RecapView recap;
  final bool aiOn;
  const RecapCard({super.key, required this.recap, required this.aiOn});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardDecoration(leftAccent: AppColors.lime),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AppChip('${recap.scope == "half-time" ? "HALF-TIME" : "FULL-TIME"} RECAP', color: AppColors.lime),
          const SizedBox(width: 6),
          AppChip(aiOn ? '✨ AI pundit' : '✨ Auto recap'),
        ]),
        const SizedBox(height: 8),
        Text(recap.text, style: const TextStyle(fontSize: 14, height: 1.45)),
        if (recap.topMember != null) ...[
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(children: [
              const TextSpan(text: 'Room leader: ', style: TextStyle(fontSize: 11, color: AppColors.mut)),
              TextSpan(
                  text: recap.topMember,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold)),
            ]),
          ),
        ],
      ]),
    );
  }
}
