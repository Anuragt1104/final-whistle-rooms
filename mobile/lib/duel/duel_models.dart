import '../api/cards.dart';

enum DuelMode { stadium, arena }

enum DuelOpponent { house, friend }

enum DuelPhase {
  waitingForOpponent,
  axisSelection,
  cardSelection,
  resolving,
  roundComplete,
  finished,
}

enum DuelPresentationPhase {
  idle,
  fanCardEntering,
  opponentCardLocking,
  floodlights,
  flipping,
  modifiers,
  scoring,
  impact,
  result,
}

String _string(Object? value, [String fallback = '']) =>
    value?.toString() ?? fallback;

int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

bool _bool(Object? value) => value == true || value == 'true';

DuelPhase parseDuelPhase(Object? raw) {
  final value = _string(raw)
      .replaceAll('_', '')
      .replaceAll('-', '')
      .toLowerCase();
  return switch (value) {
    'waitingforopponent' || 'open' => DuelPhase.waitingForOpponent,
    'axisselection' || 'awaitingaxis' => DuelPhase.axisSelection,
    'cardselection' || 'awaitingsubmissions' || 'playing' =>
      DuelPhase.cardSelection,
    'resolving' => DuelPhase.resolving,
    'roundcomplete' || 'roundrevealed' => DuelPhase.roundComplete,
    'finished' => DuelPhase.finished,
    _ => DuelPhase.waitingForOpponent,
  };
}

class LineageSnapshotModel {
  final String momentId;
  final String fixtureId;
  final String kind;
  final String? teamCode;
  final int rarity;
  final bool calledIt;
  final String? sourceEventId;
  final Map<String, dynamic> oddsSandwich;
  final Map<String, dynamic>? proof;

  const LineageSnapshotModel({
    required this.momentId,
    required this.fixtureId,
    required this.kind,
    required this.rarity,
    required this.calledIt,
    required this.oddsSandwich,
    this.teamCode,
    this.sourceEventId,
    this.proof,
  });

  factory LineageSnapshotModel.fromJson(Map<String, dynamic> json) =>
      LineageSnapshotModel(
        momentId: _string(json['momentId'] ?? json['parentMomentId']),
        fixtureId: _string(json['fixtureId']),
        kind: _string(json['kind']),
        teamCode: json['teamCode']?.toString(),
        rarity: _int(json['rarity'], 1),
        calledIt: _bool(json['calledIt']),
        sourceEventId:
            (json['sourceEventId'] ?? json['fingerprint'])?.toString(),
        oddsSandwich: Map<String, dynamic>.from(
          json['oddsSandwich'] as Map? ?? const {},
        ),
        proof: json['proof'] is Map
            ? Map<String, dynamic>.from(json['proof'] as Map)
            : null,
      );
}

class DuelCardSnapshot {
  final String id;
  final String name;
  final String teamCode;
  final String position;
  final String? playerId;
  final String? imageUrl;
  final Map<String, int> axes;
  final LineageSnapshotModel? lineage;
  final int rating;

  const DuelCardSnapshot({
    required this.id,
    required this.name,
    required this.teamCode,
    required this.position,
    required this.axes,
    required this.rating,
    this.playerId,
    this.imageUrl,
    this.lineage,
  });

  factory DuelCardSnapshot.fromJson(Map<String, dynamic> json) {
    final rawAxes = Map<String, dynamic>.from(
      json['axes'] as Map? ?? const {},
    );
    final axes = rawAxes.map((k, v) => MapEntry(k, _int(v)));
    final fallbackRating = axes.isEmpty
        ? 70
        : (axes.values.reduce((a, b) => a + b) / axes.length).round();
    return DuelCardSnapshot(
      id: _string(json['id'] ?? json['cardId']),
      name: _string(json['name'], 'Unknown player'),
      teamCode: _string(json['teamCode'], 'FWR'),
      position: _string(json['position'], '—'),
      playerId: json['playerId']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      axes: axes,
      rating: _int(json['rating'], fallbackRating),
      lineage: json['lineage'] is Map
          ? LineageSnapshotModel.fromJson(
              Map<String, dynamic>.from(json['lineage'] as Map),
            )
          : json['lineageSnapshot'] is Map
          ? LineageSnapshotModel.fromJson(
              Map<String, dynamic>.from(json['lineageSnapshot'] as Map),
            )
          : null,
    );
  }

