import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/live_data.dart';
import '../api/models.dart';
import '../data/flags.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/player_sheet.dart';
import '../widgets/ticket.dart';
import 'team_sheet.dart';

/// Production Match Center. Every displayed match fact comes from TxLINE's
/// normalized match-intelligence endpoint; unsupported analytics are omitted.
class MatchScreen extends StatefulWidget {
  final Fixture fixture;
  final VoidCallback? onWatch;
  const MatchScreen({super.key, required this.fixture, this.onWatch});
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  MatchData? _data;
  Object? _error;
  bool _loading = true;
  int _tab = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.fixture.status == 'live') {
      _poll = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _load(silent: true),
      );
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.matchData(widget.fixture.id);
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Fixture get _fixture => _data?.fixture ?? widget.fixture;
  ScoreView? get _score =>
      _data?.score ??
      (_fixture.score == null
          ? null
          : ScoreView(
              minute: _fixture.score!.minute,
              clockSeconds: _fixture.score!.clockSeconds,
              running: _fixture.score!.running,
              phase: _fixture.status == 'finished'
                  ? 4
                  : (_fixture.status == 'live' ? 1 : 0),
              goals: StatPair(_fixture.score!.home, _fixture.score!.away),
              yellow: StatPair(0, 0),
              red: StatPair(0, 0),
              corners: StatPair(0, 0),
            ));

  @override
  Widget build(BuildContext context) {
    final fx = _fixture;
    final score = _score;
    final scorers = (_data?.events ?? const <VerifiedMatchEvent>[])
        .where((e) => e.kind == 'goal')
        .map((e) => '${e.playerName ?? e.teamCode} ${e.minute}\'')
        .toList();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: StadiumColors.canvas,
        body: Column(
          children: [
            Container(
              color: AppColors.ink,
              child: TicketScoreboard(
                home: fx.home,
                away: fx.away,
                league: fx.stage,
                score: score == null || fx.status == 'scheduled'
                    ? null
                    : '${score.goals.home} - ${score.goals.away}',
                minute: _minuteText(fx, score),
                clockSeconds: score?.clockSeconds,
                clockRunning: score?.running ?? false,
                pill: fx.status == 'live'
                    ? 'LIVE · TXLINE'
                    : (fx.status == 'finished' ? 'FULL TIME' : 'UPCOMING'),
                pillColor: fx.status == 'live'
                    ? AppColors.orange
                    : AppColors.inkSoft,
                onBack: () => Navigator.of(context).maybePop(),
                onTeamTap: (t) => showTeamSheet(context, t),
                scorers: scorers.take(8).toList(),
                topRadius: 0,
                topInset: MediaQuery.of(context).padding.top,
              ),
            ),
            _sourceStrip(),
            _tabBar(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  String _minuteText(Fixture fx, ScoreView? score) {
    if (fx.status == 'finished') return 'FT';
    if (fx.status == 'live') return score == null ? 'LIVE' : "${score.minute}'";
    final at = DateTime.tryParse(fx.kickoff)?.toLocal();
    return at == null
        ? 'UPCOMING'
        : '${at.day}/${at.month} · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }

  Widget _sourceStrip() {
    final data = _data;
    final stale = data?.stale == true;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: stale
          ? StadiumColors.amber.withValues(alpha: .13)
          : StadiumColors.mint.withValues(alpha: .1),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Icon(
            stale ? Icons.cloud_off_rounded : Icons.verified_rounded,
            size: 16,
            color: stale ? StadiumColors.amber : StadiumColors.mint,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              stale
                  ? 'Showing the latest cached TxLINE snapshot'
                  : (_loading
                        ? 'Checking verified TxLINE match data…'
                        : 'Verified TxLINE match data'),
              style: body(
                color: stale ? StadiumColors.amber : StadiumColors.mint,
                size: 11.5,
                weight: FontWeight.w700,
              ),
            ),
          ),
          if (_error != null)
            GestureDetector(
              onTap: _load,
              child: Text(
                'RETRY',
                style: label(color: AppColors.orange, size: 9),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    const tabs = ['Overview', 'Stats', 'Line-ups'];
    return Container(
      color: StadiumColors.canvas,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Pressable(
                  onTap: () => setState(() => _tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tab == i
                          ? StadiumColors.orange
                          : StadiumColors.canvasRaised,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: _tab == i
                            ? StadiumColors.orange
                            : StadiumColors.hairline,
                      ),
                    ),
                    child: Text(
                      tabs[i].toUpperCase(),
                      style: label(
                        color: _tab == i ? Colors.white : StadiumColors.muted,
                        size: 9.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _data == null)
      return const Center(
        child: CircularProgressIndicator(color: StadiumColors.orange),
      );
    if (_data == null) return _unavailable();
    return switch (_tab) {
      1 => _stats(),
      2 => _lineups(),
      _ => _overview(),
    };
  }

  Widget _unavailable() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 44,
            color: StadiumColors.muted,
          ),
          const SizedBox(height: 12),
          Text(
            'Verified match data is unavailable',
            style: display(19, color: StadiumColors.text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'No dummy stats or old squad will be substituted.',
            style: body(color: StadiumColors.muted, size: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          PrimaryButton('Retry', icon: Icons.refresh_rounded, onTap: _load),
        ],
      ),
    ),
  );

  Widget _overview() {
    final data = _data!;
    return RefreshIndicator(
      color: AppColors.orange,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          if (widget.onWatch != null) ...[
            PrimaryButton(
              _fixture.status == 'finished'
                  ? 'Watch verified replay'
                  : 'Open Official Match Hub',
              icon: _fixture.status == 'finished'
                  ? Icons.replay_rounded
                  : Icons.podcasts_rounded,
              expand: true,
              onTap: widget.onWatch,
            ),
            const SizedBox(height: 14),
          ],
          _lineupStatus(data),
          const SizedBox(height: 14),
          _darkSection('Confirmed match events'),
          if (data.events.isEmpty)
            _empty(
              _fixture.status == 'scheduled'
                  ? 'Events will appear when the match begins.'
                  : 'No confirmed action records are available yet.',
            )
          else
            _events(data.events),
          const SizedBox(height: 14),
          _darkSection('Match information'),
          Container(
            decoration: cardBox(),
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _info(Icons.emoji_events_outlined, _fixture.competition),
                _info(Icons.layers_outlined, _fixture.stage),
                if (_fixture.venue.isNotEmpty)
                  _info(Icons.stadium_outlined, _fixture.venue),
                _info(
                  Icons.schedule_rounded,
                  DateTime.tryParse(_fixture.kickoff)?.toLocal().toString() ??
                      _fixture.kickoff,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineupStatus(MatchData data) {
    final announced =
        data.lineupStatus == 'confirmed' &&
        data.home.players.isNotEmpty &&
        data.away.players.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: announced ? const Color(0xFFE9F7E1) : AppColors.cardAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: announced ? const Color(0xFF9BCB91) : AppColors.line,
        ),
      ),
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Icon(
            announced ? Icons.groups_2_rounded : Icons.schedule_rounded,
            color: announced ? const Color(0xFF2D6A30) : AppColors.mut,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announced ? 'Confirmed lineups' : 'Lineups not announced',
                  style: body(weight: FontWeight.w800, size: 13.5),
                ),
                Text(
                  announced
                      ? '${data.home.formation ?? 'Formation pending'} · ${data.away.formation ?? 'Formation pending'}'
                      : 'The fixture page will update when TxLINE confirms the starters.',
                  style: body(color: AppColors.mut, size: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _events(List<VerifiedMatchEvent> events) => Container(
    decoration: cardBox(),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
    child: Column(
      children: events.map((event) {
        final home = event.side == 'home';
        final icon = switch (event.kind) {
          'goal' => '⚽',
          'yellow' => '🟨',
          'red' => '🟥',
          'corner' => '🚩',
          'substitution' => '🔁',
          _ => '•',
        };
        final name = event.kind == 'substitution'
            ? '${event.secondaryPlayerName ?? 'Player on'} · ${event.playerName ?? 'Player off'}'
            : event.playerName ?? event.teamCode;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: home
                ? [
                    SizedBox(
                      width: 34,
                      child: Text(
                        "${event.minute}'",
                        style: display(13, color: AppColors.orange),
                      ),
                    ),
                    Text(icon),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: body(size: 12.5, weight: FontWeight.w700),
                      ),
                    ),
                  ]
                : [
                    Expanded(
                      child: Text(
                        name,
                        textAlign: TextAlign.right,
                        style: body(size: 12.5, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(icon),
                    SizedBox(
                      width: 34,
                      child: Text(
                        "${event.minute}'",
                        textAlign: TextAlign.right,
                        style: display(13, color: AppColors.orange),
                      ),
                    ),
                  ],
          ),
        );
      }).toList(),
    ),
  );

  Widget _stats() {
    final score = _data!.score;
    if (score == null)
      return _centerEmpty(
        'Supported match statistics will appear when the TxLINE feed begins.',
      );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Container(
          decoration: cardBox(),
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              _statRow('Goals', score.goals.home, score.goals.away),
              _statRow('Corners', score.corners.home, score.corners.away),
              _statRow('Yellow cards', score.yellow.home, score.yellow.away),
              _statRow('Red cards', score.red.home, score.red.away),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _empty(
          'Possession, xG, shots, ratings and player-of-the-match are not shown because this TxLINE feed does not verify them.',
        ),
      ],
    );
  }

  Widget _statRow(String name, int home, int away) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        SizedBox(width: 42, child: Text('$home', style: display(18))),
        Expanded(
          child: Column(
            children: [
              Text(
                name.toUpperCase(),
                style: label(color: AppColors.mut, size: 9),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Row(
                  children: [
                    Expanded(
                      flex: home + 1,
                      child: Container(height: 5, color: AppColors.orange),
                    ),
                    Expanded(
                      flex: away + 1,
                      child: Container(
                        height: 5,
                        color: const Color(0xFF8B5CF6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 42,
          child: Text('$away', textAlign: TextAlign.right, style: display(18)),
        ),
      ],
    ),
  );

  Widget _lineups() {
    final data = _data!;
    if (data.lineupStatus != 'confirmed' ||
        data.home.players.isEmpty ||
        data.away.players.isEmpty) {
      return _centerEmpty(
        'Lineups not announced. This page will update from TxLINE when starters are confirmed.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _lineupTeam(_fixture.home, data.home),
        const SizedBox(height: 14),
        _lineupTeam(_fixture.away, data.away),
      ],
    );
  }

  Widget _lineupTeam(Team team, VerifiedTeamLineup lineup) {
    final starters = lineup.players.where((p) => p.starter).toList();
    final bench = lineup.players.where((p) => !p.starter).toList();
    Widget row(VerifiedPlayer player) => Pressable(
      onTap: () => showPlayerSheet(context, team, player),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 29,
              child: Text(
                player.shirtNumber ?? '—',
                style: display(13, color: AppColors.orange),
              ),
            ),
            Expanded(
              child: Text(
                player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: body(weight: FontWeight.w700, size: 13),
              ),
            ),
            if (player.onPitch)
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF75C043),
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 7),
            Text(
              player.position,
              style: label(color: AppColors.mut, size: 8.5),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: AppColors.mut,
            ),
          ],
        ),
      ),
    );
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          Row(
            children: [
              InlineFlag(team: team, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(team.name.toUpperCase(), style: display(18)),
              ),
              Text(
                lineup.formation ?? '—',
                style: label(color: AppColors.orange, size: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'STARTING XI',
              style: label(color: AppColors.mut, size: 8.5),
            ),
          ),
          ...starters.map(row),
          if (bench.isNotEmpty) ...[
            const Divider(color: AppColors.line),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SUBSTITUTES',
                style: label(color: AppColors.mut, size: 8.5),
              ),
            ),
            ...bench.map(row),
          ],
        ],
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.orange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: body(size: 12.5, weight: FontWeight.w600)),
        ),
      ],
    ),
  );
  Widget _empty(String text) => Container(
    decoration: cardBox(),
    padding: const EdgeInsets.all(17),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: body(color: StadiumColors.muted, size: 12.5),
    ),
  );
  Widget _centerEmpty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: body(color: StadiumColors.muted, size: 13.5),
      ),
    ),
  );

  Widget _darkSection(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Text(
      text.toUpperCase(),
      style: label(
        color: StadiumColors.text,
        size: 11,
        weight: FontWeight.w900,
      ),
    ),
  );
}
