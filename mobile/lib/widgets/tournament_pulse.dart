import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

/// Tournament progress at a glance — how deep into the World Cup we are, with
/// stage tick markers and a live count. The "how much is left" bar fans check
/// between matches.
class TournamentPulse extends StatelessWidget {
  final List<Fixture> fixtures;
  const TournamentPulse({super.key, required this.fixtures});

  static const _stageBoundaries = [
    (72, 'GRP'),
    (88, 'R32'),
    (96, 'R16'),
    (100, 'QF'),
    (102, 'SF'),
    (104, 'F'),
  ];

  String _currentStage(int played) {
    if (played < 72) return 'GROUP STAGE';
    if (played < 88) return 'ROUND OF 32';
    if (played < 96) return 'ROUND OF 16';
    if (played < 100) return 'QUARTER-FINALS';
    if (played < 102) return 'SEMI-FINALS';
    if (played < 104) return 'THE FINAL';
    return 'TOURNAMENT COMPLETE';
  }

  @override
  Widget build(BuildContext context) {
    final total = fixtures.length >= 104 ? fixtures.length : 104;
    final played = fixtures.where((f) => f.status == 'finished').length;
    final liveNow = fixtures.where((f) => f.status == 'live').length;
    if (fixtures.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'TOURNAMENT',
                style: label(
                  color: AppColors.ink,
                  size: 11,
                  weight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  _currentStage(played),
                  style: label(
                    color: AppColors.cream,
                    size: 8,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              AnimatedCount(
                played,
                style: display(16, color: AppColors.orange),
              ),
              Text(
                ' of $total played',
                style: body(color: AppColors.mut, size: 11.5),
              ),
              if (liveNow > 0)
                Text(
                  ' · $liveNow live',
                  style: body(
                    color: AppColors.orange,
                    size: 11.5,
                    weight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // progress track with stage tick markers
          LayoutBuilder(
            builder: (_, box) {
              final w = box.maxWidth;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 10,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.cardAlt,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: AppColors.line),
                          ),
                        ),
                        TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0,
                            end: (played / total).clamp(0.0, 1.0),
                          ),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: v,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppColors.orange, AppColors.gold],
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ),
                        // stage boundary ticks
                        for (final (n, _) in _stageBoundaries.take(
                          _stageBoundaries.length - 1,
                        ))
                          Positioned(
                            left: w * n / total - 1,
                            top: 2,
                            bottom: 2,
                            child: Container(
                              width: 2,
                              color: played >= n
                                  ? const Color(0x66FFFFFF)
                                  : AppColors.line,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // stage labels under their segments
                  SizedBox(
                    height: 12,
                    child: Stack(
                      children: [
                        for (var i = 0; i < _stageBoundaries.length; i++)
                          Positioned(
                            left: i == 0
                                ? 0
                                : w * _stageBoundaries[i - 1].$1 / total,
                            width: i == 0
                                ? w * 72 / total
                                : w *
                                      (_stageBoundaries[i].$1 -
                                          _stageBoundaries[i - 1].$1) /
                                      total,
                            child: Center(
                              child: Text(
                                _stageBoundaries[i].$2,
                                style: label(
                                  color: played >= _stageBoundaries[i].$1
                                      ? AppColors.orange
                                      : AppColors.mut,
                                  size: 7,
                                  weight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
