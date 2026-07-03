// Dart mirrors of the backend's serialized RoomView (see lib/store/types.ts).

class Team {
  final String id, name, code, flag;
  final int rating;
  Team({required this.id, required this.name, required this.code, required this.flag, required this.rating});
  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        code: j['code'] ?? '',
        flag: j['flag'] ?? '🏳️',
        rating: (j['rating'] ?? 75) as int,
      );
}

class FixtureScore {
  final int home, away, minute, clockSeconds;
  final bool running;
  FixtureScore(this.home, this.away, this.minute, this.clockSeconds, this.running);
  factory FixtureScore.fromJson(Map<String, dynamic> j) => FixtureScore(
        (j['home'] ?? 0) as int,
        (j['away'] ?? 0) as int,
        (j['minute'] ?? 0) as int,
        (j['clockSeconds'] ?? ((j['minute'] ?? 0) as int) * 60) as int,
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
        score: j['score'] != null ? FixtureScore.fromJson(Map<String, dynamic>.from(j['score'])) : null,
      );
}

class RoomSummary {
  final String id, code, name, status;
  final Fixture fixture;
  final int memberCount;
  final ScoreView? score;
  RoomSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.fixture,
    required this.memberCount,
    required this.score,
  });
  factory RoomSummary.fromJson(Map<String, dynamic> j) => RoomSummary(
        id: j['id'],
        code: j['code'],
        name: j['name'],
        status: j['status'],
        fixture: Fixture.fromJson(j['fixture']),
        memberCount: j['memberCount'] ?? 0,
        score: j['score'] == null ? null : ScoreView.fromJson(j['score']),
      );
}

class StatPair {
  final int home, away;
  StatPair(this.home, this.away);
  factory StatPair.fromJson(Map<String, dynamic>? j) =>
      j == null ? StatPair(0, 0) : StatPair((j['home'] ?? 0) as int, (j['away'] ?? 0) as int);
}

/// One period's stat lines (a half or extra-time period).
class PeriodStat {
  final StatPair goals, yellow, red, corners;
  PeriodStat({required this.goals, required this.yellow, required this.red, required this.corners});
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
        minute: (j['minute'] ?? 0) as int,
        clockSeconds: (j['clockSeconds'] ?? ((j['minute'] ?? 0) as int) * 60) as int,
        running: (j['running'] ?? false) as bool,
        phase: (j['phase'] ?? 0) as int,
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
      : WinChance((j['home'] ?? 33) as int, (j['draw'] ?? 34) as int, (j['away'] ?? 33) as int);
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
        points: (j['points'] ?? 0) as int,
        streak: (j['streak'] ?? 0) as int,
        bestStreak: (j['bestStreak'] ?? 0) as int,
        correct: (j['correct'] ?? 0) as int,
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
        reactions: ((j['reactions'] ?? {}) as Map).map((k, v) => MapEntry(k as String, (v ?? 0) as int)),
      );
}

class MotmCandidate {
  final String key, name, teamCode;
  final int votes;
  MotmCandidate({required this.key, required this.name, required this.teamCode, required this.votes});
  factory MotmCandidate.fromJson(Map<String, dynamic> j) =>
      MotmCandidate(key: j['key'], name: j['name'] ?? '', teamCode: j['teamCode'] ?? '', votes: (j['votes'] ?? 0) as int);
}

class MotmPoll {
  final int totalVotes;
  final List<MotmCandidate> candidates;
  final String? myVote;
  MotmPoll({required this.totalVotes, required this.candidates, this.myVote});
  factory MotmPoll.fromJson(Map<String, dynamic> j) => MotmPoll(
        totalVotes: (j['totalVotes'] ?? 0) as int,
        myVote: j['myVote'],
        candidates: ((j['candidates'] ?? []) as List).map((c) => MotmCandidate.fromJson(c)).toList(),
      );
}

