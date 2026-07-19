import 'package:flutter/foundation.dart';

import '../api/live_data.dart';
import '../api/models.dart';

enum MatchHubSection { live, calls, lineups, stats, fans }

enum TimelineStatus { verified, corrected, discarded }

@immutable
class MatchTimelineItem {
  final String id;
  final String? sourceEventId;
  final String kind;
  final int phase;
  final int clockSec;
  final String? teamId;
  final String? playerId;
  final String? scoreAfter;
  final String title;
  final String detail;
  final TimelineStatus status;
  final int createdAt;
  final String? artwork;

  const MatchTimelineItem({
    required this.id,
    required this.kind,
    required this.phase,
    required this.clockSec,
    required this.title,
    required this.detail,
    required this.status,
    required this.createdAt,
    this.sourceEventId,
    this.teamId,
    this.playerId,
    this.scoreAfter,
    this.artwork,
  });
}

@immutable
class MatchHubHeaderState {
  final String competition;
  final String lifecycleBadge;
  final Team home;
  final Team away;
  final String scoreText;
  final String clockText;
  final bool clockFrozen;
  final String? freezeReason;
  final int watching;
  final String feedFreshness;
  final bool notifyOn;
  final String? latestEventRibbon;
  final bool replay;

  const MatchHubHeaderState({
    required this.competition,
    required this.lifecycleBadge,
    required this.home,
    required this.away,
    required this.scoreText,
    required this.clockText,
    required this.clockFrozen,
    required this.watching,
    required this.feedFreshness,
    required this.notifyOn,
    required this.replay,
    this.freezeReason,
    this.latestEventRibbon,
  });
}

@immutable
class MatchHubMyGameSummary {
  final int points;
  final int streak;
  final int bestStreak;
  final int correct;
  final int answered;
  final String? side;

  const MatchHubMyGameSummary({
    required this.points,
    required this.streak,
    required this.bestStreak,
    required this.correct,
    required this.answered,
    this.side,
  });
}

@immutable
class MatchHubUnreadCounts {
  final int calls;
  final int fans;
  final int rewards;

  const MatchHubUnreadCounts({
    this.calls = 0,
    this.fans = 0,
    this.rewards = 0,
  });
}

@immutable
class MatchHubRewardState {
  final List<MomentDropView> recentDrops;
  final Set<String> seenDropIds;
  final MomentDropView? pendingReveal;

  const MatchHubRewardState({
    this.recentDrops = const [],
    this.seenDropIds = const {},
    this.pendingReveal,
  });
}

@immutable
class MatchHubViewState {
  final MatchHubHeaderState header;
  final String lifecycle;
  final String freshness;
  final MatchHubSection selectedSection;
  final PromptView? activeCall;
  final PromptView? quickCall;
  final List<PromptView> settledCalls;
  final List<MatchTimelineItem> timeline;
  final MatchData? lineup;
  final ScoreView? supportedStats;
  final List<int> matchPulse;
  final List<MemberView> presence;
  final Map<String, int> reactionTally;
  final List<ChatView> partyChat;
  final bool officialHub;
  final bool callsPaused;
  final String? callsPausedReason;
  final MatchHubMyGameSummary myGame;
  final MatchHubUnreadCounts unread;
  final MatchHubRewardState rewards;
  final ReplayStateView? replayState;
  final int newTimelineCount;
  final bool followingLive;
  final RecapView? latestRecap;
  final int revision;

  const MatchHubViewState({
    required this.header,
    required this.lifecycle,
    required this.freshness,
    required this.selectedSection,
    required this.timeline,
    required this.presence,
    required this.reactionTally,
    required this.partyChat,
    required this.officialHub,
    required this.callsPaused,
    required this.myGame,
    required this.unread,
    required this.rewards,
    required this.matchPulse,
    required this.newTimelineCount,
    required this.followingLive,
    required this.revision,
    this.activeCall,
    this.quickCall,
    this.settledCalls = const [],
    this.lineup,
    this.supportedStats,
    this.callsPausedReason,
    this.replayState,
    this.latestRecap,
  });
}
