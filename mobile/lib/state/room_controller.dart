import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/sse_client.dart';
import '../local/live_engine.dart';
import 'local_store.dart';

/// Owns one room's live state. Two backends:
///  - remote: subscribes to the server SSE stream (multiplayer)
///  - local:  drives an on-device LiveMatchEngine (solo, always works)
class RoomController extends ChangeNotifier {
  final String roomId;
  final ApiClient api = ApiClient.instance;
  final LiveMatchEngine? engine; // non-null = local mode

  RoomSseClient? _sse;
  RoomView? _remoteRoom;
  bool connected = false;
  bool notFound = false;
  String? memberId;
  Map<String, String> _myPicks = {};

  RoomController(this.roomId) : engine = null;
  RoomController.local(this.engine) : roomId = 'local';

  bool get isLocal => engine != null;

  Future<void> init() async {
    if (isLocal) {
      memberId = 'me';
      engine!.addListener(notifyListeners);
      notifyListeners();
      return;
    }
    memberId = await LocalStore.memberId(roomId);
    _myPicks = await LocalStore.picks(roomId);
    try {
      _remoteRoom = await api.room(roomId);
    } catch (_) {
      notFound = true;
    }
    notifyListeners();

    _sse = RoomSseClient(api.baseUrl, roomId);
    _sse!.rooms.listen((r) {
      _remoteRoom = r;
      notFound = false;
      notifyListeners();
    });
    _sse!.connection.listen((c) {
      connected = c;
      notifyListeners();
    });
  }

  RoomView? get room => isLocal ? engine!.view : _remoteRoom;
  Map<String, String> get myPicks => isLocal ? engine!.myPicks : _myPicks;

  MemberView? get me {
    final members = room?.members;
    if (members == null) return null;
    for (final m in members) {
      if (m.id == memberId) return m;
    }
    return null;
  }

  bool get joined => isLocal ? true : me != null;
  bool get isHost => isLocal ? true : (room != null && room!.hostId == memberId);

  Future<void> join(String name, String wallet) async {
    if (isLocal) return;
    final id = await api.join(roomId, name, walletPubkey: wallet);
    memberId = id;
    await LocalStore.setMemberId(roomId, id);
    notifyListeners();
  }

  Future<void> pickSide(String side) async {
    if (isLocal) {
      engine!.pickSide(side);
      return;
    }
    if (memberId != null) await api.pickSide(roomId, memberId!, side);
  }

  Future<void> startMatch() async {
    if (isLocal) {
      engine!.start();
      return;
    }
    if (memberId != null) await api.start(roomId, memberId!);
  }

  Future<void> predict(String promptId, String key) async {
    if (isLocal) {
      engine!.predict(promptId, key);
      return;
    }
    if (memberId == null) return;
    _myPicks = {..._myPicks, promptId: key};
    await LocalStore.savePicks(roomId, _myPicks);
    notifyListeners();
    try {
      await api.predict(roomId, memberId!, promptId, key);
    } catch (_) {}
  }

  Future<void> sendChat(String text) async {
    if (isLocal) {
      engine!.chat(text);
      return;
    }
    if (memberId != null) await api.chat(roomId, memberId!, text);
  }

  Future<void> react(String emoji) async {
    if (isLocal) {
      engine!.react(emoji);
      return;
    }
    if (memberId != null) await api.chat(roomId, memberId!, emoji, kind: 'reaction');
  }

  @override
  void dispose() {
    _sse?.close();
    if (isLocal) {
      engine!.removeListener(notifyListeners);
      engine!.dispose();
    }
    super.dispose();
  }
}
