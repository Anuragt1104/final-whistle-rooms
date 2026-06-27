import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../local/fixtures.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ticket.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;
  bool _showLogin = false;

  final List<_Slide> _slides = const [
    _Slide(
      tag: 'THE TERRACE',
      title: 'WATCH THE\nWORLD CUP\nTOGETHER',
      body: 'A private live room for your group. One place — everyone reacting to every goal, together.',
      visual: _Visual.ticket,
    ),
    _Slide(
      tag: 'NEXT SWING',
      title: 'CALL IT\nLIVE',
      body: 'Predict the next goal, corner or odds swing as it happens. Build streaks and climb the terrace. Points only — no cash staking.',
      visual: _Visual.predict,
    ),
    _Slide(
      tag: 'ON-CHAIN',
      title: 'VERIFIED\nON SOLANA',
      body: 'Every moment the room reacts to is provably real — hashed and anchorable on Solana. Trust, as a fan feature.',
      visual: _Visual.proof,
    ),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_page < _slides.length - 1) {
      _pc.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    } else {
      setState(() => _showLogin = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          child: _showLogin
              ? _LoginCard(onDone: _finish)
              : Column(children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextButton(
                        onPressed: () => setState(() => _showLogin = true),
                        child: Text('Skip', style: body(color: AppColors.mut, weight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pc,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemCount: _slides.length,
                      itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_slides.length, (i) {
                          final on = i == _page;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: on ? 26 : 8,
                            height: 8,
                            decoration: BoxDecoration(color: on ? AppColors.orange : AppColors.line, borderRadius: BorderRadius.circular(99)),
                          );
                        }),
                      ),
                      const SizedBox(height: 18),
                      PrimaryButton(_page < _slides.length - 1 ? 'Continue' : 'Get started', icon: Icons.arrow_forward_rounded, expand: true, onTap: _next),
                    ]),
                  ),
                ]),
        ),
      ),
    );
  }

  Future<void> _finish(String name, String? wallet) async {
    final id = await IdentityStore.getOrCreate();
    await IdentityStore.sign('final-whistle-rooms:auth:$name:${id.pubkey}');
    await LocalStore.setDisplayName(name);
    if (wallet != null && wallet.isNotEmpty) await LocalStore.setWalletAddress(wallet);
    await LocalStore.setOnboarded();
    if (!mounted) return;
    Navigator.pushReplacement(context, fwrRoute(const HomeScreen()));
  }
}

enum _Visual { ticket, predict, proof }

class _Slide {
  final String tag, title, body;
  final _Visual visual;
  const _Slide({required this.tag, required this.title, required this.body, required this.visual});
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(flex: 2),
        _visual(),
        const Spacer(flex: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(99)),
          child: Text(slide.tag, style: label(color: AppColors.cream, size: 10.5)),
        ),
        const SizedBox(height: 14),
        Text(slide.title, style: display(40, spacing: 0.5)),
        const SizedBox(height: 14),
        Text(slide.body, style: body(color: AppColors.mut, size: 15)),
        const Spacer(flex: 1),
      ]),
    );
  }

  Widget _visual() {
    final teams = localFixtures();
    final f = teams.isNotEmpty ? teams.first : null;
    switch (slide.visual) {
      case _Visual.ticket:
        if (f == null) return const SizedBox(height: 160);
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          builder: (_, s, child) => Transform.scale(scale: s, child: child),
          child: ClipPath(
            clipper: TicketClipper(radius: 18),
            child: Container(
              color: AppColors.ink,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
              child: Row(children: [
                Expanded(child: Column(children: [TeamBadge(team: f.home, size: 50), const SizedBox(height: 8), Text(f.home.code, style: display(16, color: AppColors.cream))])),
                Column(children: [Text('2 - 1', style: display(40, color: AppColors.orangeBright)), const SizedBox(height: 4), Text("67'", style: label(color: AppColors.mutInk, size: 10))]),
                Expanded(child: Column(children: [TeamBadge(team: f.away, size: 50), const SizedBox(height: 8), Text(f.away.code, style: display(16, color: AppColors.cream))])),
              ]),
            ),
          ),
        );
      case _Visual.predict:
        return Container(
          decoration: cardBox(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text('⚡ NEXT SWING', style: label(color: AppColors.ink, size: 11)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)), child: Text('+140', style: label(color: AppColors.orangeBright, size: 10)))]),
            const SizedBox(height: 10),
            Text("Next goal before 27'?", style: display(20)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12), alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(12)), child: Text('ARG', style: body(color: Colors.white, weight: FontWeight.w800)))),
              const SizedBox(width: 8),
              Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12), alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)), child: Text('No goal', style: body(weight: FontWeight.w800)))),
              const SizedBox(width: 8),
              Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12), alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)), child: Text('MEX', style: body(weight: FontWeight.w800)))),
            ]),
          ]),
        );
      case _Visual.proof:
        return Center(
          child: Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(28)),
            child: const Icon(Icons.verified_user_rounded, color: AppColors.orange, size: 64),
          ),
        );
    }
  }
}

class _LoginCard extends StatefulWidget {
  final Future<void> Function(String name, String? wallet) onDone;
  const _LoginCard({required this.onDone});
  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  final _nameCtrl = TextEditingController();
  final _walletCtrl = TextEditingController();
  bool _wallet = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    LocalStore.displayName().then((n) => _nameCtrl.text = n);
  }

  Future<void> _go() async {
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    final name = _nameCtrl.text.trim().isEmpty ? 'Fan' : _nameCtrl.text.trim();
    final w = _wallet ? _walletCtrl.text.trim() : null;
    await widget.onDone(name, w);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        Container(width: 56, height: 56, decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(16)), alignment: Alignment.center, child: const Text('⚽', style: TextStyle(fontSize: 28))),
        const SizedBox(height: 18),
        Text('JOIN THE\nTERRACE', style: display(36, spacing: 0.5)),
        const SizedBox(height: 8),
        Text('Pick a name and you\'re in. A secure on-device Solana identity is created for you — no wallet, no funds.', style: body(color: AppColors.mut, size: 14)),
        const SizedBox(height: 24),
        Text('YOUR NAME', style: label(color: AppColors.ink, size: 11)),
        const SizedBox(height: 8),
        TextField(controller: _nameCtrl, autofocus: true, decoration: fwrInput('e.g. Ana')),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() => _wallet = !_wallet),
          child: Row(children: [
            Icon(_wallet ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: _wallet ? AppColors.orange : AppColors.mut, size: 22),
            const SizedBox(width: 8),
            Text('I have a Solana wallet — connect address', style: body(size: 13.5, weight: FontWeight.w600)),
          ]),
        ),
        if (_wallet) ...[
          const SizedBox(height: 10),
          TextField(controller: _walletCtrl, decoration: fwrInput('Paste your Solana address')),
          const SizedBox(height: 4),
          Text('Used for your profile + leaderboard. Full wallet signing arrives with mainnet.', style: body(color: AppColors.mut, size: 11)),
        ],
        const SizedBox(height: 24),
        PrimaryButton(_busy ? 'Setting up…' : '◎ Continue with Solana', icon: Icons.arrow_forward_rounded, expand: true, busy: _busy, onTap: _go),
        const SizedBox(height: 12),
        Center(child: Text('Skill-based · points & streaks only · no cash staking', style: body(color: AppColors.mut, size: 11))),
      ]),
    );
  }
}
