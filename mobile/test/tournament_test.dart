import 'package:flutter_test/flutter_test.dart';

import 'package:final_whistle/local/fixtures.dart';
import 'package:final_whistle/local/match_facts.dart';
import 'package:final_whistle/local/squads.dart';
import 'package:final_whistle/local/tournament.dart';
import 'package:final_whistle/api/models.dart';

void main() {
  test('full World Cup: 104 fixtures (72 group + 32 knockout)', () {
    final all = localFixtures();
    expect(all.length, 104);
    final group = all.where((f) => groupOf(f) != null).toList();
    final knockout = all.where((f) => groupOf(f) == null).toList();
    expect(group.length, 72);
    expect(knockout.length, 32);
    // every fixture has a real venue
    expect(all.every((f) => f.venue.isNotEmpty && f.venue != '—'), isTrue);
  });

  test('group stage complete with consistent standings', () {
    final all = localFixtures();
    final tables = groupStandings(all);
    expect(tables.length, 12);
    for (final rows in tables.values) {
      expect(rows.length, 4);
      // each team played all 3 group games
      for (final r in rows) {
        expect(r.played, 3);
      }
      // 6 matches * 3 points distributed (win) or 2 (draw): total pts 12..18
      final pts = rows.fold(0, (s, r) => s + r.pts);
      expect(pts, inInclusiveRange(12, 18));
      // sorted by points
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i - 1].pts >= rows[i].pts, isTrue);
      }
    }
  });

  test('match facts are deterministic and agree with fixture scores', () {
    final finished = localFixtures().where((f) => f.status == 'finished' && groupOf(f) != null).take(10);
    for (final f in finished) {
      final a = factsFor(f);
      final b = factsFor(f);
      expect(identical(a, b) || (a.homeGoals == b.homeGoals && a.awayGoals == b.awayGoals), isTrue);
      expect(f.score!.home, a.homeGoals);
      expect(f.score!.away, a.awayGoals);
      // goal events match the scoreline
      expect(a.events.where((e) => e.kind == 'goal' && e.side == 'home').length, a.homeGoals);
      expect(a.events.where((e) => e.kind == 'goal' && e.side == 'away').length, a.awayGoals);
      // exactly one man of the match
      final motm = [...a.homeRatings, ...a.awayRatings].where((r) => r.motm);
      expect(motm.length, 1);
    }
  });

  test('knockout bracket resolves finished ties to real teams', () {
    final all = localFixtures();
    final r32 = all.where((f) => f.stage.startsWith('Round of 32')).toList();
    expect(r32.length, 16);
    // no side in the R32 is a placeholder and no team meets its own group
    for (final f in r32) {
      expect(f.home.code == 'TBD' || f.away.code == 'TBD', isFalse);
    }
    final finalMatch = all.firstWhere((f) => f.stage == 'Final');
    expect(finalMatch.status, 'scheduled');
  });

  test('every WC team has an 11-man XI matching its formation', () {
    for (final entry in worldCupGroups().entries) {
      for (final t in entry.value) {
        final sq = squadFor(t);
        expect(sq.startingXI.length, 11, reason: '${t.code} XI');
        final lines = sq.formation.split('-').map(int.parse).fold(0, (a, b) => a + b);
        expect(lines, 10, reason: '${t.code} formation ${sq.formation}');
        expect(sq.startingXI.first.pos, 'GK', reason: '${t.code} first player must be GK');
        expect(sq.bench.isNotEmpty, isTrue, reason: '${t.code} bench');
      }
    }
  });

  test('golden boot aggregates goals from played matches', () {
    final leaders = tournamentLeaders(localFixtures());
    expect(leaders.scorers, isNotEmpty);
    // leaderboard is sorted
    for (var i = 1; i < leaders.scorers.length; i++) {
      expect(leaders.scorers[i - 1].goals >= leaders.scorers[i].goals, isTrue);
    }
    // totals agree with the facts engine
    final total = leaders.scorers.fold(0, (s, p) => s + p.goals);
    var expected = 0;
    for (final f in localFixtures()) {
      if (f.status == 'scheduled' || f.home.code == 'TBD' || f.away.code == 'TBD') continue;
      final liveMin = f.status == 'live' ? (f.score?.minute ?? 0) : 999;
      expected += factsFor(f).events.where((e) => e.kind == 'goal' && e.minute <= liveMin).length;
    }
    expect(total, expected);
  });

  test('h2h is symmetric regardless of argument order', () {
    final t1 = Team(id: 'bra', name: 'Brazil', code: 'BRA', flag: '🇧🇷', rating: 93);
    final t2 = Team(id: 'arg', name: 'Argentina', code: 'ARG', flag: '🇦🇷', rating: 92);
    final ab = h2hFor(t1, t2);
    final ba = h2hFor(t2, t1);
    expect(ab.length, ba.length);
    for (var i = 0; i < ab.length; i++) {
      expect(ab[i].goalsA, ba[i].goalsB);
      expect(ab[i].goalsB, ba[i].goalsA);
      expect(ab[i].year, ba[i].year);
    }
  });
}
