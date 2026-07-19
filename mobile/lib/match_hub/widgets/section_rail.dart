import 'package:flutter/material.dart';

import '../../theme.dart';
import '../models.dart';
import '../palette.dart';

class MatchHubSectionRail extends StatelessWidget {
  final MatchHubSection selected;
  final ValueChanged<MatchHubSection> onSelect;

  const MatchHubSectionRail({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  static const _tabs = [
    (MatchHubSection.live, 'LIVE'),
    (MatchHubSection.calls, 'CALLS'),
    (MatchHubSection.lineups, 'LINEUPS'),
    (MatchHubSection.stats, 'STATS'),
    (MatchHubSection.fans, 'FANS'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HubColors.stadiumLift,
      height: 48,
      child: Row(
        children: [
          for (final (section, labelText) in _tabs)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(section),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      labelText,
                      style: label(
                        color: selected == section
                            ? AppColors.orange
                            : AppColors.mutInk,
                        size: 10,
                        weight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 2,
                      width: selected == section ? 28 : 0,
                      color: AppColors.orange,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
