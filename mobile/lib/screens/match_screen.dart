import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../data/flags.dart';
import '../data/player_images.dart';
import '../local/fixtures.dart';
import '../local/match_facts.dart';
import '../local/squads.dart';
import '../local/tournament.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/player_avatar.dart';
import '../widgets/player_sheet.dart';
import '../widgets/ticket.dart';
import 'team_sheet.dart';

/// The Match Center — a FotMob/Sofascore-style page for a single fixture:
/// Overview (timeline, key facts, preview), Stats (full team comparison),
/// Line-ups (formation pitch with player ratings), Table (group standings)
/// and H2H (past meetings). Works for scheduled, live and finished matches.
class MatchScreen extends StatefulWidget {
  final Fixture fixture;
  final VoidCallback? onWatch; // "Watch in a room" CTA (provided by Home)
  const MatchScreen({super.key, required this.fixture, this.onWatch});
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  late Fixture _fx = widget.fixture;
  int _tab = 0;
  Timer? _tick;

  bool get _isLocal => localFixtureById(widget.fixture.id) != null;

  @override
  void initState() {
    super.initState();
    _refresh();
    // faces ready before the user reaches the Line-ups tab
    PlayerImages.warm(widget.fixture.home.name);
    PlayerImages.warm(widget.fixture.away.name);
    // keep live minute/score honest while the page is open
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  void _refresh() {
    if (!_isLocal) return;
    setState(() => _fx = applyClock(widget.fixture, DateTime.now()));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get _played => _fx.status != 'scheduled' && _fx.home.code != 'TBD' && _fx.away.code != 'TBD';
  bool get _isKnockout => groupOf(_fx) == null;
  int get _liveMinute => _fx.status == 'live' ? (_fx.score?.minute ?? 0) : 999;

  MatchFacts? get _facts => _played ? factsFor(_fx) : null;

  List<MatchEvent> get _events =>
      _facts == null ? const [] : _facts!.events.where((e) => e.minute <= _liveMinute).toList();

  @override
  Widget build(BuildContext context) {
    final s = _fx.score;
    final scorers = _events
        .where((e) => e.kind == 'goal')
        .map((e) => "${e.player} ${e.minute}'")
        .toList();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: Column(children: [
          Container(
            color: AppColors.ink,
            child: TicketScoreboard(
              home: _fx.home,
              away: _fx.away,
              league: _fx.stage,
              score: s != null ? '${s.home} - ${s.away}' : null,
              minute: _fx.status == 'finished'
                  ? 'FT'
                  : _fx.status == 'live'
                      ? "${s?.minute ?? 0}'"
                      : kickoffWhen(_fx.kickoff).toUpperCase(),
              clockSeconds: s?.clockSeconds,
              clockRunning: s?.running ?? false,
              pill: _fx.status == 'live' ? 'LIVE' : (_fx.status == 'finished' ? 'FULL TIME' : 'UPCOMING'),
              pillColor: _fx.status == 'live' ? AppColors.orange : AppColors.inkSoft,
              onBack: () => Navigator.of(context).maybePop(),
              onTeamTap: (t) => t.code == 'TBD' ? null : showTeamSheet(context, t),
              scorers: scorers.take(6).toList(),
              topRadius: 0,
              topInset: MediaQuery.of(context).padding.top,
            ),
          ),
          _tabBar(),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _tabBar() {
    const tabs = ['Overview', 'Stats', 'Line-ups', 'Table', 'H2H'];
    return Container(
      color: AppColors.paper,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Pressable(
                haptic: HapticFeedbackType.selection,
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _tab == i ? AppColors.ink : AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: _tab == i ? AppColors.ink : AppColors.line),
                  ),
                  child: Text(tabs[i].toUpperCase(),
                      style: label(color: _tab == i ? AppColors.cream : AppColors.mut, size: 10.5, weight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case 1:
        return _statsTab();
      case 2:
        return _lineupsTab();
      case 3:
        return _tableTab();
      case 4:
        return _h2hTab();
      default:
        return _overviewTab();
    }
  }

  // ---------------- OVERVIEW ----------------
  Widget _overviewTab() {
    final children = <Widget>[];

    if (widget.onWatch != null && _fx.home.code != 'TBD') {
      children.addAll([
        PrimaryButton(
          _fx.status == 'live'
              ? 'Watch live in a room'
              : _fx.status == 'finished'
                  ? 'Watch verified replay'
                  : 'Open the watch-along room',
          icon: Icons.play_arrow_rounded,
          expand: true,
          onTap: widget.onWatch,
        ),
        const SizedBox(height: 14),
      ]);
    }

    if (_played) {
      final facts = _facts!;
      // penalties note for drawn knockout ties
      if (_fx.status == 'finished' && _isKnockout && facts.homeGoals == facts.awayGoals) {
        final adv = knockoutHomeAdvances(_fx) ? _fx.home : _fx.away;
        children.addAll([
          Container(
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Text('🥅', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Text('${adv.name.toUpperCase()} ADVANCE ON PENALTIES', style: display(16, color: AppColors.cream))),
            ]),
          ),
          const SizedBox(height: 12),
        ]);
      }
      if (_events.isNotEmpty) {
        children.addAll([const SectionLabel('Match events'), _timeline(), const SizedBox(height: 14)]);
      }
      if (_fx.status == 'finished') {
        children.addAll([const SectionLabel('Player of the match'), _motmCard(facts), const SizedBox(height: 14)]);
      }
      children.addAll([const SectionLabel('Top stats'), _quickStats(facts), const SizedBox(height: 14)]);
    } else {
      // preview mode
      children.addAll([
        const SectionLabel('Win probability'),
        _winProbability(),
        const SizedBox(height: 14),
      ]);
      if (_fx.home.code != 'TBD') {
        children.addAll([
          const SectionLabel('Form guide'),
          _formGuide(),
          const SizedBox(height: 14),
        ]);
      }
    }

    children.addAll([const SectionLabel('Match info'), _infoCard()]);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 28), children: children);
  }

  Widget _timeline() {
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(children: _events.map(_eventRow).toList()),
    );
  }

  Widget _eventRow(MatchEvent e) {
    final isHome = e.side == 'home';
    final (emoji, text) = switch (e.kind) {
      'goal' => ('⚽', '${e.player}${e.assist != null ? "  (assist ${e.assist})" : ""}'),
      'yellow' => ('🟨', e.player),
      'red' => ('🟥', e.player),
      'sub' => ('🔁', '${e.assist} on · ${e.player} off'),
      _ => ('•', e.player),
    };
    final content = Row(
      mainAxisAlignment: isHome ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: [
        if (isHome) ...[
          SizedBox(width: 34, child: Text("${e.minute}'", style: display(13, color: AppColors.orange))),
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 7),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(size: 12.5, weight: e.kind == 'goal' ? FontWeight.w800 : FontWeight.w600))),
        ] else ...[
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: body(size: 12.5, weight: e.kind == 'goal' ? FontWeight.w800 : FontWeight.w600))),
          const SizedBox(width: 7),
          Text(emoji, style: const TextStyle(fontSize: 14)),
          SizedBox(width: 34, child: Text("${e.minute}'", textAlign: TextAlign.right, style: display(13, color: AppColors.orange))),
        ],
      ],
    );
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: content);
  }

  Widget _motmCard(MatchFacts facts) {
    final team = facts.motmSide == 'home' ? _fx.home : _fx.away;
    final all = facts.motmSide == 'home' ? facts.homeRatings : facts.awayRatings;
    final pr = all.firstWhere((r) => r.motm, orElse: () => all.first);
    return Pressable(
      onTap: () => showPlayerSheet(context, team, pr.player),
      child: Container(
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          InitialAvatar(name: pr.player.name, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pr.player.name.toUpperCase(), style: display(18, color: AppColors.cream)),
              const SizedBox(height: 2),
              Row(children: [
                InlineFlag(team: team, size: 16),
                const SizedBox(width: 5),
                Text('${team.name} · ${positionLabel(pr.player.pos)}', style: body(color: AppColors.mutInk, size: 11)),
              ]),
            ]),
          ),
          ratingBadge(pr.rating, big: true),
        ]),
      ),
    );
  }

  Widget _quickStats(MatchFacts facts) {
    final scale = _fx.status == 'live' ? (_liveMinute / 90).clamp(0.05, 1.0) : 1.0;
    int sc(int v) => (v * scale).round();
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        _statRow('Possession', facts.home.possession, facts.away.possession, suffix: '%'),
        _statRow('Expected goals (xG)', facts.home.xg * scale, facts.away.xg * scale, decimals: 2),
        _statRow('Shots', sc(facts.home.shots), sc(facts.away.shots)),
        _statRow('Shots on target', sc(facts.home.onTarget), sc(facts.away.onTarget)),
        _statRow('Corners', sc(facts.home.corners), sc(facts.away.corners)),
      ]),
    );
  }

  Widget _winProbability() {
    final diff = (_fx.home.rating - _fx.away.rating).toDouble();
    var h = (38 + diff * 1.6).clamp(8.0, 84.0);
    var a = (38 - diff * 1.6).clamp(8.0, 84.0);
    final d = max(8.0, 100 - h - a);
    final total = h + a + d;
    h = h / total * 100;
    a = a / total * 100;
    final dd = 100 - h - a;
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 26,
            child: Row(children: [
              Expanded(flex: h.round(), child: Container(color: teamColor(_fx.home.code), alignment: Alignment.center, child: Text('${h.round()}%', style: const TextStyle(fontFamily: kBody, fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)))),
              Expanded(flex: dd.round(), child: Container(color: const Color(0xFF6E665A), alignment: Alignment.center, child: Text('${dd.round()}%', style: const TextStyle(fontFamily: kBody, fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)))),
              Expanded(flex: a.round(), child: Container(color: teamColor(_fx.away.code), alignment: Alignment.center, child: Text('${a.round()}%', style: const TextStyle(fontFamily: kBody, fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text(_fx.home.code, style: label(color: teamColor(_fx.home.code), size: 10, weight: FontWeight.w800)),
          const Spacer(),
          Text('DRAW', style: label(color: AppColors.mut, size: 10)),
          const Spacer(),
          Text(_fx.away.code, style: label(color: teamColor(_fx.away.code), size: 10, weight: FontWeight.w800)),
        ]),
      ]),
    );
  }

  Widget _formGuide() {
    Widget teamForm(Team t) {
      final results = <(String, Fixture)>[];
      for (final f in localFixtures()) {
        if (f.status != 'finished' || f.score == null) continue;
        final isHome = f.home.code == t.code, isAway = f.away.code == t.code;
        if (!isHome && !isAway) continue;
        final mine = isHome ? f.score!.home : f.score!.away;
        final theirs = isHome ? f.score!.away : f.score!.home;
        results.add((mine > theirs ? 'W' : mine < theirs ? 'L' : 'D', f));
      }
      final recent = results.reversed.take(5).toList().reversed.toList();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          InlineFlag(team: t, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(weight: FontWeight.w700, size: 13))),
          ...recent.map(((String, Fixture) r) {
            final c = switch (r.$1) { 'W' => const Color(0xFF1F7A3D), 'L' => const Color(0xFFD8392B), _ => const Color(0xFF6E665A) };
            return Container(
              width: 22, height: 22,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
              alignment: Alignment.center,
              child: Text(r.$1, style: const TextStyle(fontFamily: kBody, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
            );
          }),
          if (recent.isEmpty) Text('no games yet', style: body(color: AppColors.mut, size: 11)),
        ]),
      );
    }

    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(children: [teamForm(_fx.home), Container(height: 1, color: AppColors.line), teamForm(_fx.away)]),
    );
  }

  Widget _infoCard() {
    Widget row(IconData icon, String title, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 16, color: AppColors.mut),
            const SizedBox(width: 10),
            Text(title.toUpperCase(), style: label(color: AppColors.mut, size: 9)),
            const Spacer(),
            Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: body(size: 12.5, weight: FontWeight.w700))),
          ]),
        );
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(children: [
        row(Icons.emoji_events_outlined, 'Competition', _fx.competition),
        row(Icons.flag_outlined, 'Stage', _fx.stage),
        row(Icons.stadium_outlined, 'Venue', _fx.venue),
        row(Icons.schedule, 'Kick-off', kickoffWhen(_fx.kickoff)),
      ]),
    );
  }

  // ---------------- STATS ----------------
  Widget _statsTab() {
    if (!_played) {
      return _placeholder('Match stats appear once the game kicks off.');
    }
    final facts = _facts!;
    final scale = _fx.status == 'live' ? (_liveMinute / 90).clamp(0.05, 1.0) : 1.0;
    int sc(int v) => (v * scale).round();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 28), children: [
      if (_fx.status == 'live')
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text("Live — stats through $_liveMinute'", style: body(color: AppColors.mut, size: 12)),
        ),
      Container(
        decoration: cardBox(),
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            InlineFlag(team: _fx.home, size: 22),
            const Spacer(),
            Text('TEAM STATS', style: label(color: AppColors.ink, size: 11)),
            const Spacer(),
            InlineFlag(team: _fx.away, size: 22),
          ]),
          const SizedBox(height: 8),
          _statRow('Possession', facts.home.possession, facts.away.possession, suffix: '%'),
          _statRow('Expected goals (xG)', facts.home.xg * scale, facts.away.xg * scale, decimals: 2),
          _statRow('Total shots', sc(facts.home.shots), sc(facts.away.shots)),
          _statRow('Shots on target', sc(facts.home.onTarget), sc(facts.away.onTarget)),
          _statRow('Big chances', sc(facts.home.bigChances), sc(facts.away.bigChances)),
          _statRow('Passes', sc(facts.home.passes), sc(facts.away.passes)),
          _statRow('Pass accuracy', facts.home.passAccuracy, facts.away.passAccuracy, suffix: '%'),
          _statRow('Corners', sc(facts.home.corners), sc(facts.away.corners)),
          _statRow('Fouls', sc(facts.home.fouls), sc(facts.away.fouls)),
          _statRow('Offsides', sc(facts.home.offsides), sc(facts.away.offsides)),
          _statRow('Tackles', sc(facts.home.tackles), sc(facts.away.tackles)),
          _statRow('Saves', sc(facts.home.saves), sc(facts.away.saves)),
          _statRow('Yellow cards', facts.home.yellow, facts.away.yellow),
          _statRow('Red cards', facts.home.red, facts.away.red),
        ]),
      ),
    ]);
  }

  Widget _statRow(String name, num h, num a, {String suffix = '', int decimals = 0}) {
    String fmt(num v) => decimals > 0 ? v.toStringAsFixed(decimals) : '${v.round()}$suffix';
    final total = (h + a) == 0 ? 1 : (h + a).toDouble();
    final homeLeads = h >= a;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        Row(children: [
          SizedBox(width: 52, child: Text(fmt(h), style: body(size: 13, weight: homeLeads ? FontWeight.w800 : FontWeight.w500))),
          Expanded(child: Text(name.toUpperCase(), textAlign: TextAlign.center, style: label(color: AppColors.mut, size: 9))),
          SizedBox(width: 52, child: Text(fmt(a), textAlign: TextAlign.right, style: body(size: 13, weight: !homeLeads ? FontWeight.w800 : FontWeight.w500))),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 5,
            child: Row(children: [
              Expanded(
                flex: max(1, (h / total * 100).round()),
                child: Container(color: teamColor(_fx.home.code)),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: max(1, (a / total * 100).round()),
                child: Container(color: teamColor(_fx.away.code)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ---------------- LINE-UPS ----------------
  Widget _lineupsTab() {
    if (_fx.home.code == 'TBD' || _fx.away.code == 'TBD') {
      return _placeholder('Line-ups appear once both teams are decided.');
    }
    final homeSq = squadFor(_fx.home);
    final awaySq = squadFor(_fx.away);
    final facts = _facts;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 28), children: [
      if (!_played)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Probable line-ups', style: body(color: AppColors.mut, size: 12)),
        ),
      Row(children: [
        Expanded(child: _formationHeader(_fx.home, homeSq)),
        const SizedBox(width: 10),
        Expanded(child: _formationHeader(_fx.away, awaySq)),
      ]),
      const SizedBox(height: 10),
      _pitch(homeSq, awaySq, facts),
      const SizedBox(height: 14),
      const SectionLabel('Bench'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _benchList(_fx.home, homeSq)),
        const SizedBox(width: 10),
        Expanded(child: _benchList(_fx.away, awaySq)),
      ]),
    ]);
  }

  Widget _formationHeader(Team t, TeamSquad sq) {
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        InlineFlag(team: t, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sq.formation, style: display(16)),
            Text(sq.coach, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mut, size: 10)),
          ]),
        ),
      ]),
    );
  }

  /// Full-pitch view: home XI in the top half (GK highest), away XI mirrored
  /// in the bottom half — like FotMob's line-up screen.
  Widget _pitch(TeamSquad home, TeamSquad away, MatchFacts? facts) {
    List<List<SquadPlayer>> lines(TeamSquad sq) {
      final xi = sq.startingXI;
      final nums = sq.formation.split('-').map(int.parse).toList();
      final out = <List<SquadPlayer>>[
        [xi[0]] // GK
      ];
      var idx = 1;
      for (final n in nums) {
        out.add(xi.sublist(idx, min(idx + n, xi.length)));
        idx += n;
      }
      return out;
    }

    double? ratingOf(String name, bool isHome) {
      if (facts == null || _fx.status == 'live') return null;
      final rs = isHome ? facts.homeRatings : facts.awayRatings;
      for (final r in rs) {
        if (r.player.name == name) return r.rating;
      }
      return null;
    }

    Widget playerChip(Team team, SquadPlayer p, bool isHome) {
      final rating = ratingOf(p.name, isHome);
      return Pressable(
        haptic: HapticFeedbackType.selection,
        onTap: () => showPlayerSheet(context, team, p),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            // official face on the pitch (initials fallback), shirt number badged
            PlayerAvatar(team: team, name: p.name, size: 38, ringColor: Colors.white),
            Positioned(
              left: -5,
              bottom: -3,
              child: Container(
                width: 15,
                height: 15,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: teamColor(team.code), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1)),
                child: Text('${p.number}', style: const TextStyle(fontFamily: kBody, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 8)),
              ),
            ),
            if (rating != null)
              Positioned(right: -12, top: -6, child: ratingBadge(rating)),
          ]),
          const SizedBox(height: 3),
          SizedBox(
            width: 62,
            child: Text(p.name.split(' ').last, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: kBody, color: Colors.white, fontWeight: FontWeight.w700, fontSize: 9.5)),
          ),
        ]),
      );
    }

    Widget half(Team team, TeamSquad sq, bool isHome) {
      var ls = lines(sq);
      if (!isHome) ls = ls.reversed.toList();
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: ls
            .map((line) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: line.map((p) => playerChip(team, p, isHome)).toList(),
                ))
            .toList(),
      );
    }

    return Container(
      height: 640,
      decoration: BoxDecoration(
        color: const Color(0xFF14421F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
          Column(children: [
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: half(_fx.home, home, true))),
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: half(_fx.away, away, false))),
          ]),
        ]),
      ),
    );
  }

  Widget _benchList(Team t, TeamSquad sq) {
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sq.bench
            .map((p) => Pressable(
                  onTap: () => showPlayerSheet(context, t, p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 22, child: Text('${p.number}', style: label(color: AppColors.mut, size: 10))),
                      Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(size: 12, weight: FontWeight.w600))),
                      Text(p.pos, style: label(color: AppColors.mut, size: 8.5)),
                    ]),
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ---------------- TABLE ----------------
  Widget _tableTab() {
    final standings = groupStandings(localFixtures());
    final letters = <String>{};
    final g = groupOf(_fx);
    if (g != null) {
      letters.add(g);
    } else {
      // knockout — show both teams' group paths
      for (final entry in worldCupGroups().entries) {
        for (final t in entry.value) {
          if (t.code == _fx.home.code || t.code == _fx.away.code) letters.add(entry.key);
        }
      }
    }
    if (letters.isEmpty) return _placeholder('Group tables appear once the teams are decided.');
    final sorted = letters.toList()..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        for (final l in sorted) ...[
          SectionLabel('Group $l'),
          groupTableCard(standings[l] ?? [], highlight: {_fx.home.code, _fx.away.code}),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  // ---------------- H2H ----------------
  Widget _h2hTab() {
    if (_fx.home.code == 'TBD' || _fx.away.code == 'TBD') {
      return _placeholder('Head-to-head appears once both teams are decided.');
    }
    final meetings = h2hFor(_fx.home, _fx.away);
    var aWins = 0, bWins = 0, draws = 0;
    for (final m in meetings) {
      if (m.goalsA > m.goalsB) {
        aWins++;
      } else if (m.goalsA < m.goalsB) {
        bWins++;
      } else {
        draws++;
      }
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 28), children: [
      Container(
        decoration: cardBox(),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(child: Column(children: [InlineFlag(team: _fx.home, size: 26), const SizedBox(height: 6), Text('$aWins', style: display(24)), Text('WINS', style: label(color: AppColors.mut, size: 8.5))])),
          Expanded(child: Column(children: [const SizedBox(height: 32), Text('$draws', style: display(24, color: AppColors.mut)), Text('DRAWS', style: label(color: AppColors.mut, size: 8.5))])),
          Expanded(child: Column(children: [InlineFlag(team: _fx.away, size: 26), const SizedBox(height: 6), Text('$bWins', style: display(24)), Text('WINS', style: label(color: AppColors.mut, size: 8.5))])),
        ]),
      ),
      const SizedBox(height: 14),
      const SectionLabel('Previous meetings'),
      ...meetings.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: cardBox(),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                SizedBox(width: 42, child: Text('${m.year}', style: display(14, color: AppColors.orange))),
                Expanded(child: Text(m.competition, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mut, size: 11.5))),
                Text('${_fx.home.code} ${m.goalsA}–${m.goalsB} ${_fx.away.code}', style: body(weight: FontWeight.w800, size: 13)),
              ]),
            ),
          )),
      const SizedBox(height: 4),
      Center(child: Text('Historic record — demo data', style: body(color: AppColors.mut, size: 10))),
    ]);
  }

  Widget _placeholder(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(text, textAlign: TextAlign.center, style: body(color: AppColors.mut, size: 13)),
        ),
      );
}

