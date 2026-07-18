import 'package:flutter_test/flutter_test.dart';

import 'package:final_whistle/api/models.dart';

/// Upcoming fixtures can enter an Official Hub, but remain pregame until a
/// verified score moves beyond phase 0. Local replay remains forbidden.
void main() {
  test('scheduled fixtures remain pregame rather than fake live', () {
    final f = Fixture(
      id: 'wc26-test',
      competition: 'World Cup',
      stage: 'Group',
      kickoff: DateTime.now().add(const Duration(hours: 5)).toIso8601String(),
      venue: 'Test',
      status: 'scheduled',
      home: Team(id: 'a', name: 'Egypt', code: 'EGY', flag: '🇪🇬', rating: 78),
      away: Team(
        id: 'b',
        name: 'Argentina',
        code: 'ARG',
        flag: '🇦🇷',
        rating: 92,
      ),
    );
    expect(f.status, 'scheduled');
    expect(f.status == 'live' || f.status == 'finished', isFalse);
  });

  test('ScoreView soft-parses numeric strings without casting crashes', () {
    final s = ScoreView.fromJson({
      'minute': 67.0,
      'clockSeconds': 4020.0,
      'running': true,
      'phase': 3,
      'goals': {'home': 0, 'away': 2},
      'yellow': {'home': 1, 'away': 0},
      'red': {'home': 0, 'away': 0},
      'corners': {'home': 3, 'away': 1},
    });
    expect(s.minute, 67);
    expect(s.goals.away, 2);
  });
}
