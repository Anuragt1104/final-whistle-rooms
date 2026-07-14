import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../api/models.dart';
import '../util/merkle.dart';
import 'ai_question_writer.dart';
import 'match_facts.dart';
import 'players.dart';

/// A fully on-device live match — produces the same RoomView the UI renders,
/// driven by a timer. This is what makes the app feel alive with zero backend:
/// a real, watchable match with pulse cards, live odds, Next Swing prompts that
/// settle, a moving leaderboard (you + simulated fans), and recaps.
class LiveMatchEngine extends ChangeNotifier {
  final Fixture fixture;
  final bool draftMode, nextSwingMode;
  final String myName;
  final String reactionPack;
  final bool voice, spoilerSafe;

  /// The fixture's real score/minute at open time. A replay room seeded with
  /// this starts where reality is instead of contradicting the home card.
  final FixtureScore? seedScore;

  LiveMatchEngine(
    this.fixture, {
    required this.draftMode,
    required this.nextSwingMode,
    required this.myName,
    this.reactionPack = 'classic',
    this.voice = false,
    this.spoilerSafe = false,
    this.seedScore,
  }) : _rng = Random(fixture.id.hashCode) {
    _members = [
      _M('me', myName.isEmpty ? 'You' : myName, isHost: true),
      _M('b1', _pick(_botNames), isBot: true)..side = 'home',
      _M('b2', _pick(_botNames), isBot: true)..side = 'away',
      _M('b3', _pick(_botNames), isBot: true)
        ..side = _rng.nextBool() ? 'home' : 'away',
    ];
  }

  final Random _rng;
  static const _botNames = [
    'marcus_k',
    'jordan.t',
    'priya_d',
    'sam',
    'mia',
    'leo',
    'noor',
    'diego',
  ];
  static const _cheers = [
    'what a room to be in 🙌',
    'GET IN! 🔥',
    'unreal 😱',
    'called it 😎',
    'pressure building',
    'this is it',
    '💯',
    'tense out here',
  ];

  final String code = _genCode();
  String status = 'lobby';
  double _minuteF = 0;
  bool _atHalfTime = false;
  int _htUntil = 0;
  bool _htRecap = false;
  // where to resume after a break (2nd half or ET 2nd half)
  int _resumePhase = 3;
  double _resumeMinute = 45.001;
  // penalty shootout state (only when a knockout-style match is level after ET)
  int _penHome = 0, _penAway = 0;
  String _penTurn = 'home';
  bool _penDecided = false;
  String? _penWinner;
  int _penNext = 0;
  final List<_Pen> _penKicks = [];

  int gH = 0, gA = 0, yH = 0, yA = 0, rH = 0, rA = 0, cH = 0, cA = 0;
  // first-half tallies (second half = total - firstHalf) for the by-half view
  int gH1 = 0, gA1 = 0, yH1 = 0, yA1 = 0, rH1 = 0, rA1 = 0, cH1 = 0, cA1 = 0;
  int _momentum = 0;
  double _oddsDrift =
      0; // mean-reverting market jitter so win-chance breathes tick-to-tick
  // Real Merkle commitment: every reacted-to event is hashed into a leaf using
  // the SAME scheme as the backend (lib/util/merkle.ts), so the "Verified" chip
  // in a solo room shows a genuine, on-device-verifiable SHA-256 root — not a
  // placeholder. Leaf format mirrors the server exactly.
  final List<String> _leaves = [];
  int _seq = 0;
  String? _cachedRoot;
  int _cachedLeafCount = -1;
  int get proofLeaves => _leaves.length;
  void _leafEvent(String kind, String side, int m) =>
      _leaves.add('${_seq++}:$m:$kind:$side:$gH-$gA');
  void _leafPhase(String kind, int m) => _leaves.add('${_seq++}:$m:$kind');
  String? get _liveRoot {
    if (_leaves.isEmpty) return null;
    if (_cachedLeafCount != _leaves.length) {
      _cachedRoot = buildMerkleTree(_leaves).root;
      _cachedLeafCount = _leaves.length;
    }
    return _cachedRoot;
  }

  int _lastPromptMinute = -99;

  final List<PulseCard> _pulse = [];
  final List<ChatView> _chat = [];
  final Map<String, PromptView> _prompts = {};
  final Map<String, _Resolver> _res = {};
  final List<RecapView> _recaps = [];
  final List<_GoalRec> _goals = [];
  late List<_M> _members;
  final Map<String, String> myPicks = {};

  // Man of the Match
  List<MotmCandidate>? _motm;
  int _motmTotal = 0;
  String? _myMotmVote;

  Timer? _timer;
  int _phase = 0; // 0 pre,1 H1,2 HT,3 H2,4 FT

  // ---- public API used by RoomController.local ----
  void start() {
    if (status == 'live') return;
    status = 'live';
    _phase = 1;
    _leafPhase('kickoff', 0);
    final seeded = _applySeed();
    if (!seeded) {
      _system('Kick-off! The terrace is live.');
      _addPulse(
        'kickoff',
        '🟢',
        "We're live",
        '${fixture.home.name} vs ${fixture.away.name} is under way.',
        'neutral',
        0,
      );
    }
    _timer = Timer.periodic(const Duration(milliseconds: 750), (_) => _tick());
    notifyListeners();
  }

