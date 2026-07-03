import 'dart:math';

import '../api/models.dart';
import 'squads.dart';

/// Deterministic "match facts" engine — the FotMob/Sofascore data layer, fully
/// on-device. Every fixture id always produces the same final score, goal
/// scorers, cards, substitutions, team stats (possession, xG, shots…) and
/// player ratings, so tables, brackets, the Golden Boot race and match pages
/// all agree with each other without any backend.

class MatchEvent {
  final int minute;
  final String kind; // 'goal' | 'yellow' | 'red' | 'sub'
  final String side; // 'home' | 'away'
  final String player;
  final String? assist; // goal: assist name; sub: player coming on
  MatchEvent({required this.minute, required this.kind, required this.side, required this.player, this.assist});
}

class TeamStats {
  final int possession; // %
  final int shots, onTarget, corners, fouls, offsides, passes, passAccuracy, bigChances, saves, tackles, yellow, red;
  final double xg;
  TeamStats({
    required this.possession,
    required this.shots,
    required this.onTarget,
    required this.corners,
    required this.fouls,
    required this.offsides,
    required this.passes,
    required this.passAccuracy,
    required this.bigChances,
    required this.saves,
    required this.tackles,
    required this.yellow,
    required this.red,
    required this.xg,
  });
}

class PlayerRating {
  final SquadPlayer player;
  final double rating;
  final int goals, assists;
  final bool motm;
  PlayerRating({required this.player, required this.rating, this.goals = 0, this.assists = 0, this.motm = false});
}

class MatchFacts {
  final String fixtureId;
  final int homeGoals, awayGoals;
  final List<MatchEvent> events; // sorted by minute
  final TeamStats home, away;
  final List<PlayerRating> homeRatings, awayRatings; // XI order
  final String motmName;
  final String motmSide;
  MatchFacts({
    required this.fixtureId,
    required this.homeGoals,
    required this.awayGoals,
    required this.events,
    required this.home,
    required this.away,
    required this.homeRatings,
    required this.awayRatings,
    required this.motmName,
    required this.motmSide,
  });

  /// Goals scored up to (and including) a given minute — used to show honest
  /// partial scores for in-play fixtures.
  int goalsAt(String side, int minute) =>
      events.where((e) => e.kind == 'goal' && e.side == side && e.minute <= minute).length;
}

final Map<String, MatchFacts> _factsCache = {};

MatchFacts factsFor(Fixture f) => _factsCache[f.id] ??= _generate(f);

/// Final score only (cheap accessor used by standings/bracket).
({int home, int away}) finalScoreFor(Fixture f) {
  final m = factsFor(f);
  return (home: m.homeGoals, away: m.awayGoals);
}

/// For a drawn knockout tie: who advances on penalties. Deterministic.
bool knockoutHomeAdvances(Fixture f) {
  final m = factsFor(f);
  if (m.homeGoals != m.awayGoals) return m.homeGoals > m.awayGoals;
  return Random(f.id.hashCode ^ 0x5EED).nextBool();
}

