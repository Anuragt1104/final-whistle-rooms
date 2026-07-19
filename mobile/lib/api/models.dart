// Dart mirrors of the backend's serialized RoomView (see lib/store/types.ts).

class Team {
  final String id, name, code, flag;
  final int rating;
  Team({
    required this.id,
    required this.name,
    required this.code,
    required this.flag,
    required this.rating,
  });
  factory Team.fromJson(Map<String, dynamic> j) => Team(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    code: j['code'] ?? '',
    flag: j['flag'] ?? '🏳️',
    rating: (j['rating'] as num?)?.toInt() ?? 75,
  );
}

class FixtureScore {
  final int home, away, minute, clockSeconds;
  final bool running;
  FixtureScore(
    this.home,
    this.away,
    this.minute,
    this.clockSeconds,
    this.running,
  );
  factory FixtureScore.fromJson(Map<String, dynamic> j) => FixtureScore(
    (j['home'] as num?)?.toInt() ?? 0,
    (j['away'] as num?)?.toInt() ?? 0,
    (j['minute'] as num?)?.toInt() ?? 0,
    (j['clockSeconds'] as num?)?.toInt() ??
        ((j['minute'] as num?)?.toInt() ?? 0) * 60,
    (j['running'] ?? false) as bool,
  );
}

class Fixture {
  final String id, competition, stage, kickoff, venue, status;
  final Team home, away;
  final FixtureScore? score; // live/final score (live + finished only)
  Fixture({
    required this.id,
    required this.competition,
    required this.stage,
    required this.kickoff,
    required this.venue,
    required this.status,
    required this.home,
    required this.away,
    this.score,
  });
  factory Fixture.fromJson(Map<String, dynamic> j) => Fixture(
    id: j['id'] ?? '',
    competition: j['competition'] ?? '',
    stage: j['stage'] ?? '',
    kickoff: j['kickoff'] ?? '',
    venue: j['venue'] ?? '',
    status: j['status'] ?? 'scheduled',
    home: Team.fromJson(j['home']),
    away: Team.fromJson(j['away']),
    score: j['score'] != null
        ? FixtureScore.fromJson(Map<String, dynamic>.from(j['score']))
        : null,
  );
}

class RoomSummary {
  final String id, code, name, status, kind;
  final bool autoManaged;
  final Fixture fixture;
  final int memberCount;
  final ScoreView? score;
  RoomSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.kind,
    required this.autoManaged,
    required this.fixture,
    required this.memberCount,
    required this.score,
  });
  factory RoomSummary.fromJson(Map<String, dynamic> j) => RoomSummary(
    id: j['id'],
    code: j['code'],
    name: j['name'],
    status: j['status'],
    kind: j['kind'] ?? 'party',
    autoManaged: j['autoManaged'] == true,
    fixture: Fixture.fromJson(j['fixture']),
    memberCount: j['memberCount'] ?? 0,
    score: j['score'] == null ? null : ScoreView.fromJson(j['score']),
  );
}

class StatPair {
  final int home, away;
  StatPair(this.home, this.away);
  factory StatPair.fromJson(Map<String, dynamic>? j) => j == null
      ? StatPair(0, 0)
      : StatPair(
          (j['home'] as num?)?.toInt() ?? 0,
          (j['away'] as num?)?.toInt() ?? 0,
        );
}

/// One period's stat lines (a half or extra-time period).
class PeriodStat {
  final StatPair goals, yellow, red, corners;
  PeriodStat({
    required this.goals,
    required this.yellow,
    required this.red,
    required this.corners,
  });
  factory PeriodStat.fromJson(Map<String, dynamic> j) => PeriodStat(
    goals: StatPair.fromJson(j['goals']),
    yellow: StatPair.fromJson(j['yellow']),
    red: StatPair.fromJson(j['red']),
    corners: StatPair.fromJson(j['corners']),
  );
}

