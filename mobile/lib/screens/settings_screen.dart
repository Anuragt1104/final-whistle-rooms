import 'package:flutter/material.dart';

import '../api/api_client.dart';
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
                _row(
                  Icons.dns_outlined,
                  'Server',
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
