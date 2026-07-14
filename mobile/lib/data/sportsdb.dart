import 'dart:convert';
import 'package:http/http.dart' as http;

/// TheSportsDB (free tier) — official national-team badges + squad photos, used
/// for the team profile sheet. TxLINE has no player data, so this fills in the
/// "official images of the players / team info" layer. Best-effort + cached;
/// the app degrades to flags/initials if a lookup misses or the network is down.
class PlayerInfo {
  final String name, position, photo;
  PlayerInfo(this.name, this.position, this.photo);
}

class TeamInfo {
  final String name;
  final String? badge, country, stadium, description, formedYear;
  final List<PlayerInfo> squad;
  TeamInfo({
    required this.name,
    this.badge,
    this.country,
    this.stadium,
    this.description,
    this.formedYear,
    this.squad = const [],
  });
}

class SportsDb {
  static const _base = 'https://www.thesportsdb.com/api/v1/json/3';
  static final http.Client _http = http.Client();
  static final Map<String, TeamInfo?> _cache = {};
  static final Map<String, Future<TeamInfo?>> _inflight = {};

  /// Look up a national team by name (TxLINE gives the country name). Cached.
  static Future<TeamInfo?> team(String name) {
    final key = name.trim().toLowerCase();
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _inflight[key] ??= _fetch(name).then((t) {
      _cache[key] = t;
      _inflight.remove(key);
      return t;
    });
  }

  static Future<TeamInfo?> _fetch(String name) async {
    try {
      final tRes = await _http
          .get(
            Uri.parse('$_base/searchteams.php?t=${Uri.encodeComponent(name)}'),
          )
          .timeout(const Duration(seconds: 10));
      if (tRes.statusCode >= 400) return null;
      final teams = (jsonDecode(tRes.body)['teams'] as List?) ?? [];
      // STRICTLY soccer — never fall back to e.g. the Jordan F1 team. Among
      // soccer results prefer the national team (FIFA World Cup / exact name).
      final soccer = teams
          .where((x) => (x['strSport'] ?? '') == 'Soccer')
          .toList();
      Map<String, dynamic>? t;
      for (final x in soccer) {
        final lg = (x['strLeague'] ?? '').toString().toLowerCase();
        if (lg.contains('world cup') ||
            lg.contains('national') ||
            (x['strTeam'] ?? '').toString().toLowerCase() ==
                name.trim().toLowerCase()) {
          t = Map<String, dynamic>.from(x);
          break;
        }
      }
      t ??= soccer.isNotEmpty ? Map<String, dynamic>.from(soccer.first) : null;
      if (t == null) return null;

      final squad = <PlayerInfo>[];
      try {
        final id = t['idTeam'];
        final sRes = await _http
            .get(Uri.parse('$_base/lookup_all_players.php?id=$id'))
            .timeout(const Duration(seconds: 10));
        final players = (jsonDecode(sRes.body)['player'] as List?) ?? [];
        for (final p in players) {
          final photo = (p['strThumb'] ?? p['strCutout'] ?? '') as String;
          if (photo.isEmpty) continue;
          squad.add(
            PlayerInfo(
              (p['strPlayer'] ?? '') as String,
              (p['strPosition'] ?? '') as String,
              photo,
            ),
          );
        }
      } catch (_) {
        /* squad optional */
      }

      return TeamInfo(
        name: (t['strTeam'] ?? name) as String,
        badge: (t['strBadge'] as String?)?.isNotEmpty == true
            ? t['strBadge'] as String
            : null,
        country: t['strCountry'] as String?,
        stadium: t['strStadium'] as String?,
        description: t['strDescriptionEN'] as String?,
        formedYear: t['intFormedYear'] as String?,
        squad: squad,
      );
    } catch (_) {
      return null;
    }
  }
}
