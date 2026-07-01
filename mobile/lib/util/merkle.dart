import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// On-device SHA-256 Merkle tree — a byte-for-byte port of the backend
/// (lib/util/merkle.ts) so a root computed here is identical to the server's
/// for the same leaves. Leaves are domain-separated with a 0x00 prefix; nodes
/// hash the concatenation of children; an odd node duplicates itself.
Uint8List _sha(List<int> b) => Uint8List.fromList(sha256.convert(b).bytes);

Uint8List leafHash(String data) => _sha(utf8.encode('${String.fromCharCode(0)}$data'));

Uint8List _hashPair(Uint8List a, Uint8List b) {
  final buf = Uint8List(a.length + b.length)
    ..setRange(0, a.length, a)
    ..setRange(a.length, a.length + b.length, b);
  return _sha(buf);
}

String _hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

class MerkleStep {
  final String hash; // hex
  final String position; // 'left' | 'right'
  MerkleStep(this.hash, this.position);
  Map<String, dynamic> toJson() => {'hash': hash, 'position': position};
}

class MerkleTree {
  final String root; // hex
  final List<List<Uint8List>> _levels;
  MerkleTree(this.root, this._levels);

  List<MerkleStep> proof(int index) {
    final steps = <MerkleStep>[];
    var idx = index;
    for (var lvl = 0; lvl < _levels.length - 1; lvl++) {
      final level = _levels[lvl];
      final isRight = idx % 2 == 1;
      final siblingIdx = isRight ? idx - 1 : idx + 1;
      final sibling = siblingIdx < level.length ? level[siblingIdx] : level[idx];
      steps.add(MerkleStep(_hex(sibling), isRight ? 'left' : 'right'));
      idx = idx ~/ 2;
    }
    return steps;
  }
}

MerkleTree buildMerkleTree(List<String> items) {
  if (items.isEmpty) {
    return MerkleTree(_hex(_sha(utf8.encode('EMPTY'))), [<Uint8List>[]]);
  }
  final leaves = items.map(leafHash).toList();
  final levels = <List<Uint8List>>[leaves];
  while (levels.last.length > 1) {
    final prev = levels.last;
    final next = <Uint8List>[];
    for (var i = 0; i < prev.length; i += 2) {
      final left = prev[i];
      final right = i + 1 < prev.length ? prev[i + 1] : prev[i];
      next.add(_hashPair(left, right));
    }
    levels.add(next);
  }
  return MerkleTree(_hex(levels.last[0]), levels);
}

/// Verify a leaf belongs to [root] given its inclusion [proof].
bool verifyMerkleProof(String leafData, List<MerkleStep> proof, String root) {
  var acc = leafHash(leafData);
  for (final s in proof) {
    final sib = _hexToBytes(s.hash);
    acc = s.position == 'left' ? _hashPair(sib, acc) : _hashPair(acc, sib);
  }
  return _hex(acc) == root;
}
