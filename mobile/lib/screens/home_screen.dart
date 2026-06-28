import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../data/flags.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../local/fixtures.dart';
import '../local/live_engine.dart';
import '../solana/wallet_connect.dart';
import '../theme.dart';
import '../widgets/app_header.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common.dart';
import '../widgets/ticket.dart';
import 'create_screen.dart';
import 'room_screen.dart';

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
  final _codeCtrl = TextEditingController();
  String _joinErr = '';
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    _identity = await IdentityStore.getOrCreate();
    _name = await LocalStore.displayName();
    _walletAddr = await LocalStore.walletAddress();
    _api.config().then((c) => mounted ? setState(() => _config = c) : null).catchError((_) {});
    await _refresh();
    if (mounted) setState(() => _loading = false);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _loadRooms());
  }

  Future<void> _refresh() async {
    // Always have matches to show: use the server when reachable, fall back to
    // the on-device fixture list so the app is never empty.
    try {
      final f = await _api.fixtures();
      _fixtures = f.isNotEmpty ? f : localFixtures();
    } catch (_) {
      _fixtures = localFixtures();
    }
    await _loadRooms();
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

  /// Instantly watch a match live, fully on-device (no backend needed).
  Future<void> _watchLive(Fixture f) async {
    // When the backend serves real TxLINE data, host a backend room that
    // follows the actual live match; otherwise play it fully on-device.
    if (_config?.mode == 'live') {
      try {
        final id = await IdentityStore.getOrCreate();
        final res = await _api.createRoom(
          name: '${f.home.name} watch-along',
          fixtureId: f.id,
          draft: true,
          nextSwing: true,
          hostName: _name.isEmpty ? 'You' : _name,
          hostWallet: id.pubkey,
        );
        await LocalStore.setMemberId(res.roomId, res.hostId);
        await _api.start(res.roomId, res.hostId); // begin streaming the real feed
        if (!mounted) return;
        Navigator.push(context, fwrRoute(RoomScreen(roomId: res.roomId)));
        return;
      } catch (_) {
        // backend hiccup — fall back to the on-device engine
      }
    }
    final engine = LiveMatchEngine(f, draftMode: true, nextSwingMode: true, myName: _name.isEmpty ? 'You' : _name);
    if (!mounted) return;
    Navigator.push(context, fwrRoute(RoomScreen(roomId: 'local', engine: engine, autoStart: true)));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    final n = await showNameDialog(context, initial: _name);
    if (n == null) return;
    _identity = await IdentityStore.getOrCreate();
    await IdentityStore.sign('final-whistle-rooms:auth:$n:${_identity!.pubkey}');
    await LocalStore.setDisplayName(n);
    setState(() => _name = n);
  }

  Future<void> _connectWallet() async {
    if (!await WalletConnect.isAvailable()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No Solana wallet app detected (Phantom/Solflare). Android only.')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wallet connection failed')));
      }
    }
  }

  void _openRoom(String id) => Navigator.push(context, fwrRoute(RoomScreen(roomId: id))).then((_) => _refresh());

  void _openCreate([String? fixtureId]) =>
      Navigator.push(context, fwrRoute(CreateScreen(fixtureId: fixtureId))).then((_) => _refresh());

  Future<void> _joinByCode() async {
    setState(() => _joinErr = '');
    try {
      final id = await _api.resolveCode(_codeCtrl.text.trim());
      if (mounted) _openRoom(id);
    } catch (_) {
      setState(() => _joinErr = 'No room with that code');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: Column(children: [
          FwrHeader(
            trailing: GestureDetector(
              onTap: () => setState(() => _nav = 'you'),
              child: InitialAvatar(name: _name.isEmpty ? 'You' : _name, size: 38),
            ),
          ),
          Expanded(child: _body()),
        ]),
        bottomNavigationBar: BottomNav(
          active: _nav,
          onSelect: (k) => setState(() => _nav = k),
          onCreate: () => _openCreate(_featuredFixtureId()),
        ),
      ),
    );
  }

  String? _featuredFixtureId() {
    final live = _fixtures.where((f) => f.status == 'live');
    if (live.isNotEmpty) return live.first.id;
    final up = _fixtures.where((f) => f.status == 'scheduled');
    if (up.isNotEmpty) return up.first.id;
    return _fixtures.isNotEmpty ? _fixtures.first.id : null;
  }

  Widget _body() {
    switch (_nav) {
      case 'fixtures':
        return _fixturesTab();
      case 'inbox':
        return _inboxTab();
      case 'you':
        return _youTab();
      default:
        return _roomsTab();
    }
  }

  // ---- ROOMS (Browse) ----
  Widget _roomsTab() {
    final liveRooms = _rooms.where((r) => r.status == 'live').toList();
    final hero = liveRooms.isNotEmpty ? liveRooms.first : (_rooms.isNotEmpty ? _rooms.first : null);
    final moreRooms = _rooms.where((r) => hero == null || r.id != hero.id).toList();
    final upcoming = _fixtures.where((f) => f.status == 'scheduled').take(6).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.orange,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Row(children: [
          const LiveDot(),
          const SizedBox(width: 6),
          Text('LIVE NOW', style: label(color: AppColors.ink, size: 12.5, weight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        if (hero != null) _heroRoom(hero) else _heroFixture(_featuredLiveFixture()),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: fwrInput('Have a code? e.g. K7M2QX'),
              onSubmitted: (_) => _joinByCode(),
            ),
          ),
          const SizedBox(width: 8),
          GhostButton('Join', onTap: _joinByCode),
        ]),
        if (_joinErr.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_joinErr, style: body(color: const Color(0xFFD8392B), size: 12))),
        if (moreRooms.isNotEmpty) ...[
          const SizedBox(height: 22),
          const SectionLabel('More rooms live'),
          ...moreRooms.map(_roomRow),
        ],
        const SizedBox(height: 22),
        const SectionLabel('Kicking off soon'),
        if (_loading)
          ...[0, 1].map((_) => _skeleton())
        else if (upcoming.isEmpty)
          Text('No upcoming matches in range.', style: body(color: AppColors.mut, size: 13))
        else
          ...upcoming.map(_fixtureRow),
        const SizedBox(height: 16),
        Center(child: Text('Powered by TxLINE · sign-in with Solana · points only, no cash staking', textAlign: TextAlign.center, style: body(color: AppColors.mut, size: 11))),
      ]),
    );
  }

  Widget _heroRoom(RoomSummary r) {
    return Pressable(
      haptic: HapticFeedbackType.medium,
      onTap: () => _openRoom(r.id),
      child: Container(
        decoration: cardBox(),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          TicketScoreboard(
            home: r.fixture.home,
            away: r.fixture.away,
            league: r.fixture.stage,
            score: _scoreText(r.score, r.status),
            minute: _minuteText(r.score, r.status),
            pill: r.status == 'live' ? 'LIVE' : (r.status == 'finished' ? 'FULL TIME' : 'LOBBY'),
            watching: r.memberCount,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(17)),
                  const SizedBox(height: 2),
                  Text('${r.memberCount} ${r.memberCount == 1 ? "fan" : "fans"} watching', style: body(color: AppColors.mut, size: 12)),
                ]),
              ),
              const SizedBox(width: 10),
              PrimaryButton('Join', icon: Icons.play_arrow_rounded, onTap: () => _openRoom(r.id)),
            ]),
          ),
        ]),
      ),
    );
  }

  Fixture? _featuredLiveFixture() {
    final live = _fixtures.where((f) => f.status == 'live');
    if (live.isNotEmpty) return live.first;
    final up = _fixtures.where((f) => f.status == 'scheduled');
    if (up.isNotEmpty) return up.first;
    return _fixtures.isNotEmpty ? _fixtures.first : null;
  }

  /// Hero when there are no multiplayer rooms yet — watch a match live, solo.
  Widget _heroFixture(Fixture? f) {
    if (f == null) {
      return Container(decoration: cardBox(), padding: const EdgeInsets.all(18), child: Text('Loading matches…', style: body(color: AppColors.mut)));
    }
    return Pressable(
      haptic: HapticFeedbackType.medium,
      onTap: () => _watchLive(f),
      child: Container(
        decoration: cardBox(),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          TicketScoreboard(
            home: f.home,
            away: f.away,
            league: f.stage,
            score: null,
            minute: f.status == 'live' ? 'LIVE' : relativeKickoff(f.kickoff),
            pill: f.status == 'live' ? 'LIVE' : 'WATCH',
            watching: null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${f.home.name} vs ${f.away.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(16)),
                  const SizedBox(height: 2),
                  Text('Watch live with the room — pulse, predictions & recap', style: body(color: AppColors.mut, size: 12)),
                ]),
              ),
              const SizedBox(width: 10),
              PrimaryButton('Watch', icon: Icons.play_arrow_rounded, onTap: () => _watchLive(f)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _roomRow(RoomSummary r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        onTap: () => _openRoom(r.id),
        child: Container(
          decoration: cardBox(),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            MiniScore(top: _scoreText(r.score, r.status) ?? 'VS', bottom: _miniBottom(r.score, r.status)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(weight: FontWeight.w800, size: 14)),
                const SizedBox(height: 2),
                Text('${r.fixture.home.code} v ${r.fixture.away.code} · ${r.fixture.stage}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mut, size: 11.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(children: [
                const Icon(Icons.visibility_outlined, size: 13, color: AppColors.mut),
                const SizedBox(width: 3),
                Text(compactNum(r.memberCount), style: label(color: AppColors.mut, size: 10)),
              ]),
              const SizedBox(height: 6),
              const Icon(Icons.chevron_right, color: AppColors.mut, size: 18),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _fixtureRow(Fixture f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        onTap: () => _watchLive(f),
        child: Container(
          decoration: cardBox(),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            MiniScore(top: f.status == 'live' ? 'VS' : kickoffClock(f.kickoff), bottom: f.status == 'live' ? 'LIVE' : 'KO'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  InlineFlag(team: f.home, size: 20),
                  const SizedBox(width: 6),
                  Text(f.home.code, style: body(weight: FontWeight.w800, size: 14)),
                  Text('  v  ', style: body(color: AppColors.mut)),
                  Text(f.away.code, style: body(weight: FontWeight.w800, size: 14)),
                  const SizedBox(width: 6),
                  InlineFlag(team: f.away, size: 20),
                ]),
                const SizedBox(height: 2),
                Text('Tap to watch live · ${relativeKickoff(f.kickoff)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mut, size: 11.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Pressable(
              haptic: HapticFeedbackType.selection,
              onTap: () => _openCreate(f.id),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
                child: const Icon(Icons.add, color: AppColors.ink, size: 20),
              ),
            ),
            const SizedBox(width: 6),
            Pressable(
              haptic: HapticFeedbackType.medium,
              onTap: () => _watchLive(f),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: const [BoxShadow(color: Color(0x33E9531E), blurRadius: 8, offset: Offset(0, 3))],
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ---- FIXTURES ----
  Widget _fixturesTab() {
    final live = _fixtures.where((f) => f.status == 'live').toList();
    final up = _fixtures.where((f) => f.status == 'scheduled').toList();
    final fin = _fixtures.where((f) => f.status == 'finished').toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.orange,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Text('FIXTURES', style: display(26)),
        const SizedBox(height: 4),
        Text('All 48 group-stage matches. Tap + to host a room.', style: body(color: AppColors.mut, size: 13)),
        const SizedBox(height: 16),
        if (live.isNotEmpty) ...[const SectionLabel('Live'), ...live.map(_fixtureRow), const SizedBox(height: 12)],
        if (up.isNotEmpty) ...[const SectionLabel('Upcoming'), ...up.map(_fixtureRow), const SizedBox(height: 12)],
        if (fin.isNotEmpty) ...[const SectionLabel('Finished'), ...fin.map(_fixtureRow)],
      ]),
    );
  }

  // ---- INBOX ----
  Widget _inboxTab() {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text('INBOX', style: display(26)),
      const SizedBox(height: 16),
      Container(
        decoration: cardBox(),
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Icon(Icons.notifications_none_rounded, color: AppColors.mut, size: 34),
          const SizedBox(height: 10),
          Text('You\'re all caught up', style: display(18)),
          const SizedBox(height: 6),
          Text('Room invites, kick-off reminders and final-whistle recaps will land here.', textAlign: TextAlign.center, style: body(color: AppColors.mut, size: 13)),
        ]),
      ),
    ]);
  }

  // ---- YOU ----
  Widget _youTab() {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text('YOU', style: display(26)),
      const SizedBox(height: 16),
      Container(
        decoration: cardBox(),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          InitialAvatar(name: _name.isEmpty ? 'You' : _name, size: 54),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name.isEmpty ? 'Set your name' : _name, style: display(20)),
              const SizedBox(height: 2),
              Text(_identity == null ? '' : '◎ ${_identity!.short}', style: body(color: AppColors.mut, size: 12)),
            ]),
          ),
          GhostButton('Edit', onTap: _connect),
        ]),
      ),
      const SizedBox(height: 12),
      _settingRow(Icons.dns_outlined, 'Server', _api.baseUrl, () => showServerSettings(context, _api.baseUrl, (u) async {
        await _api.setBaseUrl(u);
        _refresh();
      })),
      _settingRow(Icons.bolt_outlined, 'Data source', _config?.mode == 'live' ? 'Live TxLINE' : 'Replay (TxLINE-shaped)', null),
      _settingRow(Icons.account_balance_wallet_outlined, 'Wallet', _walletAddr.isEmpty ? 'Tap to connect a Solana wallet' : _walletAddr, _connectWallet),
      _settingRow(Icons.verified_outlined, 'On-device identity', _identity == null ? '—' : _identity!.pubkey, null),
      const SizedBox(height: 16),
      Center(child: Text('Final Whistle Rooms · skill-based, points only', style: body(color: AppColors.mut, size: 11))),
    ]);
  }

  Widget _settingRow(IconData icon, String title, String value, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: cardBox(),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(icon, color: AppColors.ink, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title.toUpperCase(), style: label(color: AppColors.mut, size: 9.5)),
                const SizedBox(height: 2),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(size: 13, weight: FontWeight.w600)),
              ]),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.mut, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _skeleton() => Padding(padding: const EdgeInsets.only(bottom: 10), child: Container(height: 70, decoration: cardBox()));

  // ---- helpers ----
  String? _scoreText(ScoreView? s, String status) {
    if (s == null || status == 'lobby') return null;
    return '${s.goals.home}-${s.goals.away}';
  }

  String _minuteText(ScoreView? s, String status) {
    if (status == 'finished' || (s != null && s.phase == 4)) return 'FT';
    if (s == null) return status == 'lobby' ? 'LOBBY' : '';
    if (s.phase == 2) return 'HT';
    if (s.phase == 0) return 'SOON';
    return "${s.minute}'";
  }

  String _miniBottom(ScoreView? s, String status) {
    if (status == 'finished') return 'FT';
    if (status == 'lobby') return 'LOBBY';
    if (s == null) return 'LIVE';
    if (s.phase == 2) return 'HT';
    return "${s.minute}'";
  }
}
