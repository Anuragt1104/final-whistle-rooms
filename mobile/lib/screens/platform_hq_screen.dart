import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Platform HQ — the business model as a running system: revenue by layer
/// (pass, packs, marketplace fee, mint fee, ranked rake), live event feed.
/// This is the screen you show an investor.
class PlatformHqScreen extends StatefulWidget {
  const PlatformHqScreen({super.key});
  @override
  State<PlatformHqScreen> createState() => _PlatformHqScreenState();
}

class _PlatformHqScreenState extends State<PlatformHqScreen> {
  Map<String, dynamic>? _hq;
  String? _err;
  Timer? _poll;

  static const _layers = [
    ('pass', 'World Cup Pass', 'season pass sales', Icons.workspace_premium_rounded),
    ('packs', 'Card Packs', 'direct pack purchases', Icons.style_rounded),
    ('market-fee', 'Marketplace', '2% of every trade', Icons.storefront_rounded),
    ('mint-fee', 'Solana Mints', '◎0.005 per on-chain mint', Icons.link_rounded),
    ('queue-rake', 'Ranked Queues', 'entry rake', Icons.emoji_events_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.instance.platformHq();
      if (mounted) setState(() => _hq = d);
    } catch (e) {
      if (mounted) setState(() => _err = 'HQ needs the server — $e');
    }
  }

  String _fmt(num amount, String unit) {
    switch (unit) {
      case 'USD':
        return '\$${amount.toStringAsFixed(0)}';
      case 'lamports':
        return '◎${(amount / 1e9).toStringAsFixed(3)}';
      default:
        return '${amount.toStringAsFixed(0)} FC';
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = (_hq?['totals'] ?? {}) as Map<String, dynamic>;
    final recent = (_hq?['recent'] ?? []) as List<dynamic>;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.cream,
        title: Text('PLATFORM HQ', style: display(18, color: AppColors.cream)),
      ),
      body: _err != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, textAlign: TextAlign.center, style: body(color: AppColors.mut))))
          : _hq == null
              ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text('A gaming platform where football is the content — every layer earns.',
                      style: body(color: AppColors.mut, size: 12.5)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _statTile('${_hq?['fans'] ?? 0}', 'FANS WITH WALLETS')),
                    const SizedBox(width: 8),
                    Expanded(child: _statTile('${_hq?['circulating'] ?? 0}', 'FC CIRCULATING')),
                  ]),
                  const SizedBox(height: 14),
                  const SectionLabel('Revenue by layer'),
                  ..._layers.map((l) {
                    final t = (totals[l.$1] ?? {}) as Map<String, dynamic>;
                    final amount = (t['amount'] ?? 0) as num;
                    final unit = (t['unit'] ?? 'FC') as String;
                    final events = (t['events'] ?? 0) as int;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: cardBox(),
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Icon(l.$4, size: 20, color: amount > 0 ? AppColors.orange : AppColors.mut),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l.$2, style: body(weight: FontWeight.w800, size: 14)),
                              Text(l.$3, style: body(color: AppColors.mut, size: 11)),
                            ]),
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(_fmt(amount, unit), style: display(17, color: amount > 0 ? AppColors.orange : AppColors.mut)),
                            Text('$events events', style: body(color: AppColors.mut, size: 10)),
                          ]),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  const SectionLabel('Live revenue feed'),
                  if (recent.isEmpty)
                    Text('Buy a pack, trade a card or mint on Solana — events land here in real time.',
                        style: body(color: AppColors.mut, size: 12))
                  else
                    ...recent.take(12).map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(e['detail'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(size: 12))),
                            Text(_fmt((e['amount'] ?? 0) as num, (e['unit'] ?? 'FC') as String),
                                style: body(size: 12, weight: FontWeight.w800, color: AppColors.orange)),
                          ]),
                        )),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Roadmap rails: creator cups (10/10 split) · club cards · AI coach · guilds\nWorld Cup → Champions League → every season, forever.',
                      textAlign: TextAlign.center,
                      style: body(color: AppColors.mut, size: 11),
                    ),
                  ),
                ]),
    );
  }

  Widget _statTile(String value, String labelText) => Container(
        decoration: cardBox(),
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Text(value, style: display(22, color: AppColors.orange)),
          const SizedBox(height: 2),
          Text(labelText, style: label(color: AppColors.mut, size: 9)),
        ]),
      );
}
