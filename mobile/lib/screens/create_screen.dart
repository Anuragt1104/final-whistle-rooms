import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../theme.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import 'room_screen.dart';

class CreateScreen extends StatefulWidget {
  final String? fixtureId;
  const CreateScreen({super.key, this.fixtureId});
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _api = ApiClient.instance;
  List<Fixture> _fixtures = [];
  String? _fixtureId;
  final _roomCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _draft = true, _nextSwing = true, _busy = false;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _fixtureId = widget.fixtureId;
    _boot();
  }

  Future<void> _boot() async {
    _nameCtrl.text = await LocalStore.displayName();
    final f = await _api.fixtures();
    if (!mounted) return;
    setState(() {
      _fixtures = f;
      _fixtureId ??= f.isNotEmpty ? f.first.id : null;
      final fx = _fixtureById(_fixtureId);
      if (fx != null && _roomCtrl.text.isEmpty) _roomCtrl.text = '${fx.home.name} watch party';
    });
  }

  Fixture? _fixtureById(String? id) {
    for (final f in _fixtures) {
      if (f.id == id) return f;
    }
    return null;
  }

  Future<void> _create() async {
    setState(() => _err = '');
    final name = _nameCtrl.text.trim().isEmpty ? 'Host' : _nameCtrl.text.trim();
    if (_fixtureId == null) {
      setState(() => _err = 'Pick a match first');
      return;
    }
    setState(() => _busy = true);
    try {
      final identity = await IdentityStore.getOrCreate();
      await IdentityStore.sign('final-whistle-rooms:auth:$name:${identity.pubkey}');
      await LocalStore.setDisplayName(name);
      final fx = _fixtureById(_fixtureId);
      final res = await _api.createRoom(
        name: _roomCtrl.text.trim().isEmpty ? '${fx?.home.name ?? "World Cup"} watch party' : _roomCtrl.text.trim(),
        fixtureId: _fixtureId!,
        draft: _draft,
        nextSwing: _nextSwing,
        hostName: name,
        hostWallet: identity.pubkey,
      );
      await LocalStore.setMemberId(res.roomId, res.hostId);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RoomScreen(roomId: res.roomId)));
    } catch (e) {
      setState(() {
        _err = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        FwrHeader(small: true, showBack: true, identityLabel: 'Solana', onIdentityTap: () {}),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
            const Text('Create a room', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Spin up a private watch party. Share the code and your group joins on their phones.',
                style: TextStyle(color: AppColors.mut, fontSize: 13)),
            const SizedBox(height: 18),
            const SectionLabel('Match'),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: cardDecoration(),
              child: _fixtures.isEmpty
                  ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                  : ListView(
                      padding: const EdgeInsets.all(4),
                      children: _fixtures.map((f) {
                        final sel = _fixtureId == f.id;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _fixtureId = f.id;
                            _roomCtrl.text = '${f.home.name} watch party';
                          }),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 1),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: sel ? const Color(0x26C7F24D) : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: sel ? const Color(0x66C7F24D) : Colors.transparent),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Row(children: [
                                Text('${f.home.flag} ', style: const TextStyle(fontSize: 15)),
                                Text(f.home.code, style: const TextStyle(fontWeight: FontWeight.w700)),
                                const Text('  v  ', style: TextStyle(color: AppColors.mut)),
                                Text(f.away.code, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(' ${f.away.flag}', style: const TextStyle(fontSize: 15)),
                              ]),
                              Text(f.status == 'live' ? 'LIVE' : relativeKickoff(f.kickoff),
                                  style: const TextStyle(fontSize: 11, color: AppColors.mut)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Room name'),
            TextField(controller: _roomCtrl, decoration: fwrInput('Sunday squad')),
            const SizedBox(height: 14),
            const SectionLabel('Your name'),
            TextField(controller: _nameCtrl, decoration: fwrInput('e.g. Ana')),
            const SizedBox(height: 16),
            const SectionLabel('Game modes'),
            Row(children: [
              Expanded(
                child: _ModeCard(
                  active: _draft,
                  emoji: '🏆',
                  title: 'Tournament Draft',
                  sub: 'Draft a side, earn points as they perform',
                  onTap: () => setState(() => _draft = !_draft),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeCard(
                  active: _nextSwing,
                  emoji: '⚡',
                  title: 'Next Swing',
                  sub: 'Live micro-predictions on goals, corners, odds',
                  onTap: () => setState(() => _nextSwing = !_nextSwing),
                ),
              ),
            ]),
            if (_err.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_err, style: const TextStyle(color: AppColors.away)),
              ),
            const SizedBox(height: 18),
            PrimaryButton('Create room & invite friends', expand: true, busy: _busy, onTap: _create),
            const SizedBox(height: 8),
            const Center(
              child: Text('A secure on-device Solana identity is created automatically.',
                  style: TextStyle(fontSize: 11, color: AppColors.mut)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final bool active;
  final String emoji, title, sub;
  final VoidCallback onTap;
  const _ModeCard({required this.active, required this.emoji, required this.title, required this.sub, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: active ? 1 : 0.6,
        child: Container(
          decoration: cardDecoration(borderColor: active ? AppColors.lime : AppColors.line),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.lime : Colors.transparent,
                  border: Border.all(color: active ? AppColors.lime : AppColors.line),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.mut)),
          ]),
        ),
      ),
    );
  }
}
