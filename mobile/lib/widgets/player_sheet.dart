import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/live_data.dart';
import '../api/models.dart';
import '../data/flags.dart';
import '../local/squads.dart';
import '../theme.dart';
import 'common.dart';

/// Opens a verified TxLINE player profile. A legacy SquadPlayer is accepted
/// only by the explicitly labelled demo tournament path.
void showPlayerSheet(BuildContext context, Team team, Object source) {
  final player = source is VerifiedPlayer
      ? source
      : source is SquadPlayer
      ? VerifiedPlayer(
          id: 'demo:${team.code}:${source.number}',
          name: source.name,
          position: source.pos,
          portraitKind: 'illustration',
          starter: false,
          onPitch: false,
          shirtNumber: '${source.number}',
          stats: const VerifiedPlayerStats(
            goals: 0,
            yellowCards: 0,
            redCards: 0,
            starts: 0,
            squadSelections: 0,
          ),
        )
      : throw ArgumentError('Unsupported player source');
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _PlayerSheet(team: team, player: player),
  );
}

String positionLabel(String pos) => switch (pos) {
  'GK' => 'Goalkeeper',
  'DF' => 'Defender',
  'MF' => 'Midfielder',
  'FW' => 'Forward',
  _ => 'Position not supplied',
};

class _PlayerSheet extends StatelessWidget {
  final Team team;
  final VerifiedPlayer player;
  const _PlayerSheet({required this.team, required this.player});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.ink, Color(0xFF251A48)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  _portrait(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.name.toUpperCase(),
                          style: display(24, color: AppColors.cream),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            InlineFlag(team: team, size: 20),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                '${team.name} · ${positionLabel(player.position)}',
                                style: body(color: AppColors.mutInk, size: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (player.shirtNumber != null)
                              _pill('#${player.shirtNumber}'),
                            if (player.starter) _pill('STARTER'),
                            if (player.onPitch) _pill('ON PITCH', lime: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionLabel('Verified tournament totals'),
            Row(
              children: [
                _stat('${player.stats.squadSelections}', 'SQUADS'),
                const SizedBox(width: 8),
                _stat('${player.stats.starts}', 'STARTS'),
                const SizedBox(width: 8),
                _stat('${player.stats.goals}', 'GOALS'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('${player.stats.yellowCards}', 'YELLOW'),
                const SizedBox(width: 8),
                _stat('${player.stats.redCards}', 'RED'),
                const SizedBox(width: 8),
                _stat(player.country ?? '—', 'COUNTRY'),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: cardBox(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: AppColors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Only TxLINE-confirmed selections, starts, goals and cards are shown. Ratings, assists and xG are intentionally omitted when the source does not provide them.',
                      style: body(color: AppColors.mut, size: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _portrait() {
    if (player.photoUrl != null && player.portraitKind == 'photo') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: CachedNetworkImage(
          imageUrl: player.photoUrl!,
          width: 84,
          height: 100,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _fallbackPortrait(),
        ),
      );
    }
    return _fallbackPortrait();
  }

  Widget _fallbackPortrait() {
    final initials = player.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join();
    return Container(
      width: 84,
      height: 100,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB8FF36), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .24)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -14,
            top: -12,
            child: Icon(
              Icons.sports_soccer_rounded,
              size: 66,
              color: Colors.white.withValues(alpha: .16),
            ),
          ),
          Text(
            initials.toUpperCase(),
            style: display(29, color: AppColors.ink),
          ),
          Positioned(
            bottom: 7,
            child: Text(team.code, style: label(color: AppColors.ink, size: 9)),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, {bool lime = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: lime
          ? const Color(0xFFB8FF36)
          : Colors.white.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: label(color: lime ? AppColors.ink : AppColors.cream, size: 8.5),
    ),
  );

  Widget _stat(String value, String title) => Expanded(
    child: Container(
      decoration: cardBox(),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: display(20),
          ),
          const SizedBox(height: 3),
          Text(title, style: label(color: AppColors.mut, size: 8)),
        ],
      ),
    ),
  );
}
