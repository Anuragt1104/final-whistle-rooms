import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/local_store.dart';
import '../theme.dart';
import 'common.dart';

/// The Season Pass paywall — the app's monetization surface. One tournament-long
/// purchase that unlocks the Pro reaction pack, a supporter badge and priority
/// perks. Purchase here is a demo entitlement (stored locally); in production
/// this is where StoreKit / Play Billing plugs in.
/// Returns true when the pass was unlocked.
Future<bool> showSeasonPassSheet(BuildContext context) async {
  final unlocked = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _SeasonPassSheet(),
  );
  return unlocked ?? false;
}

class _SeasonPassSheet extends StatefulWidget {
  const _SeasonPassSheet();
  @override
  State<_SeasonPassSheet> createState() => _SeasonPassSheetState();
}

class _SeasonPassSheetState extends State<_SeasonPassSheet> {
  bool _busy = false;

  Future<void> _unlock() async {
    setState(() => _busy = true);
    // Demo purchase: instant entitlement. Swap for Play Billing / StoreKit.
    await Future.delayed(const Duration(milliseconds: 650));
    await LocalStore.setPro(true);
    HapticFeedback.heavyImpact();
    if (mounted) Navigator.pop(context, true);
  }

  Widget _perk(String emoji, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: body(weight: FontWeight.w800, size: 14)),
                const SizedBox(height: 1),
                Text(sub, style: body(color: AppColors.mut, size: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // hero
            Container(
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text('🏆', style: const TextStyle(fontSize: 34)),
                  const SizedBox(height: 8),
                  Text(
                    'SEASON PASS',
                    style: display(28, color: AppColors.cream, spacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'One pass. Every match of the tournament.',
                    textAlign: TextAlign.center,
                    style: body(color: AppColors.mutInk, size: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _perk(
              '💎',
              'Pro reaction pack',
              '10 exclusive reactions — 🐐 👑 🥶 💯 and more — in every Hub or Party you join',
            ),
            _perk(
              '🛡️',
              'Supporter badge',
              '★ PRO on your leaderboard row + gold badge on your profile',
            ),
            _perk(
              '⚡',
              'Priority Private Parties',
              'Front of the queue when big matches fill up',
            ),
            _perk(
              '🔮',
              'Coming next',
              'Custom Party themes and post-match super-recaps',
            ),
            const SizedBox(height: 6),
            Container(
              decoration: cardBox(),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOURNAMENT PASS',
                        style: label(color: AppColors.mut, size: 9),
                      ),
                      Text('\$4.99', style: display(24, color: AppColors.ink)),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    'one-time · all 104 matches',
                    style: body(color: AppColors.mut, size: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              _busy ? 'Unlocking…' : 'Unlock Season Pass',
              icon: Icons.lock_open_rounded,
              expand: true,
              busy: _busy,
              onTap: _unlock,
            ),
            const SizedBox(height: 8),
            GhostButton(
              'Not now',
              expand: true,
              onTap: () => Navigator.pop(context, false),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Skill-based, points only — the pass never buys an advantage.',
                textAlign: TextAlign.center,
                style: body(color: AppColors.mut, size: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
