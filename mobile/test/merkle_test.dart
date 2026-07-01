import 'package:flutter_test/flutter_test.dart';
import 'package:final_whistle/util/merkle.dart';

void main() {
  // The on-device Merkle tree must be byte-for-byte identical to the backend
  // (lib/util/merkle.ts) so a solo room's "Verified" root is the real thing —
  // the exact scheme used to verify live TxLINE rooms.
  test('Dart Merkle root matches the backend for identical leaves', () {
    final leaves = [
      '0:0:kickoff',
      '1:23:goal:home:1-0',
      '2:45:half-time',
      '3:67:corner:away:1-0',
      '4:90:full-time',
    ];
    final tree = buildMerkleTree(leaves);
    // Root produced by the backend TypeScript implementation for these leaves.
    expect(tree.root, 'c0a0b04a337ed6c97b9d4c706419455d3cbe3551c307a201d0ebcab10ef04a93');

    final idx = leaves.length - 1;
    final pf = tree.proof(idx);
    expect(pf.length, 3);
    expect(verifyMerkleProof(leaves[idx], pf, tree.root), isTrue);
    // a tampered leaf must not verify against the same proof/root
    expect(verifyMerkleProof('4:90:tampered', pf, tree.root), isFalse);
  });

  test('empty tree yields a stable 32-byte root', () {
    final tree = buildMerkleTree(const []);
    expect(tree.root.length, 64);
  });
}
