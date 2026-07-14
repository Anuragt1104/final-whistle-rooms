import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/live_data.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import '../widgets/player_avatar.dart';

class LeadersScreen extends StatefulWidget {
  const LeadersScreen({super.key});
  @override
  State<LeadersScreen> createState() => _LeadersScreenState();
}

class _LeadersScreenState extends State<LeadersScreen> {
  late Future<TournamentLeadersData> _future = ApiClient.instance
      .tournamentLeaders();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: Column(
      children: [
        const FwrHeader(showBack: true, title: 'Tournament Leaders'),
        Expanded(
          child: FutureBuilder<TournamentLeadersData>(
            future: _future,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done)
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.orange),
                );
              if (snap.hasError || snap.data == null)
                return Center(
                  child: PrimaryButton(
                    'Retry',
                    icon: Icons.refresh_rounded,
                    onTap: () => setState(
                      () => _future = ApiClient.instance.tournamentLeaders(),
                    ),
                  ),
                );
              final data = snap.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _source(data.asOf),
                  const SizedBox(height: 16),
                  const SectionLabel('Golden Boot'),
                  if (data.goals.isEmpty)
                    _empty('No confirmed goals yet.')
                  else
                    ...data.goals
                        .take(12)
                        .toList()
                        .asMap()
                        .entries
                        .map((e) => _leader(e.key + 1, e.value, 'GOALS')),
                  const SizedBox(height: 16),
                  const SectionLabel('Discipline leaders'),
                  if (data.yellowCards.isEmpty)
                    _empty('No confirmed cards yet.')
                  else
                    ...data.yellowCards
                        .take(8)
                        .toList()
                        .asMap()
                        .entries
                        .map((e) => _leader(e.key + 1, e.value, 'YELLOW')),
                  const SizedBox(height: 16),
                  const SectionLabel('Team records'),
                  ...data.teamRecords
                      .take(16)
                      .toList()
                      .asMap()
                      .entries
                      .map((e) => _team(e.key + 1, e.value)),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _source(int asOf) {
    final at = asOf > 0
        ? DateTime.fromMillisecondsSinceEpoch(asOf).toLocal()
        : null;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE9F7E1),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF9BCB91)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: Color(0xFF2D6A30)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Aggregated only from completed TxLINE snapshots${at == null ? '' : ' · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'}',
              style: body(
                color: const Color(0xFF2D6A30),
                size: 11.5,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leader(int rank, LeaderEntry entry, String labelText) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: cardBox(),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        SizedBox(
          width: 25,
          child: Text(
            '$rank',
            style: display(
              14,
              color: rank <= 3 ? AppColors.orange : AppColors.mut,
            ),
          ),
        ),
        PlayerAvatar(
          team: _teamShell(entry),
          name: entry.name,
          imageUrl: entry.photoUrl,
          size: 34,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name, style: body(weight: FontWeight.w800, size: 13)),
              Text(
                entry.teamCode,
                style: label(color: AppColors.mut, size: 8.5),
              ),
            ],
          ),
        ),
        Text('${entry.value}', style: display(20, color: AppColors.orange)),
        const SizedBox(width: 4),
        Text(labelText, style: label(color: AppColors.mut, size: 7)),
      ],
    ),
  );

  Widget _team(int rank, TeamRecordData record) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: cardBox(),
    padding: const EdgeInsets.all(11),
    child: Row(
      children: [
        SizedBox(
          width: 25,
          child: Text('$rank', style: display(13, color: AppColors.mut)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.teamName,
                style: body(weight: FontWeight.w800, size: 13),
              ),
              Text(
                '${record.played} played · ${record.wins}W ${record.draws}D ${record.losses}L',
                style: body(color: AppColors.mut, size: 10.5),
              ),
            ],
          ),
        ),
        Text('${record.goalsFor}–${record.goalsAgainst}', style: display(17)),
      ],
    ),
  );

  Team _teamShell(LeaderEntry entry) => Team(
    id: entry.teamId,
    name: entry.teamCode,
    code: entry.teamCode,
    flag: '🏳️',
    rating: 0,
  );
  Widget _empty(String text) => Container(
    decoration: cardBox(),
    padding: const EdgeInsets.all(16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: body(color: AppColors.mut),
    ),
  );
}
