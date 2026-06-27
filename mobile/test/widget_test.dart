import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:final_whistle/util/base58.dart';
import 'package:final_whistle/api/models.dart';

void main() {
  test('base58 round-trips', () {
    final bytes = Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) & 0xff));
    expect(base58Decode(base58Encode(bytes)), bytes);
  });

  test('phaseLabel maps known game phases', () {
    expect(phaseLabel(1), '1st half');
    expect(phaseLabel(2), 'Half-time');
    expect(phaseLabel(4), 'Full-time');
  });

  test('RoomView parses a minimal payload', () {
    final room = RoomView.fromJson({
      'id': 'r1',
      'code': 'ABC123',
      'name': 'Test',
      'hostId': 'h1',
      'status': 'lobby',
      'fixture': {
        'id': 'f1',
        'home': {'id': 'a', 'name': 'A', 'code': 'AAA', 'flag': '🏳️', 'rating': 80},
        'away': {'id': 'b', 'name': 'B', 'code': 'BBB', 'flag': '🏳️', 'rating': 75},
      },
      'win': {'home': 40, 'draw': 30, 'away': 30},
      'proof': {'leafCount': 0, 'anchored': false, 'cluster': 'devnet'},
    });
    expect(room.code, 'ABC123');
    expect(room.fixture.home.code, 'AAA');
    expect(room.win.home, 40);
  });
}
