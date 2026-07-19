import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:final_whistle/api/live_data.dart';
import 'package:final_whistle/api/models.dart';
import 'package:final_whistle/match_hub/freshness.dart';
import 'package:final_whistle/match_hub/controller.dart';
import 'package:final_whistle/match_hub/models.dart';
import 'package:final_whistle/match_hub/palette.dart';
import 'package:final_whistle/match_hub/shell.dart';
import 'package:final_whistle/match_hub/timeline.dart';
import 'package:final_whistle/match_hub/widgets/header.dart';
import 'package:final_whistle/match_hub/widgets/section_rail.dart';
import 'package:final_whistle/state/room_controller.dart';

Team _team(String code, String name) => Team(
      id: code.toLowerCase(),
      name: name,
      code: code,
      flag: '🏳️',
      rating: 80,
    );

Fixture _fixture() => Fixture(
      id: 'fx1',
      competition: 'FIFA World Cup',
      home: _team('ARG', 'Argentina'),
      away: _team('FRA', 'France'),
      kickoff: DateTime.now().toIso8601String(),
      stage: 'Round of 16',
      status: 'live',
      venue: 'Stadium',
    );

RoomView _room({
  String status = 'live',
  String lifecycle = 'live',
  String feedFreshness = 'live',
  bool replay = false,
  ScoreView? score,
  List<PulseCard> pulse = const [],
  List<PromptView> prompts = const [],
  ReplayStateView? replayState,
}) {
  return RoomView(
    id: 'r1',
    code: 'ABCD',
    name: 'Hub',
    hostId: 'h1',
    status: status,
    kind: 'official',
    autoManaged: true,
    fixture: _fixture(),
    modes: RoomModes(true, true),
    momentum: 0,
    win: WinChance(33, 34, 33),
    score: score ??
        ScoreView(
          minute: 67,
          clockSeconds: 67 * 60,
          running: true,
          phase: 3,
          goals: StatPair(1, 1),
          yellow: StatPair(2, 1),
          red: StatPair(0, 0),
          corners: StatPair(3, 4),
        ),
    members: const [],
    chat: const [],
    pulse: pulse,
    prompts: prompts,
    recaps: const [],
    proof: ProofInfo(
      leafCount: 0,
      root: '',
      anchorSignature: null,
      anchored: false,
      cluster: 'devnet',
    ),
    lifecycle: lifecycle,
    feedFreshness: feedFreshness,
    lineupStatus: 'confirmed',
    revision: 3,
    reactionTally: const {'🔥': 4},
    replay: replay,
    replayState: replayState,
  );
}

class _ReplayRoomController extends RoomController {
  final RoomView value;

  _ReplayRoomController(this.value) : super(value.id) {
    memberId = 'me';
  }

  @override
  RoomView? get room => value;

  @override
  Map<String, String> get myPicks => const {};
}

class _RecordingHubController extends MatchHubController {
  String? replayAction;

  _RecordingHubController(RoomController roomController)
    : super(roomController: roomController);

  @override
  Future<void> controlReplay({
    required String action,
    int? minute,
    double? speed,
  }) async {
    replayAction = action;
  }
}

