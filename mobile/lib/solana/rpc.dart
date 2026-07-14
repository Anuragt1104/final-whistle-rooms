import 'dart:convert';
import 'package:http/http.dart' as http;

/// Tiny Solana JSON-RPC client — just enough to show a wallet's SOL balance on
/// the profile so the connected identity feels real. Best-effort, returns null
/// on any failure.
class SolanaRpc {
  static String _endpoint(String cluster) => cluster == 'mainnet-beta'
      ? 'https://api.mainnet-beta.solana.com'
      : 'https://api.devnet.solana.com';

  static Future<double?> balance(
    String pubkey, {
    String cluster = 'mainnet-beta',
  }) async {
    if (pubkey.isEmpty) return null;
    try {
      final res = await http
          .post(
            Uri.parse(_endpoint(cluster)),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'getBalance',
              'params': [pubkey],
            }),
          )
          .timeout(const Duration(seconds: 8));
      final v = (jsonDecode(res.body)['result'] as Map?)?['value'];
      if (v is int) return v / 1e9;
      return null;
    } catch (_) {
      return null;
    }
  }
}
