import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../data/flags.dart';
import '../data/player_images.dart';
import '../local/fixtures.dart';
import '../local/match_facts.dart';
import '../local/squads.dart';
import '../theme.dart';
import 'common.dart';

/// FotMob-style player profile: photo (when TheSportsDB has one), position &
/// shirt number, tournament totals (games, goals, assists, average rating) and
/// a per-match log — all from the on-device facts engine.
void showPlayerSheet(BuildContext context, Team team, SquadPlayer player) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _PlayerSheet(team: team, player: player),
  );
}

String positionLabel(String pos) => switch (pos) {
      'GK' => 'Goalkeeper',
      'DF' => 'Defender',
      'MF' => 'Midfielder',
      'FW' => 'Forward',
      _ => pos,
    };

class _MatchLine {
  final Fixture fixture;
  final double? rating;
  final int goals, assists;
  _MatchLine(this.fixture, this.rating, this.goals, this.assists);
}

class _PlayerSheet extends StatefulWidget {
  final Team team;
  final SquadPlayer player;
  const _PlayerSheet({required this.team, required this.player});
  @override
  State<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<_PlayerSheet> {
  String? _photo;

  @override
  void initState() {
    super.initState();
    // best-effort real photo via the shared index — degrades to initials
    _photo = PlayerImages.photoFor(widget.team.name, widget.player.name);
    if (_photo == null) {
      PlayerImages.warm(widget.team.name).then((_) {
        if (!mounted) return;
        setState(() => _photo = PlayerImages.photoFor(widget.team.name, widget.player.name));
      });
    }
  }

  List<_MatchLine> _matchLog() {
    final lines = <_MatchLine>[];
    for (final f in localFixtures()) {
      if (f.status == 'scheduled') continue;
      final isHome = f.home.code == widget.team.code;
      final isAway = f.away.code == widget.team.code;
      if (!isHome && !isAway) continue;
      final facts = factsFor(f);
      final ratings = isHome ? facts.homeRatings : facts.awayRatings;
      PlayerRating? mine;
      for (final pr in ratings) {
        if (pr.player.name == widget.player.name) mine = pr;
      }
      final liveMinute = f.status == 'live' ? (f.score?.minute ?? 0) : 999;
      final goals = facts.events
          .where((e) => e.kind == 'goal' && e.player == widget.player.name && e.minute <= liveMinute)
          .length;
      final assists = facts.events
          .where((e) => e.kind == 'goal' && e.assist == widget.player.name && e.minute <= liveMinute)
          .length;
      lines.add(_MatchLine(f, f.status == 'finished' ? mine?.rating : null, goals, assists));
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final log = _matchLog();
    final games = log.where((l) => l.fixture.status == 'finished').length;
    final goals = log.fold(0, (s, l) => s + l.goals);
    final assists = log.fold(0, (s, l) => s + l.assists);
    final rated = log.where((l) => l.rating != null).toList();
    final avg = rated.isEmpty ? null : rated.fold(0.0, (s, l) => s + l.rating!) / rated.length;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 16),
          // hero
          Container(
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(18)),
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              _avatar(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.player.name.toUpperCase(), style: display(24, color: AppColors.cream)),
                  const SizedBox(height: 4),
                  Row(children: [
                    InlineFlag(team: widget.team, size: 20),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('${widget.team.name} · #${widget.player.number} · ${positionLabel(widget.player.pos)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mutInk, size: 12)),
                    ),
                  ]),
                ]),
              ),
              if (avg != null) _ratingBadge(avg, big: true),
            ]),
          ),
          const SizedBox(height: 12),
          // tournament totals
          Row(children: [
            _stat('$games', 'MATCHES'),
            const SizedBox(width: 8),
            _stat('$goals', 'GOALS'),
            const SizedBox(width: 8),
            _stat('$assists', 'ASSISTS'),
            const SizedBox(width: 8),
            _stat(avg == null ? '—' : avg.toStringAsFixed(1), 'AVG RATING'),
          ]),
          const SizedBox(height: 18),
          const SectionLabel('This World Cup'),
          if (log.isEmpty)
            Text('No matches played yet.', style: body(color: AppColors.mut, size: 13))
          else
            ...log.map(_matchRow),
        ]),
      ),
    );
  }

  Widget _avatar() {
    const size = 62.0;
    if (_photo != null) {
      return ClipOval(
        child: CachedNetworkImage(
            imageUrl: _photo!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, __) => InitialAvatar(name: widget.player.name, size: size),
            errorWidget: (_, __, ___) => InitialAvatar(name: widget.player.name, size: size)),
      );
    }
    return InitialAvatar(name: widget.player.name, size: size);
  }

  Widget _stat(String value, String label_) => Expanded(
        child: Container(
          decoration: cardBox(),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(children: [
            Text(value, style: display(20)),
            const SizedBox(height: 2),
            Text(label_, style: label(color: AppColors.mut, size: 7.5)),
          ]),
        ),
      );

  Widget _matchRow(_MatchLine l) {
    final f = l.fixture;
    final isHome = f.home.code == widget.team.code;
    final opp = isHome ? f.away : f.home;
    final s = f.score;
    final scoreText = s == null ? '—' : (isHome ? '${s.home}–${s.away}' : '${s.away}–${s.home}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: cardBox(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          InlineFlag(team: opp, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${isHome ? "vs" : "@"} ${opp.name}  $scoreText${f.status == 'live' ? "  ·  LIVE" : ""}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: body(weight: FontWeight.w700, size: 13)),
              Text(f.stage, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mut, size: 10.5)),
            ]),
          ),
          if (l.goals > 0) ...[Text('⚽ ${l.goals}', style: body(size: 12, weight: FontWeight.w800)), const SizedBox(width: 8)],
          if (l.assists > 0) ...[Text('🅰 ${l.assists}', style: body(size: 12, weight: FontWeight.w800)), const SizedBox(width: 8)],
          if (l.rating != null) _ratingBadge(l.rating!),
        ]),
      ),
    );
  }
}

/// Sofascore-style rating chip, color-graded from red (poor) to gold (elite).
Widget _ratingBadge(double rating, {bool big = false}) {
  final color = rating >= 8.4
      ? AppColors.gold
      : rating >= 7.4
          ? const Color(0xFF1F7A3D)
          : rating >= 6.5
              ? const Color(0xFF7A8C1F)
              : const Color(0xFFD8392B);
  return Container(
    padding: EdgeInsets.symmetric(horizontal: big ? 10 : 7, vertical: big ? 6 : 3),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
    child: Text(rating.toStringAsFixed(1),
        style: TextStyle(fontFamily: kBody, color: Colors.white, fontWeight: FontWeight.w800, fontSize: big ? 16 : 12)),
  );
}

/// Public version for other widgets (line-ups, leaderboards).
Widget ratingBadge(double rating, {bool big = false}) => _ratingBadge(rating, big: big);
