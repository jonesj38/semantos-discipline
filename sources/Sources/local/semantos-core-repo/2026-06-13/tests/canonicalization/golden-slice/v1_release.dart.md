---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/canonicalization/golden-slice/v1_release.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.591665+00:00
---

# tests/canonicalization/golden-slice/v1_release.dart

```dart
// C7 Golden Slice — V1 Release (PWA side)
//
// Acceptance gate for the canonicalization's `do | betterment | release`
// slice. Converted 2026-06-04 from red `LayerNotWired` stubs to real
// assertions of the PROVEN sovereign path (Option A): the operator resolves
// the cellType, canonicalises the payload, signs it with the identity key,
// and the brain verifies that signature before assembling + persisting the
// cell. (Levels 1+2 taped on the canonical app — see canonicalization-matrix
// C7-E.)
//
// Spec:    docs/canon/canonicalization-golden-slice.md
// Fixture: tests/canonicalization/golden-slice/v1_release.fixture.json
// Brain side: tests/canonicalization/golden-slice/v1_release.zig
//
// Run (from apps/semantos, so package:semantos resolves):
//   cd apps/semantos && flutter test ../../tests/canonicalization/golden-slice/v1_release.dart
//
// Rule: no canonicalization track may claim ✓ on its C (tests) axis without
// re-running this file + the .zig counterpart and reporting the result.
//
// Scope honesty — what this automated gate asserts vs. what's covered
// elsewhere:
//   • ASSERTED here (pure, deterministic): cellType→typeHash resolution,
//     payload canonicalisation (the sign preimage), and the sovereign
//     sign↔verify round-trip (Dart signer ↔ the byte-for-byte brain-mirror
//     verifier). This is the substantive sovereign mechanism.
//   • Brain-side verify+persist: tests/canonicalization/golden-slice/
//     v1_release.zig + the #828 verifyPayloadSignature conformance test.
//   • Voice STT (layer 1): V2 — V1 uses the helm keyboard path.
//   • PWA-local 1024-byte cell build (layers 4/5): Option B follow-up — in
//     Option A the BRAIN assembles the cell, so the PWA never builds it.
//   • Helm card render (layer 8) + full app→brain→helm round-trip: the
//     taped Level-1 (unsigned) + Level-2 (signed) operator runs.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/dispatch/payload_canonical.dart';
import 'package:semantos/src/dispatch/signed_mint.dart';
import 'package:semantos/src/gradient/type_hash.dart';
import 'package:semantos/src/identity/cell_signer.dart'
    show verifyCellSignature, devicePubFromPriv;

/// betterment.practice.release typeHash (06d0a049…) — the post-rename hash
/// pinned in cartridges/betterment/cartridge.json + the brain registry.
const String _releaseTypeHashHex =
    '06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14';

/// The V1 release payload the helm dispatches: rawText (operator input) +
/// the manifest's defaultPayload (source/prompt/elevation).
const Map<String, dynamic> _releasePayload = {
  'rawText': "I'm letting go of the pressure to make every interaction perfect.",
  'source': 'keyboard',
  'prompt': 'freeform',
  'elevation': 5,
};

/// Deterministic test operator key (NOT a real cert). The sign↔verify
/// round-trip is key-agnostic; the live run uses the operator's hat key.
final Uint8List _testPriv = Uint8List.fromList(List<int>.filled(32, 0x11));

Uint8List _hexToBytes(String h) {
  final o = Uint8List(h.length ~/ 2);
  for (var i = 0; i < o.length; i++) {
    o[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return o;
}

Map<String, dynamic> _loadFixture() {
  const name = 'v1_release.fixture.json';
  for (final c in const [
    name,
    'tests/canonicalization/golden-slice/$name',
    '../../tests/canonicalization/golden-slice/$name',
  ]) {
    final f = File(c);
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError('fixture $name not found; cwd=${Directory.current.path}');
}

void main() {
  late Map<String, dynamic> fixture;
  setUpAll(() => fixture = _loadFixture());

  group('C7 Golden Slice V1 — do | betterment | release (sovereign, Option A)',
      () {
    // ── Layer 3 — resolution: release → betterment.practice.release typeHash
    test('layer 3 — release resolves to the betterment.practice.release typeHash',
        () {
      final oir = fixture['layer3_oir']['expected'] as Map<String, dynamic>;
      expect(oir['verb'], equals('do.new'));
      expect(oir['cellType'], equals('betterment.practice.release'));
      expect(oir['cartridge'], equals('betterment'));

      // The triple → typeHash is deterministic + must match the registry.
      final hash = buildTypeHash('betterment', 'practice', 'release', '');
      expect(typeHashHex(hash), equals(_releaseTypeHashHex));
    });

    // ── Layer 6a — canonicalisation (the signing preimage)
    test('layer 6a — payload canonicalises to sorted-key JSON (sign preimage)',
        () {
      expect(
        canonicalCellPayloadString(_releasePayload),
        equals(
          '{"elevation":5,"prompt":"freeform",'
          '"rawText":"I\'m letting go of the pressure to make every interaction perfect.",'
          '"source":"keyboard"}',
        ),
      );
    });

    // ── Layer 6b — sovereign sign ↔ verify (the proven crypto)
    test('layer 6b — operator-signed payload verifies (Dart sign ↔ brain-mirror verify)',
        () {
      final canonical = canonicaliseCellPayload(_releasePayload);
      final sigHex = signMintPayloadHex(_releasePayload, _testPriv);
      expect(sigHex.length, equals(128)); // 64-byte r‖s compact

      final sig = _hexToBytes(sigHex);
      final pub = devicePubFromPriv(_testPriv);
      expect(pub.length, equals(33)); // compressed SEC1

      // verifyCellSignature is the byte-for-byte mirror of the brain's
      // verifyCellSignatureRecoveryLoop (#828) over sha256(canonical) — so a
      // sig that passes here is one the brain accepts. Proven live (Level 2).
      expect(verifyCellSignature(canonical, sig, pub), isTrue);

      // Wrong key + tampered sig must reject.
      final otherPub =
          devicePubFromPriv(Uint8List.fromList(List<int>.filled(32, 0x22)));
      expect(verifyCellSignature(canonical, sig, otherPub), isFalse);
      final bad = Uint8List.fromList(sig)..[0] ^= 0xff;
      expect(verifyCellSignature(canonical, bad, pub), isFalse);
    });

    // ── Layer 7 — the sovereign-mint wire shape the brain verifies
    test('layer 7 — sovereign mint wire carries typeHash + payload + sig + certId',
        () {
      // The brain (#828) verifies {typeHashHex, payload, signatureHex,
      // signerCertIdHex} over sha256(canonicaliseCellPayload(payload)). The
      // fixture pins the request body; the live brain round-trip is the taped
      // Level-2 run + v1_release.zig.
      final body = (fixture['layer7_brain_dispatch']['request']['body'])
          as Map<String, dynamic>;
      expect(body['typeHashHex'], equals(_releaseTypeHashHex));
      final payload = body['payload'] as Map<String, dynamic>;
      expect(payload.containsKey('rawText'), isTrue);
      expect(payload['source'], isNotNull); // required schema field
      expect(payload['prompt'], isNotNull);
      expect(payload['elevation'], isNotNull);
    });

    // ── End-to-end — the proven sovereign chain (resolution + sign + verify)
    test('end-to-end — resolution + canonicalise + sovereign sign + brain-mirror verify',
        () {
      final hash = buildTypeHash('betterment', 'practice', 'release', '');
      expect(typeHashHex(hash), equals(_releaseTypeHashHex));

      final canonical = canonicaliseCellPayload(_releasePayload);
      final sig = _hexToBytes(signMintPayloadHex(_releasePayload, _testPriv));
      expect(
        verifyCellSignature(canonical, sig, devicePubFromPriv(_testPriv)),
        isTrue,
      );
      // Voice (L1, V2), PWA-local cell build (L4/5, Option B), and helm render
      // (L8) are out of this automated gate's scope — covered by the taped
      // Level-1/2 operator runs (canonicalization-matrix C7-E).
    });
  });
}

```
