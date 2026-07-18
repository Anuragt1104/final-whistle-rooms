import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/cards.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gyro_card.dart';
import 'card_detail_screen.dart';

/// Album — Moments / Packs / Players. Duels open from Home → Play.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key});
  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen>
    with SingleTickerProviderStateMixin {
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
  final CardMotionController _motion = CardMotionController();
  String _kindFilter = 'all';
  int _rarityFilter = 0;
  String _momentSort = 'newest';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _displayName = (await LocalStore.displayName()).isEmpty
        ? 'You'
        : await LocalStore.displayName();
    await _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _motion.dispose();
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
        _err = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Soft-fail: keep tabs usable with empty inventory + retry, not a raw stack.
      setState(() {
        _inv ??= FanInventory(
          fanId: '',
          moments: const [],
          players: const [],
          skills: const [],
          packs: const [],
          packWeightBonus: 0,
        );
        _err = 'server';
        _loading = false;
      });
    }
  }

  Future<void> _openPack(PackModel p) async {
    try {
      final fanId = await _fanId();
      final raw = await _api.openPack(fanId, p.id);
      final opened = PackModel.fromJson(raw);
      final reduceMotion = await LocalStore.reducedMotion();
      final playerRaw = opened.cards
          .cast<dynamic>()
          .where((c) => c is Map && c['type'] == 'player')
          .cast<Map>()
          .firstOrNull;
      final player = playerRaw == null
          ? null
          : PlayerCardModel.fromJson(Map<String, dynamic>.from(playerRaw));
      if (!mounted) return;
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Pack opening',
        barrierColor: Colors.black.withValues(alpha: .9),
        transitionDuration:
            reduceMotion || MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => _PackOpeningOverlay(
          pack: opened,
          player: player,
          reduceMotion: reduceMotion,
          onView: player == null
              ? null
              : () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    fwrRoute(CardDetailScreen.player(player)),
                  );
                },
          onDone: () => Navigator.pop(context),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Crafted a Player Card')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  bool get _albumEmpty {
    final inv = _inv;
    if (inv == null) return true;
    return inv.moments.isEmpty && inv.players.isEmpty && inv.packs.isEmpty;
  }

  Future<void> _seedDemo() async {
    try {
      setState(() => _loading = true);
      final fanId = await _fanId();
      final res = await _api.seedInventory(fanId);
      await _load();
      if (!mounted) return;
      final seeded = res['seeded'] == true;
      _tabs.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            seeded
                ? 'Demo cards loaded — swipe the Moments'
                : 'Album already has cards (seed skipped)',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
          decoration: const InputDecoration(
            labelText: 'Price (FC)',
            hintText: '50',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? 0),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Listed ${p.name} for $price FC')),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _playerActions(PlayerCardModel player) async {
    final pins = await LocalStore.pinnedCards();
    final pinned = pins.contains(player.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              Text(player.name.toUpperCase(), style: display(19)),
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(
                  pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  color: AppColors.orange,
                ),
                title: Text(
                  pinned ? 'Remove from showcase' : 'Pin to fan showcase',
                ),
                subtitle: const Text(
                  'Display up to three cards on your profile',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final next = [...pins];
                  if (pinned) {
                    next.remove(player.id);
                  } else {
                    if (next.length >= 3) next.removeAt(0);
                    next.add(player.id);
                  }
                  await LocalStore.setPinnedCards(next);
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          pinned
                              ? 'Removed from showcase'
                              : 'Pinned to your fan showcase',
                        ),
                      ),
                    );
                },
              ),
              ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: const Text('List on Market'),
                onTap: () {
                  Navigator.pop(ctx);
                  _listForSale(player);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _mint(PlayerCardModel p) async {
    try {
      final fanId = await _fanId();
      final res = await _api.mintCard(fanId, p.id);
      await _load();
      if (mounted) {
        final sig = res['signature'] ?? res['tx'] ?? 'ok';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Minted on Solana — $sig')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('501') || e.toString().contains('anchor')
                  ? 'On-chain mint unavailable (anchor not configured)'
                  : '$e',
            ),
          ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Purchased')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _cancelListing(Map listing) async {
    try {
      final fanId = await _fanId();
      await _api.marketCancel(fanId, listing['id'].toString());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Listing cancelled')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _buyShop(String tierId) async {
    try {
      final fanId = await _fanId();
      await _api.shopBuy(fanId, tierId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pack purchased — check Packs tab')),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  int get _fc {
    final w = _wallet?['wallet'];
    if (w is Map) {
      final c = w['credits'];
      if (c is num) return c.toInt();
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
          child: Row(
            children: [
              Text('ALBUM', style: display(22)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      color: Color(0xFFB8FF36),
                      size: 15,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_fc FC',
                      style: label(color: AppColors.cream, size: 10.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _openStore,
                icon: const Icon(Icons.storefront_rounded, size: 18),
                label: const Text('Store'),
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: AppColors.orange,
          unselectedLabelColor: AppColors.mut,
          indicatorColor: AppColors.orange,
          tabs: const [
            Tab(text: 'Moments'),
            Tab(text: 'Packs'),
            Tab(text: 'Players'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _momentsTab(),
                    _packsTab(),
                    _playersTab(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _emptyDemoPrompt({required String hint}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_err == 'server') ...[
              Text(
                'Can\'t reach the server — check Settings → Server, then retry.',
                textAlign: TextAlign.center,
                style: body(color: AppColors.mut),
              ),
              const SizedBox(height: 12),
              PrimaryButton('Retry', expand: true, onTap: _load),
              const SizedBox(height: 16),
            ],
            Text(
              hint,
              textAlign: TextAlign.center,
              style: body(color: AppColors.mut),
            ),
            const SizedBox(height: 16),
            if (_showSeedButton)
              PrimaryButton('Load demo cards', expand: true, onTap: _seedDemo),
          ],
        ),
      ),
    );
  }

  bool get _demoMode => ApiClient.instance.cachedConfig?.mode == 'simulation';
  bool get _showSeedButton => _demoMode;

  Widget _momentFilters() {
    const kinds = ['all', 'goal', 'yellow', 'red', 'corner', 'market-swing'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kinds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final value = kinds[i];
                final on = value == _kindFilter;
                return ChoiceChip(
                  selected: on,
                  onSelected: (_) => setState(() => _kindFilter = value),
                  label: Text(
                    value == 'all'
                        ? 'ALL'
                        : '${kindGlyph(value)} ${value.toUpperCase()}',
                  ),
                  labelStyle: label(
                    color: on ? AppColors.cream : AppColors.mut,
                    size: 8.5,
                  ),
                  selectedColor: AppColors.ink,
                  backgroundColor: AppColors.cardAlt,
                  side: BorderSide(color: on ? AppColors.ink : AppColors.line),
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('RARITY', style: label(color: AppColors.mut, size: 8.5)),
              const SizedBox(width: 7),
              for (var rarity = 0; rarity <= 5; rarity++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _rarityFilter = rarity),
                    child: Container(
                      width: rarity == 0 ? 30 : 27,
                      height: 27,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _rarityFilter == rarity
                            ? rarityBorder(rarity == 0 ? 1 : rarity)
                            : AppColors.cardAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _rarityFilter == rarity
                              ? Colors.transparent
                              : AppColors.line,
                        ),
                      ),
                      child: Text(
                        rarity == 0 ? 'ALL' : '$rarity★',
                        style: label(
                          color: _rarityFilter == rarity
                              ? Colors.white
                              : AppColors.mut,
                          size: 7.5,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              PopupMenuButton<String>(
                initialValue: _momentSort,
                onSelected: (value) => setState(() => _momentSort = value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'newest', child: Text('Newest first')),
                  PopupMenuItem(value: 'rarest', child: Text('Rarest first')),
                ],
                child: Row(
                  children: [
                    Text(
                      _momentSort == 'rarest' ? 'RAREST' : 'NEWEST',
                      style: label(color: AppColors.orange, size: 8.5),
                    ),
                    const Icon(
                      Icons.swap_vert_rounded,
                      color: AppColors.orange,
                      size: 17,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _packTile(PackModel pack) {
    final elite = pack.weight >= 2.5;
    final rare = pack.weight >= 1.5;
    final title = elite ? 'ELITE' : (rare ? 'RARE' : 'STANDARD');
    final accent = elite
        ? const Color(0xFFB8FF36)
        : (rare ? const Color(0xFF9B6BFF) : AppColors.orangeBright);
    return Container(
      height: 174,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF090D13), Color(0xFF221747)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: -38,
            child: Transform.rotate(
              angle: .3,
              child: Icon(
                Icons.bolt_rounded,
                size: 180,
                color: accent.withValues(alpha: .11),
              ),
            ),
          ),
          Positioned(
            left: 18,
            top: 17,
            child: Text(
              '$title PACK',
              style: display(24, color: AppColors.cream),
            ),
          ),
          Positioned(
            left: 19,
            top: 49,
            child: Text(
              'SEALED COLLECTIBLE · ${pack.weight.toStringAsFixed(2)} WEIGHT',
              style: label(color: accent, size: 8.5),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 18,
            child: Row(
              children: [
                Container(
                  width: 45,
                  height: 62,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, const Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.style_rounded, color: AppColors.ink),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 145,
                  child: Text(
                    'Lift, tear, glow and reveal your player card.',
                    style: body(color: AppColors.mutInk, size: 11.5),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 14,
            bottom: 16,
            child: PrimaryButton('Open', onTap: () => _openPack(pack)),
          ),
        ],
      ),
    );
  }

  void _openStore() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DefaultTabController(
        length: 2,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 4),
                child: Row(
                  children: [
                    Text('STORE', style: display(23)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$_fc FC',
                        style: label(color: const Color(0xFFB8FF36), size: 10),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const TabBar(
                labelColor: AppColors.orange,
                indicatorColor: AppColors.orange,
                tabs: [
                  Tab(text: 'Market'),
                  Tab(text: 'Pack Shop'),
                ],
              ),
              Expanded(child: TabBarView(children: [_marketTab(), _shopTab()])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _momentsTab() {
    final moments =
        (_inv?.moments ?? []).where((m) {
          final kindOk = _kindFilter == 'all' || m.kind == _kindFilter;
          final rarityOk = _rarityFilter == 0 || m.rarity == _rarityFilter;
          return kindOk && rarityOk;
        }).toList()..sort(
          (a, b) => _momentSort == 'rarest'
              ? b.rarity.compareTo(a.rarity)
              : b.createdAt.compareTo(a.createdAt),
        );
    if (moments.isEmpty) {
      return _emptyDemoPrompt(
        hint: _albumEmpty && _demoMode
            ? 'No Moments yet. Load a demo set to try Craft, Packs, and Duels — or watch a replay to mint live.'
            : 'No Moments yet. Join an Official Match Hub or verified replay — confirmed goals and cards mint here.',
      );
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _momentFilters()),
        if (_craftSel.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: PrimaryButton(
                'Craft ${_craftSel.length} Moments → Player',
                onTap: _craftSel.length >= 2 ? _craft : null,
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 2.5 / 3.5,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final m = moments[i];
              final sel = _craftSel.contains(m.id);
              return GyroTiltCard(
                motion: _motion,
                selected: sel,
                borderColor: rarityBorder(m.rarity),
                intensity: 0,
                enableTilt: false,
                rarity: m.rarity,
                seed: cardSeed('${m.id}|${m.artKey ?? m.kind}'),
                foilAccent: kindAccent(m.kind),
                reduceParallax: true,
                onTap: () => Navigator.push(
                  context,
                  fwrRoute(
                    CardDetailScreen.moment(m, onVerify: () => _verify(m)),
                  ),
                ),
                onLongPress: () {
                  HapticFeedback.selectionClick();
                  setState(
                    () => sel ? _craftSel.remove(m.id) : _craftSel.add(m.id),
                  );
                },
                child: MomentCardFace(
                  title: m.label,
                  matchLabel: m.matchLabel,
                  kind: m.kind,
                  rarity: m.rarity,
                  minute: m.minute,
                  calledIt: m.calledIt,
                  imageUrl: m.imageUrl,
                  playerId: m.playerId,
                  playerName: m.playerName,
                  teamCode: m.teamCode,
                  artKey: m.artKey,
                ),
              );
            }, childCount: moments.length),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              'Tap to inspect · long-press to select for Craft',
              textAlign: TextAlign.center,
              style: body(size: 11, color: AppColors.mut),
            ),
          ),
        ),
      ],
    );
  }

  Widget _packsTab() {
    final packs = (_inv?.packs ?? []).where((p) => !p.opened).toList();
    if (packs.isEmpty) {
      return _albumEmpty && _demoMode
          ? _emptyDemoPrompt(
              hint: 'No packs yet. Load demo cards to get unopened packs.',
            )
          : Center(
              child: Text(
                'No unopened packs — earn Moments or buy in Shop',
                style: body(color: AppColors.mut),
              ),
            );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: packs.map(_packTile).toList(),
    );
  }

  Widget _playersTab() {
    final players = _inv?.players ?? [];
    final skills = _inv?.skills ?? [];
    if (players.isEmpty && skills.isEmpty) {
      return _albumEmpty && _demoMode
          ? _emptyDemoPrompt(
              hint:
                  'No Player Cards yet. Load demo cards to duel and list on Market.',
            )
          : Center(
              child: Text(
                'Open a pack to get Player Cards',
                style: body(color: AppColors.mut),
              ),
            );
    }
    return CustomScrollView(
      slivers: [
        if (players.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                childAspectRatio: 2.5 / 3.5,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final p = players[i];
                return GyroTiltCard(
                  motion: _motion,
                  borderColor: teamColor(p.teamCode),
                  intensity: 0,
                  enableTilt: false,
                  rarity: 3,
                  seed: cardSeed('${p.id}|${p.teamCode}'),
                  foilAccent: teamColor(p.teamCode),
                  reduceParallax: true,
                  frameShape: CardFrameShape.stadiumCrown,
                  onLongPress: () => _playerActions(p),
                  onTap: () => Navigator.push(
                    context,
                    fwrRoute(
                      CardDetailScreen.player(
                        p,
                        onPrimary: () => _mint(p),
                        primaryLabel: 'Mint on Solana',
                      ),
                    ),
                  ),
                  child: PlayerCardFace(
                    playerId: p.playerId,
                    name: p.name,
                    teamCode: p.teamCode,
                    position: p.position,
                    imageUrl: p.imageUrl,
                    axes: p.axes,
                    frameShape: CardFrameShape.stadiumCrown,
                  ),
                );
              }, childCount: players.length),
            ),
          ),
        if (players.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Tap to inspect · long-press to pin or list on Market',
                textAlign: TextAlign.center,
                style: body(size: 11, color: AppColors.mut),
              ),
            ),
          ),
        if (skills.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('SKILLS', style: label(weight: FontWeight.w800)),
            ),
          ),
        if (skills.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                childAspectRatio: 2.5 / 3.5,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final s = skills[i];
                return GyroTiltCard(
                  motion: _motion,
                  intensity: 0,
                  enableTilt: false,
                  rarity: 3,
                  seed: cardSeed('${s.id}|${s.name}'),
                  borderColor: const Color(0xFFB8FF36),
                  foilAccent: const Color(0xFF9B6BFF),
                  reduceParallax: true,
                  onTap: () => Navigator.push(
                    context,
                    fwrRoute(CardDetailScreen.skill(s)),
                  ),
                  child: SkillCardFace(
                    name: s.name,
                    description: s.description,
                    effect: s.effect,
                  ),
                );
              }, childCount: skills.length),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _marketTab() {
    if (_listings.isEmpty && _myListings.isEmpty) {
      return Center(
        child: Text(
          'No listings yet — list a Player Card from the Players tab.',
          textAlign: TextAlign.center,
          style: body(color: AppColors.mut),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
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
      ],
    );
  }

  Widget _listingTile(Map<String, dynamic> L, {required bool mine}) {
    final card = L['card'] is Map
        ? Map<String, dynamic>.from(L['card'] as Map)
        : <String, dynamic>{};
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: label(weight: FontWeight.w800)),
                Text(
                  '$price FC · ${L['sellerName'] ?? 'seller'}',
                  style: body(size: 12, color: AppColors.mut),
                ),
              ],
            ),
          ),
          if (mine)
            GhostButton('Cancel', onTap: () => _cancelListing(L))
          else
            PrimaryButton('Buy', onTap: () => _buyListing(L)),
        ],
      ),
    );
  }

  Widget _shopTab() {
    if (_shopTiers.isEmpty) {
      return Center(
        child: Text(
          'Shop unavailable — check server connection',
          style: body(color: AppColors.mut),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Spend Fan Credits on packs. Bought packs add variety — not raw power.',
          style: body(size: 13, color: AppColors.mut),
        ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t['label']?.toString() ?? t['id'].toString(),
                  style: label(weight: FontWeight.w800, size: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  t['blurb']?.toString() ?? '',
                  style: body(size: 12, color: AppColors.mut),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${t['priceFC']} FC',
                      style: label(
                        weight: FontWeight.w800,
                        color: AppColors.orange,
                      ),
                    ),
                    const Spacer(),
                    PrimaryButton(
                      'Buy',
                      onTap: () => _buyShop(t['id'].toString()),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _PackOpeningOverlay extends StatefulWidget {
  final PackModel pack;
  final PlayerCardModel? player;
  final VoidCallback? onView;
  final VoidCallback onDone;
  final bool reduceMotion;
  const _PackOpeningOverlay({
    required this.pack,
    required this.player,
    required this.onView,
    required this.onDone,
    required this.reduceMotion,
  });

  @override
  State<_PackOpeningOverlay> createState() => _PackOpeningOverlayState();
}

class _PackOpeningOverlayState extends State<_PackOpeningOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final CardMotionController _motion = CardMotionController();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.reduceMotion ||
          MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final accent = widget.pack.weight >= 2.5
        ? const Color(0xFFB8FF36)
        : widget.pack.weight >= 1.5
        ? const Color(0xFF9B6BFF)
        : AppColors.orangeBright;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            final t = _controller.value;
            final reveal = Curves.easeOutBack.transform(
              ((t - .48) / .52).clamp(0, 1),
            );
            final lift = Curves.easeOutCubic.transform((t / .42).clamp(0, 1));
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          accent.withValues(alpha: .35 * reveal),
                          const Color(0xFF080A0E),
                        ],
                        radius: .8,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SparkPainter(progress: reveal, color: accent),
                    ),
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: Offset(0, 34 * (1 - lift)),
                    child: Transform.scale(
                      scale: t < .48 ? .82 + .18 * lift : .72 + .28 * reveal,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .0016)
                          ..rotateY((1 - reveal) * 3.14159),
                        child: SizedBox(
                          width: 250,
                          height: 350,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: t < .48
                                ? Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          accent,
                                          const Color(0xFF8B5CF6),
                                          const Color(0xFF080A0E),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      border: Border.all(
                                        color: Colors.white30,
                                        width: 2,
                                      ),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Positioned.fill(
                                          child: Opacity(
                                            opacity: .42,
                                            child: CollectibleCardBack(
                                              label: '',
                                              accent: accent,
                                            ),
                                          ),
                                        ),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'FINAL',
                                              style: display(
                                                34,
                                                color: Colors.white,
                                              ),
                                            ),
                                            Text(
                                              'WHISTLE',
                                              style: display(
                                                34,
                                                color: AppColors.ink,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'SEALED PACK',
                                              style: label(
                                                color: Colors.white,
                                                size: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (t > .32)
                                          Positioned(
                                            top: 0,
                                            left: 0,
                                            right: 0,
                                            child: Container(
                                              height: 8,
                                              color: Colors.white.withValues(
                                                alpha: .8,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  )
                                : (player == null
                                      ? Container(
                                          color: AppColors.ink,
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${widget.pack.cards.length} CARDS',
                                            style: display(
                                              26,
                                              color: Colors.white,
                                            ),
                                          ),
                                        )
                                      : GyroTiltCard(
                                          motion: _motion,
                                          intensity: 1,
                                          enableTilt: true,
                                          rarity: widget.pack.weight >= 2.5
                                              ? 5
                                              : widget.pack.weight >= 1.5
                                              ? 4
                                              : 3,
                                          seed: cardSeed(
                                            '${player.id}|${widget.pack.id}',
                                          ),
                                          borderColor: accent,
                                          frameShape:
                                              CardFrameShape.stadiumCrown,
                                          child: PlayerCardFace(
                                            playerId: player.playerId,
                                            name: player.name,
                                            teamCode: player.teamCode,
                                            position: player.position,
                                            imageUrl: player.imageUrl,
                                            axes: player.axes,
                                            frameShape:
                                                CardFrameShape.stadiumCrown,
                                          ),
                                        )),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: 20,
                  child: AnimatedOpacity(
                    opacity: t > .86 ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Column(
                      children: [
                        Text(
                          player?.name.toUpperCase() ?? 'PACK OPENED',
                          style: display(24, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        if (widget.onView != null)
                          PrimaryButton(
                            'View Card',
                            icon: Icons.view_in_ar_rounded,
                            expand: true,
                            onTap: widget.onView,
                          ),
                        const SizedBox(height: 8),
                        GhostButton(
                          'Back to Album',
                          expand: true,
                          onTap: widget.onDone,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _SparkPainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: .75 * progress)
      ..strokeWidth = 2;
    final center = Offset(size.width / 2, size.height / 2 - 25);
    for (var i = 0; i < 18; i++) {
      final angle = i * 6.28318 / 18;
      final inner = 128 + 28 * progress;
      final outer = inner + 42 * progress;
      canvas.drawLine(
        center + Offset.fromDirection(angle, inner),
        center + Offset.fromDirection(angle, outer),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