class MatchPeriods {
  final PeriodStat firstHalf, secondHalf;
  MatchPeriods({required this.firstHalf, required this.secondHalf});
  factory MatchPeriods.fromJson(Map<String, dynamic> j) => MatchPeriods(
    firstHalf: PeriodStat.fromJson(j['firstHalf']),
    secondHalf: PeriodStat.fromJson(j['secondHalf']),
  );
}

class ScoreView {
  final int minute, phase;
  final int clockSeconds;
  final bool running;
  final String? statusNote;
  final StatPair goals, yellow, red, corners;
  final MatchPeriods? periods;
  ScoreView({
    required this.minute,
    required this.clockSeconds,
    required this.running,
    required this.phase,
    this.statusNote,
    required this.goals,
    required this.yellow,
    required this.red,
    required this.corners,
    this.periods,
  });
  factory ScoreView.fromJson(Map<String, dynamic> j) => ScoreView(
    minute: (j['minute'] as num?)?.toInt() ?? 0,
    clockSeconds:
        (j['clockSeconds'] as num?)?.toInt() ??
        ((j['minute'] as num?)?.toInt() ?? 0) * 60,
    running: (j['running'] ?? false) as bool,
    phase: (j['phase'] as num?)?.toInt() ?? 0,
    statusNote: j['statusNote'],
    goals: StatPair.fromJson(j['goals']),
    yellow: StatPair.fromJson(j['yellow']),
    red: StatPair.fromJson(j['red']),
    corners: StatPair.fromJson(j['corners']),
    periods: j['periods'] == null ? null : MatchPeriods.fromJson(j['periods']),
  );
}

class WinChance {
  final int home, draw, away;
  WinChance(this.home, this.draw, this.away);
  factory WinChance.fromJson(Map<String, dynamic>? j) => j == null
      ? WinChance(33, 34, 33)
      : WinChance(
          (j['home'] as num?)?.toInt() ?? 33,
          (j['draw'] as num?)?.toInt() ?? 34,
          (j['away'] as num?)?.toInt() ?? 33,
        );
}

class MemberView {
  final String id, name, avatar;
  final String? side, walletShort;
  final int points, streak, bestStreak, correct;
  final bool isHost;
  MemberView({
    required this.id,
    required this.name,
    required this.avatar,
    required this.side,
    required this.walletShort,
    required this.points,
    required this.streak,
    required this.bestStreak,
    required this.correct,
    required this.isHost,
  });
  factory MemberView.fromJson(Map<String, dynamic> j) => MemberView(
    id: j['id'],
    name: j['name'] ?? 'Fan',
    avatar: j['avatar'] ?? '👤',
    side: j['side'],
    walletShort: j['walletShort'],
    points: (j['points'] as num?)?.toInt() ?? 0,
    streak: (j['streak'] as num?)?.toInt() ?? 0,
    bestStreak: (j['bestStreak'] as num?)?.toInt() ?? 0,
    correct: (j['correct'] as num?)?.toInt() ?? 0,
    isHost: j['isHost'] ?? false,
  );
}

class ChatView {
  final String id, memberId, name, avatar, text, kind;
  final int ts;
  final Map<String, int> reactions; // emoji -> count
  ChatView({
    required this.id,
    required this.memberId,
    required this.name,
    required this.avatar,
    required this.text,
    required this.kind,
    required this.ts,
    this.reactions = const {},
  });
  factory ChatView.fromJson(Map<String, dynamic> j) => ChatView(
    id: j['id'],
    memberId: j['memberId'] ?? '',
    name: j['name'] ?? 'Fan',
    avatar: j['avatar'] ?? '👤',
    text: j['text'] ?? '',
    kind: j['kind'] ?? 'chat',
    ts: (j['ts'] ?? 0) as int,
    reactions: ((j['reactions'] ?? {}) as Map).map(
      (k, v) => MapEntry(k as String, (v ?? 0) as int),
    ),
  );
}

class MotmCandidate {
  final String key, name, teamCode;
  final int votes;
  MotmCandidate({
    required this.key,
    required this.name,
    required this.teamCode,
    required this.votes,
  });
  factory MotmCandidate.fromJson(Map<String, dynamic> j) => MotmCandidate(
    key: j['key'],
    name: j['name'] ?? '',
    teamCode: j['teamCode'] ?? '',
    votes: (j['votes'] ?? 0) as int,
  );
}

