import '../api/models.dart';
import 'match_facts.dart';
import 'tournament.dart';

/// On-device World Cup 2026 dataset — the FULL 104-match tournament (12 groups
/// of 4 → 72 group games, then a 32-team knockout to the final), with real
/// venues and deterministic results, so the app always shows the whole World
/// Cup even with no backend.
///
/// The timeline is anchored relative to "now": the group stage has just
/// finished (complete tables, Golden Boot race, every result), the Round of 32
/// is underway — one match live right now — and the rest of the knockout runs
/// over the coming days.
class _RawTeam {
  final String name, code, flag;
  final int rating;
  const _RawTeam(this.name, this.code, this.flag, this.rating);
}

const Map<String, List<_RawTeam>> _groups = {
  'A': [
    _RawTeam('Mexico', 'MEX', '🇲🇽', 78),
    _RawTeam('South Korea', 'KOR', '🇰🇷', 74),
    _RawTeam('Poland', 'POL', '🇵🇱', 74),
    _RawTeam('Cape Verde', 'CPV', '🇨🇻', 62),
  ],
  'B': [
    _RawTeam('Canada', 'CAN', '🇨🇦', 73),
    _RawTeam('Switzerland', 'SUI', '🇨🇭', 78),
    _RawTeam('Qatar', 'QAT', '🇶🇦', 65),
    _RawTeam('Ivory Coast', 'CIV', '🇨🇮', 71),
  ],
  'C': [
    _RawTeam('USA', 'USA', '🇺🇸', 76),
    _RawTeam('Croatia', 'CRO', '🇭🇷', 81),
    _RawTeam('Egypt', 'EGY', '🇪🇬', 70),
    _RawTeam('New Zealand', 'NZL', '🇳🇿', 60),
  ],
  'D': [
    _RawTeam('Brazil', 'BRA', '🇧🇷', 93),
    _RawTeam('Scotland', 'SCO', '🏴󠁧󠁢󠁳󠁣󠁴󠁿', 71),
    _RawTeam('Tunisia', 'TUN', '🇹🇳', 67),
    _RawTeam('Jordan', 'JOR', '🇯🇴', 61),
  ],
  'E': [
    _RawTeam('Argentina', 'ARG', '🇦🇷', 92),
    _RawTeam('Denmark', 'DEN', '🇩🇰', 79),
    _RawTeam('South Africa', 'RSA', '🇿🇦', 64),
    _RawTeam('Uzbekistan', 'UZB', '🇺🇿', 63),
  ],
  'F': [
    _RawTeam('France', 'FRA', '🇫🇷', 91),
    _RawTeam('Japan', 'JPN', '🇯🇵', 77),
    _RawTeam('Paraguay', 'PAR', '🇵🇾', 69),
    _RawTeam('Haiti', 'HAI', '🇭🇹', 58),
  ],
  'G': [
    _RawTeam('Spain', 'ESP', '🇪🇸', 90),
    _RawTeam('Uruguay', 'URU', '🇺🇾', 80),
    _RawTeam('Saudi Arabia', 'KSA', '🇸🇦', 66),
    _RawTeam('Australia', 'AUS', '🇦🇺', 70),
  ],
  'H': [
    _RawTeam('England', 'ENG', '🏴󠁧󠁢󠁥󠁮󠁧󠁿', 89),
    _RawTeam('Senegal', 'SEN', '🇸🇳', 75),
    _RawTeam('Austria', 'AUT', '🇦🇹', 76),
    _RawTeam('Panama', 'PAN', '🇵🇦', 62),
  ],
  'I': [
    _RawTeam('Portugal', 'POR', '🇵🇹', 90),
    _RawTeam('Colombia', 'COL', '🇨🇴', 80),
    _RawTeam('Norway', 'NOR', '🇳🇴', 78),
    _RawTeam('Iraq', 'IRQ', '🇮🇶', 61),
  ],
  'J': [
    _RawTeam('Germany', 'GER', '🇩🇪', 87),
    _RawTeam('Morocco', 'MAR', '🇲🇦', 79),
    _RawTeam('Sweden', 'SWE', '🇸🇪', 75),
    _RawTeam('Costa Rica', 'CRC', '🇨🇷', 64),
  ],
  'K': [
    _RawTeam('Netherlands', 'NED', '🇳🇱', 88),
    _RawTeam('Italy', 'ITA', '🇮🇹', 84),
    _RawTeam('Iran', 'IRN', '🇮🇷', 66),
    _RawTeam('Ghana', 'GHA', '🇬🇭', 69),
  ],
  'L': [
    _RawTeam('Belgium', 'BEL', '🇧🇪', 84),
    _RawTeam('Türkiye', 'TUR', '🇹🇷', 77),
    _RawTeam('Ecuador', 'ECU', '🇪🇨', 72),
    _RawTeam('Algeria', 'ALG', '🇩🇿', 70),
  ],
};

