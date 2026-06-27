import 'dart:typed_data';

/// Minimal Base58 (Bitcoin alphabet) — for Solana address display/storage.
const _alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
const _base = 58;

String base58Encode(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  final digits = <int>[0];
  for (final b in bytes) {
    var carry = b;
    for (var j = 0; j < digits.length; j++) {
      carry += digits[j] << 8;
      digits[j] = carry % _base;
      carry = carry ~/ _base;
    }
    while (carry > 0) {
      digits.add(carry % _base);
      carry = carry ~/ _base;
    }
  }
  final sb = StringBuffer();
  for (var k = 0; k < bytes.length - 1 && bytes[k] == 0; k++) {
    sb.write('1');
  }
  for (var q = digits.length - 1; q >= 0; q--) {
    sb.write(_alphabet[digits[q]]);
  }
  return sb.toString();
}

Uint8List base58Decode(String str) {
  if (str.isEmpty) return Uint8List(0);
  final bytes = <int>[0];
  for (final ch in str.split('')) {
    final value = _alphabet.indexOf(ch);
    if (value < 0) throw FormatException('Invalid base58 char: $ch');
    var carry = value;
    for (var j = 0; j < bytes.length; j++) {
      carry += bytes[j] * _base;
      bytes[j] = carry & 0xff;
      carry >>= 8;
    }
    while (carry > 0) {
      bytes.add(carry & 0xff);
      carry >>= 8;
    }
  }
  for (var k = 0; k < str.length - 1 && str[k] == '1'; k++) {
    bytes.add(0);
  }
  return Uint8List.fromList(bytes.reversed.toList());
}
