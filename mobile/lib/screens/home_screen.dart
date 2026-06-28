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
import '../solana/rpc.dart';
import '../theme.dart';
import '../widgets/app_header.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common.dart';
import '../widgets/ticket.dart';
import 'create_screen.dart';
import 'room_screen.dart';
import 'team_sheet.dart';

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
  double? _solBalance;
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
    _loadBalance();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _loadRooms());
  }

  Future<void> _loadBalance() async {
    final addr = _walletAddr.isNotEmpty ? _walletAddr : (_identity?.pubkey ?? '');
    final bal = await SolanaRpc.balance(addr, cluster: _config?.cluster ?? 'mainnet-beta');
    if (mounted) setState(() => _solBalance = bal);
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

  /// Watch a match live. Reuses the canonical room for that fixture if one
  /// already exists — so repeated taps never spawn duplicate rooms, and
  /// everyone watching the same match lands in the same room.
  Future<void> _watchLive(Fixture f) async {
    final existing = _rooms.where((r) => r.fixture.id == f.id).toList();
    if (existing.isNotEmpty) {
      _openRoom(existing.first.id);
      return;
    }
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
        _loadBalance();
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
    final liveFixtures = _fixtures.where((f) => f.status == 'live').toList();
    final upcoming = _fixtures.where((f) => f.status == 'scheduled').take(8).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.orange,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Row(children: [
          const LiveDot(),
          const SizedBox(width: 6),
          Text(liveFixtures.isEmpty ? 'LIVE NOW' : 'LIVE NOW · ${liveFixtures.length} ${liveFixtures.length == 1 ? "match" : "matches"}',
              style: label(color: AppColors.ink, size: 12.5, weight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        // every live match shown clearly as its own card
        if (_loading)
          _skeleton()
        else if (liveFixtures.isEmpty)
          _noLiveCard(upcoming.isNotEmpty ? upcoming.first : null)
        else
          ...liveFixtures.map((f) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _liveMatchCard(f))),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: fwrInput('Have a private code? e.g. K7M2QX'),
              onSubmitted: (_) => _joinByCode(),
            ),
          ),
          const SizedBox(width: 8),
          GhostButton('Join', onTap: _joinByCode),
        ]),
        if (_joinErr.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_joinErr, style: body(color: const Color(0xFFD8392B), size: 12))),
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

  /// Honest empty state when nothing is in play — never a future match dressed
  /// up as "LIVE".
  Widget _noLiveCard(Fixture? next) {
    return Container(
      decoration: cardBox(),
      padding: const EdgeInsets.all(22),
      child: Column(children: [
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
      ]),
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
        child: Column(children: [
          TicketScoreboard(
            home: f.home,
            away: f.away,
            league: f.stage,
            score: f.score != null ? '${f.score!.home} - ${f.score!.away}' : null,
            minute: f.score != null ? "${f.score!.minute}'" : 'LIVE',
            pill: 'LIVE',
            watching: room?.memberCount,
            onTeamTap: (t) => showTeamSheet(context, t),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${f.home.name} vs ${f.away.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(16)),
                  const SizedBox(height: 2),
                  Text(room != null ? '${room.memberCount} watching · join the room' : 'Watch live — pulse, predictions & chat',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mut, size: 12)),
                ]),
              ),
              const SizedBox(width: 10),
              PrimaryButton(room != null ? 'Join' : 'Watch', icon: Icons.play_arrow_rounded, onTap: () => _watchLive(f)),
            ]),
          ),
        ]),
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
            MiniScore(top: _fxTop(f), bottom: _fxBottom(f)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  GestureDetector(onTap: () => showTeamSheet(context, f.home), child: InlineFlag(team: f.home, size: 28)),
                  const SizedBox(width: 6),
                  Text(f.home.code, style: body(weight: FontWeight.w800, size: 14)),
                  Text('  v  ', style: body(color: AppColors.mut)),
                  Text(f.away.code, style: body(weight: FontWeight.w800, size: 14)),
                  const SizedBox(width: 6),
                  GestureDetector(onTap: () => showTeamSheet(context, f.away), child: InlineFlag(team: f.away, size: 28)),
                ]),
                const SizedBox(height: 2),
                Text(_fxSubtitle(f), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mut, size: 11.5)),
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
    final connected = _walletAddr.isNotEmpty;
    final activeAddr = connected ? _walletAddr : (_identity?.pubkey ?? '');
    final cluster = _config?.cluster ?? 'mainnet-beta';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text('YOU', style: display(26)),
      const SizedBox(height: 16),
      // profile hero — ink card with avatar, name, sign-in method
      Container(
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Row(children: [
            InitialAvatar(name: _name.isEmpty ? 'You' : _name, size: 60),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_name.isEmpty ? 'Set your name' : _name, style: display(24, color: AppColors.cream)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(connected ? Icons.account_balance_wallet_rounded : Icons.verified_user_rounded, size: 13, color: AppColors.orangeBright),
                  const SizedBox(width: 5),
                  Text(connected ? 'Solana wallet' : 'On-device Solana ID', style: label(color: AppColors.mutInk, size: 9.5)),
                ]),
              ]),
            ),
            GhostButton('Edit', onTap: _connect),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _profileStat('◎ ${_solBalance == null ? '—' : _solBalance!.toStringAsFixed(3)}', 'SOL BALANCE')),
            Container(width: 1, height: 34, color: AppColors.lineInk),
            Expanded(child: _profileStat(cluster == 'mainnet-beta' ? 'MAINNET' : 'DEVNET', 'NETWORK')),
            Container(width: 1, height: 34, color: AppColors.lineInk),
            Expanded(child: _profileStat(_config?.mode == 'live' ? 'LIVE' : 'REPLAY', 'TXLINE FEED')),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      // wallet card
      Container(
        decoration: cardBox(),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet_outlined, color: AppColors.ink, size: 18),
            const SizedBox(width: 8),
            Text(connected ? 'CONNECTED WALLET' : 'YOUR WALLET', style: label(color: AppColors.ink, size: 10.5, weight: FontWeight.w800)),
            const Spacer(),
            if (!connected)
              GhostButton('Connect', onTap: _connectWallet),
          ]),
          const SizedBox(height: 8),
          SelectableText(activeAddr.isEmpty ? '—' : activeAddr, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.orange)),
          const SizedBox(height: 6),
          Text(connected
              ? 'Your Phantom/Solflare wallet — used to sign in and prove room membership.'
              : 'A secure Solana keypair was created on this device. Connect Phantom/Solflare to use your own wallet.',
              style: body(color: AppColors.mut, size: 11.5)),
        ]),
      ),
      const SizedBox(height: 12),
      _settingRow(Icons.bolt_outlined, 'Data source', _config?.mode == 'live' ? 'Live TxLINE (mainnet oracle)' : 'Replay (TxLINE-shaped)', null),
      _settingRow(Icons.dns_outlined, 'Server', _api.baseUrl, () => showServerSettings(context, _api.baseUrl, (u) async {
        await _api.setBaseUrl(u);
        _refresh();
      })),
      const SizedBox(height: 16),
      Center(child: Text('Final Whistle Rooms · skill-based, points only', style: body(color: AppColors.mut, size: 11))),
    ]);
  }

  Widget _profileStat(String value, String label_) => Column(children: [
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(17, color: AppColors.orangeBright)),
        const SizedBox(height: 2),
        Text(label_, style: label(color: AppColors.mutInk, size: 8)),
      ]);

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

  // Fixtures board (live/final scores from TxLINE)
  String _fxTop(Fixture f) =>
      f.score != null ? '${f.score!.home}-${f.score!.away}' : (f.status == 'live' ? 'VS' : kickoffClock(f.kickoff));
  String _fxBottom(Fixture f) {
    if (f.status == 'finished') return 'FT';
    if (f.status == 'live') return f.score != null ? "${f.score!.minute}'" : 'LIVE';
    return 'KO';
  }

  String _fxSubtitle(Fixture f) {
    if (f.status == 'finished') return 'Full time · tap to open the room';
    if (f.status == 'live') return 'LIVE now · tap to watch';
    return 'Tap to watch live · ${relativeKickoff(f.kickoff)}';
  }
}