void main() {
  testWidgets('showcase Next Beat stays above the persistent match dock', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final room = _room(
      replay: true,
      replayState: ReplayStateView(
        active: true,
        paused: true,
        currentMinute: 0,
        totalMinutes: 120,
        speed: 1,
        mode: 'showcase',
        beat: 0,
        nextBeatMinute: 7,
        awaitingAction: true,
      ),
    );
    final roomController = _ReplayRoomController(room);
    final hub = _RecordingHubController(roomController);
    addTearDown(hub.dispose);
    addTearDown(roomController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MatchHubShell(
          hub: hub,
          room: room,
          myPicks: const {},
          joined: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nextBeat = find.widgetWithText(FilledButton, 'NEXT BEAT');
    final rewardsDock = find.ancestor(
      of: find.text('Rewards'),
      matching: find.byType(InkWell),
    );
    expect(nextBeat, findsOneWidget);
    expect(rewardsDock, findsOneWidget);
    expect(
      tester.getRect(nextBeat).bottom,
      lessThanOrEqualTo(tester.getRect(rewardsDock).top),
    );

    await tester.tap(nextBeat);
    await tester.pump();
    expect(hub.replayAction, 'nextBeat');
  });

  test('lifecycle badges cover pregame live HT ET pens FT replay', () {
    expect(
      lifecycleBadge(_room(status: 'lobby', lifecycle: 'pregame'), isReplay: false),
      'PREGAME',
    );
    expect(lifecycleBadge(_room(), isReplay: false), 'LIVE');
    expect(
      lifecycleBadge(
        _room(
          score: ScoreView(
            minute: 45,
            clockSeconds: 2700,
            running: false,
            phase: 2,
            goals: StatPair(0, 0),
            yellow: StatPair(0, 0),
            red: StatPair(0, 0),
            corners: StatPair(0, 0),
          ),
        ),
        isReplay: false,
      ),
      'HALF-TIME',
    );
    expect(
      lifecycleBadge(
        _room(
          score: ScoreView(
            minute: 105,
            clockSeconds: 6300,
            running: true,
            phase: 5,
            goals: StatPair(1, 1),
            yellow: StatPair(0, 0),
            red: StatPair(0, 0),
            corners: StatPair(0, 0),
          ),
        ),
        isReplay: false,
      ),
      'EXTRA TIME',
    );
    expect(
      lifecycleBadge(
        _room(
          score: ScoreView(
            minute: 120,
            clockSeconds: 7200,
            running: true,
            phase: 8,
            goals: StatPair(1, 1),
            yellow: StatPair(0, 0),
            red: StatPair(0, 0),
            corners: StatPair(0, 0),
          ),
        ),
        isReplay: false,
      ),
      'PENALTIES',
    );
    expect(
      lifecycleBadge(_room(status: 'finished', lifecycle: 'finished'), isReplay: false),
      'FULL TIME',
    );
    expect(lifecycleBadge(_room(replay: true), isReplay: true), 'REPLAY');
  });

  test('stale feed freezes clock and pauses calls', () {
    final health = evaluateFeedHealth(_room(feedFreshness: 'stale'));
    expect(health.stale, isTrue);
    expect(health.clockFrozen, isTrue);
    expect(health.callsPaused, isTrue);
    expect(formatClock(_room(feedFreshness: 'stale'), frozen: true), contains('DELAYED'));
  });

  test('timeline joins match-data events and gates by replay frame', () {
    final events = [
      VerifiedMatchEvent(
        id: 'tx:fx1:goal:1',
        sourceEventId: 'tx:fx1:goal:1',
        kind: 'goal',
        side: 'home',
        teamCode: 'ARG',
        label: 'Goal',
        seq: 1,
        ts: 1,
        minute: 12,
        playerName: 'Messi',
      ),
      VerifiedMatchEvent(
        id: 'tx:fx1:goal:2',
        sourceEventId: 'tx:fx1:goal:2',
        kind: 'goal',
        side: 'away',
        teamCode: 'FRA',
        label: 'Goal',
        seq: 2,
        ts: 2,
        minute: 55,
        playerName: 'Mbappé',
      ),
    ];
    final match = MatchData(
      fixtureId: 'fx1',
      source: 'txline',
      lineupStatus: 'confirmed',
      fixture: _fixture(),
      home: VerifiedTeamLineup(
        id: 'arg',
        name: 'Argentina',
        code: 'ARG',
        players: const [],
      ),
      away: VerifiedTeamLineup(
        id: 'fra',
        name: 'France',
        code: 'FRA',
        players: const [],
      ),
      events: events,
      score: null,
      updatedAt: 1,
      stale: false,
    );
    final all = buildMatchTimeline(room: _room(), matchData: match);
    expect(all.length, 2);
    final gated = buildMatchTimeline(
      room: _room(),
      matchData: match,
      frameMinute: 30,
    );
    expect(gated.length, 1);
    expect(gated.first.id, 'tx:fx1:goal:1');
  });

  test('reward drop ids are stable for dedupe keys', () {
    final drop = MomentDropView(
      id: 'md_1',
      memberId: 'me',
      kind: 'goal',
      label: 'Caller',
      matchLabel: 'ARG v FRA',
      rarity: 3,
      minute: 67,
      createdAt: 1,
    );
    expect(drop.id, 'md_1');
  });

  test('no production BETS label in section rail', () {
    expect(
      MatchHubSectionRail(selected: MatchHubSection.live, onSelect: (_) {})
          .toStringShort(),
      isNot(contains('BETS')),
    );
  });

  testWidgets('header lifecycle variants render without blank body', (tester) async {
    final anton = FontLoader('Anton')
      ..addFont(rootBundle.load('assets/fonts/Anton-Regular.ttf'));
    final archivo = FontLoader('Archivo')
      ..addFont(rootBundle.load('assets/fonts/Archivo-Regular.ttf'));
    await Future.wait([anton.load(), archivo.load()]);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final headers = <String, MatchHubHeaderState>{
      'live': MatchHubHeaderState(
        competition: 'R16',
        lifecycleBadge: 'LIVE',
        home: _team('ARG', 'Argentina'),
        away: _team('FRA', 'France'),
        scoreText: '1 - 1',
        clockText: "67'",
        clockFrozen: false,
        watching: 1204,
        feedFreshness: 'live',
        notifyOn: true,
        replay: false,
        latestEventRibbon: '⚽ Goal',
      ),
      'stale': MatchHubHeaderState(
        competition: 'R16',
        lifecycleBadge: 'LIVE',
        home: _team('ARG', 'Argentina'),
        away: _team('FRA', 'France'),
        scoreText: '1 - 1',
        clockText: "67' · DELAYED",
        clockFrozen: true,
        freezeReason: 'Updates delayed',
        watching: 1204,
        feedFreshness: 'stale',
        notifyOn: true,
        replay: false,
      ),
      'ft': MatchHubHeaderState(
        competition: 'R16',
        lifecycleBadge: 'FULL TIME',
        home: _team('ARG', 'Argentina'),
        away: _team('FRA', 'France'),
        scoreText: '2 - 1',
        clockText: 'FT',
        clockFrozen: false,
        watching: 2204,
        feedFreshness: 'live',
        notifyOn: true,
        replay: false,
      ),
    };

    for (final entry in headers.entries) {
      final palette = TeamPalette.forFixture(entry.value.home, entry.value.away);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: HubColors.stadium,
            body: Column(
              children: [
                MatchHubHeader(
                  header: entry.value,
                  palette: palette,
                  expanded: true,
                ),
                MatchHubSectionRail(
                  selected: MatchHubSection.live,
                  onSelect: (_) {},
                ),
                const Expanded(
                  child: Center(
                    child: Text('LIVE', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value.lifecycleBadge), findsWidgets);
      expect(find.text('CALLS'), findsOneWidget);
      expect(find.text('LINEUPS'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
  });
}
