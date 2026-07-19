import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme.dart';
import '../../widgets/next_swing_card.dart';
import '../models.dart';
import '../palette.dart';

class LiveTab extends StatefulWidget {
  final MatchHubViewState state;
  final Map<String, String> myPicks;
  final void Function(String promptId, String optionKey)? onPick;
  final VoidCallback? onJumpToLive;
  final void Function(bool readingOlder)? onScrollAway;

  const LiveTab({
    super.key,
    required this.state,
    required this.myPicks,
    this.onPick,
    this.onJumpToLive,
    this.onScrollAway,
  });

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearBottom =
        _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;
    widget.onScrollAway?.call(!nearBottom);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = widget.state;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Stack(
      children: [
        CustomScrollView(
          key: const PageStorageKey('hub_live'),
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (s.freshness == 'stale' || s.freshness == 'disconnected')
                    _feedHealth(s),
                  if (s.activeCall != null && widget.onPick != null) ...[
                    NextSwingCard(
                      prompts: [
                        s.activeCall!,
                        if (s.quickCall != null) s.quickCall!,
                      ],
                      myPicks: widget.myPicks,
                      onPick: s.callsPaused ? (_, __) {} : widget.onPick!,
                      streak: s.myGame.streak,
                      bestStreak: s.myGame.bestStreak,
                      embedded: false,
                    ),
                    if (s.callsPaused)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        child: Text(
                          s.callsPausedReason ??
                              'Calls paused while match data reconnects.',
                          style: body(color: HubColors.stale, size: 12),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                  ],
                  _matchNow(s),
                  const SizedBox(height: 12),
                  Text('TIMELINE', style: label(color: AppColors.mutInk, size: 10)),
                  const SizedBox(height: 8),
                  if (s.timeline.isEmpty)
                    _skeleton(reduceMotion)
                  else
                    ...s.timeline.reversed.take(40).map(_timelineRow),
                  const SizedBox(height: 16),
                  Text('MATCH PULSE', style: label(color: AppColors.mutInk, size: 10)),
                  const SizedBox(height: 8),
                  _pulseStrip(s.matchPulse),
                  const SizedBox(height: 16),
                  _myProgress(s.myGame),
                  if (s.latestRecap != null) ...[
                    const SizedBox(height: 12),
                    _phaseCard(s.latestRecap!),
                  ],
                ]),
              ),
            ),
          ],
        ),
        if (!s.followingLive && s.newTimelineCount > 0)
          Positioned(
            left: 16,
            right: 16,
            bottom: 88,
            child: Material(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: widget.onJumpToLive,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Text(
                    '${s.newTimelineCount} new updates · Jump to live',
                    textAlign: TextAlign.center,
                    style: body(color: AppColors.cream, weight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _feedHealth(MatchHubViewState s) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HubColors.stadiumLift,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HubColors.stale.withValues(alpha: 0.4)),
        ),
        child: Text(
          'Updates delayed · Calls paused while match data reconnects.',
          style: body(color: HubColors.stale, size: 12.5),
        ),
      );

  Widget _matchNow(MatchHubViewState s) {
    final last = s.timeline.isEmpty ? null : s.timeline.last;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HubColors.stadiumLift,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MATCH NOW', style: label(color: AppColors.orange, size: 10)),
          const SizedBox(height: 6),
          Text(
            last?.title ?? 'Waiting for the next verified moment',
            style: body(color: AppColors.cream, size: 15, weight: FontWeight.w700),
          ),
          if (last != null && last.detail.isNotEmpty)
            Text(last.detail, style: body(color: AppColors.mutInk, size: 12)),
        ],
      ),
    );
  }

  Widget _timelineRow(MatchTimelineItem item) {
    final statusColor = switch (item.status) {
      TimelineStatus.corrected => AppColors.gold,
      TimelineStatus.discarded => HubColors.stale,
      TimelineStatus.verified => AppColors.cream,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              "${item.clockSec ~/ 60}'",
              style: label(color: AppColors.orange, size: 10),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: body(color: statusColor, size: 13, weight: FontWeight.w700),
                ),
                if (item.detail.isNotEmpty)
                  Text(item.detail, style: body(color: AppColors.mutInk, size: 11)),
              ],
            ),
          ),
          if (item.status != TimelineStatus.verified)
            Text(
              item.status.name.toUpperCase(),
              style: label(color: statusColor, size: 8),
            ),
        ],
      ),
    );
  }

  Widget _pulseStrip(List<int> pulse) {
    return SizedBox(
      height: 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in pulse)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  height: 6.0 + v * 3.5,
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.35 + v * 0.08),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _myProgress(MatchHubMyGameSummary g) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HubColors.stadiumLift,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _stat('${g.points}', 'PTS'),
            _stat('${g.correct}/${g.answered}', 'CALLS'),
            _stat('${g.streak}', 'STREAK'),
          ],
        ),
      );

  Widget _stat(String v, String l) => Expanded(
        child: Column(
          children: [
            Text(v, style: display(20, color: AppColors.cream)),
            Text(l, style: label(color: AppColors.mutInk, size: 9)),
          ],
        ),
      );

  Widget _phaseCard(RecapView r) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HubColors.stadiumLift,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PHASE', style: label(color: HubColors.violet, size: 10)),
            const SizedBox(height: 6),
            Text(r.text, style: body(color: AppColors.cream, size: 13)),
          ],
        ),
      );

  Widget _skeleton(bool reduceMotion) => Container(
        height: 72,
        decoration: BoxDecoration(
          color: HubColors.stadiumLift,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          reduceMotion ? 'Loading timeline…' : 'Syncing verified events…',
          style: body(color: AppColors.mutInk, size: 12),
        ),
      );
}