  /// Fast-forward the sim to the fixture's real score/minute (replay rooms).
  /// Goal/card history comes from the deterministic facts engine so the pulse
  /// feed, final-whistle scorers and MOTM all agree with the match centre.
  bool _applySeed() {
    final s = seedScore;
    if (s == null) return false;
    final m = s.minute.clamp(
      0,
      88,
    ); // ≥90 clamps so the room still has an ending
    if (s.home + s.away == 0 && m <= 1) return false;

    final facts = factsFor(fixture);
    gH = s.home;
    gA = s.away;
    _minuteF = m < 45 ? m.toDouble() : (m.toDouble() + 0.001);
    _phase = m < 45 ? 1 : 3;
    if (m >= 45)
      _htRecap = true; // don't re-fire the HT recap for a seeded past

    // goal history: real minutes + scorers from the facts engine where they
    // line up with the seeded score; extra (untracked) goals fall back to the
    // roster cycle so counts always match the scoreboard.
    final factGoals = {'home': <MatchEvent>[], 'away': <MatchEvent>[]};
    for (final e in facts.events.where(
      (e) => e.kind == 'goal' && e.minute <= m,
    )) {
      factGoals[e.side]!.add(e);
    }
    void seedGoals(String side, int count) {
      final fg = factGoals[side]!;
      final team = side == 'home' ? fixture.home : fixture.away;
      for (var i = 0; i < count; i++) {
        final minute = i < fg.length
            ? fg[i].minute
            : (5 + (i * 17 + fixture.id.hashCode.abs()) % (m < 2 ? 1 : m - 1));
        final name = i < fg.length
            ? fg[i].player
            : scorerName(fixture, side, i);
        _goals.add(_GoalRec(name, minute, side, team.code));
        if (minute <= 45) side == 'home' ? gH1++ : gA1++;
        _leaves.add('${_seq++}:$minute:goal:$side:seed');
        _addPulse(
          'goal',
          '⚽',
          'GOAL — ${team.name}',
          '$name struck in the ${minute}\'.',
          side,
          minute,
          scorer: name,
        );
      }
    }

    seedGoals('home', s.home);
    seedGoals('away', s.away);
    _goals.sort((a, b) => a.minute - b.minute);

    // yellows from the facts engine (secondary, keeps the stats panel honest)
    for (final e in facts.events.where(
      (e) => e.kind == 'yellow' && e.minute <= m,
    )) {
      if (e.side == 'home') {
        yH++;
        if (e.minute <= 45) yH1++;
      } else {
        yA++;
        if (e.minute <= 45) yA1++;
      }
    }
    // corners: proportional share of the deterministic full-match total
    cH = (facts.home.corners * m / 94).round();
    cA = (facts.away.corners * m / 94).round();
    cH1 = m >= 45 ? (cH * 0.55).round() : cH;
    cA1 = m >= 45 ? (cA * 0.55).round() : cA;

    // win-chance history: ramp from the pre-match baseline to the seeded state
    _recomputeWin(m);
    final w1 = _win.home;
    final rh = fixture.home.rating, ra = fixture.away.rating;
    final w0 = (42 + (rh - ra) * 0.45).clamp(5, 95).round();
    for (var i = 0; i <= m; i++) {
      final t = m == 0 ? 1.0 : i / m;
      final jitter = ((i * 2654435761) % 5) - 2;
      _winHistory.add(((w0 + (w1 - w0) * t).round() + jitter).clamp(3, 97));
    }
    _winSampleMinute = m;

    _leafPhase('seeded:${s.home}-${s.away}@$m', m); // proof stays honest
    _system(
      'Joined in progress — ${fixture.home.code} $gH–$gA ${fixture.away.code}, ${m}\'.',
    );
    _addPulse(
      'kickoff',
      '⏩',
      'Joined in progress',
      '${fixture.home.code} $gH–$gA ${fixture.away.code} · picking it up at ${m}\'.',
      'neutral',
      m,
    );
    return true;
  }

  void pickSide(String side) {
    final me = _members.first;
    me.side = side;
    _system(
      '$myName drafted ${side == 'home' ? fixture.home.name : fixture.away.name}',
    );
    notifyListeners();
  }

  void predict(String promptId, String key) {
    final p = _prompts[promptId];
    if (p == null || p.status != 'open') return;
    myPicks[promptId] = key;
    notifyListeners();
  }

  void chat(String text) {
    _chat.add(
      ChatView(
        id: _id('c'),
        memberId: 'me',
        name: myName,
        avatar: '',
        text: text,
        kind: 'chat',
        ts: _now(),
      ),
    );
    _trim();
    notifyListeners();
  }