  PlayerCardModel toPlayerCard() => PlayerCardModel(
    id: id,
    playerId: playerId ?? '',
    name: name,
    teamCode: teamCode,
    teamName: teamCode,
    position: position,
    leafData: '',
    axes: axes,
    createdAt: 0,
    imageUrl: imageUrl,
    lineageMomentId: lineage?.momentId,
  );
}

class DuelModifierModel {
  final String label;
  final int value;
  final String source;

  const DuelModifierModel({
    required this.label,
    required this.value,
    required this.source,
  });

  factory DuelModifierModel.fromJson(Map<String, dynamic> json) =>
      DuelModifierModel(
        label: _string(json['label'] ?? json['kind']),
        value: _int(json['value'] ?? json['amount']),
        source: _string(json['source']),
      );
}

class DuelRoundModel {
  final int round;
  final String axis;
  final String attackerId;
  final DuelCardSnapshot? yourCard;
  final DuelCardSnapshot? opponentCard;
  final String? yourSkillName;
  final String? opponentSkillName;
  final int? yourBase;
  final int? opponentBase;
  final int? yourScore;
  final int? opponentScore;
  final String? winnerId;
  final bool autoPlayed;
  final List<DuelModifierModel> yourModifiers;
  final List<DuelModifierModel> opponentModifiers;
  final String? commitment;
  final String? revealSalt;

  const DuelRoundModel({
    required this.round,
    required this.axis,
    required this.attackerId,
    required this.yourModifiers,
    required this.opponentModifiers,
    this.yourCard,
    this.opponentCard,
    this.yourSkillName,
    this.opponentSkillName,
    this.yourBase,
    this.opponentBase,
    this.yourScore,
    this.opponentScore,
    this.winnerId,
    this.autoPlayed = false,
    this.commitment,
    this.revealSalt,
  });

