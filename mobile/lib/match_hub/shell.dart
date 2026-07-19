import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/chat_dock.dart';
import 'controller.dart';
import 'models.dart';
import 'palette.dart';
import 'tabs/calls_tab.dart';
import 'tabs/fans_tab.dart';
import 'tabs/lineups_tab.dart';
import 'tabs/live_tab.dart';
import 'tabs/stats_tab.dart';
import 'widgets/dock.dart';
import 'widgets/header.dart';
import 'widgets/replay_dock.dart';
import 'widgets/section_rail.dart';

class MatchHubShell extends StatefulWidget {
  final MatchHubController hub;
  final RoomView room;
  final Map<String, String> myPicks;
  final String? meId;
  final bool meIsPro;
  final bool joined;
  final List<String> reactionEmojis;
  final VoidCallback? onBack;
  final void Function(Team team)? onTeamTap;
  final void Function(String side)? onPickSide;
  final void Function(String promptId, String optionKey)? onPredict;
  final void Function(String emoji)? onReact;
  final void Function(String text)? onSendChat;
  final VoidCallback? onShare;
  final VoidCallback? onSourceTap;
  final Widget? joinOverlay;
  final Widget? celebrationOverlay;

  const MatchHubShell({
    super.key,
    required this.hub,
    required this.room,
    required this.myPicks,
    required this.joined,
    this.meId,
    this.meIsPro = false,
    this.reactionEmojis = const ['🔥', '😱', '👏', '⚽', '💛'],
    this.onBack,
    this.onTeamTap,
    this.onPickSide,
    this.onPredict,
    this.onReact,
    this.onSendChat,
    this.onShare,
    this.onSourceTap,
    this.joinOverlay,
    this.celebrationOverlay,
  });

  @override
  State<MatchHubShell> createState() => _MatchHubShellState();
}

class _MatchHubShellState extends State<MatchHubShell> {
  bool _headerExpanded = true;
  bool _dockVisible = true;
  String? _lineupFocusSide;

  @override
  void initState() {
    super.initState();
    widget.hub.addListener(_onHub);
  }

  @override
  void dispose() {
    widget.hub.removeListener(_onHub);
    super.dispose();
  }

  void _onHub() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.hub.state;
    if (state == null) {
      return const Scaffold(
        backgroundColor: HubColors.stadium,
        body: Center(child: CircularProgressIndicator(color: AppColors.orange)),
      );
    }
    final palette = TeamPalette.forFixture(state.header.home, state.header.away);
    final replay = state.replayState;

    // FT / live / replay share one shell — lifecycle drives header + tab copy.
    return Scaffold(
      backgroundColor: HubColors.stadium,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollUpdateNotification) {
                final dy = n.scrollDelta ?? 0;
                if (dy > 2 && _headerExpanded) {
                  setState(() => _headerExpanded = false);
                } else if (dy < -2 &&
                    !_headerExpanded &&
                    (n.metrics.pixels < 40)) {
                  setState(() => _headerExpanded = true);
                }
                if (dy > 4 && _dockVisible) {
                  setState(() => _dockVisible = false);
                } else if (dy < -4 && !_dockVisible) {
                  setState(() => _dockVisible = true);
                }
              }
              return false;
            },
            child: Column(
              children: [
                MatchHubHeader(
                  header: state.header,
                  palette: palette,
                  expanded: _headerExpanded,
                  onBack: widget.onBack,
                  onSourceTap: widget.onSourceTap,
                  onTeamTap: (t) {
                    final side =
                        t.id == state.header.home.id ? 'home' : 'away';
                    setState(() => _lineupFocusSide = side);
                    widget.hub.selectSection(MatchHubSection.lineups);
                    widget.onTeamTap?.call(t);
                  },
                ),
                MatchHubSectionRail(
                  selected: state.selectedSection,
                  onSelect: (s) {
                    if (s != MatchHubSection.lineups) {
                      _lineupFocusSide = null;
                    }
                    widget.hub.selectSection(s);
                  },
                ),
                Expanded(child: _tabBody(state)),
                if (replay != null && replay.active)
                  ReplayControlDock(
                    state: replay,
                    onControl: (action, {minute, speed}) =>
                        widget.hub.controlReplay(
                          action: action,
                          minute: minute,
                          speed: speed,
                        ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!state.officialHub && state.selectedSection == MatchHubSection.fans)
                  ChatComposer(
                    onSend: widget.onSendChat ?? (_) {},
                    onReact: widget.onReact ?? (_) {},
                    disabled: !widget.joined,
                    emojis: widget.reactionEmojis,
                  ),
                PersistentMatchDock(
                  unread: state.unread,
                  visible: _dockVisible,
                  officialHub: state.officialHub,
                  reactionEmojis: widget.reactionEmojis,
                  onReact: () => _showReactSheet(state),
                  onCalls: () => widget.hub.selectSection(MatchHubSection.calls),
                  onFans: () => widget.hub.selectSection(MatchHubSection.fans),
                  onRewards: () {
                    final drop = state.rewards.pendingReveal;
                    if (drop != null) {
                      // Host handles cinematic reveal via controller listener.
                      widget.hub.selectSection(MatchHubSection.live);
                    }
                  },
                ),
              ],
            ),
          ),
          if (widget.joinOverlay != null) widget.joinOverlay!,
          if (widget.celebrationOverlay != null) widget.celebrationOverlay!,
        ],
      ),
    );
  }

  Widget _tabBody(MatchHubViewState state) {
    final room = widget.room;
    final showDraft =
        room.modes.draft && widget.joined && state.myGame.side == null;
    switch (state.selectedSection) {
      case MatchHubSection.live:
        return LiveTab(
          state: state,
          myPicks: widget.myPicks,
          onPick: widget.onPredict,
          onJumpToLive: widget.hub.jumpToLive,
          onScrollAway: (older) {
            if (older) {
              widget.hub.markReadingOlder();
            } else {
              widget.hub.jumpToLive();
            }
          },
        );
      case MatchHubSection.calls:
        return CallsTab(
          state: state,
          room: room,
          myPicks: widget.myPicks,
          mySide: state.myGame.side,
          showDraft: showDraft,
          onPickSide: widget.onPickSide,
          onPick: widget.onPredict,
          onShare: widget.onShare,
        );
      case MatchHubSection.lineups:
        return LineupsTab(
          state: state,
          room: room,
          focusSide: _lineupFocusSide,
        );
      case MatchHubSection.stats:
        return StatsTab(state: state, room: room);
      case MatchHubSection.fans:
        return FansTab(
          state: state,
          room: room,
          hostId: room.hostId,
          meId: widget.meId,
          meIsPro: widget.meIsPro,
          onSendChat: widget.onSendChat,
          onReact: widget.onReact,
        );
    }
  }

  void _showReactSheet(MatchHubViewState state) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: HubColors.stadiumLift,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final e in widget.reactionEmojis)
              InkWell(
                onTap: () {
                  widget.onReact?.call(e);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: HubColors.stadium,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