  void react(String emoji) {
    _chat.add(
      ChatView(
        id: _id('c'),
        memberId: 'me',
        name: myName,
        avatar: '',
        text: emoji,
        kind: 'reaction',
        ts: _now(),
      ),
    );
    _trim();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ---- tick ----
  void _tick() {
    if (status != 'live') return;

    // penalty shootout runs on its own cadence (no match clock)
    if (_phase == 8) {
      _tickShootout();
      notifyListeners();
      return;
    }

    // half-time / ET-break holds
    if (_atHalfTime) {
      if (_now() >= _htUntil) {
        _atHalfTime = false;
        _phase = _resumePhase;
        _minuteF = _resumeMinute;
      } else {
        notifyListeners();
        return;
      }
    }

    _minuteF += 1.5;
    var m = _minuteF.floor();
    // clamp at the end of each running period
    if (_phase == 1 && m >= 45) {
      m = 45;
      _minuteF = 45;
    }
    if (_phase == 3 && m >= 90) {
      m = 90;
      _minuteF = 90;
    }
    if (_phase == 5 && m >= 105) {
      m = 105;
      _minuteF = 105;
    }
    if (_phase == 7 && m >= 120) {
      m = 120;
      _minuteF = 120;
    }

    _maybeEvents(m);
    _recomputeWin(m);
    if (m > _winSampleMinute) {
      _winHistory.add(_win.home);
      _winSampleMinute = m;
      if (_winHistory.length > 130) _winHistory.removeAt(0);
    }
    if (nextSwingMode) {
      _maybePrompt(m);
      _resolvePrompts(m);
    }
    _botChatter(m);

    // phase transitions
    if (m >= 45 && _phase == 1) {
      _phase = 2;
      _atHalfTime = true;
      _htUntil = _now() + 2200;
      _resumePhase = 3;
      _resumeMinute = 45.001;
      _leafPhase('half-time', 45);
      _addPulse(
        'half-time',
        '⏸️',
        'Half-time',
        '${fixture.home.code} $gH–$gA ${fixture.away.code}.',
        'neutral',
        45,
      );
      if (!_htRecap) {
        _htRecap = true;
        _makeRecap('half-time', m);
      }
    } else if (m >= 90 && _phase == 3) {
      // level after 90' → extra time (knockout drama); otherwise it's over
      gH == gA ? _startExtraTime() : _finish();
    } else if (m >= 105 && _phase == 5) {
      _phase = 6;
      _atHalfTime = true;
      _htUntil = _now() + 1600;
      _resumePhase = 7;
      _resumeMinute = 105.001;
      _leafPhase('et-half-time', 105);
      _addPulse(
        'half-time',
        '⏸️',
        'End of ET first half',
        '${fixture.home.code} $gH–$gA ${fixture.away.code}. 15 minutes left.',
        'neutral',
        105,
      );
    } else if (m >= 120 && _phase == 7) {
      // still level after extra time → penalties
      gH == gA ? _startPenalties() : _finish(outcome: 'et');
    }
    notifyListeners();
  }

  void _startExtraTime() {
    _phase = 5;
    _minuteF = 90.001;
    _leafPhase('extra-time', 90);
    _system('Level at full-time — into extra time!');
    _addPulse(
      'chaos',
      '⚡',
      'EXTRA TIME',
      'All square after 90 — 30 more minutes to settle it.',
      'hot',
      90,
    );
  }

  void _startPenalties() {
    _phase = 8;
    _leafPhase('penalties', 120);
    _penHome = 0;
    _penAway = 0;
    _penTurn = 'home';
    _penDecided = false;
    _penWinner = null;
    _penKicks.clear();
    _penNext = _now() + 1000;
    _system('Still level after extra time — it goes to penalties!');
    _addPulse(
      'chaos',
      '🎯',
      'PENALTIES',
      "It's down to spot-kicks. Nerves of steel required.",
      'hot',
      120,
    );
  }

  void _tickShootout() {
    if (_penDecided) {
      if (_now() >= _penNext) _finish(penWinner: _penWinner);
      return;
    }
    if (_now() < _penNext) return;
    _penNext = _now() + 1000;

    final side = _penTurn;
    final kickIdx = _penKicks.where((k) => k.side == side).length;
    final scored = _rng.nextDouble() < 0.74;
    _penKicks.add(_Pen(side, scored));
    if (scored) {
      side == 'home' ? _penHome++ : _penAway++;
    }
    final taker = penaltyTaker(fixture, side, kickIdx);
    final keeper = keeperName(fixture, side == 'home' ? 'away' : 'home');
    _addPulse(
      scored ? 'pen-goal' : 'pen-miss',
      scored ? '⚽' : '🧤',
      scored ? 'SCORED — $taker' : 'MISSED — $taker',
      scored
          ? '$taker buries it. $_penHome–$_penAway on pens.'
          : '$keeper saves! Still $_penHome–$_penAway.',
      side,
      120,
      scorer: taker,
    );
    if (_rng.nextBool()) _botShout(side);

    _penTurn = side == 'home' ? 'away' : 'home';
    _checkPenDecided();
    if (_penDecided) _penNext = _now() + 1800; // beat before the final whistle
  }

  void _checkPenDecided() {
    final hk = _penKicks.where((k) => k.side == 'home').length;
    final ak = _penKicks.where((k) => k.side == 'away').length;
    final hRemain = hk < 5 ? 5 - hk : 0;
    final aRemain = ak < 5 ? 5 - ak : 0;
    // within best-of-five: a lead that can't be caught ends it
    if (hk <= 5 && ak <= 5) {
      if (_penHome > _penAway + aRemain) return _decidePens('home');
      if (_penAway > _penHome + hRemain) return _decidePens('away');
    }
    // sudden death: equal kicks (>=5 each) and scores differ
    if (hk >= 5 && ak >= 5 && hk == ak && _penHome != _penAway) {
      _decidePens(_penHome > _penAway ? 'home' : 'away');
    }
  }

  void _decidePens(String winner) {
    _penDecided = true;
    _penWinner = winner;
    final team = winner == 'home' ? fixture.home : fixture.away;
    _system('${team.name} win $_penHome–$_penAway on penalties!');
  }

  void _maybeEvents(int m) {
    final rh = fixture.home.rating, ra = fixture.away.rating;
    final lambdaH = 0.018 * (0.7 + (rh - ra) / 120) * (gH < gA ? 1.25 : 1.0);
    final lambdaA = 0.018 * (0.7 + (ra - rh) / 120) * (gA < gH ? 1.25 : 1.0);
    if (_rng.nextDouble() < lambdaH.clamp(0.004, 0.05)) _goal('home', m);
    if (_rng.nextDouble() < lambdaA.clamp(0.004, 0.05)) _goal('away', m);
    if (_rng.nextDouble() < 0.06) _corner(_rng.nextBool() ? 'home' : 'away', m);
    if (_rng.nextDouble() < 0.03) _card(_rng.nextBool() ? 'home' : 'away', m);
  }

  void _goal(String side, int m) {
    if (side == 'home') {
      gH++;
      _momentum = (_momentum + 38).clamp(-100, 100);
    } else {
      gA++;
      _momentum = (_momentum - 38).clamp(-100, 100);
    }
    if (_phase == 1) side == 'home' ? gH1++ : gA1++;
    _leafEvent('goal', side, m);
    final team = side == 'home' ? fixture.home : fixture.away;
    final sideCount = side == 'home' ? gH : gA;
    final name = scorerName(fixture, side, sideCount - 1);
    _goals.add(_GoalRec(name, m, side, team.code));
    _addPulse(
      'goal',
      '⚽',
      'GOAL — ${team.name}!',
      'the room erupts! ${fixture.home.code} $gH–$gA ${fixture.away.code}',
      side,
      m,
      scorer: name,
    );
    for (final mem in _members) {
      if (mem.side == side) mem.points += 50;
    }
    if (_rng.nextBool()) _botShout(side == 'home' ? 'home' : 'away');
  }

  void _corner(String side, int m) {
    if (side == 'home') {
      cH++;
    } else {
      cA++;
    }
    if (_phase == 1) side == 'home' ? cH1++ : cA1++;
    _leafEvent('corner', side, m);
    for (final mem in _members) {
      if (mem.side == side) mem.points += 4;
    }
    if (_rng.nextDouble() < 0.4) {
      final team = side == 'home' ? fixture.home : fixture.away;
      final taker = cornerTaker(fixture, side, (side == 'home' ? cH : cA) - 1);
      _addPulse(
        'corner-storm',
        '🚩',
        'Corner — ${team.name}',
        '$taker swings it in — pressure building.',
        side,
        m,
        scorer: taker,
      );
    }
  }

  void _card(String side, int m) {
    if (side == 'home') {
      yH++;
    } else {
      yA++;
    }
    if (_phase == 1) side == 'home' ? yH1++ : yA1++;
    _leafEvent('yellow', side, m);
    _momentum = (_momentum + (side == 'home' ? -5 : 5)).clamp(-100, 100);
    if (_rng.nextDouble() < 0.5) {
      final booked = bookedPlayer(
        fixture,
        side,
        (side == 'home' ? yH : yA) - 1,
      );
      _addPulse(
        'chaos',
        '🟨',
        'Yellow — $booked',
        'Into the book. One more and he walks.',
        side,
        m,
        scorer: booked,
      );
    }
  }

  WinChance _win = WinChance(45, 28, 27);
  final List<int> _winHistory = []; // home win-chance per match-minute
  int _winSampleMinute = -1;
  void _recomputeWin(int m) {
    final rh = fixture.home.rating, ra = fixture.away.rating;
    final lead = gH - gA;
    final tLeft = ((90 - m) / 90).clamp(0.0, 1.0);
    // live-market feel: a gentle mean-reverting random walk + a momentum tilt so
    // the win chance ticks both ways between goals (and the Higher/Lower call is
    // a real read, never a static "always lower").
    _oddsDrift = (_oddsDrift * 0.8 + (_rng.nextDouble() * 2 - 1) * 0.016).clamp(
      -0.05,
      0.05,
    );
    final tilt = _momentum / 100 * 0.05 + _oddsDrift;
    var h = 0.42 + (rh - ra) / 100 * 0.45 + lead * 0.16 * (0.5 + tLeft) + tilt;
    var a =
        0.42 -
        (rh - ra) / 100 * 0.45 -
        lead * 0.16 * (0.5 + tLeft) -
        tilt * 0.6;
    h = h.clamp(0.03, 0.94);
    a = a.clamp(0.03, 0.94);
    var d = (1 - h - a).clamp(0.03, 0.6);
    final sum = h + a + d;
    _win = WinChance(
      (h / sum * 100).round(),
      (d / sum * 100).round(),
      (a / sum * 100).round(),
    );
  }

  void _maybePrompt(int m) {
    if (m >= 86 || _atHalfTime || _phase == 2) return;
    final open = _prompts.values.where((p) => p.status != 'settled').length;
    if (open >= 2 || m - _lastPromptMinute < 5) return;
    _lastPromptMinute = m;
    final lock = min(m + 5, 90);
    final homeLeads = _win.home >= _win.away;
    final leaderCode = homeLeads ? fixture.home.code : fixture.away.code;
    final chaserSide = homeLeads ? 'away' : 'home';
    final leaderPct = homeLeads ? _win.home : _win.away;
    final totalGoals = gH + gA;
    final leadTarget = min(max(m + 20, 70), 90);
    final goalTarget = totalGoals + 1 + (_rng.nextDouble() < 0.45 ? 1 : 0);
    final goalsDeadline = min(max(m + 25, 75), 90);

    // Moment-specific colour: real squad names + the match's own story so the
    // prompts read like a pundit watching THIS game, not a generic quiz.
    final lastGoal = _goals.isNotEmpty ? _goals.last : null;
    final strikerH = scorerName(fixture, 'home', gH);
    final strikerA = scorerName(fixture, 'away', gA);
    final chaserStriker = homeLeads ? strikerA : strikerH;
    final chaserCode = homeLeads ? fixture.away.code : fixture.home.code;
    final hotSide = yH >= yA ? 'home' : 'away';
    final hotBooked = bookedPlayer(fixture, hotSide, max(yH, yA));
    final cornerSide = cH >= cA ? 'home' : 'away';
    final taker = cornerTaker(fixture, cornerSide, max(cH, cA));
    final busyKeeper = keeperName(fixture, chaserSide);
    final swingLine = lastGoal != null && m - lastGoal.minute <= 12
        ? '${lastGoal.name}\'s ${lastGoal.minute}\' strike has $leaderCode at $leaderPct%'
        : _momentum.abs() > 30
              ? '$leaderCode ($leaderPct%) are turning the screw at $m\''
              : '$leaderCode hold $leaderPct% control at $m\'';

    final weighted = <(_PromptDef, double)>[
      (
        _PromptDef(
          '$swingLine — grip tighter in 5\'?',
          [_opt('up', 'Tightens 📈'), _opt('down', 'Slips 📉')],
          110 + (50 - leaderPct).abs(),
          min(m + 2, 90),
          _Resolver.winSwing,
          min(m + 5, 90),
          leaderPct,
          homeLeads ? 0 : 1,
        ),
        3.2,
      ),
      (
        _PromptDef(
          gH == gA
              ? 'Deadlock at $m\' — do ${fixture.home.code} (${_win.home}%) seize it by ${min(m + 6, 90)}\'?'
              : '${fixture.home.code} at ${_win.home}% — does their chance climb by ${min(m + 6, 90)}\'?',
          [_opt('yes', 'They rise'), _opt('no', 'They stall')],
          130,
          min(m + 2, 90),
          _Resolver.oddsRise,
          min(m + 6, 90),
          _win.home,
        ),
        2.4,
      ),
      (
        _PromptDef(
          yH + yA > 0
              ? 'Ref\'s losing patience ($yH–$yA yellows) and $hotBooked is walking a line — who\'s booked next?'
              : 'First booking incoming — which side cracks under the tackles?',
          [
            _opt('home', fixture.home.code, yH >= yA ? 'edgy' : 'cooler'),
            _opt('away', fixture.away.code, yA >= yH ? 'edgy' : 'cooler'),
          ],
          125,
          lock,
          _Resolver.nextCard,
        ),
        2.6,
      ),
      (
        _PromptDef(
          cH + cA > 0
              ? '$taker is waving the crowd up (corners $cH–$cA) — who forces the next one?'
              : 'No corners yet at $m\' — who bends the first one in?',
          [_opt('home', fixture.home.code), _opt('away', fixture.away.code)],
          105,
          lock,
          _Resolver.nextCorner,
        ),
        2.2,
      ),
      (
        _PromptDef(
          (gH - gA).abs() == 1
              ? '$leaderCode lead by one — is it a 2-goal cushion by $leadTarget\' or does $busyKeeper hold the line?'
              : 'Can anyone open a 2-goal gap by $leadTarget\'? (now $gH–$gA)',
          [_opt('yes', '2-goal cushion'), _opt('no', 'Stays tight')],
          140,
          min(m + 3, 90),
          _Resolver.leadByTwo,
          leadTarget,
        ),
        2.0,
      ),
      (
        _PromptDef(
          totalGoals > 0
              ? '$totalGoals in already — do $strikerH & $strikerA push it to $goalTarget by $goalsDeadline\'?'
              : 'Still 0–0 — is there a goal in this by $goalsDeadline\'?',
          [
            _opt('yes', 'Reaches $goalTarget'),
            _opt('no', 'Stays under'),
          ],
          135,
          min(m + 3, 90),
          _Resolver.totalGoals,
          goalsDeadline,
          goalTarget,
        ),
        2.0,
      ),
      (
        _PromptDef(
          'Next to beat the keeper before ${min(m + 15, 90)}\' — $strikerH or $strikerA?',
          [
            _opt('home', '$strikerH (${fixture.home.code})', '${_win.home}%'),
            _opt('none', 'Nobody scores'),
            _opt('away', '$strikerA (${fixture.away.code})', '${_win.away}%'),
          ],
          140,
          lock,
          _Resolver.nextGoal,
          min(m + 15, 90),
        ),
        1.4,
      ),
      (
        _PromptDef(
          '$chaserCode need $chaserStriker firing but $hotBooked keeps fouling — goal or card first?',
          [_opt('goal', 'A goal'), _opt('card', 'A card')],
          100,
          lock,
          _Resolver.firstEvent,
        ),
        0.55,
      ),
    ];

    final totalW = weighted.fold<double>(0, (s, e) => s + e.$2);
    var roll = _rng.nextDouble() * totalW;
    late _PromptDef def;
    for (final item in weighted) {
      roll -= item.$2;
      if (roll <= 0) {
        def = item.$1;
        break;
      }
      def = item.$1;
    }

    final id = _id('sw');
    _prompts[id] = PromptView(
      id: id,
      question: def.q,
      options: def.options,
      basePoints: def.pts,
      locksAtMinute: def.lock,
      status: 'open',
      winningKey: null,
      createdAt: _now(),
      tally: {for (final o in def.options) o.key: 0},
    );
    _res[id] = def.resolver;
    _resMeta[id] = [def.targetMinute, def.baseline, def.side];
    // bots vote shortly
    for (final b in _members.where((x) => x.isBot)) {
      if (_rng.nextDouble() < 0.8)
        _botPicks['$id:${b.id}'] =
            def.options[_rng.nextInt(def.options.length)].key;
    }
    // Publish the template instantly, then let the LLM sharpen the copy.
    if (AiQuestionWriter.configured) unawaited(_upgradePrompt(id, m));
  }

  /// Fire-and-forget LLM rewrite of an open prompt's question/labels. A slow,
  /// failed or invalid reply is a silent no-op; a prompt someone already
  /// answered (or that locked) is never rewritten under their feet.
  Future<void> _upgradePrompt(String id, int m) async {
    final p = _prompts[id];
    if (p == null) return;
    final res = await AiQuestionWriter.rewrite(
      question: p.question,
      options: [for (final o in p.options) (key: o.key, label: o.label)],
      context: {
        'minute': m,
        'score': '${fixture.home.code} $gH-$gA ${fixture.away.code}',
        'home': fixture.home.name,
        'away': fixture.away.name,
        'winChance': {'home': _win.home, 'draw': _win.draw, 'away': _win.away},
        'momentum': _momentum,
        'yellows': '$yH-$yA',
        'corners': '$cH-$cA',
        'recentGoals': [
          for (final g in _goals.reversed.take(6))
            "${g.minute}' ${g.name} (${g.teamCode})",
        ],
        'deadlineMinute': _resMeta[id]?[0],
      },
    );
    if (res == null) return;
    final cur = _prompts[id];
    if (cur == null || cur.status != 'open' || myPicks.containsKey(id)) return;
    _prompts[id] = PromptView(
      id: cur.id,
      question: res.question,
      options: [
        for (final o in cur.options)
          SwingOption(
            key: o.key,
            label: res.labels[o.key] ?? o.label,
            hint: o.hint,
          ),
      ],
      basePoints: cur.basePoints,
      locksAtMinute: cur.locksAtMinute,
      status: cur.status,
      winningKey: cur.winningKey,
      createdAt: cur.createdAt,
      tally: cur.tally,
    );
    notifyListeners();
  }

  final Map<String, List<int>> _resMeta = {};
  final Map<String, String> _botPicks = {};

  void _resolvePrompts(int m) {
    for (final entry in _prompts.entries.toList()) {
      final p = entry.value;
      if (p.status == 'settled') continue;
      // update tally from bot picks
      final tally = {for (final o in p.options) o.key: 0};
      for (final b in _members.where((x) => x.isBot)) {
        final k = _botPicks['${p.id}:${b.id}'];
        if (k != null && tally.containsKey(k)) tally[k] = tally[k]! + 1;
      }
      final myK = myPicks[p.id];
      if (myK != null && tally.containsKey(myK)) tally[myK] = tally[myK]! + 1;

      var status = p.status;
      if (p.status == 'open' && m >= p.locksAtMinute) status = 'locked';

      String? winKey;
      if (status == 'locked') winKey = _settle(p.id, m);

      _prompts[p.id] = PromptView(
        id: p.id,
        question: p.question,
        options: p.options,
        basePoints: p.basePoints,
        locksAtMinute: p.locksAtMinute,
        status: winKey != null ? 'settled' : status,
        winningKey: winKey,
        createdAt: p.createdAt,
        tally: tally,
      );

      if (winKey != null) _award(p.id, winKey, p);
    }
  }

  String? _settle(String id, int m) {
    final r = _res[id]!;
    final meta = _resMeta[id] ?? [0, 0];
    switch (r) {
      case _Resolver.firstEvent:
        if (_lastEvent == 'goal') return 'goal';
        if (_lastEvent == 'card') return 'card';
        return null;
      case _Resolver.nextCorner:
        if (_lastEvent == 'corner') return _lastSide;
        return null;
      case _Resolver.nextCard:
        if (_lastEvent == 'card') return _lastSide;
        return null;
      case _Resolver.nextGoal:
        if (_lastEvent == 'goal') return _lastSide;
        if (m >= meta[0]) return 'none';
        return null;
      case _Resolver.oddsRise:
        if (m >= meta[0]) return _win.home > meta[1] ? 'yes' : 'no';
        return null;
      case _Resolver.winSwing:
        if (m >= meta[0]) {
          final cur = (meta.length > 2 && meta[2] == 1) ? _win.away : _win.home;
          return cur > meta[1] ? 'up' : 'down';
        }
        return null;
      case _Resolver.leadByTwo:
        if (m >= meta[0] || _phase >= 4) {
          return (gH - gA).abs() >= 2 ? 'yes' : 'no';
        }
        return null;
      case _Resolver.totalGoals:
        final target = meta.length > 1 ? meta[1] : 1;
        if (gH + gA >= target) return 'yes';
        if (m >= meta[0] || _phase >= 4) return 'no';
        return null;
    }
  }

  void _award(String id, String winKey, PromptView p) {
    for (final b in _members.where((x) => x.isBot)) {
      final k = _botPicks['$id:${b.id}'];
      if (k == null) continue;
      if (k == winKey) {
        b.points += (p.basePoints * (1 + min(b.streak, 6) * 0.2)).round();
        b.streak++;
        b.best = max(b.best, b.streak);
        b.correct++;
      } else {
        b.streak = 0;
      }
    }
    final me = _members.first;
    final myK = myPicks[id];
    if (myK != null) {
      if (myK == winKey) {
        me.points += (p.basePoints * (1 + min(me.streak, 6) * 0.2)).round();
        me.streak++;
        me.best = max(me.best, me.streak);
        me.correct++;
      } else {
        me.streak = 0;
      }
    }
    final opt = p.options.where((o) => o.key == winKey);
    _system(
      'Next Swing settled — ${opt.isNotEmpty ? opt.first.label : winKey}.',
    );
  }

  String _lastEvent = '';
  String _lastSide = 'home';

  void _addPulse(
    String kind,
    String emoji,
    String head,
    String detail,
    String accent,
    int minute, {
    String? scorer,
  }) {
    _pulse.add(
      PulseCard(
        id: _id('p'),
        kind: kind,
        emoji: emoji,
        headline: head,
        detail: detail,
        accent: accent,
        minute: minute,
        scorer: scorer,
      ),
    );
    if (_pulse.length > 50) _pulse.removeAt(0);
    if (kind == 'goal') {
      _lastEvent = 'goal';
      _lastSide = accent;
    } else if (kind == 'corner-storm') {
      _lastEvent = 'corner';
      _lastSide = accent;
    } else if (kind == 'chaos') {
      _lastEvent = 'card';
    }
  }

  Map<String, int> _botReactions() {
    final m = <String, int>{};
    final e = packEmojis(reactionPack);
    if (_rng.nextDouble() < 0.7) m[e[0]] = _rng.nextInt(28) + 3;
    if (_rng.nextDouble() < 0.4) m[e[1]] = _rng.nextInt(12) + 1;
    return m;
  }

  void _botShout(String side) {
    final b = _members.firstWhere((x) => x.isBot, orElse: () => _members.first);
    _chat.add(
      ChatView(
        id: _id('c'),
        memberId: b.id,
        name: b.name,
        avatar: '',
        text: _pick(_cheers),
        kind: 'chat',
        ts: _now(),
        reactions: _botReactions(),
      ),
    );
    _trim();
  }

  void _botChatter(int m) {
    if (_rng.nextDouble() < 0.08) {
      final bots = _members.where((x) => x.isBot).toList();
      final b = bots[_rng.nextInt(bots.length)];
      _chat.add(
        ChatView(
          id: _id('c'),
          memberId: b.id,
          name: b.name,
          avatar: '',
          text: _pick(_cheers),
          kind: 'chat',
          ts: _now(),
          reactions: _botReactions(),
        ),
      );
      _trim();
    }
  }

  void _finish({String? penWinner, String outcome = 'normal'}) {
    status = 'finished';
    _phase = 4;
    final endMin = _minuteF.floor().clamp(90, 120);
    _leafPhase('full-time', endMin);
    _timer?.cancel();
    for (final p in _prompts.values.toList()) {
      if (p.status != 'settled') {
        _prompts[p.id] = PromptView(
          id: p.id,
          question: p.question,
          options: p.options,
          basePoints: p.basePoints,
          locksAtMinute: p.locksAtMinute,
          status: 'settled',
          winningKey: null,
          createdAt: p.createdAt,
          tally: p.tally,
        );
      }
    }
    final lead = gH - gA;
    final winningSide =
        penWinner ?? (lead > 0 ? 'home' : (lead < 0 ? 'away' : null));
    if (winningSide != null) {
      for (final mem in _members) {
        if (mem.side == winningSide) mem.points += 30;
      }
    }
    final tail = penWinner != null
        ? ' — ${penWinner == 'home' ? fixture.home.code : fixture.away.code} win $_penHome–$_penAway on pens'
        : (outcome == 'et' ? ' after extra time' : '');
    _addPulse(
      'full-time',
      '🏁',
      'Full-time',
      '${fixture.home.code} $gH–$gA ${fixture.away.code}$tail. Final whistle.',
      'neutral',
      endMin,
    );
    _makeRecap('full-time', endMin);
    _buildMotm();
  }

  void _buildMotm() {
    final lead = gH - gA;
    final winSide = lead >= 0 ? 'home' : 'away';
    final winCode = winSide == 'home' ? fixture.home.code : fixture.away.code;
    final names = <String>[];
    final codes = <String, String>{};
    for (final g in _goals.where((g) => g.side == winSide)) {
      if (!names.contains(g.name)) {
        names.add(g.name);
        codes[g.name] = g.teamCode;
      }
    }
    for (final g in _goals) {
      if (!names.contains(g.name)) {
        names.add(g.name);
        codes[g.name] = g.teamCode;
      }
    }
    final pad = roster(fixture, winSide);
    var pi = 0;
    while (names.length < 3 && pi < pad.length) {
      if (!names.contains(pad[pi])) {
        names.add(pad[pi]);
        codes[pad[pi]] = winCode;
      }
      pi++;
    }
    final top = names.take(3).toList();
    final base = 900 + _rng.nextInt(1600);
    final v0 = (base * (0.48 + _rng.nextDouble() * 0.16)).round();
    final v1 = (base * 0.26).round();
    var v2 = base - v0 - v1;
    if (v2 < 0) v2 = (base * 0.08).round();
    final votes = [v0, v1, v2];
    _motmTotal = votes.take(top.length).reduce((a, b) => a + b);
    _motm = [
      for (var i = 0; i < top.length; i++)
        MotmCandidate(
          key: 'c$i',
          name: top[i],
          teamCode: codes[top[i]] ?? winCode,
          votes: votes[i],
        ),
    ];
  }

  void voteMotm(String key) {
    if (_motm == null || _myMotmVote != null) return;
    _motm = _motm!
        .map(
          (c) => c.key == key
              ? MotmCandidate(
                  key: c.key,
                  name: c.name,
                  teamCode: c.teamCode,
                  votes: c.votes + 1,
                )
              : c,
        )
        .toList();
    _motmTotal++;
    _myMotmVote = key;
    notifyListeners();
  }

  void _makeRecap(String scope, int m) {
    final sorted = [..._members]..sort((a, b) => b.points - a.points);
    final leader = sorted.first;
    final runner = sorted.length > 1 ? sorted[1] : null;
    final when = scope == 'half-time' ? 'First half' : 'Full-time';
    final lead = gH == gA
        ? 'level at $gH–$gA'
        : (gH > gA
              ? '${fixture.home.name} ahead $gH–$gA'
              : '${fixture.away.name} in front $gA–$gH');
    final goals = _pulse.where((p) => p.kind == 'goal').length;
    final beats = <String>[
      '$when: ${fixture.home.code} $gH–$gA ${fixture.away.code}, $lead.',
    ];
    if (goals == 0) {
      beats.add('Tight and cagey — no goals yet.');
    } else if (goals >= 3) {
      beats.add('A wild $goals-goal ride that kept the room on its feet.');
    } else {
      beats.add('A goal that shifted the whole room.');
    }
    if (leader.points > 0) {
      beats.add('${leader.name} tops the room on ${leader.points}.');
      if (runner != null && runner.points > 0)
        beats.add(
          '${runner.name} leads the chase, ${leader.points - runner.points} back.',
        );
    } else {
      beats.add('The leaderboard is wide open — your next call could top it.');
    }
    _recaps.add(
      RecapView(
        id: _id('r'),
        scope: scope,
        text: beats.join(' '),
        topMember: leader.points > 0 ? leader.name : null,
        minute: m,
      ),
    );
  }

  void _system(String text) {
    _chat.add(
      ChatView(
        id: _id('c'),
        memberId: 'system',
        name: 'Room',
        avatar: '📣',
        text: text,
        kind: 'system',
        ts: _now(),
      ),
    );
    _trim();
  }

  void _trim() {
    if (_chat.length > 120) _chat.removeRange(0, _chat.length - 120);
  }

  // ---- view ----
  RoomView get view {
    final members = [..._members]..sort((a, b) => b.points - a.points);
    final mv = members
        .map(
          (m) => MemberView(
            id: m.id,
            name: m.name,
            avatar: '',
            side: m.side,
            walletShort: null,
            points: m.points,
            streak: m.streak,
            bestStreak: m.best,
            correct: m.correct,
            isHost: m.isHost,
          ),
        )
        .toList();
    final phaseInt =
        _phase; // 1 H1, 2 HT, 3 H2, 4 FT, 5 ET1, 6 ET break, 7 ET2, 8 pens
    final shootout = _penKicks.isNotEmpty
        ? ShootoutView(
            home: _penHome,
            away: _penAway,
            kicks: _penKicks
                .map((k) => ShootoutKick(side: k.side, scored: k.scored))
                .toList(),
            decided: _penDecided,
            winnerSide: _penWinner,
          )
        : null;
    final score = status == 'lobby'
        ? null
        : ScoreView(
            minute: _minuteF.floor(),
            clockSeconds: (_minuteF * 60).floor(),
            running:
                phaseInt == 1 ||
                phaseInt == 3 ||
                phaseInt == 5 ||
                phaseInt == 7,
            phase: phaseInt,
            goals: StatPair(gH, gA),
            yellow: StatPair(yH, yA),
            red: StatPair(rH, rA),
            corners: StatPair(cH, cA),
            periods: MatchPeriods(
              firstHalf: PeriodStat(
                goals: StatPair(gH1, gA1),
                yellow: StatPair(yH1, yA1),
                red: StatPair(rH1, rA1),
                corners: StatPair(cH1, cA1),
              ),
              secondHalf: PeriodStat(
                goals: StatPair(gH - gH1, gA - gA1),
                yellow: StatPair(yH - yH1, yA - yA1),
                red: StatPair(rH - rH1, rA - rA1),
                corners: StatPair(cH - cH1, cA - cA1),
              ),
            ),
          );
    final promptList = _prompts.values.toList()
      ..sort((a, b) => b.createdAt - a.createdAt);
    return RoomView(
      id: 'local',
      code: code,
      name: '${fixture.home.name} watch-along',
      hostId: 'me',
      status: status,
      kind: 'party',
      autoManaged: false,
      fixture: fixture,
      modes: RoomModes(draftMode, nextSwingMode),
      momentum: _momentum,
      win: _win,
      winHistory: List<int>.from(_winHistory),
      shootout: shootout,
      score: score,
      members: mv,
      chat: [..._chat],
      pulse: [..._pulse],
      prompts: promptList.take(8).toList(),
      recaps: [..._recaps],
      proof: ProofInfo(
        leafCount: _leaves.length,
        root: _liveRoot,
        anchorSignature: null,
        anchored: false,
        cluster: 'devnet',
      ),
      spoilerSafe: spoilerSafe,
      voice: voice,
      reactionPack: reactionPack,
      motm: _motm == null
          ? null
          : MotmPoll(
              totalVotes: _motmTotal,
              candidates: _motm!,
              myVote: _myMotmVote,
            ),
    );
  }

  /// The full proof payload for the proof sheet — a REAL SHA-256 Merkle root
  /// over the events this room reacted to, plus a live inclusion proof of the
  /// latest event that verifies on-device. Same shape the backend proof route
  /// returns, so the proof sheet renders identically for solo and hosted rooms.
  Map<String, dynamic> proofData() {
    final tree = buildMerkleTree(_leaves);
    Map<String, dynamic>? sample;
    if (_leaves.isNotEmpty) {
      final index = _leaves.length - 1;
      final pf = tree.proof(index);
      sample = {
        'leaf': _leaves[index],
        'index': index,
        'proof': pf.map((s) => s.toJson()).toList(),
        'verified': verifyMerkleProof(_leaves[index], pf, tree.root),
      };
    }
    return {
      'root': tree.root,
      'leafCount': _leaves.length,
      'leaves': _leaves.length > 12
          ? _leaves.sublist(_leaves.length - 12)
          : List<String>.from(_leaves),
      'sample': sample,
      'txline': null,
      'fixtureId': fixture.id,
      'anchored': false,
      'anchorSignature': null,
      'anchorAvailable': false,
      'cluster': 'devnet',
      'local': true, // solo/sim room — proof sheet uses on-device-honest copy
    };
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;
  int _idc = 0;
  String _id(String p) => '${p}_${_idc++}';
  String _pick(List<String> l) => l[_rng.nextInt(l.length)];
  static String _genCode() {
    const a = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(6, (_) => a[r.nextInt(a.length)]).join();
  }
}

class _M {
  final String id, name;
  final bool isHost, isBot;
  String? side;
  int points = 0, streak = 0, best = 0, correct = 0;
  _M(this.id, this.name, {this.isHost = false, this.isBot = false});
}

class _GoalRec {
  final String name;
  final int minute;
  final String side, teamCode;
  _GoalRec(this.name, this.minute, this.side, this.teamCode);
}

enum _Resolver {
  firstEvent,
  nextCorner,
  nextCard,
  nextGoal,
  oddsRise,
  winSwing,
  leadByTwo,
  totalGoals,
}

class _Pen {
  final String side; // 'home' | 'away'
  final bool scored;
  _Pen(this.side, this.scored);
}

SwingOption _opt(String key, String label, [String? hint]) =>
    SwingOption(key: key, label: label, hint: hint);

class _PromptDef {
  final String q;
  final List<SwingOption> options;
  final int pts, lock;
  final _Resolver resolver;
  final int targetMinute;
  final int baseline;
  final int
  side; // 0=home, 1=away (winSwing: whose win-chance the call is about)
  _PromptDef(
    this.q,
    this.options,
    this.pts,
    this.lock,
    this.resolver, [
    this.targetMinute = 90,
    this.baseline = 0,
    this.side = 0,
  ]);
}
