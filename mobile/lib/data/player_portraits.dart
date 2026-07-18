import 'dart:convert';

import 'package:flutter/services.dart';

class PortraitAsset {
  final String playerId;
  final String assetPath;

  const PortraitAsset({required this.playerId, required this.assetPath});
}

class PortraitAttribution {
  final String playerId;
  final String name;
  final String assetPath;
  final String sourcePage;
  final String author;
  final String license;
  final String licenseUrl;
  final String discoveryUrl;
  final String modified;

  const PortraitAttribution({
    required this.playerId,
    required this.name,
    required this.assetPath,
    required this.sourcePage,
    required this.author,
    required this.license,
    required this.licenseUrl,
    required this.discoveryUrl,
    required this.modified,
  });

  factory PortraitAttribution.fromJson(String playerId, Object? value) {
    final json = value as Map<String, dynamic>;
    return PortraitAttribution(
      playerId: playerId,
      name: json['name'] as String,
      assetPath: json['assetPath'] as String,
      sourcePage: json['sourcePage'] as String,
      author: json['author'] as String,
      license: json['license'] as String,
      licenseUrl: json['licenseUrl'] as String,
      discoveryUrl: json['discoveryUrl'] as String,
      modified: json['modified'] as String,
    );
  }
}

/// Exact stable player-card IDs only. There is intentionally no name matching.
const playerPortraitAssets = <String, PortraitAsset>{
  'mbappe': PortraitAsset(
    playerId: 'mbappe',
    assetPath: 'assets/cards/portraits/mbappe.webp',
  ),
  'messi': PortraitAsset(
    playerId: 'messi',
    assetPath: 'assets/cards/portraits/messi.webp',
  ),
  'bellingham': PortraitAsset(
    playerId: 'bellingham',
    assetPath: 'assets/cards/portraits/bellingham.webp',
  ),
  'vinicius': PortraitAsset(
    playerId: 'vinicius',
    assetPath: 'assets/cards/portraits/vinicius.webp',
  ),
  'yamal': PortraitAsset(
    playerId: 'yamal',
    assetPath: 'assets/cards/portraits/yamal.webp',
  ),
  'saka': PortraitAsset(
    playerId: 'saka',
    assetPath: 'assets/cards/portraits/saka.webp',
  ),
  'musiala': PortraitAsset(
    playerId: 'musiala',
    assetPath: 'assets/cards/portraits/musiala.webp',
  ),
  'wirtz': PortraitAsset(
    playerId: 'wirtz',
    assetPath: 'assets/cards/portraits/wirtz.webp',
  ),
  'pedri': PortraitAsset(
    playerId: 'pedri',
    assetPath: 'assets/cards/portraits/pedri.webp',
  ),
  'rodri': PortraitAsset(
    playerId: 'rodri',
    assetPath: 'assets/cards/portraits/rodri.webp',
  ),
  'valverde': PortraitAsset(
    playerId: 'valverde',
    assetPath: 'assets/cards/portraits/valverde.webp',
  ),
  'alvarez': PortraitAsset(
    playerId: 'alvarez',
    assetPath: 'assets/cards/portraits/alvarez.webp',
  ),
  'lautaro': PortraitAsset(
    playerId: 'lautaro',
    assetPath: 'assets/cards/portraits/lautaro.webp',
  ),
  'raphinha': PortraitAsset(
    playerId: 'raphinha',
    assetPath: 'assets/cards/portraits/raphinha.webp',
  ),
  'hakimi': PortraitAsset(
    playerId: 'hakimi',
    assetPath: 'assets/cards/portraits/hakimi.webp',
  ),
  'saliba': PortraitAsset(
    playerId: 'saliba',
    assetPath: 'assets/cards/portraits/saliba.webp',
  ),
  'vandijk': PortraitAsset(
    playerId: 'vandijk',
    assetPath: 'assets/cards/portraits/vandijk.webp',
  ),
  'donnarumma': PortraitAsset(
    playerId: 'donnarumma',
    assetPath: 'assets/cards/portraits/donnarumma.webp',
  ),
  'courtois': PortraitAsset(
    playerId: 'courtois',
    assetPath: 'assets/cards/portraits/courtois.webp',
  ),
  'kane': PortraitAsset(
    playerId: 'kane',
    assetPath: 'assets/cards/portraits/kane.webp',
  ),
  'son': PortraitAsset(
    playerId: 'son',
    assetPath: 'assets/cards/portraits/son.webp',
  ),
  'osimen': PortraitAsset(
    playerId: 'osimen',
    assetPath: 'assets/cards/portraits/osimen.webp',
  ),
  'guler': PortraitAsset(
    playerId: 'guler',
    assetPath: 'assets/cards/portraits/guler.webp',
  ),
  'frimpong': PortraitAsset(
    playerId: 'frimpong',
    assetPath: 'assets/cards/portraits/frimpong.webp',
  ),
};

PortraitAsset? portraitForPlayerId(String? playerId) =>
    playerId == null ? null : playerPortraitAssets[playerId];

Future<List<PortraitAttribution>> loadPortraitAttributions() async {
  final raw = await rootBundle.loadString(
    'assets/cards/portraits/attribution.json',
  );
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final credits = json.entries
      .map((entry) => PortraitAttribution.fromJson(entry.key, entry.value))
      .toList();
  credits.sort((a, b) => a.name.compareTo(b.name));
  return credits;
}
