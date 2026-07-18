import 'package:audioplayers/audioplayers.dart';

import '../state/local_store.dart';

enum DuelSound { stadiumRise, cardFlip, impact, victory, defeat }

class DuelAudio {
  DuelAudio._();
  static final DuelAudio instance = DuelAudio._();

  final AudioPlayer _player = AudioPlayer();
  bool _muted = false;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _muted = await LocalStore.duelMuted();
    await _player.setReleaseMode(ReleaseMode.stop);
    _ready = true;
  }

  bool get muted => _muted;

  Future<void> setMuted(bool value) async {
    _muted = value;
    await LocalStore.setDuelMuted(value);
    if (value) await _player.stop();
  }

  Future<void> play(DuelSound sound) async {
    await init();
    if (_muted) return;
    final file = switch (sound) {
      DuelSound.stadiumRise => 'audio/stadium_rise.wav',
      DuelSound.cardFlip => 'audio/card_flip.wav',
      DuelSound.impact => 'audio/impact.wav',
      DuelSound.victory => 'audio/victory.wav',
      DuelSound.defeat => 'audio/defeat.wav',
    };
    try {
      await _player.stop();
      await _player.play(AssetSource(file));
    } catch (_) {
      // Sound must never block a Duel command or reveal.
    }
  }

  Future<void> dispose() => _player.dispose();
}
