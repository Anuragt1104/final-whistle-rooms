import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:final_whistle/data/player_portraits.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all fixed roster portraits are exact-ID, attributed, and bundled',
    () async {
      final raw = await rootBundle.loadString(
        'assets/cards/portraits/attribution.json',
      );
      final manifest = jsonDecode(raw) as Map<String, dynamic>;

      expect(playerPortraitAssets, hasLength(24));
      expect(manifest.keys.toSet(), playerPortraitAssets.keys.toSet());

      for (final entry in playerPortraitAssets.entries) {
        final bytes = await rootBundle.load(entry.value.assetPath);
        expect(bytes.lengthInBytes, greaterThan(3000), reason: entry.key);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(80), reason: entry.key);
        expect(frame.image.height, greaterThan(150), reason: entry.key);
        frame.image.dispose();
        codec.dispose();

        final credit = manifest[entry.key] as Map<String, dynamic>;
        expect(credit['assetPath'], entry.value.assetPath);
        expect(
          credit['sourcePage'],
          startsWith('https://commons.wikimedia.org/'),
        );
        expect(credit['author'], isNotEmpty);
        expect(
          credit['license'],
          anyOf(
            startsWith('CC BY'),
            startsWith('CC0'),
            equals('Public domain'),
          ),
        );
        expect(credit['licenseUrl'], startsWith('http'));
        expect(credit['modified'], contains('WebP'));
      }
    },
  );

  test('portrait resolution never falls back to a name match', () {
    expect(portraitForPlayerId('messi')?.playerId, 'messi');
    expect(portraitForPlayerId('Lionel Messi'), isNull);
    expect(portraitForPlayerId('unknown-player'), isNull);
  });
}
