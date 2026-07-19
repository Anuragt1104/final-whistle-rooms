import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

class ShowcaseReplayRecommendation extends StatelessWidget {
  final bool available;
  final bool loading;
  final VoidCallback? onStart;

  const ShowcaseReplayRecommendation({
    super.key,
    required this.available,
    this.loading = false,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: stadiumGradientPanel(accent: StadiumColors.violet),
    child: Stack(
      children: [
        Positioned(
          right: -28,
          top: -30,
          child: Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: StadiumColors.lime.withValues(alpha: .18),
                width: 18,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'EXPERIENCE A VERIFIED CLASSIC',
                    style: label(color: StadiumColors.mint, size: 9.5),
                  ),
                  const Spacer(),
                  Text(
                    'ABOUT 3 MIN',
                    style: label(color: StadiumColors.muted, size: 8.5),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'ARG 3–1 SWI',
                style: display(29, color: StadiumColors.text),
              ),
              const SizedBox(height: 3),
              Text(
                'Guided extra-time replay · answer three Calls · earn playable lineage',
                style: body(color: StadiumColors.textSoft, size: 12),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: StadiumColors.mint.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: StadiumColors.mint.withValues(alpha: .32),
                      ),
                    ),
                    child: Text(
                      'TxLINE HISTORICAL',
                      style: label(color: StadiumColors.mint, size: 8),
                    ),
                  ),
                  const Spacer(),
                  PrimaryButton(
                    loading
                        ? 'CONNECTING…'
                        : available
                        ? 'START EXPERIENCE'
                        : 'RETRY FEED',
                    onTap: loading ? null : onStart,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
