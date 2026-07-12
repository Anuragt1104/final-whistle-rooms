import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/cards.dart';
import '../state/identity.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _axes = ['finishing', 'chaos', 'clutch', 'marketShock', 'aura'];

class DuelScreen extends StatefulWidget {
  final List<PlayerCardModel> players;
  final List<MomentCard> moments;
  const DuelScreen({super.key, required this.players, required this.moments});

  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> {
  final _api = ApiClient.instance;
  final Set<String> _hand = {};
  TrumpDuelModel? _duel;
  String _axis = 'finishing';
  String? _playCardId;
  String? _err;
  bool _busy = false;

  Future<String> _fanId() async => (await IdentityStore.getOrCreate()).pubkey;

  Future<void> _start({bool arena = false}) async {
    if (_hand.length != 3) {
      setState(() => _err = 'Select exactly 3 Player Cards');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final fanId = await _fanId();
      final hand = _hand.toList();
      Map<String, dynamic> raw;
      if (arena) {
        if (widget.moments.isEmpty) throw Exception('Need a Moment to seed the Arena');
        raw = await _api.createArena(
          fanId: fanId,
          seedMomentId: widget.moments.first.id,
          hand: hand,
        );
      } else {
        raw = await _api.createDuel(fanId: fanId, hand: hand, vsBot: true);
      }
      if (!mounted) return;
      setState(() {
        _duel = TrumpDuelModel.fromJson(raw);
        _busy = false;
        _playCardId = hand.first;
      });
      // Arena may already be finished
      if (_duel!.status == 'finished') return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _playRound() async {
    final duel = _duel;
    final cardId = _playCardId;
    if (duel == null || cardId == null) return;
    setState(() => _busy = true);
    try {
      final fanId = await _fanId();
      final raw = await _api.playDuelRound(
        duelId: duel.id,
        fanId: fanId,
        axis: _axis,
        cardId: cardId,
      );
      if (!mounted) return;
      final next = TrumpDuelModel.fromJson(raw);
      final used = next.rounds.map((r) => (r as Map)['aCardId']?.toString()).whereType<String>().toSet();
      final remaining = duel.challengerHand.where((id) => !used.contains(id)).toList();
      setState(() {
        _duel = next;
        _playCardId = remaining.isNotEmpty ? remaining.first : null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(_duel == null ? 'Build Hand' : 'Trump Duel', style: label(weight: FontWeight.w800)),
        backgroundColor: AppColors.card,
      ),
      body: _duel == null ? _pickHand() : _play(),
    );
  }

  Widget _pickHand() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Select 3 cards for your Hand', style: body()),
        const SizedBox(height: 8),
        ...widget.players.map((p) {
          final on = _hand.contains(p.id);
          return CheckboxListTile(
            value: on,
            title: Text('${p.name} (${p.teamCode})'),
            subtitle: Text('Fin ${p.axes['finishing']} · Chaos ${p.axes['chaos']} · Clutch ${p.axes['clutch']}'),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() {
                if (v == true) {
                  if (_hand.length < 3) _hand.add(p.id);
                } else {
                  _hand.remove(p.id);
                }
              });
            },
          );
        }),
        if (_err != null) Text(_err!, style: body(color: Colors.red)),
        const SizedBox(height: 12),
        PrimaryButton('Duel vs Bot', onTap: _busy ? null : () => _start()),
        const SizedBox(height: 8),
        GhostButton('Moment Arena', expand: true, onTap: _busy || widget.moments.isEmpty ? null : () => _start(arena: true)),
      ],
    );
  }

  Widget _play() {
    final d = _duel!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Code ${d.code} · ${d.status.toUpperCase()}', style: label(weight: FontWeight.w700)),
        if (d.winnerId != null) ...[
          const SizedBox(height: 8),
          Text(d.winnerId == 'bot' ? 'House wins' : 'You win!', style: display(22)),
        ],
        const SizedBox(height: 12),
        ...d.rounds.map((r) {
          final m = r as Map;
          return ListTile(
            dense: true,
            title: Text('R${m['round']} · ${m['axis']}'),
            subtitle: Text('${m['aValue']} vs ${m['bValue']} → ${m['winnerId'] ?? 'draw'}'),
          );
        }),
        if (d.status == 'playing') ...[
          const SizedBox(height: 12),
          Text('Axis', style: label()),
          Wrap(
            spacing: 6,
            children: _axes
                .map((a) => ChoiceChip(
                      label: Text(a),
                      selected: _axis == a,
                      onSelected: (_) => setState(() => _axis = a),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Text('Your card', style: label()),
          ...d.challengerHand.where((id) {
            final used = d.rounds.map((r) => (r as Map)['aCardId']).toSet();
            return !used.contains(id);
          }).map((id) {
            final p = widget.players.firstWhere((x) => x.id == id, orElse: () => widget.players.first);
            return RadioListTile<String>(
              value: id,
              groupValue: _playCardId,
              title: Text(p.name),
              onChanged: (v) => setState(() => _playCardId = v),
            );
          }),
          PrimaryButton('Play round', onTap: _busy || _playCardId == null ? null : _playRound),
        ],
        if (_err != null) Text(_err!, style: body(color: Colors.red)),
      ],
    );
  }
}
