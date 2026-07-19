import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/live_data.dart';
import '../api/models.dart';
import '../data/flags.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/player_sheet.dart';

void showTeamSheet(BuildContext context, Team team) {
  Navigator.push(context, fwrRoute(_TeamSheet(team: team)));
}

class _TeamSheet extends StatefulWidget {
  final Team team;
  const _TeamSheet({required this.team});
  @override
  State<_TeamSheet> createState() => _TeamSheetState();
}

class _TeamSheetState extends State<_TeamSheet> {
  late Future<TeamTournamentData> _future = ApiClient.instance.teamData(
    widget.team.id,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StadiumColors.canvas,
      body: SafeArea(
        child: FutureBuilder<TeamTournamentData>(
          future: _future,
          builder: (_, snap) {
            final data = snap.data;
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: StadiumColors.text,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'TEAM',
                      style: label(color: StadiumColors.muted, size: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: stadiumGradientPanel(
                    accent: teamColor(widget.team.code),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleFlag(team: widget.team, size: 64),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.team.name.toUpperCase(),
                              style: display(25, color: AppColors.cream),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '2026 TOURNAMENT · TXLINE VERIFIED',
                              style: label(
                                color: const Color(0xFFB8FF36),
                                size: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(36),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.orange),
                    ),
                  )
                else if (snap.hasError || data == null) ...[
                  _errorCard(),
                ] else ...[
                  Row(
                    children: [
                      Text(
                        'LATEST TOURNAMENT SQUAD',
                        style: label(
                          color: StadiumColors.text,
                          size: 11,
                          weight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _freshness(data),
                        style: label(color: AppColors.mut, size: 8.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (data.players.isEmpty)
                    _empty('Squad not announced by TxLINE yet.')
                  else
                    _squad(data),
                  const SizedBox(height: 20),
                  Text(
                    'TOURNAMENT RESULTS',
                    style: label(
                      color: StadiumColors.text,
                      size: 11,
                      weight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 9),
                  if (data.recentResults.isEmpty)
                    _empty('No tournament results yet.')
                  else
                    ...data.recentResults.map(_result),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String _freshness(TeamTournamentData data) {
    if (data.sourceUpdatedAt <= 0) return 'WAITING FOR SOURCE';
    final at = DateTime.fromMillisecondsSinceEpoch(
      data.sourceUpdatedAt,
    ).toLocal();
    return 'SOURCE ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }

  Widget _squad(TeamTournamentData data) {
    final positions = ['GK', 'DF', 'MF', 'FW', 'UNK'];
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          for (final pos in positions)
            if (data.players.any((p) => p.position == pos)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 7, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    positionLabel(pos).toUpperCase(),
                    style: label(color: AppColors.orange, size: 8.5),
                  ),
                ),
              ),
              ...data.players
                  .where((p) => p.position == pos)
                  .map(
                    (p) => Pressable(
                      onTap: () => showPlayerSheet(context, widget.team, p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: Text(
                                p.shirtNumber ?? '—',
                                style: display(13, color: AppColors.orange),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: body(size: 13, weight: FontWeight.w700),
                              ),
                            ),
                            if (p.stats.goals > 0)
                              Text(
                                '⚽ ${p.stats.goals}',
                                style: body(size: 11, weight: FontWeight.w800),
                              ),
                            if (p.stats.yellowCards > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  '🟨 ${p.stats.yellowCards}',
                                  style: body(size: 11),
                                ),
                              ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.mut,
                              size: 17,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
        ],
      ),
    );
  }

  Widget _result(TeamResult r) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      decoration: cardBox(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          InlineFlag(team: r.opponent, size: 25),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'v ${r.opponent.name}',
                  style: body(weight: FontWeight.w800, size: 13),
                ),
                Text(r.stage, style: body(color: AppColors.mut, size: 10.5)),
              ],
            ),
          ),
          Text(
            r.goalsFor == null ? 'UPCOMING' : '${r.goalsFor}–${r.goalsAgainst}',
            style: display(
              17,
              color: r.goalsFor == null ? AppColors.mut : AppColors.ink,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _empty(String text) => Container(
    decoration: cardBox(),
    padding: const EdgeInsets.all(18),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: body(color: AppColors.mut, size: 13),
    ),
  );
  Widget _errorCard() => Container(
    decoration: cardBox(),
    padding: const EdgeInsets.all(18),
    child: Column(
      children: [
        Text(
          'Verified squad unavailable',
          style: body(weight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          'No cached TxLINE squad is available. The app will not substitute an old roster.',
          textAlign: TextAlign.center,
          style: body(color: AppColors.mut, size: 12),
        ),
        TextButton(
          onPressed: () => setState(
            () => _future = ApiClient.instance.teamData(widget.team.id),
          ),
          child: const Text('RETRY'),
        ),
      ],
    ),
  );
}
