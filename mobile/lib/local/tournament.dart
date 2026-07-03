import '../api/models.dart';
import 'fixtures.dart';
import 'match_facts.dart';

/// Tournament engine: live group standings, best-thirds ranking, the 32-team
/// knockout bracket resolved from actual results, and tournament-wide player
/// leaderboards (Golden Boot, assists, ratings) — all computed on-device from
/// the same deterministic facts the match pages show.

class StandingRow {
  final Team team;
  int played = 0, won = 0, drawn = 0, lost = 0, gf = 0, ga = 0;
  StandingRow(this.team);
  int get gd => gf - ga;
  int get pts => won * 3 + drawn;
}

final _groupRe = RegExp(r'Group ([A-L])');

String? groupOf(Fixture f) => _groupRe.firstMatch(f.stage)?.group(1);

/// Group letter -> ranked table rows (pts, gd, gf).
Map<String, List<StandingRow>> groupStandings(List<Fixture> fixtures) {
  final tables = <String, Map<String, StandingRow>>{};
  for (final entry in worldCupGroups().entries) {
    tables[entry.key] = {for (final t in entry.value) t.code: StandingRow(t)};
  }
  for (final f in fixtures) {
    final g = groupOf(f);
    if (g == null || f.status != 'finished' || f.score == null) continue;
    final rows = tables[g];
    if (rows == null) continue;
    final home = rows[f.home.code], away = rows[f.away.code];
    if (home == null || away == null) continue;
    final hg = f.score!.home, ag = f.score!.away;
    home
      ..played += 1
      ..gf += hg
      ..ga += ag;
    away
      ..played += 1
      ..gf += ag
      ..ga += hg;
    if (hg > ag) {
      home.won += 1;
      away.lost += 1;
    } else if (hg < ag) {
      away.won += 1;
      home.lost += 1;
    } else {
      home.drawn += 1;
      away.drawn += 1;
    }
  }
  return tables.map((g, rows) {
    final list = rows.values.toList()
      ..sort((a, b) {
        if (b.pts != a.pts) return b.pts - a.pts;
        if (b.gd != a.gd) return b.gd - a.gd;
        if (b.gf != a.gf) return b.gf - a.gf;
        return a.team.name.compareTo(b.team.name);
      });
    return MapEntry(g, list);
  });
}

Team _tbd(String label) => Team(id: 'tbd', name: label, code: 'TBD', flag: '🏆', rating: 75);

const knockoutStages = ['Round of 32', 'Round of 16', 'Quarter-final', 'Semi-final', 'Third place', 'Final'];

/// Build all 32 knockout fixtures from the finished group stage. Rounds whose
/// feeder matches haven't finished yet get honest "Winner of…" placeholders.
List<Fixture> buildKnockout(List<Fixture> groupFixtures, DateTime now) {
  final tables = groupStandings(groupFixtures);
  final letters = tables.keys.toList()..sort();

  final winners = [for (final g in letters) tables[g]![0].team];
  final runners = [for (final g in letters) tables[g]![1].team];
  final thirds = [for (final g in letters) tables[g]![2]]
    ..sort((a, b) {
      if (b.pts != a.pts) return b.pts - a.pts;
      if (b.gd != a.gd) return b.gd - a.gd;
      return b.gf - a.gf;
    });
  final bestThirds = thirds.take(8).map((r) => r.team).toList();

  // Seeded field of 32; pair i against (31 - i). Group winners land the
  // best-third slots, and same-group clashes can't occur before the R16.
  final field = <Team>[...winners, ...runners, ...bestThirds];
  final r32Pairs = [for (var i = 0; i < 16; i++) (field[i], field[31 - i])];

  final out = <Fixture>[];
  var venueIdx = 3;

  // Round of 32 across ~3 days centred on now — one tie is live right now.
  final r32 = <Fixture>[];
  for (var i = 0; i < 16; i++) {
    // spread from 30h ago, every 4.5h; match 8 (index 7) kicked off 25 minutes
    // ago so the lobby always has a real knockout tie LIVE
    final ko = now.add(Duration(minutes: -30 * 60 + i * 270));
    final koFinal = i == 7 ? now.subtract(const Duration(minutes: 25)) : ko;
    var f = Fixture(
      id: 'wc26-r32-m${i + 1}',
      competition: 'FIFA World Cup 2026',
      stage: 'Round of 32 · Match ${i + 1}',
      kickoff: koFinal.toIso8601String(),
      venue: wc26Venues[venueIdx++ % wc26Venues.length],
      status: 'scheduled',
      home: r32Pairs[i].$1,
      away: r32Pairs[i].$2,
    );
    f = applyClock(f, now);
    r32.add(f);
  }
  out.addAll(r32);

  // Later rounds: resolve winners where feeders finished, else placeholders.
  Team winnerOf(Fixture f, String placeholder) {
    if (f.status != 'finished') return _tbd(placeholder);
    return knockoutHomeAdvances(f) ? f.home : f.away;
  }

  List<Fixture> nextRound(List<Fixture> prev, String stage, String idPrefix, double startHours, double gapHours) {
    final res = <Fixture>[];
    for (var i = 0; i < prev.length ~/ 2; i++) {
      final a = prev[i * 2], b = prev[i * 2 + 1];
      final ko = now.add(Duration(minutes: ((startHours + i * gapHours) * 60).round()));
      var f = Fixture(
        id: '$idPrefix-m${i + 1}',
        competition: 'FIFA World Cup 2026',
        stage: '$stage${prev.length > 2 ? " · Match ${i + 1}" : ""}',
        kickoff: ko.toIso8601String(),
        venue: wc26Venues[venueIdx++ % wc26Venues.length],
        status: 'scheduled',
        home: winnerOf(a, 'Winner ${_shortStage(a.stage)}'),
        away: winnerOf(b, 'Winner ${_shortStage(b.stage)}'),
      );
      // never simulate a live/finished match between placeholder sides
      if (f.home.code != 'TBD' && f.away.code != 'TBD') f = applyClock(f, now);
      res.add(f);
    }
    return res;
  }

  final r16 = nextRound(r32, 'Round of 16', 'wc26-r16', 60, 5);
  final qf = nextRound(r16, 'Quarter-final', 'wc26-qf', 132, 6);
  final sf = nextRound(qf, 'Semi-final', 'wc26-sf', 180, 8);
  out.addAll([...r16, ...qf, ...sf]);

  // Bronze final + Final
  Team loserOf(Fixture f, String placeholder) {
    if (f.status != 'finished') return _tbd(placeholder);
    return knockoutHomeAdvances(f) ? f.away : f.home;
  }

  final bronze = Fixture(
    id: 'wc26-bronze',
    competition: 'FIFA World Cup 2026',
    stage: 'Third place',
    kickoff: now.add(const Duration(hours: 225)).toIso8601String(),
    venue: wc26Venues[venueIdx++ % wc26Venues.length],
    status: 'scheduled',
    home: loserOf(sf[0], 'Loser SF1'),
    away: loserOf(sf[1], 'Loser SF2'),
  );
  final finalMatch = Fixture(
    id: 'wc26-final',
    competition: 'FIFA World Cup 2026',
    stage: 'Final',
    kickoff: now.add(const Duration(hours: 252)).toIso8601String(),
    venue: 'MetLife Stadium, New York/NJ',
    status: 'scheduled',
    home: winnerOf(sf[0], 'Winner SF1'),
    away: winnerOf(sf[1], 'Winner SF2'),
  );
  out.addAll([bronze, finalMatch]);
  return out;
}

