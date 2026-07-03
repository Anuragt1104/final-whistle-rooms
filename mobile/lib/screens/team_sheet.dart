import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../api/models.dart';
import '../data/flags.dart';
import '../data/sportsdb.dart';
import '../local/squads.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/player_sheet.dart';

/// Bottom-sheet team profile — official badge, info and squad with player
/// photos (TheSportsDB). Falls back to the flag + a note if a lookup misses.
void showTeamSheet(BuildContext context, Team team) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _TeamSheet(team: team),
  );
}

class _TeamSheet extends StatefulWidget {
  final Team team;
  const _TeamSheet({required this.team});
  @override
  State<_TeamSheet> createState() => _TeamSheetState();
}

class _TeamSheetState extends State<_TeamSheet> {
  late final Future<TeamInfo?> _future = SportsDb.team(widget.team.name);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => FutureBuilder<TeamInfo?>(
        future: _future,
        builder: (_, snap) {
          final info = snap.data;
          final loading = snap.connectionState != ConnectionState.done;
          return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(18, 12, 18, 28), children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 16),
            Row(children: [
              CircleFlag(team: widget.team, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.team.name.toUpperCase(), style: display(24)),
                  if (info?.stadium != null && info!.stadium!.isNotEmpty)
                    Text('🏟 ${info.stadium}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mut, size: 12.5)),
                ]),
              ),
              if (info?.badge != null)
                CachedNetworkImage(imageUrl: info!.badge!, width: 46, height: 46, errorWidget: (_, __, ___) => const SizedBox()),
            ]),
            if (info?.description != null && info!.description!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(info.description!, maxLines: 4, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mut, size: 13)),
            ],
            const SizedBox(height: 20),
            ..._tournamentSquad(),
            Row(children: [
              Text('PLAYER GALLERY', style: label(color: AppColors.ink, size: 12.5, weight: FontWeight.w800)),
              const Spacer(),
              if (info != null && info.squad.isNotEmpty) Text('${info.squad.length} players', style: body(color: AppColors.mut, size: 11.5)),
            ]),
            const SizedBox(height: 12),
            if (loading)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator(color: AppColors.orange)))
            else if (info == null || info.squad.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: cardBox(),
                child: Text('Squad photos aren\'t available for this team right now.', textAlign: TextAlign.center, style: body(color: AppColors.mut, size: 13)),
              )
            else
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.74,
                children: info.squad.map(_playerCard).toList(),
              ),
          ]);
        },
      ),
    );
  }

  /// On-device tournament squad — works offline; tap any player for their
  /// World Cup stats profile.
  List<Widget> _tournamentSquad() {
    if (widget.team.code == 'TBD') return const [];
    final sq = squadFor(widget.team);
    Widget row(SquadPlayer p, {bool starter = false}) => Pressable(
          haptic: HapticFeedbackType.selection,
          onTap: () => showPlayerSheet(context, widget.team, p),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 26, child: Text('${p.number}', style: display(13, color: AppColors.orange))),
              Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(size: 13, weight: starter ? FontWeight.w800 : FontWeight.w600))),
              Text(positionLabel(p.pos), style: label(color: AppColors.mut, size: 8.5)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: AppColors.mut, size: 16),
            ]),
          ),
        );
    return [
      Row(children: [
        Text('WORLD CUP SQUAD', style: label(color: AppColors.ink, size: 12.5, weight: FontWeight.w800)),
        const Spacer(),
        Text('${sq.formation} · ${sq.coach}', style: body(color: AppColors.mut, size: 11.5)),
      ]),
      const SizedBox(height: 10),
      Container(
        decoration: cardBox(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(children: [
          ...sq.startingXI.map((p) => row(p, starter: true)),
          Container(height: 1, color: AppColors.line, margin: const EdgeInsets.symmetric(vertical: 4)),
          ...sq.bench.map(row),
        ]),
      ),
      const SizedBox(height: 20),
    ];
  }

  Widget _playerCard(PlayerInfo p) {
    return Container(
      decoration: cardBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Container(
            color: AppColors.cardAlt,
            child: CachedNetworkImage(
              imageUrl: p.photo,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              errorWidget: (_, __, ___) => const Center(child: Icon(Icons.person, color: AppColors.mut, size: 36)),
              placeholder: (_, __) => const Center(child: Icon(Icons.person_outline, color: AppColors.line, size: 30)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(weight: FontWeight.w800, size: 11.5)),
            if (p.position.isNotEmpty)
              Text(p.position, maxLines: 1, overflow: TextOverflow.ellipsis, style: label(color: AppColors.mut, size: 8.5)),
          ]),
        ),
      ]),
    );
  }
}