/// The 16 host stadiums of World Cup 2026.
const wc26Venues = [
  'Estadio Azteca, Mexico City',
  'MetLife Stadium, New York/NJ',
  'SoFi Stadium, Los Angeles',
  'AT&T Stadium, Dallas',
  'NRG Stadium, Houston',
  'Mercedes-Benz Stadium, Atlanta',
  'Hard Rock Stadium, Miami',
  'Lincoln Financial Field, Philadelphia',
  "Levi's Stadium, San Francisco",
  'Lumen Field, Seattle',
  'Arrowhead Stadium, Kansas City',
  'Gillette Stadium, Boston',
  'BMO Field, Toronto',
  'BC Place, Vancouver',
  'Estadio BBVA, Monterrey',
  'Estadio Akron, Guadalajara',
];

const _roundRobin = [
  [
    [0, 1],
    [2, 3],
  ],
  [
    [0, 2],
    [1, 3],
  ],
  [
    [0, 3],
    [1, 2],
  ],
];

Team _team(_RawTeam r) => Team(
  id: r.code.toLowerCase(),
  name: r.name,
  code: r.code,
  flag: r.flag,
  rating: r.rating,
);

/// Group letter -> the four teams, in seed order.
Map<String, List<Team>> worldCupGroups() =>
    _groups.map((g, list) => MapEntry(g, list.map(_team).toList()));

List<Fixture>? _cache;

String _status(DateTime ko, DateTime now) {
  final diffH = ko.difference(now).inMinutes / 60.0;
  return diffH < -2 ? 'finished' : (diffH <= 0.25 ? 'live' : 'scheduled');
}

/// Attach an honest score to non-scheduled fixtures from the deterministic
/// facts engine: full result for finished, partial (by elapsed minute) for live.
Fixture _withScore(Fixture f, DateTime now) {
  if (f.status == 'scheduled') return f;
  final facts = factsFor(f);
  if (f.status == 'finished') {
    return Fixture(
      id: f.id,
      competition: f.competition,
      stage: f.stage,
      kickoff: f.kickoff,
      venue: f.venue,
      status: f.status,
      home: f.home,
      away: f.away,
      score: FixtureScore(facts.homeGoals, facts.awayGoals, 90, 90 * 60, false),
    );
  }
  final minute = now
      .difference(DateTime.parse(f.kickoff))
      .inMinutes
      .clamp(1, 90);
  return Fixture(
    id: f.id,
    competition: f.competition,
    stage: f.stage,
    kickoff: f.kickoff,
    venue: f.venue,
    status: f.status,
    home: f.home,
    away: f.away,
    score: FixtureScore(
      facts.goalsAt('home', minute),
      facts.goalsAt('away', minute),
      minute,
      minute * 60,
      true,
    ),
  );
}

/// All 104 World Cup fixtures: 72 group matches (finished) + 32 knockout
/// matches (Round of 32 underway now, then R16, QFs, SFs, bronze, final).
List<Fixture> localFixtures() {
  if (_cache != null) return _cache!;
  final now = DateTime.now();
  final fixtures = <Fixture>[];

  // ---- group stage: 3 matchdays across the past ~9 days ----
  const matchdayBaseHours = [-216.0, -144.0, -72.0]; // 9, 6, 3 days ago
  final groupKeys = _groups.keys.toList();
  var venueIdx = 0;

  for (var md = 0; md < _roundRobin.length; md++) {
    final pairings = _roundRobin[md];
    var within = 0;
    for (final g in groupKeys) {
      final teams = _groups[g]!.map(_team).toList();
      for (final pair in pairings) {
        final koHours = matchdayBaseHours[md] + within * 1.5;
        within++;
        final ko = now.add(Duration(minutes: (koHours * 60).round()));
        var f = Fixture(
          id: 'wc26-$g-md${md + 1}-${teams[pair[0]].code}-${teams[pair[1]].code}'
              .toLowerCase(),
          competition: 'FIFA World Cup 2026',
          stage: 'Group $g · Matchday ${md + 1}',
          kickoff: ko.toIso8601String(),
          venue: wc26Venues[venueIdx++ % wc26Venues.length],
          status: _status(ko, now),
          home: teams[pair[0]],
          away: teams[pair[1]],
        );
        f = _withScore(f, now);
        fixtures.add(f);
      }
    }
  }

  // ---- knockout: resolved from the group results (see tournament.dart) ----
  fixtures.addAll(buildKnockout(fixtures, now));

  fixtures.sort(
    (a, b) => DateTime.parse(a.kickoff).compareTo(DateTime.parse(b.kickoff)),
  );
  _cache = fixtures;
  return fixtures;
}

/// Re-status + re-score knockout fixtures too (they're generated in
/// tournament.dart which reuses these helpers).
Fixture applyClock(Fixture f, DateTime now) {
  final ko = DateTime.parse(f.kickoff);
  final st = _status(ko, now);
  final restatused = Fixture(
    id: f.id,
    competition: f.competition,
    stage: f.stage,
    kickoff: f.kickoff,
    venue: f.venue,
    status: st,
    home: f.home,
    away: f.away,
  );
  return _withScore(restatused, now);
}

Fixture? localFixtureById(String id) {
  for (final f in localFixtures()) {
    if (f.id == id) return f;
  }
  return null;
}