/// A group standings table card — shared with the competition hub.
Widget groupTableCard(List<StandingRow> rows, {Set<String> highlight = const {}}) {
  Widget cell(String s, {int flex = 1, bool bold = false, Color? color}) => Expanded(
        flex: flex,
        child: Text(s, textAlign: TextAlign.center, style: body(size: 12, weight: bold ? FontWeight.w800 : FontWeight.w500, color: color ?? AppColors.ink)),
      );
  return Container(
    decoration: cardBox(),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: Column(children: [
      Row(children: [
        const SizedBox(width: 20),
        Expanded(flex: 5, child: Text('TEAM', style: label(color: AppColors.mut, size: 8.5))),
        for (final h in ['P', 'W', 'D', 'L', 'GD', 'PTS'])
          Expanded(child: Text(h, textAlign: TextAlign.center, style: label(color: AppColors.mut, size: 8.5))),
      ]),
      const SizedBox(height: 6),
      for (var i = 0; i < rows.length; i++) ...[
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: highlight.contains(rows[i].team.code) ? const Color(0x14E9531E) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            SizedBox(
              width: 20,
              child: Text('${i + 1}',
                  textAlign: TextAlign.center,
                  style: body(size: 11, weight: FontWeight.w800, color: i < 2 ? const Color(0xFF1F7A3D) : (i == 2 ? AppColors.gold : AppColors.mut))),
            ),
            Expanded(
              flex: 5,
              child: Row(children: [
                InlineFlag(team: rows[i].team, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(rows[i].team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(size: 12, weight: FontWeight.w700))),
              ]),
            ),
            cell('${rows[i].played}'),
            cell('${rows[i].won}'),
            cell('${rows[i].drawn}'),
            cell('${rows[i].lost}'),
            cell(rows[i].gd > 0 ? '+${rows[i].gd}' : '${rows[i].gd}'),
            cell('${rows[i].pts}', bold: true, color: AppColors.orange),
          ]),
        ),
      ],
      const SizedBox(height: 2),
      Row(children: [
        _legendDot(const Color(0xFF1F7A3D), 'Advance'),
        const SizedBox(width: 12),
        _legendDot(AppColors.gold, 'Best 3rd — possible'),
      ]),
      const SizedBox(height: 4),
    ]),
  );
}

Widget _legendDot(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(text, style: body(color: AppColors.mut, size: 9.5)),
    ]);

/// White pitch markings on green.
class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final w = size.width, h = size.height;
    // halfway line + centre circle
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), p);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.13, p);
    // penalty boxes
    canvas.drawRect(Rect.fromLTWH(w * 0.25, 0, w * 0.5, h * 0.09), p);
    canvas.drawRect(Rect.fromLTWH(w * 0.25, h * 0.91, w * 0.5, h * 0.09), p);
    // six-yard boxes
    canvas.drawRect(Rect.fromLTWH(w * 0.38, 0, w * 0.24, h * 0.038), p);
    canvas.drawRect(Rect.fromLTWH(w * 0.38, h * 0.962, w * 0.24, h * 0.038), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