class MotmPoll {
  final int totalVotes;
  final List<MotmCandidate> candidates;
  final String? myVote;
  MotmPoll({required this.totalVotes, required this.candidates, this.myVote});
  factory MotmPoll.fromJson(Map<String, dynamic> j) => MotmPoll(
    totalVotes: (j['totalVotes'] ?? 0) as int,
    myVote: j['myVote'],
    candidates: ((j['candidates'] ?? []) as List)
        .map((c) => MotmCandidate.fromJson(c))
        .toList(),
  );
}

class PulseCard {
  final String id, kind, emoji, headline, detail, accent;
  final int minute;
  final String? scorer; // player name for goal cards (local engine)
  final String? sourceEventId;
  final String? side;
  PulseCard({
    required this.id,
    required this.kind,
    required this.emoji,
    required this.headline,
    required this.detail,
    required this.accent,
    required this.minute,
    this.scorer,
    this.sourceEventId,
    this.side,
  });
  factory PulseCard.fromJson(Map<String, dynamic> j) => PulseCard(
    id: j['id'],
    kind: j['kind'] ?? '',
    emoji: j['emoji'] ?? '•',
    headline: j['headline'] ?? '',
    detail: j['detail'] ?? '',
    accent: j['accent'] ?? 'neutral',
    minute: (j['minute'] ?? 0) as int,
    scorer: j['scorer'],
    sourceEventId: j['sourceEventId']?.toString(),
    side: j['side']?.toString(),
  );
}

class ReplayStateView {
  final bool active, paused;
  final int currentMinute, totalMinutes;
  final double speed;
  final String mode;
  final int beat;
  final int? nextBeatMinute;
  final bool awaitingAction;
  const ReplayStateView({
    required this.active,
    required this.paused,
    required this.currentMinute,
    required this.totalMinutes,
    required this.speed,
    this.mode = 'standard',
    this.beat = 0,
    this.nextBeatMinute,
    this.awaitingAction = false,
  });
  factory ReplayStateView.fromJson(Map<String, dynamic> j) => ReplayStateView(
    active: j['active'] == true,
    paused: j['paused'] == true,
    currentMinute: (j['currentMinute'] as num?)?.toInt() ?? 0,
    totalMinutes: (j['totalMinutes'] as num?)?.toInt() ?? 90,
    speed: (j['speed'] as num?)?.toDouble() ?? 1,
    mode: j['mode']?.toString() ?? 'standard',
    beat: (j['beat'] as num?)?.toInt() ?? 0,
    nextBeatMinute: (j['nextBeatMinute'] as num?)?.toInt(),
    awaitingAction: j['awaitingAction'] == true,
  );
}

class SwingOption {
  final String key, label;
  final String? hint;
  SwingOption({required this.key, required this.label, this.hint});
  factory SwingOption.fromJson(Map<String, dynamic> j) =>
      SwingOption(key: j['key'], label: j['label'] ?? '', hint: j['hint']);
}

