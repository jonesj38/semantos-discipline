---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/address.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.108999+00:00
---

# apps/semantos/lib/src/wallet/address.dart

```dart
// C11 PR-C11-7a — P2PKH address encoding for the wallet renderer.
//
// References:
//   - BSV P2PKH: SHA-256 → RIPEMD-160 → version-prefix → base58check.
//   - The wallet works on BSV mainnet by default (per Todd's memory
//     note `mnca_anchor_onchain_mainnet`). The version byte is
//     overridable via `BsvNetwork.mainnet` / `BsvNetwork.testnet` so a
//     future testnet branch (or fuzzer fixture) can flip without
//     touching call sites.
//
// Implementation notes:
//   - `pointycastle` ships `SHA256Digest` + `RIPEMD160Digest`. We chain
//     them ourselves rather than depend on an external `bitcoin_base`
//     package — the substrate-clean rule applies to the wallet just
//     like everywhere else, and the encoding is a hundred lines.
//   - Base58 is hand-written here; the only base58 in the Dart tree
//     today is via embedded shims in dead-code archive paths, none of
//     which we want to reach into.

import 'dart:typed_data';

import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/sha256.dart';

/// BSV network selector. The version byte differs between mainnet
/// (0x00) and testnet/regtest (0x6f). The wallet currently defaults
/// to mainnet per the operator's working network.
enum BsvNetwork {
  mainnet(0x00),
  testnet(0x6f);

  const BsvNetwork(this.p2pkhVersionByte);
  final int p2pkhVersionByte;
}

/// Default network used by `addressFromPub` and `addressFromPubHex`
/// when the caller doesn't specify one. Mutable so a future config
/// surface can flip it once at boot; otherwise leave alone.
BsvNetwork kDefaultNetwork = BsvNetwork.mainnet;

/// SHA-256(input) — exposed for callers that want to compose the
/// transformation themselves (e.g. address back-validation).
Uint8List sha256(Uint8List input) => SHA256Digest().process(input);

/// hash160(input) = RIPEMD-160(SHA-256(input)).
Uint8List hash160(Uint8List input) =>
    RIPEMD160Digest().process(sha256(input));

/// Encode a compressed (or uncompressed) secp256k1 pubkey as a BSV
/// P2PKH address. Returns the base58check-encoded string.
String addressFromPub(Uint8List pub, {BsvNetwork? network}) {
  if (pub.length != 33 && pub.length != 65) {
    throw ArgumentError.value(
        pub.length, 'pub.length', 'must be 33 (compressed) or 65 (uncompressed)');
  }
  final net = network ?? kDefaultNetwork;
  final h160 = hash160(pub);
  final payload = Uint8List(1 + h160.length);
  payload[0] = net.p2pkhVersionByte;
  payload.setRange(1, payload.length, h160);
  return base58CheckEncode(payload);
}

/// Convenience: decode a hex-encoded pubkey first, then encode.
String addressFromPubHex(String pubHex, {BsvNetwork? network}) {
  return addressFromPub(_hexDecode(pubHex), network: network);
}

/// Base58 alphabet (Bitcoin / BSV).
const String _b58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Base58check-encode: payload + sha256(sha256(payload))[0..4] →
/// base58 of the concatenation, with leading zero bytes preserved as
/// '1' characters.
String base58CheckEncode(Uint8List payload) {
  final checksum = sha256(sha256(payload)).sublist(0, 4);
  final raw = Uint8List(payload.length + 4);
  raw.setRange(0, payload.length, payload);
  raw.setRange(payload.length, raw.length, checksum);
  return _base58Encode(raw);
}

/// Decode a base58check string back to the payload (version byte +
/// hash160 for a P2PKH address). Returns null if the checksum fails
/// or the input is malformed — callers typically treat that as
/// "unknown address" rather than throw.
Uint8List? base58CheckDecode(String s) {
  final raw = _base58Decode(s);
  if (raw == null || raw.length < 4) return null;
  final payload = raw.sublist(0, raw.length - 4);
  final checksum = raw.sublist(raw.length - 4);
  final expected = sha256(sha256(payload)).sublist(0, 4);
  for (var i = 0; i < 4; i++) {
    if (checksum[i] != expected[i]) return null;
  }
  return payload;
}

String _base58Encode(Uint8List input) {
  // Count leading zero bytes — they map to leading '1' chars.
  var leadingZeros = 0;
  while (leadingZeros < input.length && input[leadingZeros] == 0) {
    leadingZeros++;
  }
  var n = BigInt.zero;
  for (final b in input) {
    n = (n << 8) | BigInt.from(b);
  }
  final radix = BigInt.from(58);
  final out = StringBuffer();
  while (n > BigInt.zero) {
    final qr = _divmod(n, radix);
    n = qr.quotient;
    out.write(_b58Alphabet[qr.remainder.toInt()]);
  }
  for (var i = 0; i < leadingZeros; i++) {
    out.write('1');
  }
  return String.fromCharCodes(out.toString().codeUnits.reversed);
}

Uint8List? _base58Decode(String s) {
  var n = BigInt.zero;
  for (final ch in s.codeUnits) {
    final idx = _b58Alphabet.indexOf(String.fromCharCode(ch));
    if (idx < 0) return null;
    n = n * BigInt.from(58) + BigInt.from(idx);
  }
  // Reconstruct bytes from BigInt.
  final bytes = <int>[];
  var tmp = n;
  final byte = BigInt.from(0xff);
  while (tmp > BigInt.zero) {
    bytes.insert(0, (tmp & byte).toInt());
    tmp = tmp >> 8;
  }
  // Restore leading '1' characters as zero bytes.
  for (var i = 0; i < s.length && s[i] == '1'; i++) {
    bytes.insert(0, 0);
  }
  return Uint8List.fromList(bytes);
}

({BigInt quotient, BigInt remainder}) _divmod(BigInt n, BigInt d) {
  final q = n ~/ d;
  return (quotient: q, remainder: n - q * d);
}

Uint8List _hexDecode(String hex) {
  if (hex.length.isOdd) {
    throw ArgumentError.value(hex.length, 'hex.length', 'must be even');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final b = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (b == null) {
      throw ArgumentError.value(hex, 'hex', 'non-hex char at index ${i * 2}');
    }
    out[i] = b;
  }
  return out;
}

```