  factory DuelRoundModel.fromJson(
    Map<String, dynamic> json, {
    String? actorId,
  }) {
    DuelCardSnapshot? card(Object? value) => value is Map
        ? DuelCardSnapshot.fromJson(Map<String, dynamic>.from(value))
        : null;

    List<DuelModifierModel> modifiersFromScore(Object? score) {
      if (score is! Map) return const [];
      final out = <DuelModifierModel>[];
      final resonance = _int(score['resonance']);
      final calledIt = _int(score['calledIt']);
      final skill = _int(score['skill']);
      if (resonance != 0) {
        out.add(
          DuelModifierModel(
            label: 'Lineage',
            value: resonance,
            source: 'lineage',
          ),
        );
      }
      if (calledIt != 0) {
        out.add(
          DuelModifierModel(
            label: 'Called It',
            value: calledIt,
            source: 'calledIt',
          ),
        );
      }
      if (skill != 0) {
        out.add(
          DuelModifierModel(label: 'Skill', value: skill, source: 'skill'),
        );
      }
      return out;
    }

    List<DuelModifierModel> modifiers(Object? value) => value is List
        ? value
              .whereType<Map>()
              .map(
                (m) => DuelModifierModel.fromJson(
                  Map<String, dynamic>.from(m),
                ),
              )
              .toList()
        : const [];

    final bFanId = json['bFanId']?.toString();
    final youAreB = actorId != null && bFanId == actorId;
    final aScore = json['aScore'] is Map
        ? Map<String, dynamic>.from(json['aScore'] as Map)
        : null;
    final bScore = json['bScore'] is Map
        ? Map<String, dynamic>.from(json['bScore'] as Map)
        : null;
    final yourSideScore = youAreB ? bScore : aScore;
    final oppSideScore = youAreB ? aScore : bScore;
    final houseReveal = json['houseReveal'] is Map
        ? Map<String, dynamic>.from(json['houseReveal'] as Map)
        : null;

    return DuelRoundModel(
      round: _int(json['round'] ?? json['roundNumber'], 1),
      axis: _string(json['axis']),
      attackerId: _string(json['attackerId']),
      yourCard: card(
        json['yourCard'] ??
            json['fanCard'] ??
            (youAreB ? json['bCard'] : json['aCard']),
      ),
      opponentCard: card(
        json['opponentCard'] ??
            json['houseCard'] ??
            (youAreB ? json['aCard'] : json['bCard']),
      ),
      yourSkillName:
          (json['yourSkillName'] ??
                  json['fanSkillName'] ??
                  (youAreB
                      ? (json['bSkill'] is Map
                            ? (json['bSkill'] as Map)['name']
                            : null)
                      : (json['aSkill'] is Map
                            ? (json['aSkill'] as Map)['name']
                            : null)))
              ?.toString(),
      opponentSkillName:
          (json['opponentSkillName'] ??
                  json['houseSkillName'] ??
                  (youAreB
                      ? (json['aSkill'] is Map
                            ? (json['aSkill'] as Map)['name']
                            : null)
                      : (json['bSkill'] is Map
                            ? (json['bSkill'] as Map)['name']
                            : null)))
              ?.toString(),
      yourBase: json['yourBase'] == null
          ? (yourSideScore == null ? null : _int(yourSideScore['base']))
          : _int(json['yourBase']),
      opponentBase: json['opponentBase'] == null
          ? (oppSideScore == null ? null : _int(oppSideScore['base']))
          : _int(json['opponentBase']),
      yourScore: json['yourScore'] == null
          ? (yourSideScore == null
                ? (json['aValue'] == null ? null : _int(json['aValue']))
                : _int(yourSideScore['total']))
          : _int(json['yourScore']),
      opponentScore: json['opponentScore'] == null
          ? (oppSideScore == null
                ? (json['bValue'] == null ? null : _int(json['bValue']))
                : _int(oppSideScore['total']))
          : _int(json['opponentScore']),
      winnerId: json['winnerId']?.toString(),
      autoPlayed: _bool(
        json['autoPlayed'] ??
            (youAreB ? json['bAutoPlayed'] : json['aAutoPlayed']),
      ),
      yourModifiers: (() {
        final explicit = modifiers(
          json['yourModifiers'] ?? json['fanModifiers'],
        );
        return explicit.isNotEmpty
            ? explicit
            : modifiersFromScore(yourSideScore);
      })(),
      opponentModifiers: (() {
        final explicit = modifiers(
          json['opponentModifiers'] ?? json['houseModifiers'],
        );
        return explicit.isNotEmpty
            ? explicit
            : modifiersFromScore(oppSideScore);
      })(),
      commitment: (json['commitment'] ?? houseReveal?['cardId'])?.toString(),
      revealSalt: (json['revealSalt'] ?? houseReveal?['salt'])?.toString(),
    );
  }
}

class ArenaConditionModel {
  final int round;
  final String name;
  final String axis;
  final String explanation;

  const ArenaConditionModel({
    required this.round,
    required this.name,
    required this.axis,
    required this.explanation,
  });

  factory ArenaConditionModel.fromJson(Map<String, dynamic> json) =>
      ArenaConditionModel(
        round: _int(json['round'], 1),
        name: _string(json['name'] ?? json['type']),
        axis: _string(json['axis']),
        explanation: _string(json['explanation']),
      );
}

class ArenaContextModel {
  final MomentCard moment;
  final String? fingerprint;
  final Map<String, dynamic>? proof;
  final List<ArenaConditionModel> conditions;

  const ArenaContextModel({
    required this.moment,
    required this.conditions,
    this.fingerprint,
    this.proof,
  });

