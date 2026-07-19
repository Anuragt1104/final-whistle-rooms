import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:final_whistle/widgets/showcase_replay_recommendation.dart';

void main() {
  testWidgets('Home exposes the verified classic replay journey', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShowcaseReplayRecommendation(
            available: true,
            onStart: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('EXPERIENCE A VERIFIED CLASSIC'), findsOneWidget);
    expect(find.text('ARG 3–1 SWI'), findsOneWidget);
    expect(find.text('ABOUT 3 MIN'), findsOneWidget);
    expect(find.text('TxLINE HISTORICAL'), findsOneWidget);
    await tester.tap(find.text('START EXPERIENCE'));
    expect(opened, isTrue);
  });
}
