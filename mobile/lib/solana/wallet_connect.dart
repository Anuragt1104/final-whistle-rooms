import 'package:solana_mobile_client/solana_mobile_client.dart';
import '../util/base58.dart';

/// Real Solana wallet connect via Mobile Wallet Adapter (MWA). Auto-detects an
/// installed wallet app (Phantom/Solflare/Backpack) and authorizes to get the
/// user's actual public key. Android only — on iOS/web `isAvailable()` is false
/// and the app falls back to the on-device embedded identity / pasted address.
class WalletConnectResult {
  final String pubkey; // base58 Solana address
  final String? authToken;
  final String? label;
  WalletConnectResult(this.pubkey, this.authToken, this.label);
}

class WalletConnect {
  /// True if a compatible wallet app is installed and MWA is supported.
  static Future<bool> isAvailable() async {
    try {
      return await LocalAssociationScenario.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Open the installed wallet and authorize. Returns null if cancelled.
  static Future<WalletConnectResult?> connect({String cluster = 'mainnet-beta'}) async {
    final scenario = await LocalAssociationScenario.create();
    try {
      await scenario.startActivityForResult(null);
      final client = await scenario.start();
      final result = await client.authorize(
        identityUri: Uri.parse('https://final-whistle.app'),
        iconUri: Uri.parse('favicon.png'),
        identityName: 'Final Whistle Rooms',
        cluster: cluster,
      );
      if (result == null) return null;
      return WalletConnectResult(base58Encode(result.publicKey), result.authToken, result.accountLabel);
    } finally {
      await scenario.close();
    }
  }
}
