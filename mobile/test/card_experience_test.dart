import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:final_whistle/api/cards.dart';
import 'package:final_whistle/api/models.dart';
import 'package:final_whistle/screens/card_detail_screen.dart';

void main() {
  test('MomentDropView parses recipient collectible metadata', () {
    final d = MomentDropView.fromJson({
      'id': 'mom_1', 'memberId': 'm_1', 'kind': 'goal', 'label': 'Goal',
      'matchLabel': 'ARG vs SWI', 'rarity': 5, 'minute': 122, 'createdAt': 7,
      'sourceEventId': 'tx:18222446:goal-3', 'playerId': 'julian',
      'playerName': 'Julián Álvarez', 'teamCode': 'ARG', 'artKey': 'goal:arg',
    });
    expect(d.memberId, 'm_1');
    expect(d.rarity, 5);
    expect(d.matchLabel, 'ARG vs SWI');
    expect(d.sourceEventId, 'tx:18222446:goal-3');
    expect(d.playerName, 'Julián Álvarez');
  });

  testWidgets('collectible detail opens with layered tilt guidance', (tester) async {
    final m = MomentCard(
      id: 'mom_1', fixtureId: 'fx', matchLabel: 'ARG vs SWI', kind: 'goal',
      label: 'Extra-time winner', leafData: '', rarity: 5, minute: 122,
      createdAt: 1, calledIt: true, oddsSandwich: const {},
    );
    await tester.pumpWidget(MaterialApp(home: CardDetailScreen.moment(m)));
    await tester.pump();
    expect(find.text('Extra-time winner'), findsOneWidget);
    expect(find.text('TILT YOUR PHONE'), findsOneWidget);
    expect(find.text('5★ MOMENT'), findsOneWidget);
  });
}
