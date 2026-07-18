import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/cards.dart';
import '../api/duel_sse_client.dart';
import '../state/identity.dart';
import 'duel_models.dart';
import 'duel_presentation_controller.dart';
import 'duel_session_store.dart';

class DuelController extends ChangeNotifier {
  final ApiClient api;
  List<PlayerCardModel> players;
  List<MomentCard> moments;
  List<SkillCardModel> skills;
  final DuelPresentationController presentation;

  DuelViewModel? view;
  String? fanId;
  String? error;
  bool busy = false;
  bool connected = false;
  bool seeding = false;
  String selectedAxis = 'finishing';
  String? selectedCardId;
  String? selectedSkillId;
  String? selectedMomentId;
  final Set<String> selectedHand = {};
  final Set<String> selectedSkills = {};

  DuelSseClient? _sse;
  StreamSubscription<DuelViewModel>? _viewSub;
  StreamSubscription<bool>? _connectionSub;
  bool _disposed = false;

  DuelController({
    required List<PlayerCardModel> players,
    required List<MomentCard> moments,
    required List<SkillCardModel> skills,
    ApiClient? api,
    DuelPresentationController? presentation,
  }) : api = api ?? ApiClient.instance,
       players = List.of(players),
       moments = List.of(moments),
       skills = List.of(skills),
       presentation = presentation ?? DuelPresentationController();

  Future<void> init({String? resumeDuelId}) async {
    fanId = (await IdentityStore.getOrCreate()).pubkey;
    await presentation.init();
    presentation.addListener(_notify);
    selectedMomentId = null; // Arena charge must always be explicit.
    final duelId = resumeDuelId ?? await DuelSessionStore.activeDuelId();
    if (duelId != null && duelId.isNotEmpty) {
      await resume(duelId);
    } else {
      notifyListeners();
    }
  }

  /// Pull demo Moments / Players / Skills from the existing seed API so Arena
  /// can be tested without waiting for a live mint.
  Future<void> loadDemoCards() async {
    if (seeding) return;
    seeding = true;
    error = null;
    notifyListeners();
    try {
      final id = fanId ?? (await IdentityStore.getOrCreate()).pubkey;
      fanId = id;
      await api.seedInventory(id);
      final inv = FanInventory.fromJson(await api.inventory(id));
      players = List.of(inv.players);
      moments = List.of(inv.moments);
      skills = List.of(inv.skills);
      selectedHand
        ..clear()
        ..addAll(players.take(3).map((p) => p.id));
      if (moments.isNotEmpty) selectedMomentId = moments.first.id;
    } catch (exception) {
      error = exception.toString().replaceFirst('ApiException: ', '');
    } finally {
      seeding = false;
      if (!_disposed) notifyListeners();
    }
  }

  void toggleHand(String cardId) {
    if (selectedHand.contains(cardId)) {
      selectedHand.remove(cardId);
    } else if (selectedHand.length < 3) {
      selectedHand.add(cardId);
    }
    notifyListeners();
  }

  void toggleSkill(String skillId) {
    if (selectedSkills.contains(skillId)) {
      selectedSkills.remove(skillId);
    } else if (selectedSkills.length < 3) {
      selectedSkills.add(skillId);
    }
    notifyListeners();
  }

  void selectMoment(String momentId) {
    selectedMomentId = momentId;
    notifyListeners();
  }

  void chooseLocalAxis(String axis) {
    selectedAxis = axis;
    notifyListeners();
  }

  void selectCard(String cardId) {
    selectedCardId = cardId;
    notifyListeners();
  }

  void selectSkill(String? skillId) {
    selectedSkillId = skillId;
    notifyListeners();
  }

  Future<void> createStadium(DuelOpponent opponent) async {
    if (selectedHand.length != 3) {
      error = 'Choose exactly three Player Cards.';
      notifyListeners();
      return;
    }
    await _run(() async {
      final next = await api.createStadiumDuel(
        hand: selectedHand.toList(),
        skillIds: selectedSkills.toList(),
        opponent: opponent,
      );
      await _setView(next);
    });
  }

