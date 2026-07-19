import 'package:final_whistle/screens/arena_landing_screen.dart';
import 'package:final_whistle/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'arena explains every production duel mode without demo controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: ArenaLandingScreen(
            players: const [],
            moments: const [],
            skills: const [],
            onOpenCards: () {},
            onStartMode: (_) {},
          ),
        ),
      );

      expect(find.textContaining('Build your hand'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('HOUSE DUEL'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('HOUSE DUEL'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('FRIEND DUEL'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('FRIEND DUEL'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('MOMENT ARENA'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MOMENT ARENA'), findsOneWidget);
      expect(find.textContaining('demo'), findsNothing);
    },
  );
}