MatchFacts _generate(Fixture f) {
  final rng = Random(f.id.hashCode);
  final homeSq = squadFor(f.home);
  final awaySq = squadFor(f.away);

  // ---- final score from team strength ----
  final diff = (f.home.rating - f.away.rating).toDouble();
  final hExp = (1.35 + diff * 0.045).clamp(0.25, 3.4);
  final aExp = (1.35 - diff * 0.045).clamp(0.25, 3.4);
  final hGoals = _poisson(rng, hExp);
  final aGoals = _poisson(rng, aExp);

  // ---- events ----
  final events = <MatchEvent>[];
  final usedMinutes = <int>{};
  int freshMinute() {
    int m;
    do {
      m = 2 + rng.nextInt(89);
    } while (usedMinutes.contains(m));
    usedMinutes.add(m);
    return m;
  }

  final homeScorers = <String, int>{};
  final awayScorers = <String, int>{};
  final homeAssists = <String, int>{};
  final awayAssists = <String, int>{};

  void addGoals(String side, int count, TeamSquad sq, Map<String, int> scorers, Map<String, int> assists) {
    final xi = sq.startingXI;
    for (var i = 0; i < count; i++) {
      final scorer = _weightedPick(rng, xi);
      String? assist;
      if (rng.nextDouble() < 0.72) {
        final others = xi.where((p) => p.name != scorer.name && p.pos != 'GK').toList();
        assist = others[rng.nextInt(others.length)].name;
        assists[assist] = (assists[assist] ?? 0) + 1;
      }
      scorers[scorer.name] = (scorers[scorer.name] ?? 0) + 1;
      events.add(MatchEvent(minute: freshMinute(), kind: 'goal', side: side, player: scorer.name, assist: assist));
    }
  }

  addGoals('home', hGoals, homeSq, homeScorers, homeAssists);
  addGoals('away', aGoals, awaySq, awayScorers, awayAssists);

  // cards
  final hYellow = rng.nextInt(4);
  final aYellow = rng.nextInt(4);
  final hRed = rng.nextDouble() < 0.06 ? 1 : 0;
  final aRed = rng.nextDouble() < 0.06 ? 1 : 0;
  void addCards(String side, int yellow, int red, TeamSquad sq) {
    final xi = sq.startingXI.where((p) => p.pos != 'GK').toList();
    for (var i = 0; i < yellow; i++) {
      events.add(MatchEvent(minute: freshMinute(), kind: 'yellow', side: side, player: xi[rng.nextInt(xi.length)].name));
    }
    for (var i = 0; i < red; i++) {
      events.add(MatchEvent(minute: 50 + rng.nextInt(40), kind: 'red', side: side, player: xi[rng.nextInt(xi.length)].name));
    }
  }

  addCards('home', hYellow, hRed, homeSq);
  addCards('away', aYellow, aRed, awaySq);

  // substitutions (2-3 per side, 55'–85')
  void addSubs(String side, TeamSquad sq) {
    final bench = sq.bench.where((p) => p.pos != 'GK').toList()..shuffle(rng);
    final outfield = sq.startingXI.where((p) => p.pos != 'GK').toList()..shuffle(rng);
    final n = min(2 + rng.nextInt(2), min(bench.length, outfield.length));
    for (var i = 0; i < n; i++) {
      events.add(MatchEvent(
        minute: 55 + rng.nextInt(31),
        kind: 'sub',
        side: side,
        player: outfield[i].name,
        assist: bench[i].name,
      ));
    }
  }

  addSubs('home', homeSq);
  addSubs('away', awaySq);
  events.sort((a, b) => a.minute.compareTo(b.minute));

  // ---- team stats, anchored to the scoreline so nothing contradicts ----
  final possHome = (50 + diff * 0.65 + rng.nextInt(7) - 3).clamp(28, 72).round();
  TeamStats mkStats(int goals, int oppGoals, int poss, int yellow, int red, Random r) {
    final shots = goals * 2 + 5 + r.nextInt(8);
    final onTarget = (goals + 1 + r.nextInt(max(1, shots - goals - 1))).clamp(goals, shots);
    final xg = (goals * 0.82 + onTarget * 0.09 + r.nextDouble() * 0.5);
    final passes = 320 + (poss - 30) * 12 + r.nextInt(60);
    return TeamStats(
      possession: poss,
      shots: shots,
      onTarget: onTarget,
      corners: 2 + r.nextInt(8),
      fouls: 7 + r.nextInt(9),
      offsides: r.nextInt(5),
      passes: passes,
      passAccuracy: 74 + r.nextInt(16),
      bigChances: goals + r.nextInt(3),
      saves: max(0, oppGoals == 0 ? 1 + r.nextInt(4) : r.nextInt(4)),
      tackles: 10 + r.nextInt(12),
      yellow: yellow,
      red: red,
      xg: double.parse(xg.toStringAsFixed(2)),
    );
  }

  final homeStats = mkStats(hGoals, aGoals, possHome, hYellow, hRed, Random(f.id.hashCode ^ 1));
  final awayStats = mkStats(aGoals, hGoals, 100 - possHome, aYellow, aRed, Random(f.id.hashCode ^ 2));

  // ---- player ratings ----
  List<PlayerRating> rate(TeamSquad sq, Map<String, int> scorers, Map<String, int> assists, bool won, bool drew, Random r) {
    return sq.startingXI.map((p) {
      var v = 6.3 + r.nextDouble() * 1.0;
      if (won) v += 0.35;
      if (drew) v += 0.1;
      v += (scorers[p.name] ?? 0) * 0.9;
      v += (assists[p.name] ?? 0) * 0.45;
      return PlayerRating(
        player: p,
        rating: double.parse(v.clamp(5.4, 10.0).toStringAsFixed(1)),
        goals: scorers[p.name] ?? 0,
        assists: assists[p.name] ?? 0,
      );
    }).toList();
  }

  final homeWon = hGoals > aGoals, drew = hGoals == aGoals;
  var homeRatings = rate(homeSq, homeScorers, homeAssists, homeWon, drew, Random(f.id.hashCode ^ 3));
  var awayRatings = rate(awaySq, awayScorers, awayAssists, !homeWon && !drew, drew, Random(f.id.hashCode ^ 4));

  // man of the match = single highest rating, flag it
  PlayerRating best = homeRatings.first;
  var motmSide = 'home';
  for (final pr in homeRatings) {
    if (pr.rating > best.rating) best = pr;
  }
  for (final pr in awayRatings) {
    if (pr.rating > best.rating) {
      best = pr;
      motmSide = 'away';
    }
  }
  PlayerRating flag(PlayerRating pr) =>
      PlayerRating(player: pr.player, rating: pr.rating, goals: pr.goals, assists: pr.assists, motm: true);
  if (motmSide == 'home') {
    homeRatings = homeRatings.map((pr) => pr.player.name == best.player.name ? flag(pr) : pr).toList();
  } else {
    awayRatings = awayRatings.map((pr) => pr.player.name == best.player.name ? flag(pr) : pr).toList();
  }

  return MatchFacts(
    fixtureId: f.id,
    homeGoals: hGoals,
    awayGoals: aGoals,
    events: events,
    home: homeStats,
    away: awayStats,
    homeRatings: homeRatings,
    awayRatings: awayRatings,
    motmName: best.player.name,
    motmSide: motmSide,
  );
}

