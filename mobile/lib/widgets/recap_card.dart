import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';

class RecapCard extends StatelessWidget {
  final RecapView recap;
  final bool aiOn;
  const RecapCard({super.key, required this.recap, required this.aiOn});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.cardAlt,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Text(
                  '${recap.scope == "half-time" ? "HALF-TIME" : "FULL-TIME"} RECAP',
                  style: label(color: AppColors.orange, size: 11),
                ),
                const Spacer(),
                Text(
                  aiOn ? '✨ AI PUNDIT' : '✨ AUTO RECAP',
                  style: label(color: AppColors.mut, size: 9),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recap.text, style: body(size: 14)),
                if (recap.topMember != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'TERRACE LEADER  ',
                        style: label(color: AppColors.mut, size: 9),
                      ),
                      Text(
                        recap.topMember!,
                        style: body(
                          color: AppColors.orange,
                          size: 12,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
