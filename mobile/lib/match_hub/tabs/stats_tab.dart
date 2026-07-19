import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme.dart';
import '../models.dart';
import '../palette.dart';

class StatsTab extends StatefulWidget {
  final MatchHubViewState state;
  final RoomView room;

  const StatsTab({
    super.key,
    required this.state,
    required this.room,
  });

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final score = widget.state.supportedStats;
    final room = widget.room;
    final sourceTs = widget.state.lineup?.updatedAt ?? room.sourceUpdatedAt;

    return ColoredBox(
      color: HubColors.creamSurface,
      child: CustomScrollView(
        key: const PageStorageKey('hub_stats'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (score == null || score.phase == 0)
                  _empty('Stats unlock once the match kicks off.')
                else ...[
                  _module(
                    title: 'MATCH COMPARISON',
                    child: Column(
                      children: [
                        _bar('Goals', score.goals.home, score.goals.away),
                        _bar('Corners', score.corners.home, score.corners.away),
                        _bar('Yellow', score.yellow.home, score.yellow.away),
                        _bar('Red', score.red.home, score.red.away),
                      ],
                    ),
                    sourceTs: sourceTs,
                  ),
                  const SizedBox(height: 12),
                  _module(
                    title: 'MATCH PULSE',
                    child: _pulse(widget.state.matchPulse),
                    sourceTs: sourceTs,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tournament leaders appear only from verified endpoints. '
                    'Ratings, assists, possession, xG, and MOTM are omitted unless TxLINE supplies them.',
                    style: body(color: AppColors.mut, size: 11.5),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _module({
    required String title,
    required Widget child,
    int? sourceTs,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: label(color: AppColors.mut, size: 10)),
          const SizedBox(height: 10),
          child,
          const SizedBox(height: 10),
          Text(
            'Verified by TxLINE${sourceTs != null ? ' · ${_fmt(sourceTs)}' : ''}',
            style: body(color: AppColors.mut, size: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _bar(String labelText, int home, int away) {
    final total = (home + away).clamp(1, 999);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Text('$home', style: display(16, color: AppColors.ink)),
              Expanded(
                child: Text(
                  labelText,
                  textAlign: TextAlign.center,
                  style: label(color: AppColors.mut, size: 9),
                ),
              ),
              Text('$away', style: display(16, color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: home.clamp(1, total),
                child: Container(height: 6, color: AppColors.orange),
              ),
              const SizedBox(width: 3),
              Expanded(
                flex: away.clamp(1, total),
                child: Container(height: 6, color: AppColors.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pulse(List<int> pulse) => SizedBox(
        height: 40,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final v in pulse)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(
                    height: 8.0 + v * 3.5,
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.45 + v * 0.06),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

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
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