String _shortStage(String stage) {
  final m = RegExp(r'Match (\d+)').firstMatch(stage);
  if (stage.startsWith('Round of 32')) return 'R32 M${m?.group(1) ?? ''}';
  if (stage.startsWith('Round of 16')) return 'R16 M${m?.group(1) ?? ''}';
  if (stage.startsWith('Quarter')) return 'QF${m?.group(1) ?? ''}';
  if (stage.startsWith('Semi')) return 'SF${m?.group(1) ?? ''}';
  return stage;
}

/// Fixtures grouped per knockout stage (in play order) for the bracket view.
Map<String, List<Fixture>> knockoutByStage(List<Fixture> fixtures) {
  final out = {for (final s in knockoutStages) s: <Fixture>[]};
  for (final f in fixtures) {
    for (final s in knockoutStages) {
      if (f.stage.startsWith(s)) {
        out[s]!.add(f);
        break;
      }
    }
  }
  return out;
}

// ---------------- Tournament player leaderboards ----------------

class PlayerTotals {
  final String name;
  final Team team;
  int goals = 0, assists = 0, matches = 0;
  double ratingSum = 0;
  PlayerTotals(this.name, this.team);
  double get avgRating => matches == 0 ? 0 : ratingSum / matches;
}

class TournamentLeaders {
  final List<PlayerTotals> scorers, assisters, rated;
  TournamentLeaders(this.scorers, this.assisters, this.rated);
}

/// Aggregate every played minute of the tournament (finished matches fully,
/// live ones up to the current minute) into player leaderboards.
TournamentLeaders tournamentLeaders(List<Fixture> fixtures) {
  final totals = <String, PlayerTotals>{};
  PlayerTotals bucket(String name, Team team) =>
      totals['${team.code}|$name'] ??= PlayerTotals(name, team);

  for (final f in fixtures) {
    if (f.status == 'scheduled' || f.home.code == 'TBD' || f.away.code == 'TBD') continue;
    final facts = factsFor(f);
    final liveMinute = f.status == 'live' ? (f.score?.minute ?? 0) : 999;

    for (final e in facts.events) {
      if (e.minute > liveMinute) continue;
      final team = e.side == 'home' ? f.home : f.away;
      if (e.kind == 'goal') {
        bucket(e.player, team).goals += 1;
        if (e.assist != null) bucket(e.assist!, team).assists += 1;
      }
    }
    // ratings/matches only for completed games (a live rating would jump around)
    if (f.status == 'finished') {
      for (final pr in facts.homeRatings) {
        bucket(pr.player.name, f.home)
          ..matches += 1
          ..ratingSum += pr.rating;
      }
      for (final pr in facts.awayRatings) {
        bucket(pr.player.name, f.away)
          ..matches += 1
          ..ratingSum += pr.rating;
      }
    }
  }

  final all = totals.values.toList();
  final scorers = [...all.where((p) => p.goals > 0)]..sort((a, b) => b.goals != a.goals ? b.goals - a.goals : b.assists - a.assists);
  final assisters = [...all.where((p) => p.assists > 0)]..sort((a, b) => b.assists != a.assists ? b.assists - a.assists : b.goals - a.goals);
  final rated = [...all.where((p) => p.matches >= 2)]..sort((a, b) => b.avgRating.compareTo(a.avgRating));
  return TournamentLeaders(scorers, assisters, rated);
}