class PulseCard {
  final String id, kind, emoji, headline, detail, accent;
  final int minute;
  final String? scorer; // player name for goal cards (local engine)
  PulseCard({
    required this.id,
    required this.kind,
    required this.emoji,
    required this.headline,
    required this.detail,
    required this.accent,
    required this.minute,
    this.scorer,
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
  });
  factory PromptView.fromJson(Map<String, dynamic> j) => PromptView(
        id: j['id'],
        question: j['question'] ?? '',
        status: j['status'] ?? 'open',
        winningKey: j['winningKey'],
        basePoints: (j['basePoints'] ?? 0) as int,
        locksAtMinute: (j['locksAtMinute'] ?? 0) as int,
        createdAt: (j['createdAt'] ?? 0) as int,
        options: ((j['options'] ?? []) as List).map((o) => SwingOption.fromJson(o)).toList(),
        tally: ((j['tally'] ?? {}) as Map).map((k, v) => MapEntry(k as String, (v ?? 0) as int)),
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
  factory RoomModes.fromJson(Map<String, dynamic>? j) =>
      j == null ? RoomModes(true, true) : RoomModes(j['draft'] ?? true, j['nextSwing'] ?? true);
}

class ShootoutKick {
  final String side; // 'home' | 'away'
  final bool scored;
  ShootoutKick({required this.side, required this.scored});
  factory ShootoutKick.fromJson(Map<String, dynamic> j) => ShootoutKick(side: j['side'] ?? 'home', scored: j['scored'] ?? false);
}

class ShootoutView {
  final int home, away;
  final List<ShootoutKick> kicks;
  final bool decided;
  final String? winnerSide;
  ShootoutView({required this.home, required this.away, required this.kicks, required this.decided, this.winnerSide});
  factory ShootoutView.fromJson(Map<String, dynamic> j) => ShootoutView(
        home: (j['home'] ?? 0) as int,
        away: (j['away'] ?? 0) as int,
        kicks: ((j['kicks'] ?? []) as List).map((k) => ShootoutKick.fromJson(k)).toList(),
        decided: j['decided'] ?? false,
        winnerSide: j['winnerSide'],
      );
}

class RoomView {
  final String id, code, name, hostId, status;
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
  final List<PromptView> prompts;
  final List<RecapView> recaps;
  final ProofInfo proof;
  final bool spoilerSafe;
  final bool voice;
  final String reactionPack;
  final MotmPoll? motm;

  RoomView({
    required this.id,
    required this.code,
    required this.name,
    required this.hostId,
    required this.status,
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
    required this.prompts,
    required this.recaps,
    required this.proof,
    this.spoilerSafe = false,
    this.voice = false,
    this.reactionPack = 'classic',
    this.motm,
  });

  factory RoomView.fromJson(Map<String, dynamic> j) => RoomView(
        id: j['id'],
        code: j['code'] ?? '',
        name: j['name'] ?? '',
        hostId: j['hostId'] ?? '',
        status: j['status'] ?? 'lobby',
        fixture: Fixture.fromJson(j['fixture']),
        modes: RoomModes.fromJson(j['modes']),
        momentum: (j['momentum'] ?? 0) as int,
        win: WinChance.fromJson(j['win']),
        winHistory: ((j['winHistory'] ?? []) as List).map((e) => (e as num).toInt()).toList(),
        shootout: j['shootout'] == null ? null : ShootoutView.fromJson(j['shootout']),
        score: j['score'] == null ? null : ScoreView.fromJson(j['score']),
        members: ((j['members'] ?? []) as List).map((m) => MemberView.fromJson(m)).toList(),
        chat: ((j['chat'] ?? []) as List).map((c) => ChatView.fromJson(c)).toList(),
        pulse: ((j['pulse'] ?? []) as List).map((p) => PulseCard.fromJson(p)).toList(),
        prompts: ((j['prompts'] ?? []) as List).map((p) => PromptView.fromJson(p)).toList(),
        recaps: ((j['recaps'] ?? []) as List).map((r) => RecapView.fromJson(r)).toList(),
        proof: ProofInfo.fromJson(j['proof'] ?? {}),
        spoilerSafe: j['spoilerSafe'] ?? false,
        voice: j['voice'] ?? false,
        reactionPack: j['reactionPack'] ?? 'classic',
        motm: j['motm'] == null ? null : MotmPoll.fromJson(j['motm']),
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
List<String> packEmojis(String pack) => reactionPacks[pack] ?? reactionPacks['classic']!;

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
