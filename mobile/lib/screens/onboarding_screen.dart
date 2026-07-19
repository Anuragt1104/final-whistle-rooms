import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../solana/wallet_connect.dart';
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
      tag: 'OFFICIAL MATCH HUB',
      title: 'WATCH THE\nWORLD CUP\nTOGETHER',
      body:
          'Join the shared Official Match Hub for every live fixture, or open an invite-only Private Party for your friends.',
      visual: _Visual.ticket,
    ),
    _Slide(
      tag: 'LIVE CALLS',
      title: 'CALL IT\nLIVE',
      body:
          'Choose a side in Team Draft and answer clear Live Calls as the match unfolds. Build streaks with points only — never cash.',
      visual: _Visual.predict,
    ),
    _Slide(
      tag: 'ON-CHAIN',
      title: 'VERIFIED\nON SOLANA',
      body:
          'TxLINE-confirmed goals and cards become collectible Moments with a verifiable event proof and stable source identity.',
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
      _pc.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      setState(() => _showLogin = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: StadiumColors.canvas,
        body: SafeArea(
          child: _showLogin
              ? _LoginCard(onDone: _finish)
              : Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextButton(
                          onPressed: () => setState(() => _showLogin = true),
                          child: Text(
                            'Skip',
                            style: body(
                              color: AppColors.mut,
                              weight: FontWeight.w700,
                            ),
                          ),
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
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_slides.length, (i) {
                              final on = i == _page;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: on ? 26 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: on
                                      ? StadiumColors.orange
                                      : StadiumColors.hairline,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 18),
                          PrimaryButton(
                            _page < _slides.length - 1
                                ? 'Continue'
                                : 'Get started',
                            icon: Icons.arrow_forward_rounded,
                            expand: true,
                            onTap: _next,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _finish(String name, String? wallet, String favorite) async {
    final id = await IdentityStore.getOrCreate();
    await IdentityStore.sign('final-whistle-rooms:auth:$name:${id.pubkey}');
    await LocalStore.setDisplayName(name);
    if (favorite.isNotEmpty) await LocalStore.setFavoriteTeam(favorite);
    if (wallet != null && wallet.isNotEmpty)
      await LocalStore.setWalletAddress(wallet);
    await LocalStore.setOnboarded();
    if (!mounted) return;
    Navigator.pushReplacement(context, fwrRoute(const HomeScreen()));
  }
}

enum _Visual { ticket, predict, proof }

class _Slide {
  final String tag, title, body;
  final _Visual visual;
  const _Slide({
    required this.tag,
    required this.title,
    required this.body,
    required this.visual,
  });
}

class _SlideView extends StatefulWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  State<_SlideView> createState() => _SlideViewState();
}

class _SlideViewState extends State<_SlideView> {
  String? _samplePick;
  _Slide get slide => widget.slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          _visual(),
          const Spacer(flex: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              slide.tag,
              style: label(color: AppColors.cream, size: 10.5),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            slide.title,
            style: display(40, color: StadiumColors.text, spacing: 0.5),
          ),
          const SizedBox(height: 14),
          Text(slide.body, style: body(color: StadiumColors.muted, size: 15)),
          const Spacer(flex: 1),
        ],
      ),
    );
  }

  Widget _visual() {
    switch (slide.visual) {
      case _Visual.ticket:
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          builder: (_, s, child) => Transform.scale(scale: s, child: child),
          child: ClipPath(
            clipper: TicketClipper(radius: 18),
            child: Container(
              decoration: stadiumGradientPanel(accent: StadiumColors.orange),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      const LiveDot(color: StadiumColors.live),
                      const SizedBox(width: 6),
                      Text(
                        'ONE SHARED OFFICIAL HUB',
                        style: label(color: StadiumColors.live, size: 8.5),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.groups_rounded,
                        color: StadiumColors.muted,
                        size: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _crest('HOME', StadiumColors.violet),
                      Column(
                        children: [
                          Text(
                            'LIVE',
                            style: display(36, color: StadiumColors.text),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'SCORE · EVENTS · FRIENDS',
                            style: label(color: StadiumColors.muted, size: 7.5),
                          ),
                        ],
                      ),
                      _crest('AWAY', StadiumColors.orange),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      case _Visual.predict:
        return Container(
          decoration: cardBox(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'LIVE CALL · POINTS ONLY',
                    style: label(color: AppColors.ink, size: 11),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'MOMENT',
                      style: label(color: AppColors.orangeBright, size: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Who wins the next corner?', style: display(20)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _sampleOption('Home')),
                  const SizedBox(width: 8),
                  Expanded(child: _sampleOption('Neither')),
                  const SizedBox(width: 8),
                  Expanded(child: _sampleOption('Away')),
                ],
              ),
              if (_samplePick != null) ...[
                const SizedBox(height: 9),
                Text(
                  'Locked: $_samplePick · a correct live Call earns a Moment.',
                  style: body(color: AppColors.mut, size: 10.5),
                ),
              ],
            ],
          ),
        );
      case _Visual.proof:
        return Center(
          child: Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppColors.orange,
              size: 64,
            ),
          ),
        );
    }
  }

  Widget _crest(String text, Color accent) => Column(
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [accent, accent.withValues(alpha: .25)],
          ),
          border: Border.all(color: Colors.white24),
        ),
        child: const Icon(
          Icons.sports_soccer_rounded,
          color: Colors.white,
          size: 23,
        ),
      ),
      const SizedBox(height: 7),
      Text(text, style: label(color: StadiumColors.textSoft, size: 8)),
    ],
  );

  Widget _sampleOption(String option) {
    final selected = _samplePick == option;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _samplePick = option);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.orange : AppColors.cardAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.orange : AppColors.line,
          ),
        ),
        child: Text(
          option,
          style: body(
            color: selected ? Colors.white : AppColors.ink,
            weight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatefulWidget {
  final Future<void> Function(String name, String? wallet, String favorite)
  onDone;
  const _LoginCard({required this.onDone});
  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  final _nameCtrl = TextEditingController();
  final _walletCtrl = TextEditingController();
  bool _wallet = false;
  bool _busy = false;
  bool _walletAvail = false;
  bool _connecting = false;
  String? _connected; // base58 pubkey from a real wallet
  String _favorite = '';

  static const _favoriteTeams = [
    'ARG',
    'BRA',
    'ENG',
    'ESP',
    'FRA',
    'GER',
    'POR',
    'USA',
    'MEX',
    'JPN',
  ];

  @override
  void initState() {
    super.initState();
    LocalStore.displayName().then((n) => _nameCtrl.text = n);
    WalletConnect.isAvailable().then(
      (v) => mounted ? setState(() => _walletAvail = v) : null,
    );
  }

  Future<void> _connectWallet() async {
    setState(() => _connecting = true);
    try {
      final res = await WalletConnect.connect();
      if (res != null) {
        setState(() => _connected = res.pubkey);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wallet connection cancelled')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No Solana wallet found — install Phantom/Solflare, or paste an address',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  String _short(String pk) =>
      '${pk.substring(0, 4)}…${pk.substring(pk.length - 4)}';

  Future<void> _go() async {
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    final name = _nameCtrl.text.trim().isEmpty ? 'Fan' : _nameCtrl.text.trim();
    final w = _connected ?? (_wallet ? _walletCtrl.text.trim() : null);
    await widget.onDone(name, w, _favorite);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/icon/icon.png',
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'BUILD YOUR\nMATCHDAY',
            style: display(36, color: StadiumColors.text, spacing: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Pick a name and you\'re in. A secure on-device Solana identity is created for you — no wallet, no funds.',
            style: body(color: StadiumColors.muted, size: 14),
          ),
          const SizedBox(height: 24),
          Text(
            'YOUR NAME',
            style: label(color: StadiumColors.textSoft, size: 11),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            style: body(color: StadiumColors.text, size: 14),
            decoration: fwrInput('e.g. Ana'),
          ),
          const SizedBox(height: 18),
          Text(
            'FAVORITE TEAM',
            style: label(color: StadiumColors.textSoft, size: 11),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _favoriteTeams.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (_, index) {
                final code = _favoriteTeams[index];
                final selected = code == _favorite;
                return ChoiceChip(
                  selected: selected,
                  showCheckmark: false,
                  label: Text(code),
                  onSelected: (_) => setState(() => _favorite = code),
                  selectedColor: StadiumColors.orange,
                  backgroundColor: StadiumColors.panel,
                  side: BorderSide(
                    color: selected
                        ? StadiumColors.orange
                        : StadiumColors.hairline,
                  ),
                  labelStyle: body(
                    color: selected ? Colors.white : StadiumColors.textSoft,
                    size: 11,
                    weight: FontWeight.w800,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'You can change this later. It only personalizes fixtures and colors.',
            style: body(color: StadiumColors.muted, size: 10.5),
          ),
          const SizedBox(height: 16),
          // Real wallet connect (Mobile Wallet Adapter) when a wallet app is detected
          if (_connected != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0x14E9531E),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.orange),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Wallet connected ◎ ${_short(_connected!)}',
                    style: body(
                      color: StadiumColors.text,
                      weight: FontWeight.w700,
                      size: 13.5,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _connected = null),
                    child: Text(
                      'Change',
                      style: body(color: StadiumColors.muted, size: 12),
                    ),
                  ),
                ],
              ),
            )
          else if (_walletAvail)
            GhostButton(
              _connecting ? 'Opening wallet…' : '◎ Connect Solana wallet',
              expand: true,
              onTap: _connecting ? null : _connectWallet,
            )
          else
            GestureDetector(
              onTap: () => setState(() => _wallet = !_wallet),
              child: Row(
                children: [
                  Icon(
                    _wallet
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: _wallet ? StadiumColors.orange : StadiumColors.muted,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Have a Solana wallet? Paste your address',
                    style: body(
                      color: StadiumColors.textSoft,
                      size: 13.5,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (_connected == null && _wallet && !_walletAvail) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _walletCtrl,
              style: body(color: StadiumColors.text, size: 14),
              decoration: fwrInput('Paste your Solana address'),
            ),
          ],
          if (_connected == null && _walletAvail) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Detected a wallet app on your device',
                style: body(color: StadiumColors.muted, size: 11),
              ),
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            _busy ? 'Setting up…' : '◎ Continue with Solana',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            busy: _busy,
            onTap: _go,
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Notifications follow watched fixtures only · points, never cash',
              style: body(color: StadiumColors.muted, size: 11),
            ),
          ),
        ],
      ),
    );
  }
}