  factory ArenaContextModel.fromJson(Map<String, dynamic> json) {
    final momentMap = Map<String, dynamic>.from(
      json['moment'] as Map? ?? const {},
    );
    final script = (json['script'] as List? ?? const [])
        .map((axis) => '$axis')
        .toList();
    final names = const ['Event', 'Pressure', 'Aftershock'];
    final explanations = const [
      'Moment kind sets the opening attribute',
      'Match minute pressure tilts the second attribute',
      'Aftershock fills the remaining market axis',
    ];
    final fromScript = <ArenaConditionModel>[];
    for (var i = 0; i < script.length; i++) {
      fromScript.add(
        ArenaConditionModel(
          round: i + 1,
          name: i < names.length ? names[i] : 'Round ${i + 1}',
          axis: script[i],
          explanation: i < explanations.length
              ? explanations[i]
              : 'TxLINE arena condition',
        ),
      );
    }
    final explicit = (json['conditions'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ArenaConditionModel.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
    return ArenaContextModel(
      moment: MomentCard.fromJson({
        'id': momentMap['id'],
        'fixtureId': momentMap['fixtureId'],
        'matchLabel': momentMap['matchLabel'] ?? momentMap['fixtureId'] ?? '',
        'kind': momentMap['kind'] ?? 'goal',
        'minute': momentMap['minute'] ?? 0,
        'label': momentMap['label'] ?? momentMap['kind'] ?? 'Moment',
        'rarity': momentMap['rarity'] ?? 1,
        'oddsSandwich':
            momentMap['oddsSandwich'] ??
            {
              'before': {'home': 0.33, 'draw': 0.33, 'away': 0.34},
              'after': {'home': 0.33, 'draw': 0.33, 'away': 0.34},
            },
        'calledIt': momentMap['calledIt'] ?? false,
        'leafData': momentMap['leafData'] ?? '',
        'createdAt': momentMap['createdAt'] ?? 0,
        'teamCode': momentMap['teamCode'],
        'sourceEventId': momentMap['sourceEventId'],
      }),
      fingerprint:
          (json['fingerprint'] ??
                  momentMap['sourceEventId'] ??
                  json['sourceEventId'])
              ?.toString(),
      proof: json['proof'] is Map
          ? Map<String, dynamic>.from(json['proof'] as Map)
          : json['proofVerified'] == true
          ? const {'verified': true}
          : null,
      conditions: explicit.isNotEmpty ? explicit : fromScript,
    );
  }
}

class DuelViewModel {
  final String id;
  final String code;
  final DuelMode mode;
  final DuelOpponent opponent;
  final DuelPhase phase;
  final int version;
  final int roundNumber;
  final String fanId;
  final String? opponentId;
  final String attackerId;
  final String? winnerId;
  final int yourScore;
  final int opponentScore;
  final DateTime? deadlineAt;
  final bool yourTurn;
  final bool youSubmitted;
  final bool opponentSubmitted;
  final bool connected;
  final List<DuelCardSnapshot> yourHand;
  final List<String> usedCardIds;
  final List<String> usedSkillIds;
  final List<DuelRoundModel> rounds;
  final ArenaContextModel? arena;
  final String? houseCommitment;
  final Map<String, dynamic>? commitmentVerification;
  final Map<String, dynamic>? reward;

  const DuelViewModel({
    required this.id,
    required this.code,
    required this.mode,
    required this.opponent,
    required this.phase,
    required this.version,
    required this.roundNumber,
    required this.fanId,
    required this.attackerId,
    required this.yourScore,
    required this.opponentScore,
    required this.yourTurn,
    required this.youSubmitted,
    required this.opponentSubmitted,
    required this.connected,
    required this.yourHand,
    required this.usedCardIds,
    required this.usedSkillIds,
    required this.rounds,
    this.opponentId,
    this.winnerId,
    this.deadlineAt,
    this.arena,
    this.houseCommitment,
    this.commitmentVerification,
    this.reward,
  });

  factory DuelViewModel.fromJson(Map<String, dynamic> json) {
    final root = json['view'] is Map
        ? Map<String, dynamic>.from(json['view'] as Map)
        : json;
    final scores = Map<String, dynamic>.from(
      root['scores'] as Map? ?? const {},
    );
    final actorId = _string(root['actorId'] ?? root['fanId'] ?? root['youId']);
    final opponentMeta = root['opponent'] is Map
        ? Map<String, dynamic>.from(root['opponent'] as Map)
        : const <String, dynamic>{};
    final timer = root['timer'] is Map
        ? Map<String, dynamic>.from(root['timer'] as Map)
        : const <String, dynamic>{};
    final deadlineRaw = timer['deadlineAt'] ?? root['deadlineAt'];
    DateTime? deadline;
    if (deadlineRaw is num) {
      deadline = DateTime.fromMillisecondsSinceEpoch(deadlineRaw.toInt());
    } else if (deadlineRaw != null) {
      deadline = DateTime.tryParse(deadlineRaw.toString());
    }
    final opponentId =
        (root['opponentId'] ?? opponentMeta['id'])?.toString();
    final phase = parseDuelPhase(root['phase'] ?? root['status']);
    final youSubmitted = _bool(
      root['hasSubmitted'] ??
          root['youSubmitted'] ??
          root['yourSubmissionPending'],
    );
    final opponentSubmitted = _bool(
      opponentMeta['submitted'] ??
          root['opponentSubmitted'] ??
          root['opponentSubmissionPending'],
    );
    final attackerId = _string(root['attackerId']);
    final yourTurn = root.containsKey('yourTurn')
        ? _bool(root['yourTurn'])
        : switch (phase) {
            DuelPhase.axisSelection => attackerId == actorId,
            DuelPhase.cardSelection => !youSubmitted,
            DuelPhase.roundComplete => true,
            _ => false,
          };
    final roundsRaw = (root['rounds'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (round) => DuelRoundModel.fromJson(
            Map<String, dynamic>.from(round),
            actorId: actorId,
          ),
        )
        .toList();
    final commitments = root['commitments'] as List? ?? const [];
    final firstCommitment = commitments.whereType<Map>().cast<Map>().firstOrNull;
    return DuelViewModel(
      id: _string(root['id'] ?? root['duelId']),
      code: _string(root['code']),
      mode: _string(root['mode']).toLowerCase() == 'arena'
          ? DuelMode.arena
          : DuelMode.stadium,
      opponent:
          _string(root['opponentType'] ?? root['opponent']).toLowerCase() ==
              'friend'
          ? DuelOpponent.friend
          : DuelOpponent.house,
      phase: phase,
      version: _int(root['version']),
      roundNumber: _int(
        root['roundNumber'],
        roundsRaw.isEmpty ? 1 : roundsRaw.length + (phase == DuelPhase.finished ? 0 : 1),
      ),
      fanId: actorId,
      opponentId: opponentId,
      attackerId: attackerId,
      winnerId: root['winnerId']?.toString(),
      yourScore: _int(scores[actorId] ?? scores['you'] ?? root['yourScore']),
      opponentScore: _int(
        scores[opponentId ?? ''] ??
            scores['house'] ??
            scores['opponent'] ??
            root['opponentScore'],
      ),
      deadlineAt: deadline,
      yourTurn: yourTurn,
      youSubmitted: youSubmitted,
      opponentSubmitted: opponentSubmitted,
      connected: root['connected'] != false,
      yourHand: (root['hand'] as List? ?? root['yourHand'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (card) => DuelCardSnapshot.fromJson(
              Map<String, dynamic>.from(card),
            ),
          )
          .toList(),
      usedCardIds: (root['usedCardIds'] as List? ?? const [])
          .map((id) => '$id')
          .toList(),
      usedSkillIds: (root['usedSkillIds'] as List? ?? const [])
          .map((id) => '$id')
          .toList(),
      rounds: roundsRaw,
      arena: root['arena'] is Map
          ? ArenaContextModel.fromJson(
              Map<String, dynamic>.from(root['arena'] as Map),
            )
          : null,
      houseCommitment:
          (root['houseCommitment'] ??
                  root['commitment'] ??
                  firstCommitment?['hash'])
              ?.toString(),
      commitmentVerification: root['commitmentVerification'] is Map
          ? Map<String, dynamic>.from(
              root['commitmentVerification'] as Map,
            )
          : null,
      reward: root['reward'] is Map
          ? Map<String, dynamic>.from(root['reward'] as Map)
          : null,
    );
  }

  DuelRoundModel? get latestRound => rounds.isEmpty ? null : rounds.last;

  bool get isFinished => phase == DuelPhase.finished;
}
