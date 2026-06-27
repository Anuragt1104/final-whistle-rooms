import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../theme.dart';
import 'common.dart';

Future<void> showProofSheet(BuildContext context, String roomId, bool isHost) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.pitch850,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
      setState(() => anchoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sample = proof?['sample'] as Map<String, dynamic>?;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)),
          ),
        ),
        const SizedBox(height: 14),
        const Text('Verified by TxLINE on Solana',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 8),
        const Text(
          'Every match event this room reacted to is hashed into a Merkle tree. The root is a tamper-evident fingerprint of the verified TxLINE data the room responded to — the same model TxLINE uses, surfaced as a fan feature.',
          style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 14),
        if (proof == null && error == null)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        else if (error != null)
          Text(error!, style: const TextStyle(color: AppColors.away))
        else ...[
          _field('Events anchored (Merkle leaves)', '${proof!['leafCount']}'),
          const SizedBox(height: 10),
          _field('Merkle root (SHA-256)', proof!['root'] ?? '', mono: true, accent: AppColors.lime),
          if (sample != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0x4D000000),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LIVE INCLUSION PROOF — LATEST EVENT',
                    style: TextStyle(fontSize: 10, letterSpacing: 1, color: AppColors.mut)),
                const SizedBox(height: 6),
                Text('${sample['leaf']}',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70)),
                const SizedBox(height: 8),
                Text(
                  sample['verified'] == true
                      ? '✓ Verified against the root with a ${(sample['proof'] as List).length}-node proof'
                      : 'Verification failed',
                  style: TextStyle(
                      fontSize: 12,
                      color: sample['verified'] == true ? AppColors.lime : AppColors.away),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          _anchorBlock(),
          const SizedBox(height: 12),
          const Text(
            'In production this maps to TxLINE\'s proof endpoints — /api/scores/stat-validation and /api/odds/validation — so any score or odds the room reacted to can be independently verified on Solana.',
            style: TextStyle(fontSize: 11, color: AppColors.mut, height: 1.4),
          ),
        ],
      ]),
    );
  }

  Widget _anchorBlock() {
    final anchored = proof?['anchored'] == true;
    final sig = proof?['anchorSignature'] as String?;
    final available = proof?['anchorAvailable'] == true;
    final cluster = proof?['cluster'] ?? 'devnet';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0x4D000000),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ON-CHAIN ANCHOR ($cluster)',
            style: const TextStyle(fontSize: 10, letterSpacing: 1, color: AppColors.mut)),
        const SizedBox(height: 6),
        if (anchored && sig != null)
          SelectableText(sig,
              style: const TextStyle(fontSize: 11, color: AppColors.home, fontFamily: 'monospace'))
        else if (available)
          widget.isHost
              ? GhostButton(anchoring ? 'Anchoring…' : 'Anchor this root on Solana',
                  expand: true, onTap: anchoring ? null : _anchor)
              : const Text('Host can anchor this root.', style: TextStyle(fontSize: 11, color: AppColors.mut))
        else
          const Text(
            'Proof verifies locally. Set SOLANA_ANCHOR_SECRET_KEY to also timestamp the root on-chain.',
            style: TextStyle(fontSize: 11, color: AppColors.mut),
          ),
      ]),
    );
  }

  Widget _field(String label, String value, {bool mono = false, Color? accent}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
          style: const TextStyle(fontSize: 10, letterSpacing: 1, color: AppColors.mut)),
      const SizedBox(height: 2),
      SelectableText(value,
          style: TextStyle(
              fontSize: mono ? 11 : 14,
              fontFamily: mono ? 'monospace' : null,
              color: accent ?? AppColors.text)),
    ]);
  }
}
