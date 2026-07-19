import 'package:final_whistle/app_experience/app_experience.dart';
import 'package:final_whistle/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app shell state exposes the five-step fan journey', () {
    const state = AppShellState.initial();

    expect(AppDestination.values.map((destination) => destination.label), [
      'Home',
      'Fixtures',
      'Cards',
      'Arena',
      'Profile',
    ]);
    expect(state.destination, AppDestination.home);
    expect(state.badgeFor(AppDestination.cards), 0);
  });

  testWidgets('selecting a destination preserves state in other tabs', (
    tester,
  ) async {
    final controller = AppExperienceController();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppExperienceShell(
          controller: controller,
          destinations: {
            AppDestination.home: const _StatefulProbe(label: 'home'),
            AppDestination.fixtures: const _StatefulProbe(label: 'fixtures'),
            AppDestination.cards: const _StatefulProbe(label: 'cards'),
            AppDestination.arena: const _StatefulProbe(label: 'arena'),
            AppDestination.profile: const _StatefulProbe(label: 'profile'),
          },
        ),
      ),
    );

    await tester.tap(find.text('home:0'));
    await tester.pump();
    expect(find.text('home:1'), findsOneWidget);

    await tester.tap(find.text('ARENA'));
    await tester.pumpAndSettle();
    expect(find.text('arena:0'), findsOneWidget);

    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
    expect(find.text('home:1'), findsOneWidget);
  });

  testWidgets('badges are rendered only for actionable counts', (tester) async {
    final controller = AppExperienceController(
      initialState: const AppShellState.initial().copyWith(
        liveMatchCount: 2,
        unopenedPackCount: 3,
        duelInviteCount: 1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppExperienceShell(
          controller: controller,
          destinations: {
            for (final destination in AppDestination.values)
              destination: Text(destination.label),
          },
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-nav-badge')), findsNothing);
  });
}

class _StatefulProbe extends StatefulWidget {
  final String label;
  const _StatefulProbe({required this.label});

  @override
  State<_StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('${widget.label}:$count'),
    ),
  );
}
