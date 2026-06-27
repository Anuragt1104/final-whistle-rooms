import 'dart:async';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../theme.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
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
    _api.config().then((c) => mounted ? setState(() => _config = c) : null).catchError((_) {});
    await _refresh();
    if (mounted) setState(() => _loading = false);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _loadRooms());
  }

  Future<void> _refresh() async {
    try {
      final f = await _api.fixtures();
      if (mounted) setState(() => _fixtures = f);
    } catch (_) {}
    await _loadRooms();
  }

  Future<void> _loadRooms() async {
    try {
      final r = await _api.listRooms();
      if (mounted) setState(() => _rooms = r);
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  String get _identityLabel {
    if (_name.isNotEmpty) return _name;
    return _identity?.short ?? 'Continue with Solana';
  }

  Future<void> _connect() async {
    final n = await showNameDialog(context, initial: _name);
    if (n == null) return;
    _identity = await IdentityStore.getOrCreate();
    await IdentityStore.sign('final-whistle-rooms:auth:$n:${_identity!.pubkey}');
    await LocalStore.setDisplayName(n);
    setState(() => _name = n);
  }

  Future<void> _joinByCode() async {
    setState(() => _joinErr = '');
    try {
      final id = await _api.resolveCode(_codeCtrl.text.trim());
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => RoomScreen(roomId: id)));
    } catch (_) {
      setState(() => _joinErr = 'No room with that code');
    }
  }

  void _openCreate([String? fixtureId]) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CreateScreen(fixtureId: fixtureId)))
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final live = _fixtures.where((f) => f.status == 'live').toList();
    final upcoming = _fixtures.where((f) => f.status == 'scheduled').take(8).toList();
    final featured = (live.isNotEmpty ? live.first : (upcoming.isNotEmpty ? upcoming.first : (_fixtures.isNotEmpty ? _fixtures.first : null)));

    return Scaffold(
      body: Column(children: [
        FwrHeader(
          mode: _config?.mode,
          identityLabel: _identityLabel,
          onIdentityTap: _connect,
          onSettings: () => showServerSettings(context, _api.baseUrl, (u) async {
            await _api.setBaseUrl(u);
            _refresh();
          }),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.lime,
            backgroundColor: AppColors.pitch850,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
              _hero(featured),
              if (_rooms.isNotEmpty) ...[
                const SizedBox(height: 24),
                const SectionLabel('Active rooms'),
                ..._rooms.map(_roomTile),
              ],
              const SizedBox(height: 24),
              SectionLabel(live.isNotEmpty ? 'Live & upcoming' : 'Upcoming matches'),
              if (_loading)
                ...[0, 1, 2].map((_) => const _SkeletonTile())
              else
                ...[...live, ...upcoming].map((f) => _FixtureTile(fixture: f, onCreate: () => _openCreate(f.id))),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'Powered by TxLINE live football data · sign-in with Solana\nSkill-based predictions — points & streaks only, no cash staking.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.mut, height: 1.5),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _hero(Fixture? featured) {
    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          AppChip('World Cup 2026', color: AppColors.lime),
          SizedBox(width: 6),
          Flexible(child: AppChip('Verified by TxLINE on Solana')),
        ]),
        const SizedBox(height: 12),
        RichText(
          text: const TextSpan(children: [
            TextSpan(
                text: 'Watch the World Cup ',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text)),
            TextSpan(
                text: 'together.',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.lime)),
          ]),
        ),
        const SizedBox(height: 8),
        const Text(
          'A private live room for your group. Real-time match pulse, a room prediction game, and an AI recap — all reacting to verified TxLINE data as it happens.',
          style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        PrimaryButton('+ Create a room', expand: true, onTap: () => _openCreate(featured?.id)),
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
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_joinErr, style: const TextStyle(color: AppColors.away, fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _roomTile(RoomSummary r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RoomScreen(roomId: r.id)))
            .then((_) => _refresh()),
        child: Container(
          decoration: cardDecoration(),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${r.fixture.home.flag} ${r.fixture.home.code} vs ${r.fixture.away.code} ${r.fixture.away.flag} · ${r.memberCount} in room',
                  style: const TextStyle(fontSize: 11, color: AppColors.mut),
                ),
              ]),
            ),
            AppChip(r.status == 'live' ? 'LIVE' : r.status == 'finished' ? 'FT' : 'Lobby',
                color: r.status == 'live' ? AppColors.lime : AppColors.mut),
          ]),
        ),
      ),
    );
  }
}

class _FixtureTile extends StatelessWidget {
  final Fixture fixture;
  final VoidCallback onCreate;
  const _FixtureTile({required this.fixture, required this.onCreate});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: cardDecoration(),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                AppChip(
                  fixture.status == 'live' ? 'LIVE' : fixture.status == 'finished' ? 'FT' : 'Upcoming',
                  color: fixture.status == 'live' ? AppColors.lime : AppColors.mut,
                  leading: fixture.status == 'live' ? const LiveDot(size: 5) : null,
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(fixture.stage, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.mut))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Text('${fixture.home.flag} ', style: const TextStyle(fontSize: 16)),
                Text(fixture.home.code, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Text('  vs  ', style: TextStyle(color: AppColors.mut)),
                Text('${fixture.away.flag} ', style: const TextStyle(fontSize: 16)),
                Text(fixture.away.code, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                if (fixture.status != 'finished')
                  Text(relativeKickoff(fixture.kickoff), style: const TextStyle(fontSize: 11, color: AppColors.mut)),
              ]),
            ]),
          ),
          GhostButton('Create room', onTap: onCreate),
        ]),
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(height: 64, decoration: cardDecoration()),
      );
}