class PromptView {
  final String id, question, status;
  final String? winningKey;
  final int basePoints, locksAtMinute, createdAt;
  final List<SwingOption> options;
  final Map<String, int> tally;
  final String? lane;
  final String? category;
  final String? ruleId;
  final String? reason;
  final double? urgency;
  final int? openedClockSec;
  final int? answerClosesAt;
  final int? resolutionDeadlineClockSec;
  final String? feedFreshness;
  final String? sourceAttribution;
  final String? rewardPreview;
  final String? fanBuzzUrl;
  final String? fanBuzzFact;
  PromptView({
    required this.id,
    required this.question,
    required this.status,
    required this.winningKey,
    required this.basePoints,
    required this.locksAtMinute,
    required this.createdAt,
    required this.options,
    required this.tally,
    this.lane,
    this.category,
    this.ruleId,
    this.reason,
    this.urgency,
    this.openedClockSec,
    this.answerClosesAt,
    this.resolutionDeadlineClockSec,
    this.feedFreshness,
    this.sourceAttribution,
    this.rewardPreview,
    this.fanBuzzUrl,
    this.fanBuzzFact,
  });
  factory PromptView.fromJson(Map<String, dynamic> j) => PromptView(
    id: j['id'],
    question: j['question'] ?? '',
    status: j['status'] ?? 'open',
    // Winner only trusted after settle — ignore premature keys.
    winningKey: const {'settled', 'void', 'corrected'}.contains(j['status'])
        ? j['winningKey'] as String?
        : null,
    basePoints: (j['basePoints'] ?? 0) as int,
    locksAtMinute: (j['locksAtMinute'] ?? 0) as int,
    createdAt: (j['createdAt'] ?? 0) as int,
    options: ((j['options'] ?? []) as List)
        .map((o) => SwingOption.fromJson(o))
        .toList(),
    tally: ((j['tally'] ?? {}) as Map).map(
      (k, v) => MapEntry(k as String, (v ?? 0) as int),
    ),
    lane: j['lane'] as String?,
    category: j['category'] as String?,
    ruleId: j['ruleId'] as String?,
    reason: j['reason'] as String?,
    urgency: (j['urgency'] as num?)?.toDouble(),
    openedClockSec: j['openedClockSec'] as int?,
    answerClosesAt: j['answerClosesAt'] as int?,
    resolutionDeadlineClockSec: j['resolutionDeadlineClockSec'] as int?,
    feedFreshness: j['feedFreshness'] as String?,
    sourceAttribution: j['sourceAttribution'] as String?,
    rewardPreview: j['rewardPreview'] as String?,
    fanBuzzUrl: j['fanBuzzUrl'] as String?,
    fanBuzzFact: j['fanBuzzFact'] as String?,
  );
}

class RecapView {
  final String id, scope, text;
  final String? topMember;
  final int minute;
  RecapView({
    required this.id,
    required this.scope,
    required this.text,
    required this.topMember,
    required this.minute,
  });
  factory RecapView.fromJson(Map<String, dynamic> j) => RecapView(
    id: j['id'],
    scope: j['scope'] ?? 'full-time',
    text: j['text'] ?? '',
    topMember: j['topMember'],
    minute: (j['minute'] ?? 0) as int,
  );
}

class ProofInfo {
  final int leafCount;
  final String? root, anchorSignature;
  final bool anchored;
  final String cluster;
  ProofInfo({
    required this.leafCount,
    required this.root,
    required this.anchorSignature,
    required this.anchored,
    required this.cluster,
  });
  factory ProofInfo.fromJson(Map<String, dynamic> j) => ProofInfo(
    leafCount: (j['leafCount'] ?? 0) as int,
    root: j['root'],
    anchorSignature: j['anchorSignature'],
    anchored: j['anchored'] ?? false,
    cluster: j['cluster'] ?? 'devnet',
  );
}

class RoomModes {
  final bool draft, nextSwing;
  RoomModes(this.draft, this.nextSwing);
  factory RoomModes.fromJson(Map<String, dynamic>? j) => j == null
      ? RoomModes(true, true)
      : RoomModes(j['draft'] ?? true, j['nextSwing'] ?? true);
}

class ShootoutKick {
  final String side; // 'home' | 'away'
  final bool scored;
  ShootoutKick({required this.side, required this.scored});
  factory ShootoutKick.fromJson(Map<String, dynamic> j) =>
      ShootoutKick(side: j['side'] ?? 'home', scored: j['scored'] ?? false);
}

class ShootoutView {
  final int home, away;
  final List<ShootoutKick> kicks;
  final bool decided;
  final String? winnerSide;
  ShootoutView({
    required this.home,
    required this.away,
    required this.kicks,
    required this.decided,
    this.winnerSide,
  });
  factory ShootoutView.fromJson(Map<String, dynamic> j) => ShootoutView(
    home: (j['home'] ?? 0) as int,
    away: (j['away'] ?? 0) as int,
    kicks: ((j['kicks'] ?? []) as List)
        .map((k) => ShootoutKick.fromJson(k))
        .toList(),
    decided: j['decided'] ?? false,
    winnerSide: j['winnerSide'],
  );
}

