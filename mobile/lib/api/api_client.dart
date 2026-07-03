import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppConfig {
  final String mode, cluster, anchorCluster;
  final bool anchorConfigured, recapAI;
  AppConfig({required this.mode, required this.cluster, required this.anchorCluster, required this.anchorConfigured, required this.recapAI});
  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        mode: j['mode'] ?? 'simulation',
        cluster: j['cluster'] ?? 'devnet',
        anchorCluster: j['anchorCluster'] ?? 'devnet',
        anchorConfigured: j['anchorConfigured'] ?? false,
        recapAI: j['recapAI'] ?? false,
      );
  Map<String, dynamic> toJson() => {
        'mode': mode,
        'cluster': cluster,
        'anchorCluster': anchorCluster,
        'anchorConfigured': anchorConfigured,
        'recapAI': recapAI,
      };
}

/// Talks to the Final Whistle Rooms Next.js backend (REST). The base URL is
/// configurable in-app (Server settings) and persisted, so the same build runs
/// against localhost, a LAN IP, or a deployed URL.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final http.Client _http = http.Client();
  String _baseUrl = _platformDefault();
  String get baseUrl => _baseUrl;

  static const _defineBase = String.fromEnvironment('API_BASE');

  static String _platformDefault() {
    if (_defineBase.isNotEmpty) return _defineBase;
    if (kIsWeb) return 'http://localhost:3000';
    // Android emulator reaches the host machine via 10.0.2.2
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:3000';
    return 'http://localhost:3000';
  }

  /// Last config seen from the backend (hydrated from disk at init) — the mode
  /// rarely changes, so trusting it instantly makes cold starts and tap
  /// decisions fast; a background revalidate keeps it fresh.
  AppConfig? cachedConfig;
  List<Fixture>? _cachedFixtures;
  int _cachedFixturesTs = 0;

  /// Age of the cached fixtures — a stale cache must not flash a dead "live"
  /// match at boot.
  Duration cachedFixturesAge() =>
      Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - _cachedFixturesTs);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('api_base');
    if (_defineBase.isNotEmpty) {
      _baseUrl = _defineBase;
    } else if (stored != null && stored.isNotEmpty) {
      _baseUrl = stored;
    }
    final cfg = prefs.getString('cached_config');
    if (cfg != null) {
      try {
        cachedConfig = AppConfig.fromJson(jsonDecode(cfg));
      } catch (_) {}
    }
    final fx = prefs.getString('cached_fixtures');
    if (fx != null) {
      try {
        _cachedFixtures = ((jsonDecode(fx) as List)).map((f) => Fixture.fromJson(f)).toList();
        _cachedFixturesTs = prefs.getInt('cached_fixtures_at') ?? 0;
      } catch (_) {}
    }
  }

  /// Fixtures from the last successful fetch — instant, may be stale.
  List<Fixture>? cachedFixtures() => _cachedFixtures;

  /// Best-effort config for tap-time decisions: last-known instantly (with a
  /// background refresh), else one quick network try. Null = unreachable.
  Future<AppConfig?> resolveConfig() async {
    if (cachedConfig != null) {
      config().catchError((_) => cachedConfig!); // revalidate in background
      return cachedConfig;
    }
    try {
      return await config();
    } catch (_) {
      return null;
    }
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base', _baseUrl);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<dynamic> _get(String path, {Duration timeout = const Duration(seconds: 6)}) async {
    final res = await _http.get(_uri(path)).timeout(timeout);
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 400) {
      throw ApiException(data is Map ? (data['error'] ?? 'Request failed') : 'Request failed');
    }
    return data;
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body, {Duration timeout = const Duration(seconds: 8)}) async {
    final res = await _http
        .post(
          _uri(path),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 400) {
      throw ApiException(data is Map ? (data['error'] ?? 'Request failed') : 'Request failed');
    }
    return data;
  }

  Future<AppConfig> config() async {
    final c = AppConfig.fromJson(await _get('/api/config', timeout: const Duration(seconds: 3)));
    cachedConfig = c;
    SharedPreferences.getInstance().then((p) => p.setString('cached_config', jsonEncode(c.toJson())));
    return c;
  }

  Future<List<Fixture>> fixtures() async {
    final data = await _get('/api/fixtures');
    final raw = (data['fixtures'] ?? []) as List;
    final list = raw.map((f) => Fixture.fromJson(f)).toList();
    if (list.isNotEmpty) {
      _cachedFixtures = list;
      _cachedFixturesTs = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.getInstance().then((p) {
        p.setString('cached_fixtures', jsonEncode(raw));
        p.setInt('cached_fixtures_at', _cachedFixturesTs);
      });
    }
    return list;
  }

  Future<List<RoomSummary>> listRooms() async {
    final data = await _get('/api/rooms');
    return ((data['rooms'] ?? []) as List).map((r) => RoomSummary.fromJson(r)).toList();
  }

  Future<RoomView> room(String id) async {
    final data = await _get('/api/rooms/$id');
    return RoomView.fromJson(data['room']);
  }

  Future<String> resolveCode(String code) async {
    final data = await _get('/api/rooms/resolve?code=${Uri.encodeComponent(code)}');
    return data['id'] as String;
  }

  Future<({String roomId, String hostId})> createRoom({
    required String name,
    required String fixtureId,
    required bool draft,
    required bool nextSwing,
    required String hostName,
    String? hostWallet,
    String visibility = 'public',
    String reactionPack = 'classic',
    bool voice = false,
    bool spoilerSafe = false,
  }) async {
    final data = await _post('/api/rooms', {
      'name': name,
      'fixtureId': fixtureId,
      'modes': {'draft': draft, 'nextSwing': nextSwing},
      'hostName': hostName,
      'hostWallet': ?hostWallet,
      'visibility': visibility,
      'reactionPack': reactionPack,
      'voice': voice,
      'spoilerSafe': spoilerSafe,
    });
    return (roomId: data['roomId'] as String, hostId: data['hostId'] as String);
  }

  Future<String> join(String id, String name, {String? walletPubkey}) async {
    final data = await _post('/api/rooms/$id/join', {
      'name': name,
      'walletPubkey': ?walletPubkey,
    });
    return data['memberId'] as String;
  }

  Future<void> pickSide(String id, String memberId, String side) =>
      _post('/api/rooms/$id/side', {'memberId': memberId, 'side': side});

  Future<void> start(String id, String memberId) =>
      _post('/api/rooms/$id/start', {'memberId': memberId});

  Future<void> predict(String id, String memberId, String promptId, String optionKey) =>
      _post('/api/rooms/$id/predict', {'memberId': memberId, 'promptId': promptId, 'optionKey': optionKey});

  Future<void> chat(String id, String memberId, String text, {String kind = 'chat'}) =>
      _post('/api/rooms/$id/chat', {'memberId': memberId, 'text': text, 'kind': kind});

  Future<Map<String, dynamic>> proof(String id) async =>
      (await _get('/api/rooms/$id/proof')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> anchor(String id) async =>
      (await _post('/api/rooms/$id/proof', {})) as Map<String, dynamic>;

  /// Anchor an arbitrary on-device Merkle root (solo rooms have no server room).
  Future<Map<String, dynamic>> anchorRoot(String root, {String? tag}) async =>
      (await _post('/api/anchor', {'root': root, if (tag != null) 'tag': tag})) as Map<String, dynamic>;
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
