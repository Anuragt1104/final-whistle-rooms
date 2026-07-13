import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/cards.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'duel_screen.dart';
import 'pass_screen.dart';
import 'platform_hq_screen.dart';

/// Album — Moments, Packs, Players, Duels, Market, Shop + FC wallet.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key});
  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> with SingleTickerProviderStateMixin {
  final _api = ApiClient.instance;
  FanInventory? _inv;
  Map<String, dynamic>? _wallet;
  List<dynamic> _listings = [];
  List<dynamic> _myListings = [];
  List<dynamic> _shopTiers = [];
  String? _err;
  bool _loading = true;
  late TabController _tabs;
  final Set<String> _craftSel = {};
  String _displayName = 'You';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _displayName = (await LocalStore.displayName()).isEmpty ? 'You' : await LocalStore.displayName();
    await _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<String> _fanId() async {
    final id = await IdentityStore.getOrCreate();
    return id.pubkey;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final fanId = await _fanId();
      final inv = await _api.inventory(fanId);
      Map<String, dynamic>? wallet;
      List<dynamic> listings = [];
      List<dynamic> mine = [];
      List<dynamic> tiers = [];
      try {
        wallet = await _api.platformWallet(fanId);
      } catch (_) {}
      try {
        final m = await _api.marketBrowse(fanId);
        listings = (m['listings'] ?? []) as List;
        mine = (m['mine'] ?? []) as List;
      } catch (_) {}
      try {
        final s = await _api.shopTiers();
        tiers = (s['tiers'] ?? []) as List;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _inv = FanInventory.fromJson(inv);
        _wallet = wallet;
        _listings = listings;
        _myListings = mine;
        _shopTiers = tiers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openPack(PackModel p) async {
    try {
      final fanId = await _fanId();
      await _api.openPack(fanId, p.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pack opened — Player Card added')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _craft() async {
    if (_craftSel.length < 2) return;
    try {
      final fanId = await _fanId();
      await _api.craft(fanId, _craftSel.toList());
      _craftSel.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Crafted a Player Card')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _verify(MomentCard m) async {
    try {
      final detail = await _api.momentDetail(m.id);
      final proof = detail['proof'];
      final ok = proof is Map && proof['verified'] == true;
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('${m.rarity}★ Moment'),
          content: Text(
            ok
                ? 'Merkle inclusion verified.\nRoot: ${(proof['root'] as String).substring(0, 16)}…'
                : 'Could not verify proof.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _listForSale(PlayerCardModel p) async {
    final ctrl = TextEditingController(text: '50');
    final price = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('List ${p.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Price (FC)', hintText: '50'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('List'),
          ),
        ],
      ),
    );
    if (price == null || price <= 0) return;
    try {
      final fanId = await _fanId();
      await _api.marketList(fanId, _displayName, p.id, price);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Listed ${p.name} for $price FC')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _mint(PlayerCardModel p) async {
    try {
      final fanId = await _fanId();
      final res = await _api.mintCard(fanId, p.id);
      await _load();
      if (mounted) {
        final sig = res['signature'] ?? res['tx'] ?? 'ok';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Minted on Solana — $sig')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().contains('501') || e.toString().contains('anchor')
              ? 'On-chain mint unavailable (anchor not configured)'
              : '$e')),
        );
      }
    }
  }

  Future<void> _buyListing(Map listing) async {
    try {
      final fanId = await _fanId();
      await _api.marketBuy(fanId, _displayName, listing['id'].toString());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchased')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _cancelListing(Map listing) async {
    try {
      final fanId = await _fanId();
      await _api.marketCancel(fanId, listing['id'].toString());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listing cancelled')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _buyShop(String tierId) async {
    try {
      final fanId = await _fanId();
      await _api.shopBuy(fanId, tierId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pack purchased — check Packs tab')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _openPass() => Navigator.push(context, fwrRoute(const PassScreen())).then((_) => _load());
  void _openHq() => Navigator.push(context, fwrRoute(const PlatformHqScreen()));

  int get _fc {
    final w = _wallet?['wallet'];
    if (w is Map) {
      final c = w['credits'];
      if (c is num) return c.toInt();
    }
    return 0;
  }

  Map<String, dynamic> get _passSummary {
    final p = _wallet?['pass'];
    if (p is Map<String, dynamic>) return p;
    if (p is Map) return Map<String, dynamic>.from(p);
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final tier = (_passSummary['tier'] ?? 0) as int;
    final xp = (_passSummary['xp'] ?? 0) as int;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(children: [
          Text('ALBUM', style: display(22)),
          const Spacer(),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ]),
      ),
      _walletStrip(tier, xp),
      TabBar(
        controller: _tabs,
        isScrollable: true,
        labelColor: AppColors.orange,
        unselectedLabelColor: AppColors.mut,
        indicatorColor: AppColors.orange,
        tabs: const [
          Tab(text: 'Moments'),
          Tab(text: 'Packs'),
          Tab(text: 'Players'),
          Tab(text: 'Duels'),
          Tab(text: 'Market'),
          Tab(text: 'Shop'),
        ],
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _err != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_err!, textAlign: TextAlign.center, style: body(color: AppColors.mut)),
                    ),
                  )
                : TabBarView(controller: _tabs, children: [
                    _momentsTab(),
                    _packsTab(),
                    _playersTab(),
                    _duelsTab(),
                    _marketTab(),
                    _shopTab(),
                  ]),
      ),
    ]);
  }

  Widget _walletStrip(int tier, int xp) {
    return Pressable(
      onTap: _openPass,
      onLongPress: _openHq,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: cardBox(radius: 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_fc FC', style: label(weight: FontWeight.w800, size: 13, color: AppColors.ink)),
              const SizedBox(height: 2),
              Text(
                _wallet == null ? 'Tap Pass · long-press HQ' : 'Pass T$tier · $xp XP · tap for track',
                style: body(size: 11, color: AppColors.mut),
              ),
            ]),
          ),
          PrimaryButton('Pass', onTap: _openPass),
        ]),
      ),
    );
  }

  Widget _momentsTab() {
    final moments = _inv?.moments ?? [];
    if (moments.isEmpty) {
      return Center(
        child: Text(
          'Watch a live or replay room — goals mint Moments here.',
          textAlign: TextAlign.center,
          style: body(color: AppColors.mut),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (_craftSel.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PrimaryButton(
            'Craft ${_craftSel.length} Moments → Player',
            onTap: _craftSel.length >= 2 ? _craft : null,
          ),
        ),
      ...moments.map((m) {
        final sel = _craftSel.contains(m.id);
        return Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              if (sel) {
                _craftSel.remove(m.id);
              } else {
                _craftSel.add(m.id);
              }
            });
          },
          onLongPress: () => _verify(m),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? AppColors.orange : AppColors.line, width: sel ? 2 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('★' * m.rarity, style: const TextStyle(color: AppColors.orange)),
                const SizedBox(width: 8),
                Expanded(child: Text(m.label, style: label(weight: FontWeight.w700))),
                if (m.calledIt)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('CALLED IT', style: label(size: 9, color: AppColors.orange, weight: FontWeight.w800)),
                  ),
              ]),
              const SizedBox(height: 4),
              Text('${m.matchLabel} · ${m.minute}\' · ${m.kind}', style: body(size: 12, color: AppColors.mut)),
              const SizedBox(height: 4),
              Text('Long-press to Verify · tap to select for Craft', style: body(size: 11, color: AppColors.mut)),
            ]),
          ),
        );
      }),
    ]);
  }

  Widget _packsTab() {
    final packs = (_inv?.packs ?? []).where((p) => !p.opened).toList();
    if (packs.isEmpty) {
      return Center(child: Text('No unopened packs — earn Moments or buy in Shop', style: body(color: AppColors.mut)));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: packs
          .map((p) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('PACK', style: label(weight: FontWeight.w800)),
                      Text('Weight ${p.weight.toStringAsFixed(2)}', style: body(size: 12, color: AppColors.mut)),
                    ]),
                  ),
                  PrimaryButton('Open', onTap: () => _openPack(p)),
                ]),
              ))
          .toList(),
    );
  }

  Widget _playersTab() {
    final players = _inv?.players ?? [];
    final skills = _inv?.skills ?? [];
    if (players.isEmpty && skills.isEmpty) {
      return Center(child: Text('Open a pack to get Player Cards', style: body(color: AppColors.mut)));
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      ...players.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p.name} · ${p.teamCode} · ${p.position}', style: label(weight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: p.axes.entries
                    .map((e) => Text('${e.key[0].toUpperCase()}${e.key.substring(1)} ${e.value}',
                        style: body(size: 11, color: AppColors.mut)))
                    .toList(),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: GhostButton('List for sale', onTap: () => _listForSale(p))),
                const SizedBox(width: 8),
                Expanded(child: GhostButton('Mint NFT', onTap: () => _mint(p))),
              ]),
            ]),
          )),
      if (skills.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('SKILLS', style: label(weight: FontWeight.w800)),
        ...skills.map((s) => ListTile(
              dense: true,
              title: Text(s.name),
              subtitle: Text(s.description),
            )),
      ],
    ]);
  }

  Widget _duelsTab() {
    final players = _inv?.players ?? [];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          players.length < 3
              ? 'Need 3 Player Cards to duel. Open packs first.'
              : 'Pick a Hand of 3 and challenge the House bot, or seed a Moment Arena.',
          style: body(color: AppColors.mut),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          'Trump Duel vs Bot',
          onTap: players.length < 3
              ? null
              : () => Navigator.push(
                    context,
                    fwrRoute(DuelScreen(players: players, moments: _inv?.moments ?? [])),
                  ).then((_) => _load()),
        ),
      ]),
    );
  }

  Widget _marketTab() {
    if (_listings.isEmpty && _myListings.isEmpty) {
      return Center(
        child: Text('No listings yet — list a Player Card from the Players tab.',
            textAlign: TextAlign.center, style: body(color: AppColors.mut)),
      );
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (_myListings.isNotEmpty) ...[
        Text('YOUR LISTINGS', style: label(weight: FontWeight.w800)),
        const SizedBox(height: 8),
        ..._myListings.map((raw) {
          final L = Map<String, dynamic>.from(raw as Map);
          return _listingTile(L, mine: true);
        }),
        const SizedBox(height: 16),
      ],
      Text('OPEN MARKET', style: label(weight: FontWeight.w800)),
      const SizedBox(height: 8),
      ..._listings.map((raw) {
        final L = Map<String, dynamic>.from(raw as Map);
        return _listingTile(L, mine: false);
      }),
    ]);
  }

  Widget _listingTile(Map<String, dynamic> L, {required bool mine}) {
    final card = L['card'] is Map ? Map<String, dynamic>.from(L['card'] as Map) : <String, dynamic>{};
    final name = card['name']?.toString() ?? L['cardId']?.toString() ?? 'Card';
    final price = L['priceFC'] ?? L['price'] ?? '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: label(weight: FontWeight.w800)),
            Text('$price FC · ${L['sellerName'] ?? 'seller'}', style: body(size: 12, color: AppColors.mut)),
          ]),
        ),
        if (mine)
          GhostButton('Cancel', onTap: () => _cancelListing(L))
        else
          PrimaryButton('Buy', onTap: () => _buyListing(L)),
      ]),
    );
  }

  Widget _shopTab() {
    if (_shopTiers.isEmpty) {
      return Center(child: Text('Shop unavailable — check server connection', style: body(color: AppColors.mut)));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Spend Fan Credits on packs. Bought packs add variety — not raw power.',
            style: body(size: 13, color: AppColors.mut)),
        const SizedBox(height: 12),
        ..._shopTiers.map((raw) {
          final t = Map<String, dynamic>.from(raw as Map);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t['label']?.toString() ?? t['id'].toString(), style: label(weight: FontWeight.w800, size: 13)),
              const SizedBox(height: 4),
              Text(t['blurb']?.toString() ?? '', style: body(size: 12, color: AppColors.mut)),
              const SizedBox(height: 10),
              Row(children: [
                Text('${t['priceFC']} FC', style: label(weight: FontWeight.w800, color: AppColors.orange)),
                const Spacer(),
                PrimaryButton('Buy', onTap: () => _buyShop(t['id'].toString())),
              ]),
            ]),
          );
        }),
      ],
    );
  }
}
