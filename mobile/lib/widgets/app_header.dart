import 'package:flutter/material.dart';
import '../theme.dart';
import 'common.dart';

/// Paper top bar. Either shows the Brand (home) or a back button + title.
class FwrHeader extends StatelessWidget {
  final bool showBack;
  final String? title;
  final Widget? trailing;
  const FwrHeader({
    super.key,
    this.showBack = false,
    this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 10,
        16,
        10,
      ),
      color: AppColors.paper,
      child: Row(
        children: [
          if (showBack) ...[
            Pressable(
              haptic: HapticFeedbackType.selection,
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.chevron_left,
                  color: AppColors.cream,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (title != null)
            Text(title!.toUpperCase(), style: display(20, spacing: 0.5))
          else
            const Brand(),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

Future<String?> showNameDialog(BuildContext context, {String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('CONTINUE WITH SOLANA', style: display(18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'We create a secure on-device Solana identity for you — no wallet, no funds.',
            style: body(color: AppColors.mut, size: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: fwrInput('Display name e.g. Ana'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: body(color: AppColors.mut)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            ctrl.text.trim().isEmpty ? 'Fan' : ctrl.text.trim(),
          ),
          child: Text(
            'Continue',
            style: body(color: AppColors.orange, weight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

Future<void> showServerSettings(
  BuildContext context,
  String current,
  void Function(String) onSave,
) {
  final ctrl = TextEditingController(text: current);
  return showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('SERVER URL', style: display(18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Point the app at your Final Whistle live backend.\n• iOS simulator: http://localhost:3000\n• Android emulator: http://10.0.2.2:3000\n• Real device: your computer\'s LAN IP or deployed URL',
            style: body(color: AppColors.mut, size: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: fwrInput('http://localhost:3000'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: body(color: AppColors.mut)),
        ),
        TextButton(
          onPressed: () {
            onSave(ctrl.text.trim());
            Navigator.pop(context);
          },
          child: Text(
            'Save',
            style: body(color: AppColors.orange, weight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}
