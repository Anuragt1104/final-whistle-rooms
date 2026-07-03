import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight local persistence: display name, per-room membership, and the
/// user's own Next Swing picks (the server holds the authoritative tally).
class LocalStore {
  static Future<bool> onboarded() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('onboarded') ?? false;
  }

  static Future<void> setOnboarded() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarded', true);
  }

  static Future<String> walletAddress() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('wallet_address') ?? '';
  }

  static Future<void> setWalletAddress(String addr) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('wallet_address', addr);
  }

  static Future<String> displayName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('display_name') ?? '';
  }

  static Future<void> setDisplayName(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('display_name', name);
  }

  static Future<String?> memberId(String roomId) async {
    final p = await SharedPreferences.getInstance();
    return p.getString('member_$roomId');
  }

  static Future<void> setMemberId(String roomId, String memberId) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('member_$roomId', memberId);
  }

  static Future<Map<String, String>> picks(String roomId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('picks_$roomId');
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> savePicks(String roomId, Map<String, String> picks) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('picks_$roomId', jsonEncode(picks));
  }

  // ---- Higher-or-Lower: lifetime best streak across all rooms/matches ----
  static Future<int> streakBest() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('streak_best') ?? 0;
  }

  /// Raise the lifetime best streak; returns the (possibly unchanged) best.
  static Future<int> bumpStreakBest(int streak) async {
    final p = await SharedPreferences.getInstance();
    final best = p.getInt('streak_best') ?? 0;
    if (streak > best) {
      await p.setInt('streak_best', streak);
      return streak;
    }
    return best;
  }

  // ---- Season Pass (Pro) entitlement ----
  static Future<bool> isPro() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('pro') ?? false;
  }

  static Future<void> setPro(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('pro', v);
  }

  // ---- fan stats (profile) ----
  static Future<int> matchesWatched() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('matches_watched') ?? 0;
  }

  /// Count a fixture as watched once ever (re-entering a room doesn't double).
  static Future<void> markWatched(String fixtureId) async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('watched_$fixtureId') ?? false) return;
    await p.setBool('watched_$fixtureId', true);
    await p.setInt('matches_watched', (p.getInt('matches_watched') ?? 0) + 1);
  }

  static Future<int> callsMade() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('calls_made') ?? 0;
  }

  static Future<void> bumpCallsMade() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('calls_made', (p.getInt('calls_made') ?? 0) + 1);
  }

  static Future<int> callsCorrect() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('calls_correct') ?? 0;
  }

  static Future<void> bumpCallsCorrect() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('calls_correct', (p.getInt('calls_correct') ?? 0) + 1);
  }

  static Future<String> favoriteTeam() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('favorite_team') ?? '';
  }

  static Future<void> setFavoriteTeam(String code) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('favorite_team', code);
  }
}
