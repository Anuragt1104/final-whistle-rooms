import 'dart:async';
import 'dart:ui' as ui;
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/cards.dart';
import '../api/models.dart';
import '../data/flags.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../state/push_service.dart';
import '../local/fixtures.dart';
import '../local/live_engine.dart';
import '../local/squads.dart';
import '../local/tournament.dart';
import '../solana/wallet_connect.dart';
import '../theme.dart';
import '../widgets/app_header.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common.dart';
import '../widgets/season_pass_sheet.dart';
import '../widgets/ticket.dart';
import '../widgets/tournament_pulse.dart';
import '../widgets/gyro_card.dart';
import 'match_screen.dart';
import 'room_screen.dart';
import 'team_sheet.dart';
import 'album_screen.dart';
import 'duel_screen.dart';
import 'pass_screen.dart';
import 'settings_screen.dart';
import 'leaders_screen.dart';
import '../widgets/player_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiClient.instance;
  AppConfig? _config;
  List<Fixture> _fixtures = [];
  List<RoomSummary> _rooms = [];
  Identity? _identity;
  String _name = '';
  String _walletAddr = '';
  String _nav = 'rooms';
  String _fxSeg = 'matches'; // fixtures hub: matches | groups | bracket | stats
  bool _loading = true;
  bool _pro = false;
  String? _connectingFixture; // fixture id being resolved live-vs-replay
  // fan stats (profile)
  int _streakBest = 0;
  int _matchesWatched = 0;
  int _callsMade = 0;
  int _callsCorrect = 0;
  String _favTeam = '';
  List<Fixture> _apiFixtures =
      []; // real backend feed (live mode) — live strip + watch flow
  bool _fixturesOffline = false;
  Timer? _poll;
  int _fcCredits = 0;
  int _passTier = 0;
  int _passXp = 0;
  int _unopenedPacks = 0;
  int _playerCardCount = 0;
  List<PlayerCardModel> _inventoryPlayers = [];
  List<MomentCard> _inventoryMoments = [];
  List<SkillCardModel> _inventorySkills = [];
  List<PlayerCardModel> _showcasePlayers = [];
  final GlobalKey _profileShareKey = GlobalKey();
  final CardMotionController _profileMotion = CardMotionController();

  @override
  void initState() {
    super.initState();
    PushService.instance.pendingFixtureId.addListener(_openPendingPushFixture);
    PushService.instance.pendingDuelId.addListener(_openPendingDuel);
    _listenDuelDeepLinks();
    _boot();
  }

  Future<void> _openPendingPushFixture() async {
    final fixtureId = PushService.instance.pendingFixtureId.value;
    if (fixtureId == null || fixtureId.isEmpty || !mounted) return;
    PushService.instance.consumePendingFixture();
    var fixture = _apiFixtures.where((f) => f.id == fixtureId).firstOrNull;
    if (fixture == null) {
      await _refreshFixturesQuiet();
      fixture = _apiFixtures.where((f) => f.id == fixtureId).firstOrNull;
    }
    if (fixture != null && mounted) await _watchLive(fixture);
  }

  Future<void> _openPendingDuel() async {
    final duelId = PushService.instance.pendingDuelId.value;
    if (duelId == null || duelId.isEmpty || !mounted) return;
    PushService.instance.consumePendingDuel();
    await _openDuel(resumeDuelId: duelId);
  }

  Future<void> _listenDuelDeepLinks() async {
    try {
      final appLinks = AppLinks();
      final initial = await appLinks.getInitialLink();
      _handleDuelUri(initial);
      appLinks.uriLinkStream.listen(_handleDuelUri);
    } catch (_) {}
  }

  void _handleDuelUri(Uri? uri) {
    if (uri == null) return;
    if (uri.scheme != 'finalwhistle' || uri.host != 'duels') return;
    final duelId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (duelId.isEmpty) return;
    PushService.instance.pendingDuelId.value = duelId;
  }

  Future<void> _boot() async {
    // Paint instantly from what we already know: last-seen config + fixtures
    // (or the complete on-device dataset). Network is only a revalidation.
    _config = _api.cachedConfig;
    final cached = _api.cachedFixtures();
    _fixtures = _pickFixtures(cached ?? const []);
    // Only trust a cached feed's "live" statuses when it's fresh — a stale
    // cache must not flash a dead live match at boot and then vanish.
    if (cached != null &&
        _api.cachedFixturesAge() < const Duration(minutes: 10)) {
      _apiFixtures = cached;
    }
    _loading = false;
    if (mounted) setState(() {});

    final prefs = await Future.wait([
      IdentityStore.getOrCreate(),
      LocalStore.displayName(),
      LocalStore.walletAddress(),
      LocalStore.isPro(),
    ]);
    _identity = prefs[0] as Identity;
    _name = prefs[1] as String;
    _walletAddr = prefs[2] as String;
    _pro = prefs[3] as bool;
    if (mounted) setState(() {});
    _loadFanStats();

    _api
        .config()
        .then((c) => mounted ? setState(() => _config = c) : null)
        .catchError((_) {});
    _refresh(); // revalidate fixtures + rooms in the background
    // poll rooms every 5s; refresh the live fixtures (scores/minutes/status)
    // every ~12s so the home updates without a manual pull-to-refresh
    _poll = Timer.periodic(const Duration(seconds: 4), (t) {
      _loadRooms();
      if (t.tick % 3 == 0) _refreshFixturesQuiet();
    });
  }

  /// Prefer any non-empty API response for status/upcoming/finished.
  /// Local 104-match demo data is offline/simulation fallback only.
  List<Fixture> _pickFixtures(List<Fixture> fromApi) {
    if (fromApi.isNotEmpty) return fromApi;
    return localFixtures();
  }

  /// Home Live / Soon / Next / pulse: API feed whenever we have it.
  List<Fixture> get _stripFixtures {
    if (_apiFixtures.isNotEmpty) return _apiFixtures;
    return _fixtures;
  }

  /// Pulse uses the same source as Matchday strips so progress matches reality.
  List<Fixture> get _pulseFixtures => _stripFixtures;

  /// Matches that are genuinely live right now. In live mode that's the real
  /// feed; in replay mode the on-device schedule.
  List<Fixture> get _liveNow =>
      _stripFixtures.where((f) => f.status == 'live').toList();

  List<Fixture> get _finishedReplay => _stripFixtures
      .where(
        (f) =>
            f.status == 'finished' &&
            f.home.code != 'TBD' &&
            f.away.code != 'TBD',
      )
      .toList();

  Future<void> _refreshFixturesQuiet() async {
    try {
      final f = await _api.fixtures();
      if (f.isNotEmpty && mounted) {
        setState(() {
          _fixturesOffline = false;
          _apiFixtures = f;
          _fixtures = _pickFixtures(f);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _fixturesOffline = true);
    }
  }

  Future<void> _loadFanStats() async {
    final v = await Future.wait([
      LocalStore.streakBest(),
      LocalStore.matchesWatched(),
      LocalStore.callsMade(),
      LocalStore.callsCorrect(),
      LocalStore.favoriteTeam(),
    ]);
    if (!mounted) return;
    setState(() {
      _streakBest = v[0] as int;
      _matchesWatched = v[1] as int;
      _callsMade = v[2] as int;
      _callsCorrect = v[3] as int;
      _favTeam = v[4] as String;
    });
    // Platform FC + World Cup Pass + inventory CTAs (best-effort)
    try {
      final id = await IdentityStore.getOrCreate();
      final w = await _api.platformWallet(id.pubkey);
      final inventory = FanInventory.fromJson(await _api.inventory(id.pubkey));
      final pinned = await LocalStore.pinnedCards();
      final showcase = <PlayerCardModel>[];
      for (final cardId in pinned) {
        for (final player in inventory.players) {
          if (player.id == cardId) showcase.add(player);
        }
      }
      final wallet = w['wallet'];
      final pass = w['pass'];
      final unopened = inventory.packs.where((p) => !p.opened).length;
      if (!mounted) return;
      setState(() {
        if (wallet is Map && wallet['credits'] is num)
          _fcCredits = (wallet['credits'] as num).toInt();
        if (pass is Map) {
          if (pass['tier'] is num) _passTier = (pass['tier'] as num).toInt();
          if (pass['xp'] is num) _passXp = (pass['xp'] as num).toInt();
        }
        _unopenedPacks = unopened;
        _playerCardCount = inventory.players.length;
        _inventoryPlayers = inventory.players;
        _inventoryMoments = inventory.moments;
        _inventorySkills = inventory.skills;
        _showcasePlayers = showcase.take(3).toList();
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    // Always have matches to show: use the server when reachable, fall back to
    // the on-device fixture list so the app is never empty.
    try {
      final f = await _api.fixtures();
      _fixturesOffline = false;
      _apiFixtures = f;
      _fixtures = _pickFixtures(f);
    } catch (_) {
      _fixturesOffline = true;
      if (_config?.mode != 'live') _fixtures = localFixtures();
    }
    await Future.wait([_loadRooms(), _loadFanStats()]);
    if (mounted) setState(() {});
  }

  Future<void> _loadRooms() async {
    try {
      final r = await _api.listRooms();
      if (mounted) setState(() => _rooms = r);
    } catch (_) {
      // no backend — solo "watch live" still works from local fixtures
    }
  }

  /// Watch a match live or replay a finished fixture through the backend.
  /// Finished fixtures in live mode use TxLINE historical pacing so Moments mint.
  Future<void> _watchLive(Fixture f) async {
    if (f.home.code == 'TBD' || f.away.code == 'TBD') {
      _openMatch(f);
      return;
    }
    var cfg = _config;
    if (cfg == null) {
      if (mounted) {
        setState(() => _connectingFixture = f.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connecting to the live feed…'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      cfg = await _api.resolveConfig();
      if (mounted) {
        setState(() {
          _connectingFixture = null;
          _config = cfg ?? _config;
        });
      }
    }
    // Prefer TxLINE id when the home strip knows this pairing (local knockout
    // phantoms must not open offline rooms that never mint Moments).
    Fixture? apiMatch;
    for (final x in _apiFixtures) {
      if (x.id == f.id ||
          (x.home.code == f.home.code && x.away.code == f.away.code)) {
        apiMatch = x;
        break;
      }
    }
    final fixtureId = apiMatch?.id ?? f.id;
    final status = apiMatch?.status ?? f.status;
    final backendKnowsFixture = apiMatch != null;
    // Every fixture — live or finished replay — has exactly one concurrency-safe
    // global Official Hub the whole crowd shares. Scheduled fixtures never
    // silently become a DEMO REPLAY.
    if (cfg?.mode == 'live' && backendKnowsFixture) {
      try {
        final id = await IdentityStore.getOrCreate();
        final isReplay = status == 'finished';
        final res = await _api.watchFixture(
          fixtureId,
          _name.isEmpty ? 'Fan' : _name,
          walletPubkey: id.pubkey,
        );
        final roomId = res.roomId;
        await LocalStore.setMemberId(roomId, res.memberId);
        await PushService.instance.watchFixture(fixtureId);
        if (!mounted) return;
        final result = await Navigator.push(
          context,
          fwrRoute(RoomScreen(roomId: roomId)),
        );
        if (!mounted) return;
        if (isReplay || result == 'finished') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Correct calls earn Moment Cards — open Album',
              ),
              action: SnackBarAction(
                label: 'Album',
                onPressed: () => setState(() => _nav = 'cards'),
              ),
            ),
          );
        }
        return;
      } catch (_) {
        if (mounted) _showLiveUnavailableSheet(f);
        return;
      }
    }
    _openReplayRoom(f);
  }

  /// Live builds never silently substitute simulated coverage.
  void _showLiveUnavailableSheet(Fixture f) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('LIVE FEED UNAVAILABLE', style: display(19)),
            const SizedBox(height: 6),
            Text(
              'The verified TxLINE feed for ${f.home.code} v ${f.away.code} is not responding. Your app will not replace it with simulated match data.',
              style: body(color: AppColors.mut, size: 13),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              'Retry live',
              icon: Icons.podcasts_rounded,
              onTap: () {
                Navigator.pop(ctx);
                _watchLive(f);
              },
            ),
            const SizedBox(height: 8),
            GhostButton('Close', expand: true, onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  /// On-device room — clearly a REPLAY, seeded from the fixture's real score
  /// so it starts where reality is instead of contradicting the home card.
  /// Scheduled fixtures never auto-start (use Match Center / KO soon instead).
  void _openReplayRoom(Fixture f) {
    if (f.status == 'scheduled') {
      _openMatch(f);
      return;
    }
    final engine = LiveMatchEngine(
      f,
      draftMode: true,
      nextSwingMode: true,
      myName: _name.isEmpty ? 'You' : _name,
      seedScore: f.score,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      fwrRoute(RoomScreen(roomId: 'local', engine: engine, autoStart: true)),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    PushService.instance.pendingFixtureId.removeListener(
      _openPendingPushFixture,
    );
    PushService.instance.pendingDuelId.removeListener(_openPendingDuel);
    _profileMotion.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final n = await showNameDialog(context, initial: _name);
    if (n == null) return;
    _identity = await IdentityStore.getOrCreate();
    await IdentityStore.sign(
      'final-whistle-rooms:auth:$n:${_identity!.pubkey}',
    );
    await LocalStore.setDisplayName(n);
    setState(() => _name = n);
  }

  Future<void> _connectWallet() async {
    if (!await WalletConnect.isAvailable()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No Solana wallet app detected (Phantom/Solflare). Android only.',
            ),
          ),
        );
      }
      return;
    }
    try {
      final res = await WalletConnect.connect();
      if (res != null) {
        await LocalStore.setWalletAddress(res.pubkey);
        if (mounted) setState(() => _walletAddr = res.pubkey);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wallet connection failed')),
        );
      }
    }
  }

  void _openRoom(String id) => Navigator.push(
    context,
    fwrRoute(RoomScreen(roomId: id)),
  ).then((_) => _refresh());

  /// FotMob-style match centre: stats, line-ups, tables, H2H for any fixture.
  void _openMatch(Fixture f) => Navigator.push(
    context,
    fwrRoute(
      MatchScreen(
        fixture: f,
        onWatch: f.home.code == 'TBD' || f.away.code == 'TBD'
            ? null
            : () => _watchLive(f),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: Column(
          children: [
            FwrHeader(
              trailing: GestureDetector(
                onTap: () => setState(() => _nav = 'you'),
                child: InitialAvatar(
                  name: _name.isEmpty ? 'You' : _name,
                  size: 38,
                ),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
        bottomNavigationBar: BottomNav(
          active: _nav,
          onSelect: (k) {
            setState(() => _nav = k);
            if (k == 'you') _loadFanStats(); // counters move while watching
          },
        ),
      ),
    );
  }

  Widget _body() {
    switch (_nav) {
      case 'fixtures':
        return _fixturesTab();
      case 'inbox':
      case 'cards':
        return const AlbumScreen();
      case 'you':
        return _youTab();
      default:
        return _roomsTab();
    }
  }

  // ---- ROOMS (Matchday home hub) ----
  Widget _roomsTab() {
    final liveFixtures = _liveNow;
    final strip = _stripFixtures;
    final upcomingAll = strip.where((f) => f.status == 'scheduled').toList()
      ..sort(
        (a, b) => minutesUntilKickoff(
          a.kickoff,
        ).compareTo(minutesUntilKickoff(b.kickoff)),
      );
    // your team plays? their match jumps the queue
    if (_favTeam.isNotEmpty) {
      upcomingAll.sort((a, b) {
        final af = a.home.code == _favTeam || a.away.code == _favTeam ? 0 : 1;
        final bf = b.home.code == _favTeam || b.away.code == _favTeam ? 0 : 1;
        if (af != bf) return af - bf;
        return minutesUntilKickoff(
          a.kickoff,
        ).compareTo(minutesUntilKickoff(b.kickoff));
      });
    }
    // Next 7 days when available; otherwise the next 4 upcoming.
    final week = upcomingAll
        .where((f) => minutesUntilKickoff(f.kickoff) <= 7 * 24 * 60)
        .toList();
    final shownUpcoming = week.isNotEmpty ? week : upcomingAll.take(4).toList();
    final finished = _finishedReplay.reversed.take(2).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _homeStatusRow(),
          const SizedBox(height: 14),
          Row(
            children: [
              const LiveDot(),
              const SizedBox(width: 6),
              Text(
                liveFixtures.isEmpty
                    ? 'LIVE NOW'
                    : 'LIVE NOW · ${liveFixtures.length} ${liveFixtures.length == 1 ? "match" : "matches"}',
                style: label(
                  color: AppColors.ink,
                  size: 12.5,
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            _skeleton()
          else if (liveFixtures.isEmpty)
            _noLiveCard(upcomingAll.isNotEmpty ? upcomingAll.first : null)
          else
            ...liveFixtures.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _liveMatchCard(f),
              ),
            ),
          const SizedBox(height: 16),
          _homePlayStrip(),
          const SizedBox(height: 22),
          SectionLabel(
            week.isNotEmpty ? 'Upcoming' : 'Next up',
            trailing: upcomingAll.length > shownUpcoming.length
                ? GestureDetector(
                    onTap: () => setState(() => _nav = 'fixtures'),
                    child: Text(
                      'See all ${upcomingAll.length} →',
                      style: label(
                        color: AppColors.orange,
                        size: 11,
                        weight: FontWeight.w800,
                      ),
                    ),
                  )
                : Text(
                    '${shownUpcoming.length} matches',
                    style: label(color: AppColors.mut, size: 10.5),
                  ),
          ),
          if (_loading)
            ...[0, 1].map((_) => _skeleton())
          else if (upcomingAll.isEmpty)
            Text(
              'No upcoming matches in range.',
              style: body(color: AppColors.mut, size: 13),
            )
          else ...[
            if (week.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Nothing kicks off in the next 7 days — here\'s what\'s next.',
                  style: body(color: AppColors.mut, size: 12),
                ),
              ),
            ...shownUpcoming.map(_fixtureRow),
          ],
          ..._openRoomsSection(),
          const SizedBox(height: 18),
          TournamentPulse(fixtures: _pulseFixtures),
          if (finished.isNotEmpty) ...[
            const SizedBox(height: 22),
            SectionLabel(
              'Recent results',
              trailing: GestureDetector(
                onTap: () => setState(() {
                  _nav = 'fixtures';
                  _fxSeg = 'results';
                }),
                child: Text(
                  'All results →',
                  style: label(
                    color: AppColors.orange,
                    size: 11,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Replay finished matches to mint Moments.',
                style: body(color: AppColors.mut, size: 12),
              ),
            ),
            ...finished.map(_fixtureRow),
          ],
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Powered by TxLINE · sign-in with Solana · points only, no cash staking',
              textAlign: TextAlign.center,
              style: body(color: AppColors.mut, size: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeStatusRow() {
    return Pressable(
      haptic: HapticFeedbackType.selection,
      onTap: () => Navigator.push(
        context,
        fwrRoute(const PassScreen()),
      ).then((_) => _loadFanStats()),
      child: Container(
        decoration: cardBox(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(child: _homeStatChip('$_fcCredits', 'FC')),
            Container(width: 1, height: 28, color: AppColors.line),
            Expanded(child: _homeStatChip('T$_passTier', 'PASS')),
            Container(width: 1, height: 28, color: AppColors.line),
            Expanded(
              child: _homeStatChip(
                _streakBest > 0 ? '$_streakBest' : '—',
                'STREAK',
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.mut,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _homeStatChip(String value, String label_) => Column(
    children: [
      Text(value, style: display(16, color: AppColors.orange)),
      const SizedBox(height: 2),
      Text(label_, style: label(color: AppColors.mut, size: 8)),
    ],
  );

  Widget _homePlayStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Play'),
        Row(
          children: [
            Expanded(
              child: _playTile(
                icon: Icons.inventory_2_outlined,
                title: 'Packs',
                subtitle: _unopenedPacks > 0
                    ? '$_unopenedPacks unopened'
                    : 'Open album',
                badge: _unopenedPacks > 0 ? '$_unopenedPacks' : null,
                onTap: () => setState(() => _nav = 'cards'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _playTile(
                icon: Icons.sports_kabaddi_rounded,
                title: 'Duels',
                subtitle: _playerCardCount >= 3
                    ? 'Enter stadium'
                    : 'Need 3 cards',
                onTap: _openHomeDuel,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _playTile(
                icon: Icons.style_outlined,
                title: 'Album',
                subtitle: '$_playerCardCount cards',
                onTap: () => setState(() => _nav = 'cards'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _playTile(
                icon: Icons.confirmation_number_outlined,
                title: 'Pass',
                subtitle: '$_passXp XP',
                onTap: () => Navigator.push(
                  context,
                  fwrRoute(const PassScreen()),
                ).then((_) => _loadFanStats()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _playTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Pressable(
      haptic: HapticFeedbackType.selection,
      onTap: onTap,
      child: Container(
        decoration: cardBox(),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: AppColors.cream, size: 18),
                ),
                if (badge != null)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        badge,
                        style: label(
                          color: Colors.white,
                          size: 8,
                          weight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: label(
                color: AppColors.ink,
                size: 10,
                weight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: body(color: AppColors.mut, size: 10),
            ),
          ],
        ),
      ),
    );
  }

  void _openHomeDuel() => _openDuel();

  Future<void> _openDuel({String? resumeDuelId}) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      fwrRoute(
        DuelScreen(
          players: _inventoryPlayers,
          moments: _inventoryMoments,
          skills: _inventorySkills,
          resumeDuelId: resumeDuelId,
          initialSetupMode: 2, // Moment Arena
        ),
      ),
    );
    await _loadFanStats();
  }

  /// Official Match Hubs — the one global room per fixture everyone shares.
  List<Widget> _openRoomsSection() {
    final open = _rooms.where((r) => r.status != 'finished').toList()
      ..sort((a, b) => b.memberCount.compareTo(a.memberCount));
    if (open.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      SectionLabel(
        'Official Match Hubs',
        trailing: Text(
          '${open.length} available',
          style: label(color: AppColors.mut, size: 10.5),
        ),
      ),
      ...open.take(6).map(_roomRow),
    ];
  }

  Widget _roomRow(RoomSummary r) {
    final live =
        r.fixture.status == 'live' &&
        (r.score?.phase ?? 0) > 0 &&
        (r.score?.running ?? false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        haptic: HapticFeedbackType.medium,
        onTap: () => _openRoom(r.id),
        child: Container(
          decoration: cardBox(),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  live ? '⚡' : '🕐',
                  style: const TextStyle(fontSize: 19),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.kind == 'official'
                          ? 'Official ${r.fixture.home.code} v ${r.fixture.away.code}'
                          : r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(weight: FontWeight.w800, size: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.fixture.home.code} v ${r.fixture.away.code}'
                      '${r.score != null ? " · ${r.score!.goals.home}–${r.score!.goals.away}" : ""}'
                      ' · ${r.memberCount} ${r.memberCount == 1 ? "fan" : "fans"} in',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(color: AppColors.mut, size: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: live ? AppColors.orange : AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(99),
                  border: live ? null : Border.all(color: AppColors.line),
                ),
                child: Text(
                  live ? 'LIVE' : 'KO SOON',
                  style: label(
                    color: live ? Colors.white : AppColors.mut,
                    size: 9.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Honest empty state when nothing is in play — never a future match dressed
  /// up as "LIVE".
  Widget _noLiveCard(Fixture? next) {
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          const Icon(Icons.sports_soccer, color: AppColors.mut, size: 30),
          const SizedBox(height: 10),
          Text('No matches live right now', style: display(18)),
          const SizedBox(height: 4),
          Text(
            next != null
                ? 'Next up · ${next.home.name} vs ${next.away.name} · ${relativeKickoff(next.kickoff)}'
                : 'Check back at kick-off — live matches show here.',
            textAlign: TextAlign.center,
            style: body(color: AppColors.mut, size: 12.5),
          ),
        ],
      ),
    );
  }

  /// A live match as a rich card — real score, minute, watcher count, Watch CTA.
  Widget _liveMatchCard(Fixture f) {
    RoomSummary? room;
    for (final r in _rooms) {
      if (r.fixture.id == f.id) {
        room = r;
        break;
      }
    }
    return Pressable(
      haptic: HapticFeedbackType.medium,
      onTap: () => _watchLive(f),
      child: Container(
        decoration: cardBox(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            TicketScoreboard(
              home: f.home,
              away: f.away,
              league: f.stage,
              score: f.score != null
                  ? '${f.score!.home} - ${f.score!.away}'
                  : null,
              minute: f.score != null ? "${f.score!.minute}'" : 'LIVE',
              clockSeconds: f.score?.clockSeconds,
              clockRunning: f.score?.running ?? false,
              pill: _config?.mode == 'live' ? 'LIVE' : 'REPLAY',
              watching: room?.memberCount,
              onTeamTap: (t) => showTeamSheet(context, t),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${f.home.name} vs ${f.away.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: display(16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          room != null
                              ? '${room.memberCount} watching · Official Match Hub'
                              : 'Join the Official Match Hub · Live Calls & chat',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: body(color: AppColors.mut, size: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Pressable(
                    haptic: HapticFeedbackType.selection,
                    onTap: () => _openMatch(f),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.cardAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Icon(
                        Icons.bar_chart_rounded,
                        color: AppColors.ink,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PrimaryButton(
                    _connectingFixture == f.id
                        ? 'Connecting…'
                        : (room != null ? 'Join Hub' : 'Watch'),
                    icon: _connectingFixture == f.id
                        ? Icons.wifi_tethering_rounded
                        : Icons.play_arrow_rounded,
                    onTap: _connectingFixture == null
                        ? () => _watchLive(f)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fixtureRow(Fixture f) {
    final tbd = f.home.code == 'TBD' || f.away.code == 'TBD';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        onTap: () => _openMatch(f),
        child: Container(
          decoration: cardBox(),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              MiniScore(top: _fxTop(f), bottom: _fxBottom(f)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (!tbd) ...[
                          GestureDetector(
                            onTap: () => showTeamSheet(context, f.home),
                            child: InlineFlag(team: f.home, size: 28),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            f.home.code,
                            style: body(weight: FontWeight.w800, size: 14),
                          ),
                          Text('  v  ', style: body(color: AppColors.mut)),
                          Text(
                            f.away.code,
                            style: body(weight: FontWeight.w800, size: 14),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => showTeamSheet(context, f.away),
                            child: InlineFlag(team: f.away, size: 28),
                          ),
                        ] else
                          Flexible(
                            child: Text(
                              '${f.home.name}  v  ${f.away.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: body(weight: FontWeight.w800, size: 12.5),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _fxSubtitle(f),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(color: AppColors.mut, size: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!tbd) ...[
                if (f.status == 'finished') ...[
                  Pressable(
                    haptic: HapticFeedbackType.selection,
                    onTap: () => _openMatch(f),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.cardAlt,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Icon(
                        Icons.bar_chart_rounded,
                        color: AppColors.ink,
                        size: 19,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Pressable(
                    haptic: HapticFeedbackType.medium,
                    onTap: () => _watchLive(f),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33E9531E),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.replay_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ] else if (f.status == 'live') ...[
                  Pressable(
                    haptic: HapticFeedbackType.medium,
                    onTap: () => _watchLive(f),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33E9531E),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ] else ...[
                  // Upcoming — Match Center only (never auto-start DEMO REPLAY)
                  Pressable(
                    haptic: HapticFeedbackType.selection,
                    onTap: () => _openMatch(f),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.cardAlt,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Icon(
                        Icons.schedule_rounded,
                        color: AppColors.ink,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---- FIXTURES / COMPETITION HUB ----
  Widget _fixturesTab() {
    final liveMode = _config?.mode == 'live';
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              Expanded(child: Text('WORLD CUP 2026', style: display(26))),
              if (liveMode)
                TextButton.icon(
                  onPressed: () =>
                      Navigator.push(context, fwrRoute(const LeadersScreen())),
                  icon: const Icon(Icons.emoji_events_outlined, size: 18),
                  label: const Text('Leaders'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            liveMode
                ? '${_fixtures.length} real TxLINE fixtures · completed, live & upcoming.'
                : 'Demo tournament · replay data.',
            style: body(color: AppColors.mut, size: 13),
          ),
          if (_fixturesOffline) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4DB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0A33C)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: Color(0xFF9A6700),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fixtures.isEmpty
                          ? 'Live fixtures unavailable. Pull to retry.'
                          : 'Offline — showing the last real TxLINE update.',
                      style: body(
                        size: 12,
                        color: const Color(0xFF795000),
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _hubSegments(),
          const SizedBox(height: 14),
          ...(liveMode
              ? _matchesView(filter: _fxSeg)
              : switch (_fxSeg) {
                  'groups' => _groupsView(),
                  'bracket' => _bracketView(),
                  'stats' => _statsView(),
                  _ => _matchesView(),
                }),
        ],
      ),
    );
  }

  Widget _hubSegments() {
    final segs = _config?.mode == 'live'
        ? const [
            ('matches', 'All'),
            ('live', 'Live'),
            ('results', 'Results'),
            ('upcoming', 'Upcoming'),
          ]
        : const [
            ('matches', 'Matches'),
            ('groups', 'Groups'),
            ('bracket', 'Bracket'),
            ('stats', 'Stats'),
          ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: segs.map(((String, String) s) {
          final on = _fxSeg == s.$1;
          return Expanded(
            child: Pressable(
              haptic: HapticFeedbackType.selection,
              onTap: () => setState(() => _fxSeg = s.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? AppColors.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  s.$2.toUpperCase(),
                  style: label(
                    color: on ? AppColors.cream : AppColors.mut,
                    size: 9.5,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _matchesView({String filter = 'matches'}) {
    final live = _fixtures.where((f) => f.status == 'live').toList();
    final up = _fixtures.where((f) => f.status == 'scheduled').toList()
      ..sort(
        (a, b) => minutesUntilKickoff(
          a.kickoff,
        ).compareTo(minutesUntilKickoff(b.kickoff)),
      );
    final fin = _fixtures
        .where((f) => f.status == 'finished')
        .toList()
        .reversed
        .toList();
    if (filter == 'live') {
      return live.isEmpty
          ? [
              Text(
                'No matches are live right now.',
                style: body(color: AppColors.mut),
              ),
            ]
          : [...live.map(_fixtureRow)];
    }
    if (filter == 'results') {
      return fin.isEmpty
          ? [
              Text(
                'No completed matches yet.',
                style: body(color: AppColors.mut),
              ),
            ]
          : [...fin.map(_fixtureRow)];
    }
    if (filter == 'upcoming') {
      return up.isEmpty
          ? [Text('No upcoming fixtures.', style: body(color: AppColors.mut))]
          : [...up.map(_fixtureRow)];
    }
    return [
      if (live.isNotEmpty) ...[
        const SectionLabel('Live'),
        ...live.map(_fixtureRow),
        const SizedBox(height: 12),
      ],
      if (up.isNotEmpty) ...[
        SectionLabel(
          'Upcoming',
          trailing: Text(
            '${up.length} matches',
            style: label(color: AppColors.mut, size: 10),
          ),
        ),
        ...up.map(_fixtureRow),
        const SizedBox(height: 12),
      ],
      if (fin.isNotEmpty) ...[
        SectionLabel(
          'Results',
          trailing: Text(
            '${fin.length} played',
            style: label(color: AppColors.mut, size: 10),
          ),
        ),
        ...fin.map(_fixtureRow),
      ],
    ];
  }

  List<Widget> _groupsView() {
    final standings = groupStandings(
      _fixtures.where((f) => groupOf(f) != null).toList(),
    );
    final letters = standings.keys.toList()..sort();
    if (letters.isEmpty)
      return [
        Text(
          'Group tables appear when fixtures load.',
          style: body(color: AppColors.mut, size: 13),
        ),
      ];
    return [
      for (final l in letters) ...[
        SectionLabel('Group $l'),
        _groupTableCard(standings[l] ?? []),
        const SizedBox(height: 14),
      ],
    ];
  }

  Widget _groupTableCard(List<StandingRow> rows) => Container(
    decoration: cardBox(),
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 24),
            Expanded(
              child: Text('TEAM', style: label(color: AppColors.mut, size: 8)),
            ),
            for (final text in ['P', 'GD', 'PTS'])
              SizedBox(
                width: 34,
                child: Text(
                  text,
                  textAlign: TextAlign.right,
                  style: label(color: AppColors.mut, size: 8),
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${i + 1}',
                    style: display(
                      12,
                      color: i < 2 ? AppColors.orange : AppColors.mut,
                    ),
                  ),
                ),
                InlineFlag(team: rows[i].team, size: 20),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    rows[i].team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(size: 12, weight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${rows[i].played}',
                    textAlign: TextAlign.right,
                    style: body(size: 11),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${rows[i].gd}',
                    textAlign: TextAlign.right,
                    style: body(size: 11),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${rows[i].pts}',
                    textAlign: TextAlign.right,
                    style: display(12),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  List<Widget> _bracketView() {
    final stages = knockoutByStage(_fixtures);
    final widgets = <Widget>[];
    for (final s in knockoutStages) {
      final ms = stages[s] ?? [];
      if (ms.isEmpty) continue;
      widgets.add(
        SectionLabel(
          s,
          trailing: Text(
            '${ms.length} ${ms.length == 1 ? "tie" : "ties"}',
            style: label(color: AppColors.mut, size: 10),
          ),
        ),
      );
      widgets.addAll(ms.map(_fixtureRow));
      widgets.add(const SizedBox(height: 10));
    }
    if (widgets.isEmpty) {
      widgets.add(
        Text(
          'The knockout bracket appears once the groups finish.',
          style: body(color: AppColors.mut, size: 13),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _statsView() {
    final leaders = tournamentLeaders(_fixtures);
    Widget leaderRow(int rank, PlayerTotals p, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Pressable(
          onTap: () {
            SquadPlayer? sp;
            for (final cand in squadFor(p.team).players) {
              if (cand.name == p.name) sp = cand;
            }
            showPlayerSheet(
              context,
              p.team,
              sp ?? SquadPlayer(0, p.name, 'FW'),
            );
          },
          child: Container(
            decoration: cardBox(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '$rank',
                    style: display(
                      14,
                      color: rank <= 3 ? AppColors.orange : AppColors.mut,
                    ),
                  ),
                ),
                InitialAvatar(name: p.name, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: body(weight: FontWeight.w800, size: 13),
                      ),
                      Row(
                        children: [
                          InlineFlag(team: p.team, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            p.team.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: body(color: AppColors.mut, size: 10.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(value, style: display(17, color: AppColors.orange)),
              ],
            ),
          ),
        ),
      );
    }

    final out = <Widget>[const SectionLabel('Golden Boot')];
    if (leaders.scorers.isEmpty) {
      out.add(
        Text(
          'Goals land here as soon as matches are played.',
          style: body(color: AppColors.mut, size: 13),
        ),
      );
    } else {
      var rank = 0;
      out.addAll(
        leaders.scorers.take(10).map((p) => leaderRow(++rank, p, '${p.goals}')),
      );
    }
    if (leaders.assisters.isNotEmpty) {
      out.add(const SizedBox(height: 12));
      out.add(const SectionLabel('Most assists'));
      var rank = 0;
      out.addAll(
        leaders.assisters
            .take(10)
            .map((p) => leaderRow(++rank, p, '${p.assists}')),
      );
    }
    if (leaders.rated.isNotEmpty) {
      out.add(const SizedBox(height: 12));
      out.add(const SectionLabel('Best rated (2+ games)'));
      var rank = 0;
      out.addAll(
        leaders.rated
            .take(10)
            .map((p) => leaderRow(++rank, p, p.avgRating.toStringAsFixed(1))),
      );
    }
    return out;
  }

  // ---- INBOX ----
  // ignore: unused_element
  Widget _inboxTab() {
    final live = _liveNow;
    final strip = _stripFixtures;
    final up = strip.where((f) => f.status == 'scheduled').toList()
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    final fin = strip.where((f) => f.status == 'finished').toList();
    final hasAny = live.isNotEmpty || up.isNotEmpty || fin.isNotEmpty;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('INBOX', style: display(26)),
          const SizedBox(height: 4),
          Text(
            'Kick-off reminders, live alerts and final whistles.',
            style: body(color: AppColors.mut, size: 13),
          ),
          const SizedBox(height: 16),
          if (!hasAny)
            Container(
              decoration: cardBox(),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.mut,
                    size: 34,
                  ),
                  const SizedBox(height: 10),
                  Text('You\'re all caught up', style: display(18)),
                  const SizedBox(height: 6),
                  Text(
                    'Kick-off reminders and final-whistle recaps will land here.',
                    textAlign: TextAlign.center,
                    style: body(color: AppColors.mut, size: 13),
                  ),
                ],
              ),
            )
          else ...[
            if (live.isNotEmpty) ...[
              const SectionLabel('Live now'),
              ...live.map(
                (f) => _inboxRow(
                  Icons.podcasts_rounded,
                  AppColors.orange,
                  '${f.home.code} v ${f.away.code} is live',
                  f.score != null
                      ? "${f.score!.home}–${f.score!.away} · ${f.score!.minute}' — tap to watch"
                      : 'Tap to watch now',
                  () => _watchLive(f),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (up.isNotEmpty) ...[
              const SectionLabel('Kicking off soon'),
              ...up
                  .take(5)
                  .map(
                    (f) => _inboxRow(
                      Icons.alarm_rounded,
                      AppColors.ink,
                      '${f.home.code} v ${f.away.code}',
                      'Kicks off ${kickoffWhen(f.kickoff)} · ${relativeKickoff(f.kickoff)}',
                      () => _openMatch(f),
                    ),
                  ),
              const SizedBox(height: 12),
            ],
            if (fin.isNotEmpty) ...[
              const SectionLabel('Final whistle'),
              ...fin
                  .take(5)
                  .map(
                    (f) => _inboxRow(
                      Icons.sports_score_rounded,
                      AppColors.mut,
                      'Full time — ${f.home.code} ${f.score?.home ?? 0}–${f.score?.away ?? 0} ${f.away.code}',
                      'Tap for verified events, cards and line-ups',
                      () => _openMatch(f),
                    ),
                  ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _inboxRow(
    IconData icon,
    Color color,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        onTap: onTap,
        child: Container(
          decoration: cardBox(),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(weight: FontWeight.w800, size: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(color: AppColors.mut, size: 11.5),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.mut,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- YOU ----
  Widget _youTab() {
    final connected = _walletAddr.isNotEmpty;
    final favTeam = _favTeam.isEmpty ? null : _teamByCode(_favTeam);
    final hitRate = _callsMade == 0
        ? null
        : (_callsCorrect / _callsMade * 100).round();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Text('FAN SHOWCASE', style: display(26)),
            const Spacer(),
            IconButton(
              onPressed: _shareProfile,
              tooltip: 'Share showcase',
              icon: const Icon(Icons.ios_share_rounded),
            ),
            IconButton(
              onPressed: _openSettings,
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // fan hero — who you are + your matchday record
        RepaintBoundary(
          key: _profileShareKey,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    InitialAvatar(
                      name: _name.isEmpty ? 'You' : _name,
                      size: 60,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _name.isEmpty ? 'Set your name' : _name,
                            style: display(24, color: AppColors.cream),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (_pro) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.gold,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    'SEASON PASS',
                                    style: label(
                                      color: AppColors.ink,
                                      size: 7.5,
                                      weight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.orange.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '$_fcCredits FC · T$_passTier',
                                  style: label(
                                    color: AppColors.orangeBright,
                                    size: 7.5,
                                    weight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                connected
                                    ? Icons.account_balance_wallet_rounded
                                    : Icons.verified_user_rounded,
                                size: 13,
                                color: AppColors.orangeBright,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                connected
                                    ? 'Solana wallet'
                                    : 'On-device Solana ID',
                                style: label(
                                  color: AppColors.mutInk,
                                  size: 9.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    GhostButton('Edit', onTap: _connect),
                  ],
                ),
                const SizedBox(height: 16),
                // FAN STATS — your matchday record, not infra trivia
                Row(
                  children: [
                    Expanded(
                      child: _profileStat(
                        '🔥 $_streakBest',
                        'BEST STREAK',
                        valueColor: AppColors.gold,
                      ),
                    ),
                    Container(width: 1, height: 34, color: AppColors.lineInk),
                    Expanded(
                      child: _profileStat('$_matchesWatched', 'MATCHES'),
                    ),
                    Container(width: 1, height: 34, color: AppColors.lineInk),
                    Expanded(
                      child: _profileStat(
                        hitRate == null ? '—' : '$_callsCorrect/$_callsMade',
                        hitRate == null ? 'CALLS HIT' : 'CALLS · $hitRate%',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(height: 1, color: AppColors.lineInk),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'PINNED COLLECTIBLES',
                      style: label(color: AppColors.mutInk, size: 9),
                    ),
                    const Spacer(),
                    Text(
                      '${_showcasePlayers.length}/3',
                      style: label(color: AppColors.orangeBright, size: 9),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                if (_showcasePlayers.isEmpty)
                  Pressable(
                    onTap: () => setState(() => _nav = 'cards'),
                    child: Container(
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.inkSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.lineInk),
                      ),
                      child: Text(
                        'Long-press a Player Card in Album to pin it here',
                        textAlign: TextAlign.center,
                        style: body(color: AppColors.mutInk, size: 11.5),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 108,
                    child: Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: i < _showcasePlayers.length
                                ? _showcaseMini(_showcasePlayers[i])
                                : _emptyShowcaseSlot(),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // World Cup Pass (platform) — primary CTA
        _worldCupPassCard(),
        const SizedBox(height: 12),
        // local pro reactions upsell — kept separate from platform pass
        _seasonPassCard(),
        const SizedBox(height: 12),
        // favourite team — pins their fixtures to the top of the home
        Pressable(
          haptic: HapticFeedbackType.selection,
          onTap: _pickFavoriteTeam,
          child: Container(
            decoration: cardBox(),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                if (favTeam != null)
                  InlineFlag(team: favTeam, size: 30)
                else
                  const Icon(
                    Icons.favorite_border_rounded,
                    color: AppColors.orange,
                    size: 22,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FAVOURITE TEAM',
                        style: label(color: AppColors.mut, size: 9.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        favTeam?.name ?? 'Pick your team',
                        style: body(weight: FontWeight.w800, size: 14.5),
                      ),
                    ],
                  ),
                ),
                Text(
                  favTeam != null
                      ? 'Pinned to your home'
                      : 'Their matches, front and centre',
                  style: body(color: AppColors.mut, size: 10.5),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.mut,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Final Whistle · skill-based, points only',
            style: body(color: AppColors.mut, size: 11),
          ),
        ),
      ],
    );
  }

  Widget _showcaseMini(PlayerCardModel card) => GyroTiltCard(
    motion: _profileMotion,
    intensity: 0,
    enableTilt: false,
    rarity: 3,
    seed: cardSeed('${card.id}|profile-showcase'),
    borderColor: teamColor(card.teamCode),
    frameShape: CardFrameShape.stadiumCrown,
    child: PlayerCardFace(
      playerId: card.playerId,
      name: card.name,
      teamCode: card.teamCode,
      position: card.position,
      imageUrl: card.imageUrl,
      axes: const {},
      frameShape: CardFrameShape.stadiumCrown,
    ),
  );

  Widget _emptyShowcaseSlot() => Container(
    decoration: BoxDecoration(
      color: AppColors.inkSoft,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: AppColors.lineInk),
    ),
    child: const Icon(Icons.add_rounded, color: AppColors.mutInk),
  );

  Future<void> _shareProfile() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _profileShareKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Showcase is not ready');
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not render showcase');
      await Share.shareXFiles(
        [
          XFile.fromData(
            data.buffer.asUint8List(),
            mimeType: 'image/png',
            name: 'final-whistle-showcase.png',
          ),
        ],
        text: 'My Final Whistle World Cup fan showcase ⚽',
        subject: 'Final Whistle fan showcase',
      );
    } catch (_) {
      await Share.share(
        'My Final Whistle showcase — $_matchesWatched matches, $_callsCorrect/$_callsMade Live Calls, $_fcCredits FC.',
      );
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      fwrRoute(
        SettingsScreen(
          config: _config,
          walletAddress: _walletAddr,
          onWallet: () async => _connectWallet(),
          onServerChanged: () async => _refresh(),
        ),
      ),
    ).then((_) => _loadFanStats());
  }

  Team? _teamByCode(String code) {
    for (final f in _fixtures) {
      if (f.home.code == code) return f.home;
      if (f.away.code == code) return f.away;
    }
    return null;
  }

  /// Pick the team whose matches get pinned to the top of the home.
  void _pickFavoriteTeam() {
    // unique teams from the fixture list, alphabetical
    final seen = <String, Team>{};
    for (final f in _fixtures) {
      if (f.home.code != 'TBD') seen[f.home.code] = f.home;
      if (f.away.code != 'TBD') seen[f.away.code] = f.away;
    }
    final teams = seen.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 14),
            Text('PICK YOUR TEAM', style: display(19)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: teams.length,
                itemBuilder: (_, i) {
                  final t = teams[i];
                  final sel = t.code == _favTeam;
                  return Pressable(
                    haptic: HapticFeedbackType.selection,
                    onTap: () async {
                      await LocalStore.setFavoriteTeam(sel ? '' : t.code);
                      if (mounted) setState(() => _favTeam = sel ? '' : t.code);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0x14E9531E) : AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel ? AppColors.orange : AppColors.line,
                        ),
                      ),
                      child: Row(
                        children: [
                          InlineFlag(team: t, size: 26),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t.name,
                              style: body(weight: FontWeight.w700, size: 14),
                            ),
                          ),
                          if (sel)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.orange,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// World Cup Pass — platform battle pass (XP from calls, moments, packs, duels).
  Widget _worldCupPassCard() {
    return Pressable(
      haptic: HapticFeedbackType.medium,
      onTap: () => Navigator.push(
        context,
        fwrRoute(const PassScreen()),
      ).then((_) => _loadFanStats()),
      child: Container(
        decoration: cardBox(border: AppColors.orange),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('🎫', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WORLD CUP PASS',
                    style: label(
                      color: AppColors.ink,
                      size: 10.5,
                      weight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_fcCredits FC · Tier $_passTier · $_passXp XP — claim track rewards',
                    style: body(color: AppColors.mut, size: 11.5),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.mut, size: 18),
          ],
        ),
      ),
    );
  }

  /// Season Pass — the product's paid tier. Active state or upsell CTA.
  Widget _seasonPassCard() {
    return Pressable(
      haptic: HapticFeedbackType.medium,
      onTap: () async {
        if (_pro) return;
        final unlocked = await showSeasonPassSheet(context);
        if (unlocked && mounted) {
          setState(() => _pro = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Season Pass active — enjoy the tournament 🏆'),
            ),
          );
        }
      },
      child: Container(
        decoration: cardBox(border: _pro ? AppColors.orange : AppColors.line),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _pro ? AppColors.orange : AppColors.ink,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('🏆', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'PRO REACTIONS',
                        style: label(
                          color: AppColors.ink,
                          size: 10.5,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (_pro)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.orange,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'ACTIVE',
                            style: label(color: Colors.white, size: 8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _pro
                        ? 'Pro reactions, supporter badge & priority hub perks unlocked.'
                        : 'Optional local pro pack for reactions — separate from World Cup Pass.',
                    style: body(color: AppColors.mut, size: 11.5),
                  ),
                ],
              ),
            ),
            if (!_pro) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.mut, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _profileStat(String value, String label_, {Color? valueColor}) =>
      Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: display(17, color: valueColor ?? AppColors.orangeBright),
          ),
          const SizedBox(height: 2),
          Text(label_, style: label(color: AppColors.mutInk, size: 8)),
        ],
      );

  Widget _skeleton() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(height: 70, decoration: cardBox()),
  );

  // Fixtures board (live/final scores from TxLINE)
  String _fxTop(Fixture f) => f.score != null
      ? '${f.score!.home}-${f.score!.away}'
      : (f.status == 'live' ? 'VS' : kickoffClock(f.kickoff));
  String _fxBottom(Fixture f) {
    if (f.status == 'finished') return 'FT';
    if (f.status == 'live')
      return f.score != null ? "${f.score!.minute}'" : 'LIVE';
    return 'KO';
  }

  String _fxSubtitle(Fixture f) {
    final stage = f.stage.isNotEmpty ? '${f.stage} · ' : '';
    if (f.status == 'finished')
      return '${stage}FT · verified events & line-ups';
    if (f.status == 'live') return '${stage}LIVE now · tap for match centre';
    return '${stage}Kicks off ${kickoffWhen(f.kickoff)}';
  }
}
