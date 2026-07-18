import 'package:flutter_test/flutter_test.dart';

import 'package:final_whistle/api/live_data.dart';
import 'package:final_whistle/api/models.dart';
import 'package:final_whistle/widgets/gyro_card.dart';

Map<String, dynamic> player(int i, {bool starter = true}) => {
  'id': 'p$i',
  'name': 'Verified Player $i',
  'position': i == 1 ? 'GK' : 'DF',
  'shirtNumber': '$i',
  'starter': starter,
  'onPitch': starter,
  'portraitKind': 'illustration',
  'stats': {
    'goals': i == 9 ? 1 : 0,
    'starts': starter ? 1 : 0,
    'squadSelections': 1,
  },
};

void main() {
  test('match intelligence parses confirmed XI and attributed event', () {
    final data = MatchData.fromJson({
      'fixtureId': '18237038',
      'source': 'txline',
      'lineupStatus': 'confirmed',
      'updatedAt': 123,
      'stale': false,
      'fixture': {
        'id': '18237038',
        'status': 'live',
        'home': {'id': 'fra', 'name': 'France', 'code': 'FRA', 'flag': '🇫🇷'},
        'away': {'id': 'esp', 'name': 'Spain', 'code': 'ESP', 'flag': '🇪🇸'},
      },
      'teams': {
        'home': {
          'id': 'fra',
          'name': 'France',
          'code': 'FRA',
          'formation': '4-3-3',
          'players': List.generate(11, (i) => player(i + 1)),
        },
        'away': {
          'id': 'esp',
          'name': 'Spain',
          'code': 'ESP',
          'formation': '4-3-3',
          'players': List.generate(11, (i) => player(i + 21)),
        },
      },
      'events': [
        {
          'id': 'tx:1',
          'sourceEventId': 'tx:1',
          'kind': 'goal',
          'side': 'home',
          'teamCode': 'FRA',
          'playerId': 'p9',
          'playerName': 'Verified Player 9',
          'label': 'Goal',
          'minute': 31,
          'seq': 9,
          'ts': 1,
        },
      ],
    });
    expect(data.home.players.where((p) => p.starter), hasLength(11));
    expect(data.away.players.where((p) => p.starter), hasLength(11));
    expect(data.events.single.playerName, 'Verified Player 9');
    expect(data.home.players.first.portraitKind, 'illustration');
  });

  test('Official Hub metadata is backward-compatible', () {
    final summary = RoomSummary.fromJson({
      'id': 'hub1',
      'code': 'ABC123',
      'name': 'Official',
      'status': 'live',
      'kind': 'official',
      'autoManaged': true,
      'memberCount': 2,
      'fixture': {
        'id': 'fx',
        'home': {'id': 'fra', 'name': 'France', 'code': 'FRA'},
        'away': {'id': 'esp', 'name': 'Spain', 'code': 'ESP'},
      },
    });
    expect(summary.kind, 'official');
    expect(summary.autoManaged, isTrue);
  });

  test('shared motion controller supports deterministic drag fallback', () {
    final motion = CardMotionController();
    motion.drag(const Offset(20, -10));
    expect(motion.x, greaterThan(0));
    expect(motion.y, lessThan(0));
    motion.resetDrag();
    motion.dispose();
  });
}