  Future<void> createArena() async {
    if (selectedHand.length != 3) {
      error = 'Choose exactly three Player Cards.';
      notifyListeners();
      return;
    }
    if (selectedMomentId == null) {
      error = 'Select the verified Moment that charges this Arena.';
      notifyListeners();
      return;
    }
    await _run(() async {
      final next = await api.createMomentArena(
        hand: selectedHand.toList(),
        skillIds: selectedSkills.toList(),
        seedMomentId: selectedMomentId!,
      );
      await _setView(next);
    });
  }

  Future<void> joinFriend(String code) async {
    if (selectedHand.length != 3) {
      error = 'Choose exactly three Player Cards.';
      notifyListeners();
      return;
    }
    await _run(() async {
      final next = await api.joinStadiumDuel(
        code: code,
        hand: selectedHand.toList(),
        skillIds: selectedSkills.toList(),
      );
      await _setView(next);
    });
  }

  Future<void> resume(String duelId) async {
    await _run(() async {
      final next = await api.duelView(duelId);
      await _setView(next, reconnecting: true);
    });
  }

  Future<void> chooseAxis() async {
    final duel = view;
    if (duel == null) return;
    await _run(() async {
      final next = await api.duelAction(
        duelId: duel.id,
        type: 'choose_axis',
        payload: {'axis': selectedAxis},
        expectedVersion: duel.version,
      );
      await _setView(next);
    });
  }

  Future<void> submitCard() async {
    final duel = view;
    if (duel == null || selectedCardId == null) return;
    await _run(() async {
      final beforeRounds = duel.rounds.length;
      final next = await api.duelAction(
        duelId: duel.id,
        type: 'submit_card',
        payload: {
          'cardId': selectedCardId,
          if (selectedSkillId != null) 'skillId': selectedSkillId,
        },
        expectedVersion: duel.version,
      );
      view = next;
      selectedCardId = null;
      selectedSkillId = null;
      notifyListeners();
      if (next.rounds.length > beforeRounds && next.latestRound != null) {
        await presentation.play(
          duelId: next.id,
          round: next.latestRound!,
          fanId: fanId ?? next.fanId,
        );
      }
    });
  }

  Future<void> acknowledgeRound() async {
    final duel = view;
    if (duel == null || duel.phase != DuelPhase.roundComplete) return;
    await _run(() async {
      await _setView(
        await api.duelAction(
          duelId: duel.id,
          type: 'acknowledge_round',
          expectedVersion: duel.version,
        ),
      );
    });
  }

  Future<void> rematch() async {
    final duel = view;
    if (duel == null) return;
    await _run(() async {
      await _setView(
        await api.duelAction(
          duelId: duel.id,
          type: 'rematch',
          expectedVersion: duel.version,
        ),
      );
    });
  }

  Future<void> _setView(
    DuelViewModel next, {
    bool reconnecting = false,
  }) async {
    view = next;
    await DuelSessionStore.setActiveDuelId(next.isFinished ? null : next.id);
    _connect(next);
    if (reconnecting && next.latestRound != null) {
      final animated = await DuelSessionStore.lastAnimatedRound(next.id);
      if (next.latestRound!.round > animated) {
        await presentation.fastForward(
          duelId: next.id,
          round: next.latestRound!,
        );
      }
    }
    notifyListeners();
  }

  void _connect(DuelViewModel duel) {
    if (_sse?.duelId == duel.id) return;
    _viewSub?.cancel();
    _connectionSub?.cancel();
    _sse?.close();
    _sse = DuelSseClient(
      baseUrl: api.baseUrl,
      duelId: duel.id,
      tokenProvider: api.duelBearerToken,
      lastVersion: duel.version,
    );
    _viewSub = _sse!.views.listen((next) async {
      final previousRounds = view?.rounds.length ?? 0;
      view = next;
      notifyListeners();
      if (next.rounds.length > previousRounds &&
          next.latestRound != null &&
          !presentation.busy) {
        final animated = await DuelSessionStore.lastAnimatedRound(next.id);
        if (next.latestRound!.round > animated) {
          await presentation.play(
            duelId: next.id,
            round: next.latestRound!,
            fanId: fanId ?? next.fanId,
          );
        }
      }
    });
    _connectionSub = _sse!.connection.listen((value) {
      connected = value;
      notifyListeners();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (exception) {
      error = exception.toString().replaceFirst('ApiException: ', '');
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    presentation.removeListener(_notify);
    presentation.dispose();
    _viewSub?.cancel();
    _connectionSub?.cancel();
    _sse?.close();
    super.dispose();
  }
}
