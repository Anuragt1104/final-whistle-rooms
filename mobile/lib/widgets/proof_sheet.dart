import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../theme.dart';
import 'common.dart';

Future<void> showProofSheet(BuildContext context, String roomId, bool isHost) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _ProofSheet(roomId: roomId, isHost: isHost),
  );
}

class _ProofSheet extends StatefulWidget {
  final String roomId;
  final bool isHost;
  const _ProofSheet({required this.roomId, required this.isHost});
  @override
  State<_ProofSheet> createState() => _ProofSheetState();
}

class _ProofSheetState extends State<_ProofSheet> {
  Map<String, dynamic>? proof;
  String? error;
  bool anchoring = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ApiClient.instance.proof(widget.roomId);
      setState(() => proof = p);
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _anchor() async {
    setState(() => anchoring = true);
    try {
      await ApiClient.instance.anchor(widget.roomId);
      await _load();
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => anchoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sample = proof?['sample'] as Map<String, dynamic>?;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 26),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 14),
          Text('VERIFIED BY TXLINE', style: display(18)),
          const SizedBox(height: 8),
          Text(
            'This match\'s live data is attested by the TxLINE oracle — every stat is committed to TxLINE\'s on-chain Merkle tree, fetched live from /api/scores/stat-validation. Not our number: TxLINE\'s.',
            style: body(color: AppColors.mut, size: 13),
          ),
          const SizedBox(height: 14),
          if (proof == null && error == null)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.orange)))
          else if (error != null)
            Text(error!, style: body(color: const Color(0xFFD8392B)))
          else ...[
            _txlineBlock(),
            const SizedBox(height: 14),
            Text('ROOM ACTIVITY COMMITMENT', style: label(color: AppColors.ink, size: 11, weight: FontWeight.w800)),
            const SizedBox(height: 8),
            _field('Events anchored (Merkle leaves)', '${proof!['leafCount']}'),
            const SizedBox(height: 10),
            _field('Merkle root (SHA-256)', proof!['root'] ?? '', mono: true, accent: AppColors.orange),
            if (sample != null) ...[
              const SizedBox(height: 12),
              _box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('LIVE INCLUSION PROOF — LATEST EVENT', style: label(color: AppColors.mut, size: 9.5)),
                const SizedBox(height: 6),
                SelectableText('${sample['leaf']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.inkSoft)),
                const SizedBox(height: 8),
                Text(
                  sample['verified'] == true
                      ? '✓ Verified against the root with a ${(sample['proof'] as List).length}-node proof'
                      : 'Verification failed',
                  style: body(color: sample['verified'] == true ? AppColors.orange : const Color(0xFFD8392B), size: 12.5, weight: FontWeight.w700),
                ),
              ])),
            ],
            const SizedBox(height: 12),
            _anchorBlock(),
          ],
        ]),
      ),
    );
  }

  Widget _txlineBlock() {
    final tx = proof?['txline'] as Map<String, dynamic>?;
    if (tx == null) {
      return _box(child: Text('TxLINE oracle attestation appears once the live feed is streaming this match.', style: body(color: AppColors.mut, size: 12)));
    }
    final root = (tx['root'] ?? '') as String;
    final shortRoot = root.length > 28 ? '${root.substring(0, 18)}…${root.substring(root.length - 8)}' : root;
    Widget stat(String k, Object? v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$v', style: display(18, color: AppColors.orangeBright)),
          Text(k.toUpperCase(), style: label(color: AppColors.mutInk, size: 8)),
        ]);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.verified_rounded, color: AppColors.orangeBright, size: 18),
          const SizedBox(width: 6),
          Text('TXLINE ORACLE PROOF', style: label(color: AppColors.cream, size: 10.5, weight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        Text('EVENTSTAT MERKLE ROOT', style: label(color: AppColors.mutInk, size: 8.5)),
        const SizedBox(height: 3),
        SelectableText(shortRoot, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.orangeBright)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          stat('Seq', tx['seq']),
          stat('Stat updates', tx['updateCount']),
          stat('Proof depth', tx['proofDepth']),
        ]),
        const SizedBox(height: 10),
        Text('✓ Live stats committed to TxLINE’s on-chain tree · fixture ${tx['fixtureId']}',
            style: body(color: AppColors.orangeBright, size: 11.5, weight: FontWeight.w700)),
      ]),
    );
  }

  Widget _box({required Widget child}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
        child: child,
      );

  Widget _anchorBlock() {
    final anchored = proof?['anchored'] == true;
    final sig = proof?['anchorSignature'] as String?;
    final available = proof?['anchorAvailable'] == true;
    final cluster = proof?['cluster'] ?? 'devnet';
    return _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ON-CHAIN ANCHOR ($cluster)', style: label(color: AppColors.mut, size: 9.5)),
        const SizedBox(height: 6),
        if (anchored && sig != null)
          SelectableText(sig, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.orange))
        else if (available)
          widget.isHost
              ? GhostButton(anchoring ? 'Anchoring…' : 'Anchor this root on Solana', expand: true, onTap: anchoring ? null : _anchor)
              : Text('Host can anchor this root.', style: body(color: AppColors.mut, size: 11.5))
        else
          Text('Proof verifies locally. Set SOLANA_ANCHOR_SECRET_KEY to also timestamp the root on-chain.',
              style: body(color: AppColors.mut, size: 11.5)),
      ]),
    );
  }

  Widget _field(String labelText, String value, {bool mono = false, Color? accent}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(labelText.toUpperCase(), style: label(color: AppColors.mut, size: 9.5)),
          const SizedBox(height: 2),
          SelectableText(value, style: TextStyle(fontFamily: mono ? 'monospace' : kBody, fontSize: mono ? 11 : 15, color: accent ?? AppColors.ink, fontWeight: mono ? FontWeight.w500 : FontWeight.w700)),
        ],
      );
}
