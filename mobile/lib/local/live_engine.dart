import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../api/models.dart';
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

  LiveMatchEngine(this.fixture,
      {required this.draftMode,
      required this.nextSwingMode,
      required this.myName,
      this.reactionPack = 'classic',
      this.voice = false,
      this.spoilerSafe = false})
      : _rng = Random(fixture.id.hashCode) {
    _members = [
      _M('me', myName.isEmpty ? 'You' : myName, isHost: true),
      _M('b1', _pick(_botNames), isBot: true)..side = 'home',
      _M('b2', _pick(_botNames), isBot: true)..side = 'away',
      _M('b3', _pick(_botNames), isBot: true)..side = _rng.nextBool() ? 'home' : 'away',
    ];
  }

  final Random _rng;
  static const _botNames = ['marcus_k', 'jordan.t', 'priya_d', 'sam', 'mia', 'leo', 'noor', 'diego'];
  static const _cheers = ['what a room to be in 🙌', 'GET IN! 🔥', 'unreal 😱', 'called it 😎', 'pressure building', 'this is it', '💯', 'tense out here'];

  final String code = _genCode();
  String status = 'lobby';
  double _minuteF = 0;
  bool _atHalfTime = false;
  int _htUntil = 0;
  bool _htRecap = false;

  int gH = 0, gA = 0, yH = 0, yA = 0, rH = 0, rA = 0, cH = 0, cA = 0;
  int _momentum = 0;
  int proofLeaves = 0;
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
    _system('Kick-off! The terrace is live.');
    _addPulse('kickoff', '🟢', "We're live", '${fixture.home.name} vs ${fixture.away.name} is under way.', 'neutral', 0);
    _timer = Timer.periodic(const Duration(milliseconds: 750), (_) => _tick());
    notifyListeners();
  }

  void pickSide(String side) {
    final me = _members.first;
    me.side = side;
    _system('$myName drafted ${side == 'home' ? fixture.home.name : fixture.away.name}');
    notifyListeners();
  }

  void predict(String promptId, String key) {
    final p = _prompts[promptId];
    if (p == null || p.status != 'open') return;
    myPicks[promptId] = key;
    notifyListeners();
  }

  void chat(String text) {
    _chat.add(ChatView(id: _id('c'), memberId: 'me', name: myName, avatar: '', text: text, kind: 'chat', ts: _now()));
    _trim();
    notifyListeners();
  }

  void react(String emoji) {
    _chat.add(ChatView(id: _id('c'), memberId: 'me', name: myName, avatar: '', text: emoji, kind: 'reaction', ts: _now()));
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
    if (_atHalfTime) {
      if (_now() >= _htUntil) {
        _atHalfTime = false;
        _phase = 3;
        _minuteF = 45.001;
      } else {
        notifyListeners();
        return;
      }
    }

    _minuteF += 1.5;
    var m = _minuteF.floor();
    if (_phase == 1 && m >= 45) {
      m = 45;
      _minuteF = 45;
    }
    if (m >= 90) {
      m = 90;
      _minuteF = 90;
    }

    _maybeEvents(m);
    _recomputeWin(m);
    if (nextSwingMode) {
      _maybePrompt(m);
      _resolvePrompts(m);
    }
    _botChatter(m);

    if (m >= 45 && _phase == 1) {
      _phase = 2;
      _atHalfTime = true;
      _htUntil = _now() + 2200;
      _addPulse('half-time', '⏸️', 'Half-time', '${fixture.home.code} $gH–$gA ${fixture.away.code}.', 'neutral', 45);
      if (!_htRecap) {
        _htRecap = true;
        _makeRecap('half-time', m);
      }
    }
    if (m >= 90) _finish();
    notifyListeners();
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
    proofLeaves++;
    final team = side == 'home' ? fixture.home : fixture.away;
    final sideCount = side == 'home' ? gH : gA;
    final name = scorerName(fixture.id, side, sideCount - 1);
    _goals.add(_GoalRec(name, m, side, team.code));
    _addPulse('goal', '⚽', 'GOAL — ${team.name}!', 'the room erupts! ${fixture.home.code} $gH–$gA ${fixture.away.code}', side, m, scorer: name);
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
    proofLeaves++;
    for (final mem in _members) {
      if (mem.side == side) mem.points += 4;
    }
    if (_rng.nextDouble() < 0.4) {
      final team = side == 'home' ? fixture.home : fixture.away;
      _addPulse('corner-storm', '🚩', 'Corner — ${team.name}', 'Pressure building down the flank.', side, m);
    }
  }

  void _card(String side, int m) {
    if (side == 'home') {
      yH++;
    } else {
      yA++;
    }
    proofLeaves++;
    _momentum = (_momentum + (side == 'home' ? -5 : 5)).clamp(-100, 100);
    if (_rng.nextDouble() < 0.5) {
      _addPulse('chaos', '⚡', 'Chaos watch', 'Tempers fraying — the ref reaches for a card.', 'hot', m);
    }
  }

  WinChance _win = WinChance(45, 28, 27);
  void _recomputeWin(int m) {
    final rh = fixture.home.rating, ra = fixture.away.rating;
    final lead = gH - gA;
    final tLeft = ((90 - m) / 90).clamp(0.0, 1.0);
    var h = 0.42 + (rh - ra) / 100 * 0.45 + lead * 0.16 * (0.5 + tLeft);
    var a = 0.42 - (rh - ra) / 100 * 0.45 - lead * 0.16 * (0.5 + tLeft);
    h = h.clamp(0.03, 0.94);
    a = a.clamp(0.03, 0.94);
    var d = (1 - h - a).clamp(0.03, 0.6);
    final sum = h + a + d;
    _win = WinChance((h / sum * 100).round(), (d / sum * 100).round(), (a / sum * 100).round());
  }

  void _maybePrompt(int m) {
    if (m >= 86 || _atHalfTime || _phase == 2) return;
    final open = _prompts.values.where((p) => p.status != 'settled').length;
    if (open >= 2 || m - _lastPromptMinute < 5) return;
    _lastPromptMinute = m;
    final lock = min(m + 5, 90);
    final menu = <_PromptDef>[
      _PromptDef('What happens first?', [_opt('goal', 'A goal ⚽'), _opt('card', 'A card 🟨')], 120, lock, _Resolver.firstEvent),
      _PromptDef('Who wins the next corner?', [_opt('home', fixture.home.code), _opt('away', fixture.away.code)], 100, lock, _Resolver.nextCorner),
      _PromptDef('Next goal before ${min(m + 15, 90)}\'?', [_opt('home', fixture.home.code, '${_win.home}%'), _opt('none', 'No goal'), _opt('away', fixture.away.code, '${_win.away}%')], 140, lock, _Resolver.nextGoal, min(m + 15, 90)),
    ];
    // ⭐ the signature HIGHER OR LOWER call on the favourite's live win-chance —
    // the one stat that swings both ways. Featured most often; events are variety.
    final homeLeads = _win.home >= _win.away;
    final leaderCode = homeLeads ? fixture.home.code : fixture.away.code;
    final leaderPct = homeLeads ? _win.home : _win.away;
    final winSwing = _PromptDef(
      '$leaderCode $leaderPct% to win — higher or lower in 5\'?',
      [_opt('up', 'Higher', '📈'), _opt('down', 'Lower', '📉')],
      100 + (50 - leaderPct).abs(), min(m + 2, 90), _Resolver.winSwing, min(m + 5, 90), leaderPct, homeLeads ? 0 : 1);
    final def = _rng.nextDouble() < 0.55 ? winSwing : menu[_rng.nextInt(menu.length)];
    final id = _id('sw');
    _prompts[id] = PromptView(id: id, question: def.q, options: def.options, basePoints: def.pts, locksAtMinute: def.lock, status: 'open', winningKey: null, createdAt: _now(), tally: {for (final o in def.options) o.key: 0});
    _res[id] = def.resolver;
    _resMeta[id] = [def.targetMinute, def.baseline, def.side];
    // bots vote shortly
    for (final b in _members.where((x) => x.isBot)) {
      if (_rng.nextDouble() < 0.8) _botPicks['$id:${b.id}'] = def.options[_rng.nextInt(def.options.length)].key;
    }
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

      _prompts[p.id] = PromptView(id: p.id, question: p.question, options: p.options, basePoints: p.basePoints, locksAtMinute: p.locksAtMinute, status: winKey != null ? 'settled' : status, winningKey: winKey, createdAt: p.createdAt, tally: tally);

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
    _system('Next Swing settled — ${opt.isNotEmpty ? opt.first.label : winKey}.');
  }

  String _lastEvent = '';
  String _lastSide = 'home';

  void _addPulse(String kind, String emoji, String head, String detail, String accent, int minute, {String? scorer}) {
    _pulse.add(PulseCard(id: _id('p'), kind: kind, emoji: emoji, headline: head, detail: detail, accent: accent, minute: minute, scorer: scorer));
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
    _chat.add(ChatView(id: _id('c'), memberId: b.id, name: b.name, avatar: '', text: _pick(_cheers), kind: 'chat', ts: _now(), reactions: _botReactions()));
    _trim();
  }

  void _botChatter(int m) {
    if (_rng.nextDouble() < 0.08) {
      final bots = _members.where((x) => x.isBot).toList();
      final b = bots[_rng.nextInt(bots.length)];
      _chat.add(ChatView(id: _id('c'), memberId: b.id, name: b.name, avatar: '', text: _pick(_cheers), kind: 'chat', ts: _now(), reactions: _botReactions()));
      _trim();
    }
  }

  void _finish() {
    status = 'finished';
    _phase = 4;
    _timer?.cancel();
    for (final p in _prompts.values.toList()) {
      if (p.status != 'settled') {
        _prompts[p.id] = PromptView(id: p.id, question: p.question, options: p.options, basePoints: p.basePoints, locksAtMinute: p.locksAtMinute, status: 'settled', winningKey: null, createdAt: p.createdAt, tally: p.tally);
      }
    }
    final lead = gH - gA;
    final winningSide = lead > 0 ? 'home' : (lead < 0 ? 'away' : null);
    if (winningSide != null) {
      for (final mem in _members) {
        if (mem.side == winningSide) mem.points += 30;
      }
    }
    _addPulse('full-time', '🏁', 'Full-time', '${fixture.home.code} $gH–$gA ${fixture.away.code}. Final whistle.', 'neutral', 90);
    _makeRecap('full-time', 90);
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
    final pad = roster(fixture.id, winSide);
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
      for (var i = 0; i < top.length; i++) MotmCandidate(key: 'c$i', name: top[i], teamCode: codes[top[i]] ?? winCode, votes: votes[i]),
    ];
  }

  void voteMotm(String key) {
    if (_motm == null || _myMotmVote != null) return;
    _motm = _motm!.map((c) => c.key == key ? MotmCandidate(key: c.key, name: c.name, teamCode: c.teamCode, votes: c.votes + 1) : c).toList();
    _motmTotal++;
    _myMotmVote = key;
    notifyListeners();
  }

  void _makeRecap(String scope, int m) {
    final sorted = [..._members]..sort((a, b) => b.points - a.points);
    final leader = sorted.first;
    final runner = sorted.length > 1 ? sorted[1] : null;
    final when = scope == 'half-time' ? 'First half' : 'Full-time';
    final lead = gH == gA ? 'level at $gH–$gA' : (gH > gA ? '${fixture.home.name} ahead $gH–$gA' : '${fixture.away.name} in front $gA–$gH');
    final goals = _pulse.where((p) => p.kind == 'goal').length;
    final beats = <String>['$when: ${fixture.home.code} $gH–$gA ${fixture.away.code}, $lead.'];
    if (goals == 0) {
      beats.add('Tight and cagey — no goals yet.');
    } else if (goals >= 3) {
      beats.add('A wild $goals-goal ride that kept the room on its feet.');
    } else {
      beats.add('A goal that shifted the whole room.');
    }
    if (leader.points > 0) {
      beats.add('${leader.name} tops the room on ${leader.points}.');
      if (runner != null && runner.points > 0) beats.add('${runner.name} leads the chase, ${leader.points - runner.points} back.');
    } else {
      beats.add('The leaderboard is wide open — your next call could top it.');
    }
    _recaps.add(RecapView(id: _id('r'), scope: scope, text: beats.join(' '), topMember: leader.points > 0 ? leader.name : null, minute: m));
  }

  void _system(String text) {
    _chat.add(ChatView(id: _id('c'), memberId: 'system', name: 'Room', avatar: '📣', text: text, kind: 'system', ts: _now()));
    _trim();
  }

  void _trim() {
    if (_chat.length > 120) _chat.removeRange(0, _chat.length - 120);
  }

  // ---- view ----
  RoomView get view {
    final members = [..._members]..sort((a, b) => b.points - a.points);
    final mv = members
        .map((m) => MemberView(id: m.id, name: m.name, avatar: '', side: m.side, walletShort: null, points: m.points, streak: m.streak, bestStreak: m.best, correct: m.correct, isHost: m.isHost))
        .toList();
    final phaseInt = _phase == 1 ? 1 : (_phase == 2 ? 2 : (_phase == 3 ? 3 : (_phase == 4 ? 4 : 0)));
    final score = status == 'lobby'
        ? null
        : ScoreView(minute: _minuteF.floor(), clockSeconds: (_minuteF * 60).floor(), running: phaseInt == 1 || phaseInt == 3, phase: phaseInt, goals: StatPair(gH, gA), yellow: StatPair(yH, yA), red: StatPair(rH, rA), corners: StatPair(cH, cA));
    final promptList = _prompts.values.toList()..sort((a, b) => b.createdAt - a.createdAt);
    return RoomView(
      id: 'local',
      code: code,
      name: '${fixture.home.name} watch-along',
      hostId: 'me',
      status: status,
      fixture: fixture,
      modes: RoomModes(draftMode, nextSwingMode),
      momentum: _momentum,
      win: _win,
      score: score,
      members: mv,
      chat: [..._chat],
      pulse: [..._pulse],
      prompts: promptList.take(8).toList(),
      recaps: [..._recaps],
      proof: ProofInfo(leafCount: proofLeaves, root: proofLeaves > 0 ? _fakeRoot() : null, anchorSignature: null, anchored: false, cluster: 'devnet'),
      spoilerSafe: spoilerSafe,
      voice: voice,
      reactionPack: reactionPack,
      motm: _motm == null ? null : MotmPoll(totalVotes: _motmTotal, candidates: _motm!, myVote: _myMotmVote),
    );
  }

  String _fakeRoot() {
    final h = (proofLeaves * 2654435761 + fixture.id.hashCode).toUnsigned(32);
    return h.toRadixString(16).padLeft(8, '0') * 8;
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

enum _Resolver { firstEvent, nextCorner, nextGoal, oddsRise, winSwing }

SwingOption _opt(String key, String label, [String? hint]) => SwingOption(key: key, label: label, hint: hint);

class _PromptDef {
  final String q;
  final List<SwingOption> options;
  final int pts, lock;
  final _Resolver resolver;
  final int targetMinute;
  final int baseline;
  final int side; // 0=home, 1=away (winSwing: whose win-chance the call is about)
  _PromptDef(this.q, this.options, this.pts, this.lock, this.resolver, [this.targetMinute = 90, this.baseline = 0, this.side = 0]);
}
