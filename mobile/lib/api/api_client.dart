import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'live_data.dart';

class AppConfig {
  final String mode, cluster, anchorCluster;
  final bool anchorConfigured, recapAI, cardEconomy, historicalReplay;
  AppConfig({
    required this.mode,
    required this.cluster,
    required this.anchorCluster,
    required this.anchorConfigured,
    required this.recapAI,
    this.cardEconomy = false,
    this.historicalReplay = false,
  });
  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
    mode: j['mode'] ?? 'simulation',
    cluster: j['cluster'] ?? 'devnet',
    anchorCluster: j['anchorCluster'] ?? 'devnet',
    anchorConfigured: j['anchorConfigured'] ?? false,
    recapAI: j['recapAI'] ?? false,
    cardEconomy: j['cardEconomy'] == true,
    historicalReplay: j['historicalReplay'] == true,
  );
  Map<String, dynamic> toJson() => {
    'mode': mode,
    'cluster': cluster,
    'anchorCluster': anchorCluster,
    'anchorConfigured': anchorConfigured,
    'recapAI': recapAI,
    'cardEconomy': cardEconomy,
    'historicalReplay': historicalReplay,
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
    if (defaultTargetPlatform == TargetPlatform.android)
      return 'http://10.0.2.2:3000';
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
  Duration cachedFixturesAge() => Duration(
    milliseconds: DateTime.now().millisecondsSinceEpoch - _cachedFixturesTs,
  );

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
        _cachedFixtures = ((jsonDecode(fx) as List))
            .map((f) => Fixture.fromJson(f))
            .toList();
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

  Future<dynamic> _get(
    String path, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final res = await _http.get(_uri(path)).timeout(timeout);
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 400) {
      throw ApiException(
        data is Map ? (data['error'] ?? 'Request failed') : 'Request failed',
      );
    }
    return data;
  }

  Future<dynamic> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final res = await _http
        .post(
          _uri(path),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 400) {
      throw ApiException(
        data is Map ? (data['error'] ?? 'Request failed') : 'Request failed',
      );
    }
    return data;
  }

  Future<dynamic> _delete(
    String path, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final res = await _http.delete(_uri(path)).timeout(timeout);
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 400) {
      throw ApiException(
        data is Map ? (data['error'] ?? 'Request failed') : 'Request failed',
      );
    }
    return data;
  }

  Future<AppConfig> config() async {
    final c = AppConfig.fromJson(
      await _get('/api/config', timeout: const Duration(seconds: 3)),
    );
    cachedConfig = c;
    SharedPreferences.getInstance().then(
      (p) => p.setString('cached_config', jsonEncode(c.toJson())),
    );
    return c;
  }

  Future<List<Fixture>> fixtures() async {
    final data = await _get(
      '/api/fixtures',
      timeout: const Duration(seconds: 25),
    );
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
    return ((data['rooms'] ?? []) as List)
        .map((r) => RoomSummary.fromJson(r))
        .toList();
  }

  Future<RoomView> room(String id) async {
    final data = await _get('/api/rooms/$id');
    return RoomView.fromJson(data['room']);
  }

  Future<String> join(String id, String name, {String? walletPubkey}) async {
    final data = await _post('/api/rooms/$id/join', {
      'name': name,
      'walletPubkey': ?walletPubkey,
    });
    return data['memberId'] as String;
  }

  Future<({String roomId, String memberId})> watchFixture(
    String fixtureId,
    String name, {
    String? walletPubkey,
  }) async {
    final data = await _post(
      '/api/fixtures/${Uri.encodeComponent(fixtureId)}/watch',
      {'name': name, 'walletPubkey': ?walletPubkey},
    );
    return (
      roomId: data['roomId'] as String,
      memberId: data['memberId'] as String,
    );
  }

  Future<MatchData> matchData(String fixtureId) async {
    final data = await _get(
      '/api/fixtures/${Uri.encodeComponent(fixtureId)}/match-data',
      timeout: const Duration(seconds: 25),
    );
    return MatchData.fromJson(Map<String, dynamic>.from(data['match']));
  }

  Future<TeamTournamentData> teamData(String teamId) async {
    final data = await _get(
      '/api/teams/${Uri.encodeComponent(teamId)}',
      timeout: const Duration(seconds: 25),
    );
    return TeamTournamentData.fromJson(Map<String, dynamic>.from(data['team']));
  }

  Future<TournamentLeadersData> tournamentLeaders() async =>
      TournamentLeadersData.fromJson(
        Map<String, dynamic>.from(
          await _get(
            '/api/tournament/leaders',
            timeout: const Duration(seconds: 30),
          ),
        ),
      );

  Future<void> pickSide(String id, String memberId, String side) =>
      _post('/api/rooms/$id/side', {'memberId': memberId, 'side': side});

  Future<void> start(String id, String memberId) =>
      _post('/api/rooms/$id/start', {'memberId': memberId});

  Future<void> predict(
    String id,
    String memberId,
    String promptId,
    String optionKey,
  ) => _post('/api/rooms/$id/predict', {
    'memberId': memberId,
    'promptId': promptId,
    'optionKey': optionKey,
  });

  Future<void> chat(
    String id,
    String memberId,
    String text, {
    String kind = 'chat',
  }) => _post('/api/rooms/$id/chat', {
    'memberId': memberId,
    'text': text,
    'kind': kind,
  });

  Future<Map<String, dynamic>> proof(String id) async =>
      (await _get('/api/rooms/$id/proof')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> anchor(String id) async =>
      (await _post('/api/rooms/$id/proof', {})) as Map<String, dynamic>;

  /// Anchor an arbitrary on-device Merkle root (solo rooms have no server room).
  Future<Map<String, dynamic>> anchorRoot(String root, {String? tag}) async =>
      (await _post('/api/anchor', {'root': root, if (tag != null) 'tag': tag}))
          as Map<String, dynamic>;

  // ── Card Economy ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> inventory(String fanId) async =>
      (await _get('/api/inventory?fanId=${Uri.encodeComponent(fanId)}'))
          as Map<String, dynamic>;

  /// Fill empty inventory with demo Moments / Packs / Players for Album testing.
  Future<Map<String, dynamic>> seedInventory(String fanId) async =>
      (await _post('/api/inventory/seed', {'fanId': fanId}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> openPack(String fanId, String packId) async =>
      (await _post('/api/packs/open', {'fanId': fanId, 'packId': packId}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> craft(
    String fanId,
    List<String> momentIds,
  ) async =>
      (await _post('/api/craft', {'fanId': fanId, 'momentIds': momentIds}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> momentDetail(String id) async =>
      (await _get('/api/moments/$id')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> createDuel({
    required String fanId,
    required List<String> hand,
    bool vsBot = true,
  }) async =>
      (await _post('/api/duels', {
            'action': 'create',
            'fanId': fanId,
            'hand': hand,
            'vsBot': vsBot,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> createArena({
    required String fanId,
    required String seedMomentId,
    required List<String> hand,
  }) async =>
      (await _post('/api/duels', {
            'action': 'arena',
            'fanId': fanId,
            'seedMomentId': seedMomentId,
            'hand': hand,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> playDuelRound({
    required String duelId,
    required String fanId,
    required String axis,
    required String cardId,
    String? skillId,
  }) async =>
      (await _post('/api/duels/$duelId', {
            'fanId': fanId,
            'axis': axis,
            'cardId': cardId,
            if (skillId != null) 'skillId': skillId,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> getDuel(String id) async =>
      (await _get('/api/duels/$id')) as Map<String, dynamic>;

  // ---- platform economy (Fan Credits, Pass, Market, Shop, Mint, HQ) ----

  Future<Map<String, dynamic>> platformWallet(String fanId) async =>
      (await _get('/api/platform/wallet?fanId=${Uri.encodeComponent(fanId)}'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> platformHq() async =>
      (await _get('/api/platform/hq')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> passState(String fanId) async =>
      (await _get('/api/pass?fanId=${Uri.encodeComponent(fanId)}'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> passClaim(
    String fanId,
    int tier,
    String lane,
  ) async =>
      (await _post('/api/pass/claim', {
            'fanId': fanId,
            'tier': tier,
            'lane': lane,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> passUnlock(String fanId) async =>
      (await _post('/api/pass/unlock', {'fanId': fanId}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> marketBrowse(String fanId) async =>
      (await _get('/api/market?fanId=${Uri.encodeComponent(fanId)}'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> marketList(
    String fanId,
    String sellerName,
    String cardId,
    int priceFC,
  ) async =>
      (await _post('/api/market', {
            'fanId': fanId,
            'sellerName': sellerName,
            'cardId': cardId,
            'priceFC': priceFC,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> marketBuy(
    String fanId,
    String name,
    String listingId,
  ) async =>
      (await _post('/api/market/buy', {
            'fanId': fanId,
            'name': name,
            'listingId': listingId,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> marketCancel(
    String fanId,
    String listingId,
  ) async =>
      (await _delete(
            '/api/market?fanId=${Uri.encodeComponent(fanId)}&listingId=${Uri.encodeComponent(listingId)}',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> shopTiers() async =>
      (await _get('/api/shop')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> shopBuy(String fanId, String tierId) async =>
      (await _post('/api/shop', {'fanId': fanId, 'tierId': tierId}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> mintCard(String fanId, String cardId) async =>
      (await _post('/api/mint', {'fanId': fanId, 'cardId': cardId}))
          as Map<String, dynamic>;
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
