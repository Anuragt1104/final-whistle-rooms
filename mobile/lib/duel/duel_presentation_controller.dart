import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/local_store.dart';
import 'duel_audio.dart';
import 'duel_models.dart';

/// Holds authoritative round values privately until the cinematic sequence
/// reaches the corresponding reveal phase.
class DuelPresentationController extends ChangeNotifier {
  DuelPresentationPhase phase = DuelPresentationPhase.idle;
  DuelRoundModel? _pendingRound;
  DuelRoundModel? visibleRound;
  bool reducedMotion = false;
  bool _disposed = false;

  bool get busy => phase != DuelPresentationPhase.idle;
  bool get showOpponentCard => const {
    DuelPresentationPhase.flipping,
    DuelPresentationPhase.modifiers,
    DuelPresentationPhase.scoring,
    DuelPresentationPhase.impact,
    DuelPresentationPhase.result,
  }.contains(phase);
  bool get showModifiers => const {
    DuelPresentationPhase.modifiers,
    DuelPresentationPhase.scoring,
    DuelPresentationPhase.impact,
    DuelPresentationPhase.result,
  }.contains(phase);
  bool get showScores => const {
    DuelPresentationPhase.scoring,
    DuelPresentationPhase.impact,
    DuelPresentationPhase.result,
  }.contains(phase);
  bool get showResult => const {
    DuelPresentationPhase.impact,
    DuelPresentationPhase.result,
  }.contains(phase);

  Future<void> init() async {
    reducedMotion = await LocalStore.reducedMotion();
    await DuelAudio.instance.init();
  }

  Future<void> play({
    required String duelId,
    required DuelRoundModel round,
    required String fanId,
  }) async {
    if (_disposed) return;
    _pendingRound = round;
    visibleRound = null;
    if (reducedMotion) {
      visibleRound = round;
      phase = DuelPresentationPhase.result;
      notifyListeners();
      await LocalStore.setLastAnimatedDuelRound(duelId, round.round);
      await _delay(const Duration(milliseconds: 500));
      phase = DuelPresentationPhase.idle;
      notifyListeners();
      return;
    }

    await DuelAudio.instance.play(DuelSound.stadiumRise);
    await _step(
      DuelPresentationPhase.fanCardEntering,
      const Duration(milliseconds: 430),
      HapticFeedback.selectionClick,
    );
    await _step(
      DuelPresentationPhase.opponentCardLocking,
      const Duration(milliseconds: 360),
      HapticFeedback.mediumImpact,
    );
    await _step(
      DuelPresentationPhase.floodlights,
      const Duration(milliseconds: 300),
    );
    visibleRound = _pendingRound;
    await DuelAudio.instance.play(DuelSound.cardFlip);
    await _step(
      DuelPresentationPhase.flipping,
      const Duration(milliseconds: 620),
      HapticFeedback.lightImpact,
    );
    await _step(
      DuelPresentationPhase.modifiers,
      const Duration(milliseconds: 720),
      HapticFeedback.selectionClick,
    );
    await _step(
      DuelPresentationPhase.scoring,
      const Duration(milliseconds: 760),
    );
    await DuelAudio.instance.play(DuelSound.impact);
    await _step(
      DuelPresentationPhase.impact,
      const Duration(milliseconds: 420),
      HapticFeedback.heavyImpact,
    );
    phase = DuelPresentationPhase.result;
    notifyListeners();

    final won = round.winnerId == fanId;
    if (round.winnerId != null) {
      await DuelAudio.instance.play(
        won ? DuelSound.victory : DuelSound.defeat,
      );
    }
    await LocalStore.setLastAnimatedDuelRound(duelId, round.round);
    await _delay(const Duration(milliseconds: 950));
    if (!_disposed) {
      phase = DuelPresentationPhase.idle;
      notifyListeners();
    }
  }

  Future<void> fastForward({
    required String duelId,
    required DuelRoundModel round,
  }) async {
    visibleRound = round;
    phase = DuelPresentationPhase.result;
    notifyListeners();
    await LocalStore.setLastAnimatedDuelRound(duelId, round.round);
  }

  Future<void> _step(
    DuelPresentationPhase next,
    Duration duration, [
    Future<void> Function()? haptic,
  ]) async {
    if (_disposed) return;
    phase = next;
    notifyListeners();
    if (haptic != null) await haptic();
    await _delay(duration);
  }

  Future<void> _delay(Duration duration) =>
      Future<void>.delayed(duration);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
