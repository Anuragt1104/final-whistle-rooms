import 'package:final_whistle/duel/duel_models.dart';
import 'package:final_whistle/duel/duel_presentation_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DuelRoundModel _round({required String winnerId}) => DuelRoundModel(
  round: 1,
  axis: 'finishing',
  attackerId: 'fan-a',
  yourModifiers: const [
    DuelModifierModel(label: 'Lineage', value: 6, source: 'lineage'),
  ],
  opponentModifiers: const [],
  yourCard: const DuelCardSnapshot(
    id: 'you-1',
    name: 'You',
    teamCode: 'FRA',
    position: 'FW',
    axes: {'finishing': 90},
    rating: 90,
  ),
  opponentCard: const DuelCardSnapshot(
    id: 'opp-1',
    name: 'House',
    teamCode: 'ARG',
    position: 'FW',
    axes: {'finishing': 80},
    rating: 80,
  ),
  yourBase: 90,
  opponentBase: 80,
  yourScore: 96,
  opponentScore: 80,
  winnerId: winnerId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('reduced motion reveals scores only at result phase', () async {
    final presentation = DuelPresentationController();
    presentation.reducedMotion = true;
    final round = _round(winnerId: 'fan-a');
    expect(presentation.showScores, isFalse);
    final future = presentation.play(
      duelId: 'duel-1',
      round: round,
      fanId: 'fan-a',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(presentation.phase, DuelPresentationPhase.result);
    expect(presentation.showScores, isTrue);
    expect(presentation.visibleRound?.yourScore, 96);
    await future;
    expect(presentation.busy, isFalse);
  });

  test('DuelViewModel maps authoritative actor-centric server view', () {
    final view = DuelViewModel.fromJson({
      'id': 'duel_1',
      'code': 'ABC234',
      'mode': 'stadium',
      'opponentType': 'house',
      'phase': 'cardSelection',
      'version': 3,
      'actorId': 'fan-a',
      'attackerId': 'fan-a',
      'scores': {'fan-a': 1, 'house': 0},
      'hand': [
        {
          'id': 'c1',
          'name': 'Mbappé',
          'teamCode': 'FRA',
          'position': 'FW',
          'axes': {'finishing': 96, 'chaos': 70, 'clutch': 80, 'marketShock': 60, 'aura': 90},
        },
      ],
      'usedCardIds': [],
      'usedSkillIds': [],
      'hasSubmitted': false,
      'opponent': {'id': 'house', 'submitted': true, 'cardsRemaining': 2},
      'timer': {'startedAt': 1, 'deadlineAt': 2, 'graceEndsAt': 3},
      'rounds': [],
      'commitments': [
        {'index': 0, 'hash': 'abc123'},
      ],
    });
    expect(view.fanId, 'fan-a');
    expect(view.yourHand, hasLength(1));
    expect(view.yourScore, 1);
    expect(view.opponentScore, 0);
    expect(view.opponentSubmitted, isTrue);
    expect(view.yourTurn, isTrue);
    expect(view.houseCommitment, 'abc123');
    expect(view.deadlineAt, isNotNull);
  });

  test('round mapping keeps actor scores on the you side', () {
    final round = DuelRoundModel.fromJson({
      'round': 1,
      'axis': 'finishing',
      'attackerId': 'fan-a',
      'aFanId': 'house',
      'bFanId': 'fan-a',
      'aCard': {
        'id': 'h1',
        'name': 'House',
        'teamCode': 'ARG',
        'position': 'FW',
        'axes': {'finishing': 70},
      },
      'bCard': {
        'id': 'y1',
        'name': 'You',
        'teamCode': 'FRA',
        'position': 'FW',
        'axes': {'finishing': 95},
      },
      'aScore': {'base': 70, 'resonance': 0, 'calledIt': 0, 'skill': 0, 'total': 70},
      'bScore': {'base': 95, 'resonance': 6, 'calledIt': 2, 'skill': 0, 'total': 103},
      'winnerId': 'fan-a',
    }, actorId: 'fan-a');
    expect(round.yourCard?.id, 'y1');
    expect(round.opponentCard?.id, 'h1');
    expect(round.yourScore, 103);
    expect(round.opponentScore, 70);
    expect(round.yourModifiers.map((m) => m.label), contains('Lineage'));
  });
}
