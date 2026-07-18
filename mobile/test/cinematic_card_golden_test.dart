import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:final_whistle/widgets/gyro_card.dart';

void main() {
  testWidgets('cinematic relic families keep intentional layered artwork', (
    tester,
  ) async {
    final anton = FontLoader('Anton')
      ..addFont(rootBundle.load('assets/fonts/Anton-Regular.ttf'));
    final archivo = FontLoader('Archivo')
      ..addFont(rootBundle.load('assets/fonts/Archivo-Regular.ttf'));
    await Future.wait([anton.load(), archivo.load()]);
    await tester.binding.setSurfaceSize(const Size(1040, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget card(
      Widget face,
      Color border,
      int seed, {
      int rarity = 4,
      CardFrameShape frameShape = CardFrameShape.relic,
    }) {
      return SizedBox(
        width: 230,
        height: 322,
        child: GyroTiltCard(
          seed: seed,
          rarity: rarity,
          borderColor: border,
          reduceParallax: true,
          frameShape: frameShape,
          child: face,
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF050608),
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('cinematic-golden'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  card(
                    const MomentCardFace(
                      title: 'Extra-time winner',
                      matchLabel: 'ARG vs SUI',
                      kind: 'goal',
                      rarity: 5,
                      minute: 122,
                      calledIt: true,
                      playerName: 'Julián Álvarez',
                      teamCode: 'ARG',
                      artKey: 'goal:arg:122',
                    ),
                    const Color(0xFFE0A33C),
                    11,
                    rarity: 5,
                  ),
                  const SizedBox(width: 18),
                  card(
                    const MomentCardFace(
                      title: 'Momentum shift',
                      matchLabel: 'FRA vs ESP',
                      kind: 'market-swing',
                      rarity: 4,
                      minute: 78,
                      calledIt: false,
                      teamCode: 'FRA',
                      artKey: 'market:fra:78',
                    ),
                    const Color(0xFF9B6BFF),
                    22,
                  ),
                  const SizedBox(width: 18),
                  card(
                    const PlayerCardFace(
                      playerId: 'messi',
                      name: 'Lionel Messi',
                      teamCode: 'ARG',
                      position: 'RW',
                      axes: {'finishing': 91, 'clutch': 95},
                      frameShape: CardFrameShape.stadiumCrown,
                    ),
                    const Color(0xFF74ACDF),
                    33,
                    rarity: 3,
                    frameShape: CardFrameShape.stadiumCrown,
                  ),
                  const SizedBox(width: 18),
                  card(
                    const SkillCardFace(
                      name: 'Clutch Shift',
                      description: 'Boost the chosen axis for one round.',
                      effect: {'type': 'boost'},
                    ),
                    const Color(0xFFB8FF36),
                    44,
                    rarity: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/cards/portraits/messi.webp'),
        tester.element(find.byType(MaterialApp)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RawImage), findsNWidgets(3));
    for (final rawImage in tester.widgetList<RawImage>(find.byType(RawImage))) {
      expect(rawImage.image, isNotNull);
    }

    await expectLater(
      find.byKey(const ValueKey('cinematic-golden')),
      matchesGoldenFile('goldens/cinematic_relic_families.png'),
    );
  });
}