class MomentDropView {
  final String id, memberId, kind, label, matchLabel;
  final int rarity, minute, createdAt;
  final String? sourceEventId,
      playerId,
      playerName,
      teamCode,
      imageUrl,
      artworkKind;
  final bool calledIt;
  final String? promptId, promptQuestion, answerLabel;
  final Map<String, dynamic>? proof;
  MomentDropView({
    required this.id,
    required this.memberId,
    required this.kind,
    required this.label,
    required this.matchLabel,
    required this.rarity,
    required this.minute,
    required this.createdAt,
    this.sourceEventId,
    this.playerId,
    this.playerName,
    this.teamCode,
    this.imageUrl,
    this.artworkKind,
    this.calledIt = false,
    this.promptId,
    this.promptQuestion,
    this.answerLabel,
    this.proof,
  });
  factory MomentDropView.fromJson(Map<String, dynamic> j) => MomentDropView(
    id: j['id'] ?? '',
    memberId: j['memberId'] ?? '',
    kind: j['kind'] ?? '',
    label: j['label'] ?? '',
    matchLabel: j['matchLabel'] ?? '',
    rarity: (j['rarity'] as num?)?.toInt() ?? 1,
    minute: (j['minute'] as num?)?.toInt() ?? 0,
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    sourceEventId: j['sourceEventId']?.toString(),
    playerId: j['playerId']?.toString(),
    playerName: j['playerName']?.toString(),
    teamCode: j['teamCode']?.toString(),
    imageUrl: j['imageUrl']?.toString(),
    artworkKind: (j['artKey'] ?? j['artworkKind'])?.toString(),
    calledIt: j['calledIt'] == true,
    promptId: j['promptId']?.toString(),
    promptQuestion: j['promptQuestion']?.toString(),
    answerLabel: j['answerLabel']?.toString(),
    proof: j['proof'] is Map
        ? Map<String, dynamic>.from(j['proof'] as Map)
        : null,
  );
}

class RoomView {
  final String id, code, name, hostId, status, kind;
  final bool autoManaged;
  final Fixture fixture;
  final RoomModes modes;
  final int momentum;
  final WinChance win;
  final List<int> winHistory;
  final ShootoutView? shootout;
  final ScoreView? score;
  final List<MemberView> members;
  final List<ChatView> chat;
  final List<PulseCard> pulse;
  final List<MomentDropView> momentDrops;
  final List<PromptView> prompts;
  final List<RecapView> recaps;
  final ProofInfo proof;
  final bool spoilerSafe;
  final bool replay;
  final bool voice;
  final String reactionPack;
  final MotmPoll? motm;
  final String lifecycle;
  final String feedFreshness;
  final String lineupStatus;
  final int? sourceUpdatedAt;
  final int revision;
  final Map<String, int> reactionTally;
  final ReplayStateView? replayState;
  final List<Map<String, dynamic>> markets;

  RoomView({
    required this.id,
    required this.code,
    required this.name,
    required this.hostId,
    required this.status,
    required this.kind,
    required this.autoManaged,
    required this.fixture,
    required this.modes,
    required this.momentum,
    required this.win,
    this.winHistory = const [],
    this.shootout,
    required this.score,
    required this.members,
    required this.chat,
    required this.pulse,
    this.momentDrops = const [],
    required this.prompts,
    required this.recaps,
    required this.proof,
    this.spoilerSafe = false,
    this.replay = false,
    this.voice = false,
    this.reactionPack = 'classic',
    this.motm,
    this.lifecycle = 'pregame',
    this.feedFreshness = 'waiting',
    this.lineupStatus = 'unknown',
    this.sourceUpdatedAt,
    this.revision = 0,
    this.reactionTally = const {},
    this.replayState,
    this.markets = const [],
  });

