import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme.dart';
import '../../widgets/chat_dock.dart';
import '../../widgets/leaderboard.dart';
import '../models.dart';
import '../palette.dart';

class FansTab extends StatefulWidget {
  final MatchHubViewState state;
  final RoomView room;
  final String? hostId;
  final String? meId;
  final bool meIsPro;
  final void Function(String text)? onSendChat;
  final void Function(String emoji)? onReact;

  const FansTab({
    super.key,
    required this.state,
    required this.room,
    this.hostId,
    this.meId,
    this.meIsPro = false,
    this.onSendChat,
    this.onReact,
  });

  @override
  State<FansTab> createState() => _FansTabState();
}

class _FansTabState extends State<FansTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = widget.state;
    final room = widget.room;

    return CustomScrollView(
      key: const PageStorageKey('hub_fans'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text('IN THE HUB', style: label(color: AppColors.mutInk, size: 10)),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: s.presence.length.clamp(0, 24),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final m = s.presence[i];
                    return Chip(
                      backgroundColor: HubColors.stadiumLift,
                      label: Text(
                        '${m.avatar} ${m.name}',
                        style: body(color: AppColors.cream, size: 12),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (s.officialHub) ...[
                Text('REACTION BURSTS', style: label(color: AppColors.mutInk, size: 10)),
                const SizedBox(height: 8),
                if (s.reactionTally.isEmpty)
                  Text(
                    'React from the dock — Official Hub aggregates bursts, not free text.',
                    style: body(color: AppColors.mutInk, size: 12.5),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: s.reactionTally.entries
                        .map(
                          (e) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: HubColors.stadiumLift,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${e.key}  ${e.value}',
                              style: body(color: AppColors.cream, weight: FontWeight.w700),
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ] else ...[
                Text('PARTY CHAT', style: label(color: AppColors.mutInk, size: 10)),
                const SizedBox(height: 8),
                ChatFeed(chat: room.chat, hostId: widget.hostId ?? room.hostId),
              ],
              const SizedBox(height: 16),
              Text('CALL LEADERBOARD', style: label(color: AppColors.mutInk, size: 10)),
              const SizedBox(height: 8),
              Leaderboard(
                room: room,
                meId: widget.meId,
                meIsPro: widget.meIsPro,
              ),
              const SizedBox(height: 12),
              Text(
                'Match events stay on LIVE — this stream is fans only.',
                style: body(color: AppColors.mutInk, size: 11),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
