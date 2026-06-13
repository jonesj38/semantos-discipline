---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/mesh/signed_bundle_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.929995+00:00
---

# archive/apps-semantos-monolith/test/mesh/signed_bundle_test.dart

```dart
// D-O5m.followup-6 Phase 1 — Cross-language SignedBundle codec parity
// test.
//
// Reference: runtime/semantos-brain/src/signed_bundle.zig (the canonical Zig
//            codec); runtime/semantos-brain/tests/signed_bundle_canonical_fixture_gen.zig
//            (the Zig generator that emits the fixture this test
//            consumes); apps/oddjobz-mobile/lib/src/mesh/signed_bundle.dart
//            (the Dart port under test).
//
// What this asserts:
//   1. computeCanonicalPreimage produces byte-identical output to the
//      Zig encoder for every fixture entry.  The preimage IS the
//      load-bearing seam — Zig and Dart MUST agree on these bytes
//      before signatures can be cross-verified.
//   2. signBundle (using the cell_signer's deterministic-k ECDSA)
//      reproduces the fixture's pinned signature bytes for the same
//      {priv, bundle} input.
//   3. verifyBundleSignature returns true on the canonical bytes, and
//      false when fields are mutated.
//   4. Wire-format round-trip: encode → decode preserves every field.
//
// Without these assertions passing, Phase 2's mesh transport would be
// broken at the wire layer — a Dart-built bundle would not round-trip
// through the Zig brain.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:semantos/src/mesh/cert_ref.dart';
import 'package:semantos/src/mesh/signature_metadata.dart';
import 'package:semantos/src/mesh/signed_bundle.dart';

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Build a Dart `SignedBundle` from a fixture entry's `bundle` JSON +
/// the entry's expected signature.  The fixture stores the bundle in
/// its decoded form (cert chain elements as objects, payload as a JSON
/// string, etc.), so we marshal each piece through the Dart shape.
SignedBundle _bundleFromFixtureEntry(Map<String, dynamic> entry, {required Uint8List signature}) {
  final bundleJson = entry['bundle'] as Map<String, dynamic>;
  final chain = (bundleJson['sender_cert_chain'] as List<dynamic>)
      .map((e) => CertRef.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
  final recipient = bundleJson['recipient_cert_id'];
  final payloadStr = bundleJson['payload'] as String;
  final meta = SignatureMetadata.fromJson(
      bundleJson['signature_metadata'] as Map<String, dynamic>);
  return SignedBundle(
    v: bundleJson['v'] as int,
    senderCertChain: chain,
    recipientCertId: recipient is String ? recipient : null,
    payloadType: bundleJson['payload_type'] as String,
    payload: Uint8List.fromList(utf8.encode(payloadStr)),
    signature: signature,
    signatureMetadata: meta,
  );
}

void main() {
  group('signed_bundle cross-language fixture parity', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      // Fixture lives at runtime/semantos-brain/tests/vectors/.  The Dart test
      // process runs from apps/oddjobz-mobile/, so we walk up two
      // levels to find it.
      final f = File('../../runtime/semantos-brain/tests/vectors/signed-bundle-canonical-fixture.json');
      if (!f.existsSync()) {
        throw StateError(
            'Fixture missing: ${f.absolute.path}. Run `zig build test` from runtime/semantos-brain/ to bootstrap.');
      }
      fixture = json.decode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(fixture['sig_domain'], equals('BRAIN-SIGNED-BUNDLE-v1'));
      expect(fixture['envelope_version'], equals(1));
    });

    test('computeCanonicalPreimage produces byte-identical output for every fixture bundle', () {
      final bundles = fixture['bundles'] as List<dynamic>;
      expect(bundles, hasLength(greaterThanOrEqualTo(3)));
      for (final raw in bundles) {
        final entry = raw as Map<String, dynamic>;
        final expectedHex = entry['expected_preimage_hex'] as String;
        // Pre-sign: signature is all-zero — preimage excludes the
        // signature field by construction so the value doesn't matter,
        // but we use the expected sig anyway to match the wire bundle
        // exactly.
        final sig = _hexToBytes(entry['expected_signature_hex'] as String);
        final bundle = _bundleFromFixtureEntry(entry, signature: sig);
        final preimage = computeCanonicalPreimage(bundle);
        expect(_bytesToHex(preimage), equals(expectedHex),
            reason: 'preimage drift for fixture entry "${entry['label']}"');
      }
    });

    test('computeSignDigest produces the SHA-256 of the preimage', () {
      final bundles = fixture['bundles'] as List<dynamic>;
      for (final raw in bundles) {
        final entry = raw as Map<String, dynamic>;
        final expectedDigest = entry['expected_digest_hex'] as String;
        final sig = _hexToBytes(entry['expected_signature_hex'] as String);
        final bundle = _bundleFromFixtureEntry(entry, signature: sig);
        final digest = computeSignDigest(bundle);
        expect(_bytesToHex(digest), equals(expectedDigest),
            reason: 'digest drift for fixture entry "${entry['label']}"');
      }
    });

    test('signBundle reproduces the fixture signature byte-for-byte', () {
      final bundles = fixture['bundles'] as List<dynamic>;
      for (final raw in bundles) {
        final entry = raw as Map<String, dynamic>;
        final priv = _hexToBytes(entry['priv_hex'] as String);
        final expectedSigHex = entry['expected_signature_hex'] as String;
        // Build the bundle with an all-zero signature (signBundle
        // ignores the input signature, but we want a clean unsigned
        // shape for the test).
        final unsigned = _bundleFromFixtureEntry(
          entry,
          signature: Uint8List(signedBundleSigLen),
        );
        final signed = signBundle(unsigned: unsigned, signingPriv: priv);
        expect(_bytesToHex(signed.signature), equals(expectedSigHex),
            reason: 'signature drift for fixture entry "${entry['label']}"');
      }
    });

    test('verifyBundleSignature accepts the fixture-pinned bytes', () {
      final bundles = fixture['bundles'] as List<dynamic>;
      for (final raw in bundles) {
        final entry = raw as Map<String, dynamic>;
        final leafPub = _hexToBytes(entry['leaf_pubkey_hex'] as String);
        final sig = _hexToBytes(entry['expected_signature_hex'] as String);
        final bundle = _bundleFromFixtureEntry(entry, signature: sig);
        expect(verifyBundleSignature(bundle: bundle, expectedPubkey: leafPub),
            isTrue,
            reason: 'verify failed for fixture entry "${entry['label']}"');
      }
    });

    test('verifyBundleSignature rejects when the payload is mutated', () {
      final entry = (fixture['bundles'] as List<dynamic>).first as Map<String, dynamic>;
      final leafPub = _hexToBytes(entry['leaf_pubkey_hex'] as String);
      final sig = _hexToBytes(entry['expected_signature_hex'] as String);
      final bundle = _bundleFromFixtureEntry(entry, signature: sig);
      // Flip a byte of the payload — the canonical preimage now
      // hashes to a different digest, so the signature won't recover
      // the leaf pubkey.
      final tamperedPayload = Uint8List.fromList(bundle.payload);
      tamperedPayload[0] ^= 0x01;
      final tampered = bundle.copyWithPayload(tamperedPayload);
      expect(
          verifyBundleSignature(bundle: tampered, expectedPubkey: leafPub),
          isFalse);
    });

    test('verifyBundleSignature rejects when the signature is mutated', () {
      final entry = (fixture['bundles'] as List<dynamic>).first as Map<String, dynamic>;
      final leafPub = _hexToBytes(entry['leaf_pubkey_hex'] as String);
      final sig = _hexToBytes(entry['expected_signature_hex'] as String);
      sig[0] ^= 0x01; // flip a byte of r
      final bundle = _bundleFromFixtureEntry(entry, signature: sig);
      expect(verifyBundleSignature(bundle: bundle, expectedPubkey: leafPub),
          isFalse);
    });

    test('encode → decode round-trip preserves every field', () {
      final bundles = fixture['bundles'] as List<dynamic>;
      for (final raw in bundles) {
        final entry = raw as Map<String, dynamic>;
        final sig = _hexToBytes(entry['expected_signature_hex'] as String);
        final original = _bundleFromFixtureEntry(entry, signature: sig);
        final wire = original.encode();

        // The wire-encoded bytes must match the fixture's pinned
        // wire bytes byte-for-byte — proves the Dart encoder agrees
        // with the Zig encoder including the signature field.
        final expectedWireHex = entry['expected_wire_hex'] as String;
        expect(_bytesToHex(wire), equals(expectedWireHex),
            reason: 'wire-bytes drift for fixture entry "${entry['label']}"');

        final decoded = SignedBundle.decode(wire);
        expect(decoded.v, equals(original.v));
        expect(decoded.payloadType, equals(original.payloadType));
        expect(_bytesToHex(decoded.payload), equals(_bytesToHex(original.payload)));
        expect(decoded.recipientCertId, equals(original.recipientCertId));
        expect(decoded.senderCertChain.length,
            equals(original.senderCertChain.length));
        for (var i = 0; i < decoded.senderCertChain.length; i++) {
          expect(decoded.senderCertChain[i].certId,
              equals(original.senderCertChain[i].certId));
          expect(decoded.senderCertChain[i].contextTag,
              equals(original.senderCertChain[i].contextTag));
          expect(decoded.senderCertChain[i].parentCertId,
              equals(original.senderCertChain[i].parentCertId));
          expect(_bytesToHex(decoded.senderCertChain[i].pubkey),
              equals(_bytesToHex(original.senderCertChain[i].pubkey)));
        }
        expect(_bytesToHex(decoded.signature),
            equals(_bytesToHex(original.signature)));
        expect(decoded.signatureMetadata.algorithm,
            equals(original.signatureMetadata.algorithm));
        expect(decoded.signatureMetadata.nonceHex,
            equals(original.signatureMetadata.nonceHex));
        expect(decoded.signatureMetadata.timestampUnix,
            equals(original.signatureMetadata.timestampUnix));
      }
    });
  });
}

```