  factory RoomView.fromJson(Map<String, dynamic> j) => RoomView(
    id: j['id'],
    code: j['code'] ?? '',
    name: j['name'] ?? '',
    hostId: j['hostId'] ?? '',
    status: j['status'] ?? 'lobby',
    kind: j['kind'] ?? 'party',
    autoManaged: j['autoManaged'] == true,
    fixture: Fixture.fromJson(j['fixture']),
    modes: RoomModes.fromJson(j['modes']),
    momentum: (j['momentum'] as num?)?.toInt() ?? 0,
    win: WinChance.fromJson(j['win']),
    winHistory: ((j['winHistory'] ?? []) as List)
        .map((e) => (e as num).toInt())
        .toList(),
    shootout: j['shootout'] == null
        ? null
        : ShootoutView.fromJson(j['shootout']),
    score: j['score'] == null ? null : ScoreView.fromJson(j['score']),
    members: ((j['members'] ?? []) as List)
        .map((m) => MemberView.fromJson(m))
        .toList(),
    chat: ((j['chat'] ?? []) as List).map((c) => ChatView.fromJson(c)).toList(),
    pulse: ((j['pulse'] ?? []) as List)
        .map((p) => PulseCard.fromJson(p))
        .toList(),
    momentDrops: ((j['momentDrops'] ?? []) as List)
        .map((p) => MomentDropView.fromJson(p))
        .toList(),
    prompts: ((j['prompts'] ?? []) as List)
        .map((p) => PromptView.fromJson(p))
        .toList(),
    recaps: ((j['recaps'] ?? []) as List)
        .map((r) => RecapView.fromJson(r))
        .toList(),
    proof: ProofInfo.fromJson(j['proof'] ?? {}),
    spoilerSafe: j['spoilerSafe'] ?? false,
    replay: j['replay'] ?? false,
    voice: j['voice'] ?? false,
    reactionPack: j['reactionPack'] ?? 'classic',
    motm: j['motm'] == null ? null : MotmPoll.fromJson(j['motm']),
    lifecycle:
        '${j['lifecycle'] ?? (j['status'] == 'finished'
                ? 'finished'
                : j['status'] == 'live'
                ? 'live'
                : 'pregame')}',
    feedFreshness: '${j['feedFreshness'] ?? 'waiting'}',
    lineupStatus: '${j['lineupStatus'] ?? 'unknown'}',
    sourceUpdatedAt: (j['sourceUpdatedAt'] as num?)?.toInt(),
    revision: (j['revision'] as num?)?.toInt() ?? 0,
    reactionTally: ((j['reactionTally'] ?? {}) as Map).map(
      (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
    ),
    replayState: j['replayState'] is Map
        ? ReplayStateView.fromJson(Map<String, dynamic>.from(j['replayState']))
        : null,
    markets: ((j['markets'] ?? []) as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(),
  );
}

/// Reaction packs (chosen at create). Pack key -> emoji list.
const Map<String, List<String>> reactionPacks = {
  'classic': ['🔥', '⚽', '😱', '👏', '🎉', '😤'],
  'party': ['🎟️', '🍺', '🎉', '🥳', '🙌', '🎊'],
  'drama': ['😂', '❤️', '😱', '😭', '🤯', '💔'],
  // Pro-only pack (Season Pass) — richer set unlocked by the entitlement.
  'pro': ['🔥', '⚽', '🚀', '🐐', '🤯', '💎', '🫡', '🥶', '👑', '💯'],
};
List<String> packEmojis(String pack) =>
    reactionPacks[pack] ?? reactionPacks['classic']!;

/// GamePhase (numeric) -> label, mirrored from the backend enum.
String phaseLabel(int phase) {
  switch (phase) {
    case 0:
      return 'Pre-match';
    case 1:
      return '1st half';
    case 2:
      return 'Half-time';
    case 3:
      return '2nd half';
    case 4:
      return 'Full-time';
    case 5:
      return 'Extra time';
    case 6:
      return 'ET break';
    case 7:
      return 'Extra time';
    case 8:
      return 'Penalties';
    case 9:
      return 'Finished';
    case 10:
      return 'Abandoned';
    default:
      return '—';
  }
}
