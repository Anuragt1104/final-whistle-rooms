import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../theme.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import '../widgets/ticket.dart';
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
  String _visibility = 'public';
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
      if (fx != null && _roomCtrl.text.isEmpty) _roomCtrl.text = '${fx.home.name} watch-along';
    });
  }

  Fixture? _fixtureById(String? id) {
    for (final f in _fixtures) {
      if (f.id == id) return f;
    }
    return null;
  }

  Future<void> _pickMatch() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Text('PICK A MATCH', style: display(20))),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _fixtures
                  .map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, f.id),
                          child: Container(
                            decoration: cardBox(border: _fixtureId == f.id ? AppColors.orange : AppColors.line),
                            padding: const EdgeInsets.all(12),
                            child: Row(children: [
                              Expanded(
                                child: Row(children: [
                                  Text('${f.home.flag} ', style: const TextStyle(fontSize: 15)),
                                  Text(f.home.code, style: body(weight: FontWeight.w800, size: 14)),
                                  Text('  v  ', style: body(color: AppColors.mut)),
                                  Text(f.away.code, style: body(weight: FontWeight.w800, size: 14)),
                                  Text(' ${f.away.flag}', style: const TextStyle(fontSize: 15)),
                                ]),
                              ),
                              Text(f.status == 'live' ? 'LIVE' : relativeKickoff(f.kickoff), style: label(color: AppColors.mut, size: 10)),
                            ]),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ]),
      ),
    );
    if (picked != null) {
      setState(() {
        _fixtureId = picked;
        final fx = _fixtureById(picked);
        if (fx != null) _roomCtrl.text = '${fx.home.name} watch-along';
      });
    }
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
        name: _roomCtrl.text.trim().isEmpty ? '${fx?.home.name ?? "World Cup"} watch-along' : _roomCtrl.text.trim(),
        fixtureId: _fixtureId!,
        draft: _draft,
        nextSwing: _nextSwing,
        hostName: name,
        hostWallet: identity.pubkey,
        visibility: _visibility,
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
    final fx = _fixtureById(_fixtureId);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: Column(children: [
          const FwrHeader(showBack: true, title: 'Host a room'),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              const SectionLabel('Pick a match'),
              if (fx != null) _matchCard(fx) else Container(height: 64, decoration: cardBox()),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: GestureDetector(onTap: _pickMatch, child: Text('CHANGE MATCH', style: label(color: AppColors.orange, size: 11))),
              ),
              const SizedBox(height: 20),
              const SectionLabel('Room name'),
              TextField(controller: _roomCtrl, decoration: fwrInput('North London Watch-Along')),
              const SizedBox(height: 18),
              const SectionLabel('Your name'),
              TextField(controller: _nameCtrl, decoration: fwrInput('e.g. Ana')),
              const SizedBox(height: 18),
              const SectionLabel('Who can join'),
              Row(children: [
                Expanded(child: _segment('🌍 Public', _visibility == 'public', () => setState(() => _visibility = 'public'))),
                const SizedBox(width: 8),
                Expanded(child: _segment('🔒 Invite only', _visibility == 'invite', () => setState(() => _visibility = 'invite'))),
              ]),
              const SizedBox(height: 18),
              const SectionLabel('Game modes'),
              _modeRow('🏆', 'Tournament Draft', 'Draft a side, earn points as they perform', _draft, () => setState(() => _draft = !_draft)),
              const SizedBox(height: 8),
              _modeRow('⚡', 'Next Swing', 'Live micro-predictions on goals, corners & odds', _nextSwing, () => setState(() => _nextSwing = !_nextSwing)),
              if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err, style: body(color: const Color(0xFFD8392B)))),
              const SizedBox(height: 20),
              PrimaryButton('Go live', icon: Icons.play_arrow_rounded, expand: true, busy: _busy, onTap: _create),
              const SizedBox(height: 8),
              Center(child: Text('A secure on-device Solana identity is created automatically.', style: body(color: AppColors.mut, size: 11))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _matchCard(Fixture f) {
    return Container(
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        TeamBadge(team: f.home, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${f.home.code} V ${f.away.code}', style: display(20, color: AppColors.cream)),
            const SizedBox(height: 3),
            Text('${relativeKickoff(f.kickoff)} · ${kickoffClock(f.kickoff)} · ${f.competition}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mutInk, size: 11.5)),
          ]),
        ),
        const SizedBox(width: 12),
        TeamBadge(team: f.away, size: 40),
      ]),
    );
  }

  Widget _segment(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.orange : AppColors.cardAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.orange : AppColors.line),
        ),
        child: Text(text, style: body(color: active ? Colors.white : AppColors.ink, weight: FontWeight.w800, size: 13.5)),
      ),
    );
  }

  Widget _modeRow(String emoji, String title, String sub, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: cardBox(border: on ? AppColors.orange : AppColors.line),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: body(weight: FontWeight.w800, size: 14)),
              Text(sub, style: body(color: AppColors.mut, size: 11.5)),
            ]),
          ),
          _toggle(on),
        ]),
      ),
    );
  }

  Widget _toggle(bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: on ? AppColors.orange : AppColors.line, borderRadius: BorderRadius.circular(99)),
        child: Align(
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        ),
      );
}
