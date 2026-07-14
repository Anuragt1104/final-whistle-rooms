import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../state/identity.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The World Cup Pass — the platform's battle pass. One pass per football
/// season; XP flows from every loop (calls, moments, packs, duels, trades).
class PassScreen extends StatefulWidget {
  const PassScreen({super.key});
  @override
  State<PassScreen> createState() => _PassScreenState();
}

class _PassScreenState extends State<PassScreen> {
  final _api = ApiClient.instance;
  Map<String, dynamic>? _data;
  String? _err;
  String _fanId = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final id = await IdentityStore.getOrCreate();
      _fanId = id.pubkey;
      final d = await _api.passState(_fanId);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _err = 'Pass needs the server — $e');
    }
  }

  Map<String, dynamic> get _state =>
      (_data?['state'] ?? {}) as Map<String, dynamic>;
  List<dynamic> get _track => (_data?['track'] ?? []) as List<dynamic>;
  int get _tier => (_state['tier'] ?? 0) as int;
  int get _xp => (_state['xp'] ?? 0) as int;
  int get _xpPerTier => (_data?['xpPerTier'] ?? 100) as int;
  bool get _premium => (_state['premium'] ?? false) as bool;
  List<dynamic> get _claimed => (_state['claimed'] ?? []) as List<dynamic>;

  Future<void> _unlock() async {
    setState(() => _busy = true);
    try {
      await _api.passUnlock(_fanId);
      HapticFeedback.heavyImpact();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🏆 Premium pass unlocked — the whole track is yours',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim(int tier, String lane) async {
    try {
      final res = await _api.passClaim(_fanId, tier, lane);
      HapticFeedback.mediumImpact();
      await _load();
      if (mounted) {
        final label =
            ((res['reward'] ?? {}) as Map<String, dynamic>)['label'] ??
            'Reward';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('✓ Claimed — $label')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final priceUsd = _data?['priceUsd'] ?? 15;
    final xpInTier = _xp % _xpPerTier;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.cream,
        title: Text(
          'WORLD CUP PASS',
          style: display(18, color: AppColors.cream),
        ),
      ),
      body: _err != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _err!,
                  textAlign: TextAlign.center,
                  style: body(color: AppColors.mut),
                ),
              ),
            )
          : _data == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.orange),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // season hero: tier + XP bar + premium CTA
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _state['season'] ?? 'World Cup 2026',
                            style: label(color: AppColors.mutInk, size: 10),
                          ),
                          const Spacer(),
                          if (_premium)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.gold,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                'PREMIUM',
                                style: label(
                                  color: AppColors.ink,
                                  size: 9,
                                  weight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'TIER $_tier',
                            style: display(34, color: AppColors.cream),
                          ),
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '$xpInTier / $_xpPerTier XP to next',
                              style: body(color: AppColors.mutInk, size: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: xpInTier / _xpPerTier,
                          minHeight: 8,
                          backgroundColor: AppColors.inkSoft,
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.orange,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'XP from every loop: correct calls, minted Moments, packs, crafts, duels and trades.',
                        style: body(color: AppColors.mutInk, size: 11),
                      ),
                      if (!_premium) ...[
                        const SizedBox(height: 12),
                        PrimaryButton(
                          _busy ? 'Unlocking…' : 'Unlock Premium · \$$priceUsd',
                          icon: Icons.workspace_premium_rounded,
                          expand: true,
                          busy: _busy,
                          onTap: _unlock,
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: Text(
                            'Cosmetics, capacity and access — never pay-to-win.',
                            style: body(color: AppColors.mutInk, size: 10.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // the track
                ...List.generate(20, (i) {
                  final tier = i + 1;
                  final free = _track.firstWhere(
                    (r) => r['tier'] == tier && r['lane'] == 'free',
                    orElse: () => null,
                  );
                  final prem = _track.firstWhere(
                    (r) => r['tier'] == tier && r['lane'] == 'premium',
                    orElse: () => null,
                  );
                  final reached = _tier >= tier;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: cardBox(
                        border: reached ? AppColors.orange : AppColors.line,
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: reached
                                  ? AppColors.orange
                                  : AppColors.cardAlt,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$tier',
                              style: display(
                                16,
                                color: reached ? Colors.white : AppColors.mut,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (free != null) _rewardRow(free, reached),
                                const SizedBox(height: 4),
                                if (prem != null)
                                  _rewardRow(
                                    prem,
                                    reached && _premium,
                                    premiumLane: true,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _rewardRow(dynamic r, bool claimable, {bool premiumLane = false}) {
    final tier = r['tier'] as int;
    final lane = r['lane'] as String;
    final done = _claimed.contains('$tier:$lane');
    return Row(
      children: [
        Icon(
          premiumLane
              ? Icons.workspace_premium_rounded
              : Icons.card_giftcard_rounded,
          size: 14,
          color: premiumLane ? AppColors.gold : AppColors.mut,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            r['label'] ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: body(
              size: 12.5,
              weight: FontWeight.w700,
              color: premiumLane ? AppColors.ink : AppColors.mut,
            ),
          ),
        ),
        if (done)
          const Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: AppColors.orange,
          )
        else if (claimable)
          GhostButton('Claim', onTap: () => _claim(tier, lane))
        else
          Icon(
            Icons.lock_outline_rounded,
            size: 14,
            color: AppColors.mut.withValues(alpha: 0.6),
          ),
      ],
    );
  }
}
