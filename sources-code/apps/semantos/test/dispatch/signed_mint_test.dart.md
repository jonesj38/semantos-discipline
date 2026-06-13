---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/dispatch/signed_mint_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.129893+00:00
---

# apps/semantos/test/dispatch/signed_mint_test.dart

```dart
// C7-B 2b round-trip proof: a PWA-produced sovereign-mint signature must be
// accepted by the brain. We can't run the brain here, but cell_signer's
// `verifyCellSignature` is a byte-for-byte mirror of the brain's
// `verifyCellSignatureRecoveryLoop` (attachments_upload_http.zig) over the
// same `sha256(canonicaliseCellPayload(payload))` digest — so a sig that
// verifies here is one the brain accepts.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/dispatch/payload_canonical.dart';
import 'package:semantos/src/dispatch/signed_mint.dart';
import 'package:semantos/src/identity/cell_signer.dart'
    show verifyCellSignature, devicePubFromPriv;

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('signMintPayloadHex', () {
    final priv = Uint8List.fromList(List<int>.filled(32, 0x11));

    test('produces a 128-hex (64-byte) signature', () {
      final sigHex = signMintPayloadHex(const {'rawText': 'letting go'}, priv);
      expect(sigHex.length, equals(128));
      expect(RegExp(r'^[0-9a-f]{128}$').hasMatch(sigHex), isTrue);
    });

    test('V1 release sig verifies with the brain-mirror verifier', () {
      const payload = {
        'rawText':
            "I'm letting go of the pressure to make every interaction perfect.",
      };
      final sigHex = signMintPayloadHex(payload, priv);

      // Reconstruct exactly what the brain verifies: the canonical bytes
      // (its digest is sha256 of these) + the recovered pubkey matched
      // against the signer cert's pubkey.
      final canonical = canonicaliseCellPayload(payload);
      final sig = _hexToBytes(sigHex);
      final pub = devicePubFromPriv(priv);

      expect(verifyCellSignature(canonical, sig, pub), isTrue);
    });

    test('tampered signature is rejected', () {
      const payload = {'rawText': 'letting go'};
      final sig = _hexToBytes(signMintPayloadHex(payload, priv));
      final canonical = canonicaliseCellPayload(payload);
      final pub = devicePubFromPriv(priv);

      final bad = Uint8List.fromList(sig);
      bad[0] ^= 0xff;
      expect(verifyCellSignature(canonical, bad, pub), isFalse);
    });

    test('signature does not verify against a different operator key', () {
      const payload = {'rawText': 'letting go'};
      final sig = _hexToBytes(signMintPayloadHex(payload, priv));
      final canonical = canonicaliseCellPayload(payload);

      final otherPub =
          devicePubFromPriv(Uint8List.fromList(List<int>.filled(32, 0x22)));
      expect(verifyCellSignature(canonical, sig, otherPub), isFalse);
    });

    test('signature does not verify against a mutated payload', () {
      final sig = _hexToBytes(
          signMintPayloadHex(const {'rawText': 'letting go'}, priv));
      final pub = devicePubFromPriv(priv);

      // A different payload → different canonical bytes → different digest.
      final otherCanonical =
          canonicaliseCellPayload(const {'rawText': 'holding on'});
      expect(verifyCellSignature(otherCanonical, sig, pub), isFalse);
    });
  });
}

```
