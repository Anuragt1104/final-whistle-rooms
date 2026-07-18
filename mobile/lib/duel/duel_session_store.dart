import '../state/local_store.dart';

/// Persists active Duel id + last animated round so resume/fast-forward
/// does not replay rewards or cinematic sequences.
class DuelSessionStore {
  static Future<String?> activeDuelId() => LocalStore.activeDuelId();

  static Future<void> setActiveDuelId(String? id) =>
      LocalStore.setActiveDuelId(id);

  static Future<int> lastAnimatedRound(String duelId) =>
      LocalStore.lastAnimatedDuelRound(duelId);

  static Future<void> setLastAnimatedRound(String duelId, int round) =>
      LocalStore.setLastAnimatedDuelRound(duelId, round);

  static Future<void> clear(String duelId) async {
    await LocalStore.setActiveDuelId(null);
    await LocalStore.setLastAnimatedDuelRound(duelId, 0);
  }
}
