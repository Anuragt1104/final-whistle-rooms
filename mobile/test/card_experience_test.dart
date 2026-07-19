import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:final_whistle/api/cards.dart';
import 'package:final_whistle/api/models.dart';
import 'package:final_whistle/screens/card_detail_screen.dart';
import 'package:final_whistle/widgets/gyro_card.dart';

class _ManualMotionSource implements CardMotionSource {
  final _acceleration = StreamController<MotionVectorSample>.broadcast();
  final _rotation = StreamController<MotionVectorSample>.broadcast();

  @override
  Stream<MotionVectorSample> get acceleration => _acceleration.stream;

  @override
  Stream<MotionVectorSample> get rotation => _rotation.stream;

  void accelerate(double x, double y, double z, int millis) {
    _acceleration.add(
      MotionVectorSample(x: x, y: y, z: z, timestampMicros: millis * 1000),
    );
  }

  void rotate(double x, double y, double z, int millis) {
    _rotation.add(
      MotionVectorSample(x: x, y: y, z: z, timestampMicros: millis * 1000),
    );
  }

  Future<void> close() async {
    await _acceleration.close();
    await _rotation.close();
  }
}

void main() {
  test('MomentDropView parses recipient collectible metadata', () {
    final d = MomentDropView.fromJson({
      'id': 'mom_1',
      'memberId': 'm_1',
      'kind': 'goal',
      'label': 'Goal',
      'matchLabel': 'ARG vs SWI',
      'rarity': 5,
      'minute': 122,
      'createdAt': 7,
      'sourceEventId': 'tx:18222446:goal-3',
      'playerId': 'julian',
      'playerName': 'Julián Álvarez',
      'teamCode': 'ARG',
      'artKey': 'goal:arg',
      'calledIt': true,
      'promptId': 'showcase:18222446:108',
      'promptQuestion': "Who scores next before 115'?",
      'answerLabel': 'Argentina',
      'proof': {
        'root': 'abc123',
        'sourceEventId': 'tx:18222446:goal-3',
        'anchored': true,
      },
    });
    expect(d.memberId, 'm_1');
    expect(d.rarity, 5);
    expect(d.matchLabel, 'ARG vs SWI');
    expect(d.sourceEventId, 'tx:18222446:goal-3');
    expect(d.playerName, 'Julián Álvarez');
    expect(d.calledIt, isTrue);
    expect(d.promptQuestion, "Who scores next before 115'?");
    expect(d.answerLabel, 'Argentina');
    expect(d.proof?['anchored'], isTrue);
  });

  test('ReplayStateView parses guided showcase pacing', () {
    final state = ReplayStateView.fromJson({
      'active': true,
      'paused': true,
      'currentMinute': 7,
      'totalMinutes': 120,
      'speed': 1,
      'mode': 'showcase',
      'beat': 1,
      'nextBeatMinute': 9,
      'awaitingAction': true,
    });
    expect(state.mode, 'showcase');
    expect(state.beat, 1);
    expect(state.nextBeatMinute, 9);
    expect(state.awaitingAction, isTrue);
  });

  testWidgets('collectible detail opens with layered tilt guidance', (
    tester,
  ) async {
    final m = MomentCard(
      id: 'mom_1',
      fixtureId: 'fx',
      matchLabel: 'ARG vs SWI',
      kind: 'goal',
      label: 'Extra-time winner',
      leafData: '',
      rarity: 5,
      minute: 122,
      createdAt: 1,
      calledIt: true,
      oddsSandwich: const {},
    );
    await tester.pumpWidget(MaterialApp(home: CardDetailScreen.moment(m)));
    await tester.pump();
    expect(find.text('Extra-time winner'), findsOneWidget);
    expect(find.text('TILT YOUR PHONE · OR DRAG'), findsOneWidget);
    expect(find.text('5★ MOMENT'), findsOneWidget);
  });

  testWidgets('device tilt moves the card plane and its depth layers', (
    tester,
  ) async {
    final source = _ManualMotionSource();
    final motion = CardMotionController(source: source);
    addTearDown(() async {
      motion.dispose();
      await source.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 250,
            height: 350,
            child: GyroTiltCard(
              motion: motion,
              enableTilt: true,
              intensity: 1.0,
              child: const ParallaxLayer(
                depth: 18,
                debugLabel: 'test-subject',
                child: ColoredBox(color: Colors.orange),
              ),
            ),
          ),
        ),
      ),
    );

    source.accelerate(0, 9.8, 0, 0);
    await tester.pump();
    final neutralCard = tester.widget<Transform>(
      find.byKey(const ValueKey('collectible-card-transform')),
    );
    final neutralLayer = tester.widget<Transform>(
      find.byKey(const ValueKey('parallax-test-subject')),
    );

    source.accelerate(4.8, 8.5, 0.7, 16);
    source.accelerate(4.8, 8.5, 0.7, 32);
    source.accelerate(4.8, 8.5, 0.7, 48);
    await tester.pump(const Duration(milliseconds: 48));

    final tiltedCard = tester.widget<Transform>(
      find.byKey(const ValueKey('collectible-card-transform')),
    );
    final tiltedLayer = tester.widget<Transform>(
      find.byKey(const ValueKey('parallax-test-subject')),
    );
    expect(
      motion.x,
      greaterThan(0),
      reason: 'positive screen-space phone tilt must produce positive yaw',
    );
    expect(tiltedCard.transform, isNot(equals(neutralCard.transform)));
    expect(tiltedLayer.transform, isNot(equals(neutralLayer.transform)));
    expect(motion.hasMoved, isTrue);
  });

  test('gyroscope and drag use the same screen-space direction', () async {
    final source = _ManualMotionSource();
    final motion = CardMotionController(source: source)..start();
    addTearDown(() async {
      motion.dispose();
      await source.close();
    });

    source.accelerate(0, 9.8, 0, 0);
    await Future<void>.delayed(Duration.zero);
    source.rotate(0, 1, 0, 10);
    source.rotate(0, 1, 0, 30);
    await Future<void>.delayed(Duration.zero);
    expect(motion.x, greaterThan(0));

    final dragOnly = CardMotionController();
    addTearDown(dragOnly.dispose);
    dragOnly.drag(const Offset(20, 10));
    expect(dragOnly.x, greaterThan(0));
    expect(dragOnly.y, greaterThan(0));
  });
}
