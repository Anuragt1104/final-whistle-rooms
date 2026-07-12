import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/cards.dart';
import '../state/identity.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'duel_screen.dart';

/// Album — Moments, Packs, Player Cards, Craft, Duels.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key});
  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> with SingleTickerProviderStateMixin {
  final _api = ApiClient.instance;
  FanInventory? _inv;
  String? _err;
  bool _loading = true;
  late TabController _tabs;
  final Set<String> _craftSel = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
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
      final raw = await _api.inventory(fanId);
      if (!mounted) return;
      setState(() {
        _inv = FanInventory.fromJson(raw);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Crafted a Player Card')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Text('ALBUM', style: display(22)),
          const Spacer(),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ]),
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
          Tab(text: 'Duels'),
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
                  ]),
      ),
    ]);
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
                Text('${'★' * m.rarity}', style: const TextStyle(color: AppColors.orange)),
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
      return Center(child: Text('No unopened packs', style: body(color: AppColors.mut)));
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
}
