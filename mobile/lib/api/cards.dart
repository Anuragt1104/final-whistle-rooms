/// Card Economy models + API helpers for Moments / Packs / Duels.
library;

class MomentCard {
  final String id, fixtureId, matchLabel, kind, label, leafData;
  final String? side,
      roomId,
      sourceEventId,
      playerId,
      playerName,
      teamCode,
      imageUrl,
      artKey;
  final int rarity, minute, createdAt;
  final bool calledIt;
  final Map<String, dynamic> oddsSandwich;

  MomentCard({
    required this.id,
    required this.fixtureId,
    required this.matchLabel,
    required this.kind,
    required this.label,
    required this.leafData,
    required this.rarity,
    required this.minute,
    required this.createdAt,
    required this.calledIt,
    required this.oddsSandwich,
    this.side,
    this.roomId,
    this.sourceEventId,
    this.playerId,
    this.playerName,
    this.teamCode,
    this.imageUrl,
    this.artKey,
  });

  factory MomentCard.fromJson(Map<String, dynamic> j) => MomentCard(
    id: j['id'] ?? '',
    fixtureId: j['fixtureId'] ?? '',
    matchLabel: j['matchLabel'] ?? '',
    kind: j['kind'] ?? '',
    label: j['label'] ?? '',
    leafData: j['leafData'] ?? '',
    rarity: (j['rarity'] as num?)?.toInt() ?? 1,
    minute: (j['minute'] as num?)?.toInt() ?? 0,
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    calledIt: j['calledIt'] == true,
    oddsSandwich: Map<String, dynamic>.from(j['oddsSandwich'] ?? {}),
    side: j['side'],
    roomId: j['roomId'],
    sourceEventId: j['sourceEventId'],
    playerId: j['playerId'],
    playerName: j['playerName'],
    teamCode: j['teamCode'],
    imageUrl: j['imageUrl'],
    artKey: j['artKey'],
  );
}

class PlayerCardModel {
  final String id, playerId, name, teamCode, teamName, position, leafData;
  final String? imageUrl, lineageMomentId;
  final Map<String, int> axes;
  final int createdAt;

  PlayerCardModel({
    required this.id,
    required this.playerId,
    required this.name,
    required this.teamCode,
    required this.teamName,
    required this.position,
    required this.leafData,
    required this.axes,
    required this.createdAt,
    this.imageUrl,
    this.lineageMomentId,
  });

  factory PlayerCardModel.fromJson(Map<String, dynamic> j) {
    final raw = Map<String, dynamic>.from(j['axes'] ?? {});
    return PlayerCardModel(
      id: j['id'] ?? '',
      playerId: j['playerId'] ?? '',
      name: j['name'] ?? '',
      teamCode: j['teamCode'] ?? '',
      teamName: j['teamName'] ?? '',
      position: j['position'] ?? '',
      leafData: j['leafData'] ?? '',
      axes: raw.map((k, v) => MapEntry(k, (v as num).toInt())),
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      imageUrl: j['imageUrl'],
      lineageMomentId: j['lineageMomentId'],
    );
  }
}

class SkillCardModel {
  final String id, name, description, leafData;
  final Map<String, dynamic> effect;
  final int createdAt;

  SkillCardModel({
    required this.id,
    required this.name,
    required this.description,
    required this.leafData,
    required this.effect,
    required this.createdAt,
  });

  factory SkillCardModel.fromJson(Map<String, dynamic> j) => SkillCardModel(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    description: j['description'] ?? '',
    leafData: j['leafData'] ?? '',
    effect: Map<String, dynamic>.from(j['effect'] ?? {}),
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
  );
}

class PackModel {
  final String id;
  final double weight;
  final bool opened;
  final List<String> momentIds;
  final List<dynamic> cards;

  PackModel({
    required this.id,
    required this.weight,
    required this.opened,
    required this.momentIds,
    required this.cards,
  });

  factory PackModel.fromJson(Map<String, dynamic> j) => PackModel(
    id: j['id'] ?? '',
    weight: (j['weight'] as num?)?.toDouble() ?? 1,
    opened: j['opened'] == true,
    momentIds: ((j['momentIds'] ?? []) as List)
        .map((e) => e.toString())
        .toList(),
    cards: (j['cards'] ?? []) as List,
  );
}

class FanInventory {
  final String fanId;
  final List<MomentCard> moments;
  final List<PlayerCardModel> players;
  final List<SkillCardModel> skills;
  final List<PackModel> packs;
  final double packWeightBonus;

  FanInventory({
    required this.fanId,
    required this.moments,
    required this.players,
    required this.skills,
    required this.packs,
    required this.packWeightBonus,
  });

  factory FanInventory.fromJson(Map<String, dynamic> j) => FanInventory(
    fanId: j['fanId'] ?? '',
    moments: ((j['moments'] ?? []) as List)
        .map((e) => MomentCard.fromJson(e))
        .toList(),
    players: ((j['players'] ?? []) as List)
        .map((e) => PlayerCardModel.fromJson(e))
        .toList(),
    skills: ((j['skills'] ?? []) as List)
        .map((e) => SkillCardModel.fromJson(e))
        .toList(),
    packs: ((j['packs'] ?? []) as List)
        .map((e) => PackModel.fromJson(e))
        .toList(),
    packWeightBonus: (j['packWeightBonus'] as num?)?.toDouble() ?? 0,
  );
}

class TrumpDuelModel {
  final String id, code, mode, status, challengerId;
  final String? opponentId, winnerId, seedMomentId;
  final List<String> challengerHand, opponentHand;
  final List<dynamic> rounds;

  TrumpDuelModel({
    required this.id,
    required this.code,
    required this.mode,
    required this.status,
    required this.challengerId,
    required this.challengerHand,
    required this.opponentHand,
    required this.rounds,
    this.opponentId,
    this.winnerId,
    this.seedMomentId,
  });

  factory TrumpDuelModel.fromJson(Map<String, dynamic> j) => TrumpDuelModel(
    id: j['id'] ?? '',
    code: j['code'] ?? '',
    mode: j['mode'] ?? 'trump',
    status: j['status'] ?? '',
    challengerId: j['challengerId'] ?? '',
    opponentId: j['opponentId'],
    winnerId: j['winnerId'],
    seedMomentId: j['seedMomentId'],
    challengerHand: ((j['challengerHand'] ?? []) as List)
        .map((e) => e.toString())
        .toList(),
    opponentHand: ((j['opponentHand'] ?? []) as List)
        .map((e) => e.toString())
        .toList(),
    rounds: (j['rounds'] ?? []) as List,
  );
}
