import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/base58.dart';

/// On-device Solana identity ("Continue with Solana"): a real ed25519 keypair
/// generated and stored locally — no wallet extension, no funds. Mirrors the
/// web app's embedded-wallet approach.
class Identity {
  final String pubkey; // base58 Solana address
  final Uint8List seed; // 32-byte ed25519 seed
  Identity(this.pubkey, this.seed);
  String get short =>
      '${pubkey.substring(0, 4)}…${pubkey.substring(pubkey.length - 4)}';
}

class IdentityStore {
  static final _algo = Ed25519();
  static Identity? _cached;

  static Future<Identity> getOrCreate() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('fwr_seed');

    if (stored != null && stored.isNotEmpty) {
      final seed = base58Decode(stored);
      final kp = await _algo.newKeyPairFromSeed(seed);
      final pub = await kp.extractPublicKey();
      _cached = Identity(base58Encode(Uint8List.fromList(pub.bytes)), seed);
      return _cached!;
    }

    final kp = await _algo.newKeyPair();
    final priv = await kp.extract();
    final seed = Uint8List.fromList(priv.bytes);
    final pub = await kp.extractPublicKey();
    final identity = Identity(
      base58Encode(Uint8List.fromList(pub.bytes)),
      seed,
    );
    await prefs.setString('fwr_seed', base58Encode(seed));
    _cached = identity;
    return identity;
  }

  /// Sign a message (base58 detached signature). Used to make sign-in a real
  /// Solana signature rather than a stub.
  static Future<String> sign(String message) async {
    final id = await getOrCreate();
    final kp = await _algo.newKeyPairFromSeed(id.seed);
    final sig = await _algo.sign(utf8.encode(message), keyPair: kp);
    return base58Encode(Uint8List.fromList(sig.bytes));
  }
}