SquadPlayer _weightedPick(Random rng, List<SquadPlayer> xi) {
  // forwards score most, then mids, then defenders; keepers never
  final weighted = <SquadPlayer>[];
  for (final p in xi) {
    final w = switch (p.pos) { 'FW' => 6, 'MF' => 3, 'DF' => 1, _ => 0 };
    for (var i = 0; i < w; i++) {
      weighted.add(p);
    }
  }
  return weighted[rng.nextInt(weighted.length)];
}

int _poisson(Random rng, double lambda) {
  final l = exp(-lambda);
  var k = 0;
  var p = 1.0;
  do {
    k++;
    p *= rng.nextDouble();
  } while (p > l);
  return min(k - 1, 5);
}

// ---------------- Head-to-head history ----------------

class H2HMeeting {
  final int year;
  final String competition;
  final int goalsA, goalsB; // oriented to (a, b) as passed to h2hFor
  H2HMeeting({required this.year, required this.competition, required this.goalsA, required this.goalsB});
}

const _h2hComps = ['World Cup', 'World Cup Qualifier', 'International Friendly', 'Continental Cup', 'Nations League'];

/// Seeded, order-independent pseudo-history between two nations.
List<H2HMeeting> h2hFor(Team a, Team b) {
  final key = ([a.code, b.code]..sort()).join('-');
  final rng = Random(key.hashCode);
  final flipped = a.code.compareTo(b.code) > 0;
  final n = 3 + rng.nextInt(3);
  final res = <H2HMeeting>[];
  var year = 2024;
  for (var i = 0; i < n; i++) {
    year -= 1 + rng.nextInt(4);
    // strength-informed but noisy
    final diff = ((flipped ? b.rating - a.rating : a.rating - b.rating)).toDouble();
    final gFirst = _poisson(rng, (1.2 + diff * 0.04).clamp(0.2, 3.0));
    final gSecond = _poisson(rng, (1.2 - diff * 0.04).clamp(0.2, 3.0));
    res.add(H2HMeeting(
      year: year,
      competition: _h2hComps[rng.nextInt(_h2hComps.length)],
      goalsA: flipped ? gSecond : gFirst,
      goalsB: flipped ? gFirst : gSecond,
    ));
  }
  return res;
}
