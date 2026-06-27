import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/sse_client.dart';
import 'local_store.dart';

/// Owns one room's live state: subscribes to SSE, tracks membership and the
/// user's own picks, and exposes the room actions.
class RoomController extends ChangeNotifier {
  final String roomId;
  final ApiClient api = ApiClient.instance;

  RoomSseClient? _sse;
  RoomView? room;
  bool connected = false;
  bool notFound = false;
  String? memberId;
  Map<String, String> myPicks = {};

  RoomController(this.roomId);

  Future<void> init() async {
    memberId = await LocalStore.memberId(roomId);
    myPicks = await LocalStore.picks(roomId);
    try {
      room = await api.room(roomId);
    } catch (_) {
      notFound = true;
    }
    notifyListeners();

    _sse = RoomSseClient(api.baseUrl, roomId);
    _sse!.rooms.listen((r) {
      room = r;
      notFound = false;
      notifyListeners();
    });
    _sse!.connection.listen((c) {
      connected = c;
      notifyListeners();
    });
  }

  MemberView? get me {
    final members = room?.members;
    if (members == null) return null;
    for (final m in members) {
      if (m.id == memberId) return m;
    }
    return null;
  }

  bool get joined => me != null;
  bool get isHost => room != null && room!.hostId == memberId;

  Future<void> join(String name, String wallet) async {
    final id = await api.join(roomId, name, walletPubkey: wallet);
    memberId = id;
    await LocalStore.setMemberId(roomId, id);
    notifyListeners();
  }

  Future<void> pickSide(String side) async {
    if (memberId != null) await api.pickSide(roomId, memberId!, side);
  }

  Future<void> startMatch() async {
    if (memberId != null) await api.start(roomId, memberId!);
  }

  Future<void> predict(String promptId, String key) async {
    if (memberId == null) return;
    myPicks = {...myPicks, promptId: key};
    await LocalStore.savePicks(roomId, myPicks);
    notifyListeners();
    try {
      await api.predict(roomId, memberId!, promptId, key);
    } catch (_) {
      // window may have just locked — keep local pick
    }
  }

  Future<void> sendChat(String text) async {
    if (memberId != null) await api.chat(roomId, memberId!, text);
  }

  Future<void> react(String emoji) async {
    if (memberId != null) await api.chat(roomId, memberId!, emoji, kind: 'reaction');
  }

  @override
  void dispose() {
    _sse?.close();
    super.dispose();
  }
}
