import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sportsdb.dart';

/// Player face index — the one place that maps a squad player's name to their
/// official TheSportsDB photo URL, per team.
///
/// Design goals (this powers every live surface, so it must be fast + robust):
///  - one squad fetch per team ever (persisted to disk with a 7-day TTL)
///  - instant synchronous lookups once warm (`photoFor`)
///  - diacritic/initial-safe name matching ("Mbappé" ↔ "Kylian Mbappé",
///    "E. Álvarez" ↔ "Edson Álvarez", "ter Stegen" ↔ "Marc-André ter Stegen")
///  - listeners so avatars re-render the moment a team's index arrives
class PlayerImages {
  static final Map<String, Map<String, String>> _byTeam = {}; // teamKey → normName → url
  static final Map<String, Future<void>> _warming = {};
  static final List<VoidCallback> _listeners = [];

  static String _teamKey(String teamName) => teamName.trim().toLowerCase();

  static void addListener(VoidCallback fn) => _listeners.add(fn);
  static void removeListener(VoidCallback fn) => _listeners.remove(fn);
  static void _notify() {
    for (final fn in List.of(_listeners)) {
      fn();
    }
  }

  /// Build (or load) the name→photo index for a team. Deduped + idempotent —
  /// call freely from initState/build paths.
  static Future<void> warm(String teamName) {
    final key = _teamKey(teamName);
    if (_byTeam.containsKey(key)) return Future.value();
    return _warming[key] ??= _build(teamName, key).whenComplete(() => _warming.remove(key));
  }

  static Future<void> _build(String teamName, String key) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('player_photos_$key');
    final ts = prefs.getInt('player_photos_ts_$key') ?? 0;
    const week = 7 * 24 * 60 * 60 * 1000;
    if (cached != null && DateTime.now().millisecondsSinceEpoch - ts < week) {
      try {
        _byTeam[key] = Map<String, String>.from(jsonDecode(cached));
        _notify();
        return;
      } catch (_) {/* fall through to network */}
    }
    final info = await SportsDb.team(teamName);
    final map = <String, String>{};
    if (info != null) {
      for (final p in info.squad) {
        if (p.photo.isEmpty) continue;
        map[_norm(p.name)] = p.photo;
      }
    }
    _byTeam[key] = map;
    if (map.isNotEmpty) {
      await prefs.setString('player_photos_$key', jsonEncode(map));
      await prefs.setInt('player_photos_ts_$key', DateTime.now().millisecondsSinceEpoch);
    }
    _notify();
  }

  /// Synchronous best-match photo lookup. Null while cold or on no match —
  /// callers fall back to an initials avatar and re-render via the listener.
  static String? photoFor(String teamName, String playerName) {
    final map = _byTeam[_teamKey(teamName)];
    if (map == null || map.isEmpty) return null;
    final q = _norm(playerName);
    // 1) exact normalized name
    final exact = map[q];
    if (exact != null) return exact;
    // 2) surname containment ("mbappe" matches "kylian mbappe"); squad entries
    //    like "E. Alvarez" reduce to "alvarez" via the initial-strip below.
    final surname = _surname(q);
    if (surname.length >= 3) {
      for (final e in map.entries) {
        if (e.key.contains(surname)) return e.value;
      }
    }
    return null;
  }

  /// Normalize for matching: lowercase, strip diacritics + "X." initials.
  static String _norm(String s) {
    var t = s.trim().toLowerCase();
    const from = 'àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿğışćčđšžłńęąź';
    const to = 'aaaaaaaceeeeiiiinoooooouuuuyygisccdszlneaz';
    final sb = StringBuffer();
    for (final ch in t.split('')) {
      final i = from.indexOf(ch);
      sb.write(i >= 0 ? to[i] : ch);
    }
    t = sb.toString();
    // strip a leading single-letter initial ("e. alvarez" → "alvarez")
    t = t.replaceAll(RegExp(r'^[a-z]\.\s*'), '');
    return t;
  }

  static String _surname(String normalized) {
    final parts = normalized.split(' ').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? normalized : parts.last;
  }
}
