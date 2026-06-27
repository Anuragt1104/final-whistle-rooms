import 'package:flutter/material.dart';
import '../theme.dart';
import 'common.dart';

class FwrHeader extends StatelessWidget {
  final bool small;
  final bool showBack;
  final String? mode; // 'simulation' | 'live'
  final String identityLabel;
  final bool connected;
  final VoidCallback onIdentityTap;
  final VoidCallback? onSettings;

  const FwrHeader({
    super.key,
    this.small = false,
    this.showBack = false,
    this.mode,
    required this.identityLabel,
    this.connected = false,
    required this.onIdentityTap,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 8, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xB8070B14),
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(children: [
        if (showBack)
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20, color: AppColors.text),
            onPressed: () => Navigator.of(context).maybePop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        Brand(small: small),
        const Spacer(),
        if (mode != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: AppChip(
              mode == 'live' ? 'Live TxLINE' : 'Replay',
              leading: LiveDot(size: 6, color: mode == 'live' ? AppColors.lime : AppColors.gold),
            ),
          ),
        if (onSettings != null)
          GestureDetector(
            onTap: onSettings,
            child: const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.settings_outlined, size: 18, color: AppColors.mut),
            ),
          ),
        AppChip(identityLabel, color: AppColors.text, leading: const Text('◎', style: TextStyle(fontSize: 12)), onTap: onIdentityTap),
      ]),
    );
  }
}

/// Simple dialog to set a display name and (re)create the Solana identity.
Future<String?> showNameDialog(BuildContext context, {String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.pitch850,
      title: const Text('Continue with Solana', style: TextStyle(fontSize: 17)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'We create a secure on-device Solana identity for you — no wallet, no funds.',
          style: TextStyle(color: AppColors.mut, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(controller: ctrl, autofocus: true, decoration: fwrInput('Display name e.g. Ana')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim().isEmpty ? 'Fan' : ctrl.text.trim()),
          child: const Text('Continue', style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

Future<void> showServerSettings(BuildContext context, String current, void Function(String) onSave) {
  final ctrl = TextEditingController(text: current);
  return showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.pitch850,
      title: const Text('Server URL', style: TextStyle(fontSize: 17)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Point the app at your Final Whistle Rooms backend.\n• iOS simulator: http://localhost:3000\n• Android emulator: http://10.0.2.2:3000\n• Real device: your computer\'s LAN IP or deployed URL',
          style: TextStyle(color: AppColors.mut, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        TextField(controller: ctrl, decoration: fwrInput('http://localhost:3000')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            onSave(ctrl.text.trim());
            Navigator.pop(context);
          },
          child: const Text('Save', style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}
