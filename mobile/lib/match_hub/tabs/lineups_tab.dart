import 'package:flutter/material.dart';

import '../../api/live_data.dart';
import '../../api/models.dart';
import '../../data/flags.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/player_sheet.dart';
import '../models.dart';
import '../palette.dart';

class LineupsTab extends StatefulWidget {
  final MatchHubViewState state;
  final RoomView room;
  final String? focusSide;

  const LineupsTab({
    super.key,
    required this.state,
    required this.room,
    this.focusSide,
  });

  @override
  State<LineupsTab> createState() => _LineupsTabState();
}

class _LineupsTabState extends State<LineupsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = widget.state.lineup;
    final room = widget.room;

    return ColoredBox(
      color: HubColors.creamSurface,
      child: CustomScrollView(
        key: const PageStorageKey('hub_lineups'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (data == null)
                  _empty('Loading verified lineups…')
                else ...[
                  _status(data),
                  const SizedBox(height: 12),
                  if (data.lineupStatus != 'confirmed' ||
                      data.home.players.isEmpty)
                    _empty(
                      'Lineups not announced. This updates from TxLINE when starters are confirmed.',
                    )
                  else ...[
                    if (widget.focusSide != 'away')
                      _team(room.fixture.home, data.home),
                    if (widget.focusSide == null) const SizedBox(height: 14),
                    if (widget.focusSide != 'home')
                      _team(room.fixture.away, data.away),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Verified by TxLINE · updated ${_fmt(data.updatedAt)}',
                    style: body(color: AppColors.mut, size: 11),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _status(MatchData data) {
    final announced = data.lineupStatus == 'confirmed' &&
        data.home.players.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: cardBox(),
      child: Row(
        children: [
          Icon(
            announced ? Icons.check_circle_rounded : Icons.schedule_rounded,
            color: AppColors.orange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announced ? 'Confirmed lineups' : 'Lineups not announced',
                  style: body(weight: FontWeight.w800, size: 13.5),
                ),
                Text(
                  announced
                      ? '${data.home.formation ?? 'Formation pending'} · ${data.away.formation ?? 'Formation pending'}'
                      : 'Waiting on club confirmation',
                  style: body(color: AppColors.mut, size: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _team(Team team, VerifiedTeamLineup lineup) {
    final starters = lineup.players.where((p) => p.starter).toList();
    final bench = lineup.players.where((p) => !p.starter).toList();
    Widget row(VerifiedPlayer player) => Pressable(
          onTap: () => showPlayerSheet(context, team, player),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 29,
                  child: Text(
                    player.shirtNumber ?? '—',
                    style: display(13, color: AppColors.orange),
                  ),
                ),
                Expanded(
                  child: Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(weight: FontWeight.w700, size: 13),
                  ),
                ),
                if (player.stats.goals > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text('⚽${player.stats.goals}', style: body(size: 11)),
                  ),
                if (player.stats.yellowCards > 0)
                  Container(
                    width: 8,
                    height: 12,
                    margin: const EdgeInsets.only(right: 6),
                    color: AppColors.gold,
                  ),
                if (player.stats.redCards > 0)
                  Container(
                    width: 8,
                    height: 12,
                    margin: const EdgeInsets.only(right: 6),
                    color: AppColors.orange,
                  ),
                if (player.onPitch)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF75C043),
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 7),
                Text(player.position, style: label(color: AppColors.mut, size: 8.5)),
              ],
            ),
          ),
        );

    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          Row(
            children: [
              InlineFlag(team: team, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(team.name.toUpperCase(), style: display(18)),
              ),
              Text(
                lineup.formation ?? '—',
                style: label(color: AppColors.orange, size: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('STARTING XI', style: label(color: AppColors.mut, size: 8.5)),
          ),
          ...starters.map(row),
          if (bench.isNotEmpty) ...[
            const Divider(color: AppColors.line),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('SUBSTITUTES', style: label(color: AppColors.mut, size: 8.5)),
            ),
            ...bench.map(row),
          ],
        ],
      ),
    );
  }

  Widget _empty(String text) => Container(
        decoration: cardBox(),
        padding: const EdgeInsets.all(17),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: body(color: AppColors.mut, size: 12.5),
        ),
      );

  String _fmt(int ms) {
    if (ms <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
