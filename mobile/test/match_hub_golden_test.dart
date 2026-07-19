import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:final_whistle/api/models.dart';
import 'package:final_whistle/match_hub/models.dart';
import 'package:final_whistle/match_hub/palette.dart';
import 'package:final_whistle/match_hub/widgets/header.dart';
import 'package:final_whistle/match_hub/widgets/section_rail.dart';

Team _t(String code) => Team(
      id: code,
      name: code,
      code: code,
      flag: '🏳️',
      rating: 80,
    );

MatchHubHeaderState _header(String badge, {bool frozen = false}) =>
    MatchHubHeaderState(
      competition: 'World Cup',
      lifecycleBadge: badge,
      home: _t('ARG'),
      away: _t('FRA'),
      scoreText: badge == 'PREGAME' ? 'v' : '1 - 0',
      clockText: frozen ? "44' · DELAYED" : (badge == 'FULL TIME' ? 'FT' : "44'"),
      clockFrozen: frozen,
      freezeReason: frozen ? 'Updates delayed' : null,
      watching: 842,
      feedFreshness: frozen ? 'stale' : 'live',
      notifyOn: true,
      replay: badge == 'REPLAY',
      latestEventRibbon: badge == 'PREGAME' ? null : '⚽ Goal',
    );

void main() {
  testWidgets('match hub expanded and collapsed headers golden', (tester) async {
    final anton = FontLoader('Anton')
      ..addFont(rootBundle.load('assets/fonts/Anton-Regular.ttf'));
    final archivo = FontLoader('Archivo')
      ..addFont(rootBundle.load('assets/fonts/Archivo-Regular.ttf'));
    await Future.wait([anton.load(), archivo.load()]);
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final badges = [
      'PREGAME',
      'LIVE',
      'HALF-TIME',
      'EXTRA TIME',
      'PENALTIES',
      'FULL TIME',
      'REPLAY',
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: HubColors.stadium,
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: const ValueKey('hub-goldens'),
              child: Column(
                children: [
                  for (final b in badges) ...[
                    MatchHubHeader(
                      header: _header(b, frozen: b == 'LIVE'),
                      palette: TeamPalette.forFixture(_t('ARG'), _t('FRA')),
                      expanded: true,
                    ),
                    MatchHubHeader(
                      header: _header(b),
                      palette: TeamPalette.forFixture(_t('ARG'), _t('FRA')),
                      expanded: false,
                    ),
                  ],
                  MatchHubSectionRail(
                    selected: MatchHubSection.calls,
                    onSelect: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('hub-goldens')),
      matchesGoldenFile('goldens/match_hub_headers.png'),
    );
  });
}
