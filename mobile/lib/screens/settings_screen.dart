import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../data/player_portraits.dart';
import '../state/identity.dart';
import '../state/local_store.dart';
import '../theme.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  final AppConfig? config;
  final String walletAddress;
  final Future<void> Function() onWallet;
  final Future<void> Function() onServerChanged;
  const SettingsScreen({
    super.key,
    required this.config,
    required this.walletAddress,
    required this.onWallet,
    required this.onServerChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _spoiler = false;
  bool _reducedMotion = false;
  String _deviceIdentity = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      LocalStore.defaultSpoilerSafe(),
      LocalStore.reducedMotion(),
      IdentityStore.getOrCreate(),
    ]);
    if (!mounted) return;
    final identity = values[2] as Identity;
    setState(() {
      _spoiler = values[0] as bool;
      _reducedMotion = values[1] as bool;
      _deviceIdentity = identity.short;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Column(
        children: [
          const FwrHeader(showBack: true, title: 'Settings'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                const SectionLabel('Match experience'),
                _switch(
                  Icons.visibility_off_outlined,
                  'Spoiler-safe by default',
                  'Hide live scores until you reveal them',
                  _spoiler,
                  (value) async {
                    await LocalStore.setDefaultSpoilerSafe(value);
                    if (mounted) setState(() => _spoiler = value);
                  },
                ),
                _switch(
                  Icons.motion_photos_off_outlined,
                  'Reduce motion',
                  'Use simpler pack and card transitions',
                  _reducedMotion,
                  (value) async {
                    await LocalStore.setReducedMotion(value);
                    if (mounted) setState(() => _reducedMotion = value);
                  },
                ),
                const SizedBox(height: 16),
                const SectionLabel('Account and data'),
                _row(
                  Icons.account_balance_wallet_outlined,
                  'Wallet',
                  widget.walletAddress.isEmpty
                      ? 'On-device Solana ID · $_deviceIdentity'
                      : widget.walletAddress,
                  widget.onWallet,
                ),
                _row(
                  Icons.bolt_outlined,
                  'Data source',
                  widget.config?.mode == 'live'
                      ? 'Live TxLINE verified feed'
                      : 'Explicit Demo mode',
                  null,
                ),
                if (!kReleaseMode)
                  _row(
                    Icons.dns_outlined,
                    'Developer server',
                    ApiClient.instance.baseUrl,
                    () async {
                      await showServerSettings(
                        context,
                        ApiClient.instance.baseUrl,
                        (url) async {
                          await ApiClient.instance.setBaseUrl(url);
                          await widget.onServerChanged();
                          if (mounted) setState(() {});
                        },
                      );
                    },
                  ),
                _row(
                  Icons.photo_library_outlined,
                  'Player photo credits',
                  '24 reusable portraits · exact-ID mapped',
                  _showPhotoCredits,
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: cardBox(),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.orange,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Live builds never substitute simulated fixtures, scores, players or ratings when TxLINE is unavailable.',
                          style: body(color: AppColors.mut, size: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switch(
    IconData icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    decoration: cardBox(),
    padding: const EdgeInsets.all(13),
    child: Row(
      children: [
        Icon(icon, color: AppColors.ink),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: body(weight: FontWeight.w800, size: 13.5)),
              Text(subtitle, style: body(color: AppColors.mut, size: 11)),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeTrackColor: AppColors.orange,
          onChanged: onChanged,
        ),
      ],
    ),
  );

  Future<void> _showPhotoCredits() async {
    final credits = await loadPortraitAttributions();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('PLAYER PHOTO CREDITS', style: display(20)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  'Bundled from the original Wikimedia Commons source under the license shown. Images are resized, cropped and color-treated inside cards.',
                  style: body(color: AppColors.mut, size: 11),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                  itemCount: credits.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (_, index) {
                    final credit = credits[index];
                    return ListTile(
                      tileColor: AppColors.cream,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          credit.assetPath,
                          width: 46,
                          height: 54,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        credit.name,
                        style: body(weight: FontWeight.w800, size: 13),
                      ),
                      subtitle: Text(
                        '${credit.license} · ${credit.author}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: body(color: AppColors.mut, size: 10),
                      ),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => launchUrl(
                        Uri.parse(credit.sourcePage),
                        mode: LaunchMode.externalApplication,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    IconData icon,
    String title,
    String subtitle,
    Future<void> Function()? onTap,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    child: Pressable(
      onTap: onTap,
      child: Container(
        decoration: cardBox(),
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Icon(icon, color: AppColors.ink),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: label(color: AppColors.mut, size: 8.5),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(weight: FontWeight.w700, size: 12.5),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: AppColors.mut),
          ],
        ),
      ),
    ),
  );
}
