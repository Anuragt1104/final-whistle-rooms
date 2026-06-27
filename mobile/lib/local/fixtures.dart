import '../api/models.dart';

/// On-device World Cup dataset so the app ALWAYS shows matches and a live feed,
/// even with no backend. Mirrors the server's worldcup data.
class _RawTeam {
  final String name, code, flag;
  final int rating;
  const _RawTeam(this.name, this.code, this.flag, this.rating);
}

const Map<String, List<_RawTeam>> _groups = {
  'A': [_RawTeam('Argentina', 'ARG', '🇦🇷', 92), _RawTeam('Mexico', 'MEX', '🇲🇽', 78), _RawTeam('Poland', 'POL', '🇵🇱', 74), _RawTeam('Saudi Arabia', 'KSA', '🇸🇦', 66)],
  'B': [_RawTeam('France', 'FRA', '🇫🇷', 91), _RawTeam('Denmark', 'DEN', '🇩🇰', 79), _RawTeam('Australia', 'AUS', '🇦🇺', 70), _RawTeam('Tunisia', 'TUN', '🇹🇳', 67)],
  'C': [_RawTeam('Spain', 'ESP', '🇪🇸', 90), _RawTeam('Germany', 'GER', '🇩🇪', 87), _RawTeam('Japan', 'JPN', '🇯🇵', 77), _RawTeam('Costa Rica', 'CRC', '🇨🇷', 64)],
  'D': [_RawTeam('Brazil', 'BRA', '🇧🇷', 93), _RawTeam('Switzerland', 'SUI', '🇨🇭', 78), _RawTeam('Serbia', 'SRB', '🇷🇸', 75), _RawTeam('Cameroon', 'CMR', '🇨🇲', 68)],
  'E': [_RawTeam('England', 'ENG', '🏴󠁧󠁢󠁥󠁮󠁧󠁿', 89), _RawTeam('USA', 'USA', '🇺🇸', 76), _RawTeam('Senegal', 'SEN', '🇸🇳', 75), _RawTeam('Iran', 'IRN', '🇮🇷', 66)],
  'F': [_RawTeam('Portugal', 'POR', '🇵🇹', 90), _RawTeam('Uruguay', 'URU', '🇺🇾', 80), _RawTeam('South Korea', 'KOR', '🇰🇷', 74), _RawTeam('Ghana', 'GHA', '🇬🇭', 69)],
  'G': [_RawTeam('Netherlands', 'NED', '🇳🇱', 88), _RawTeam('Croatia', 'CRO', '🇭🇷', 81), _RawTeam('Morocco', 'MAR', '🇲🇦', 79), _RawTeam('Canada', 'CAN', '🇨🇦', 71)],
  'H': [_RawTeam('Belgium', 'BEL', '🇧🇪', 84), _RawTeam('Colombia', 'COL', '🇨🇴', 80), _RawTeam('Nigeria', 'NGA', '🇳🇬', 73), _RawTeam('Ecuador', 'ECU', '🇪🇨', 72)],
};

const _roundRobin = [
  [[0, 1], [2, 3]],
  [[0, 2], [1, 3]],
  [[0, 3], [1, 2]],
];

Team _team(_RawTeam r) => Team(id: r.code.toLowerCase(), name: r.name, code: r.code, flag: r.flag, rating: r.rating);

List<Fixture>? _cache;

/// All 48 group-stage fixtures, kickoffs anchored relative to now so the lobby
/// always shows a realistic mix of live / upcoming / finished.
List<Fixture> localFixtures() {
  if (_cache != null) return _cache!;
  final now = DateTime.now();
  final fixtures = <Fixture>[];
  const matchdayBaseHours = [-26, -2, 46];
  final groupKeys = _groups.keys.toList();

  for (var md = 0; md < _roundRobin.length; md++) {
    final pairings = _roundRobin[md];
    var within = 0;
    for (final g in groupKeys) {
      final teams = _groups[g]!.map(_team).toList();
      for (final pair in pairings) {
        final koHours = matchdayBaseHours[md] + within * 1.5;
        within++;
        final ko = now.add(Duration(minutes: (koHours * 60).round()));
        final diffH = ko.difference(now).inMinutes / 60.0;
        final status = diffH < -2 ? 'finished' : (diffH <= 0.25 ? 'live' : 'scheduled');
        fixtures.add(Fixture(
          id: 'wc26-$g-md${md + 1}-${teams[pair[0]].code}-${teams[pair[1]].code}'.toLowerCase(),
          competition: 'FIFA World Cup 2026',
          stage: 'Group $g · Matchday ${md + 1}',
          kickoff: ko.toIso8601String(),
          venue: '—',
          status: status,
          home: teams[pair[0]],
          away: teams[pair[1]],
        ));
      }
    }
  }
  fixtures.sort((a, b) => DateTime.parse(a.kickoff).compareTo(DateTime.parse(b.kickoff)));
  _cache = fixtures;
  return fixtures;
}

Fixture? localFixtureById(String id) {
  for (final f in localFixtures()) {
    if (f.id == id) return f;
  }
  return null;
}
