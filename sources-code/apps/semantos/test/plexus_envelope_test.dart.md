---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/plexus_envelope_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.094438+00:00
---

# apps/semantos/test/plexus_envelope_test.dart

```dart
// C11 PR-C11-2 — Plexus recovery envelope round-trip + invariant tests.
//
// Mirrors the test surface for `cartridges/wallet-headers/brain/src/plexus/
// envelope.ts`. Locks the wire shape + crypto round-trip so a Dart-side
// envelope decrypts under the same answers the TS reference would
// produce — and vice versa.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/plexus/envelope.dart';

void main() {
  // Deterministic inputs — fixed identity pub, certId, seed, salt, nonce.
  // Don't include the seed bytes in the answers/questions/email so the
  // invariant-1 "no plaintext seed in JSON" check has real signal.
  final identityKey = Uint8List.fromList(
    List.generate(33, (i) => 0x02 + (i * 7) % 200),
  );
  final certId =
      Uint8List.fromList(List.generate(32, (i) => 0x10 + i));
  final recoverySeed =
      Uint8List.fromList(List.generate(64, (i) => 0xa0 + i));
  final salt = Uint8List.fromList(List.generate(32, (i) => 0x55 + i));
  final nonce = Uint8List.fromList(List.generate(12, (i) => 0x80 + i));

  group('PlexusRecoveryEnvelope build', () {
    test('builds + round-trips under correct answers', () {
      final input = BuildEnvelopeInput(
        identityKey: identityKey,
        certId: certId,
        contactEmail: 'todd@semantos.me',
        questions: const [
          "Mother's maiden name?",
          "City of birth?",
          "First pet?",
        ],
        answers: const ['McEachan', 'Sydney', 'Marlowe'],
        recoverySeed: recoverySeed,
        saltOverride: salt,
        nonceOverride: nonce,
      );

      final result = buildEnvelope(input);
      expect(result, isA<BuildOk>(), reason: 'build should succeed');
      final envelope = (result as BuildOk).envelope;

      // Wire FORMAT stays v1; KDF-era counter bumped to 2 (L11 P6 —
      // recipes carry per-domain kdfVersion; mirrors brain PR #876).
      expect(envelope.envelopeVersion, 1);
      expect(envelope.algorithmVersion, 2);
      expect(envelope.contactEmail, 'todd@semantos.me');
      expect(envelope.challengeBundle.questions, hasLength(3));
      expect(envelope.challengeBundle.answerHashes, hasLength(3));
      expect(envelope.challengeBundle.kdfIterations, 100000);
      expect(envelope.challengeBundle.saltHex.length, 64);
      expect(envelope.encryptedRecoverySeed.nonceHex.length, 24);
      expect(envelope.encryptedRecoverySeed.tagHex.length, 32);
      expect(envelope.encryptedRecoverySeed.aadHex.length, 68);
      expect(envelope.encryptedRecoverySeed.ciphertextHex.length, 128,
          reason: 'seed (64 bytes) → GCM ciphertext (64 bytes) hex (128 chars)');

      // Round-trip: correct answers → original seed
      final recovered =
          decryptRecoverySeed(envelope, const ['McEachan', 'Sydney', 'Marlowe']);
      expect(recovered, isNotNull);
      expect(recovered, equals(recoverySeed));
    });

    test('round-trip succeeds with case/whitespace variations (normalize)',
        () {
      final input = BuildEnvelopeInput(
        identityKey: identityKey,
        certId: certId,
        contactEmail: 'todd@semantos.me',
        questions: const ["Mother's maiden name?"],
        answers: const ['McEachan'],
        recoverySeed: recoverySeed,
        saltOverride: salt,
        nonceOverride: nonce,
      );
      final envelope = (buildEnvelope(input) as BuildOk).envelope;

      // Same answer in different case + whitespace forms — normalize rule
      // (lowercase + collapse whitespace + trim) makes them equivalent.
      expect(decryptRecoverySeed(envelope, const ['mceachan']),
          equals(recoverySeed));
      expect(decryptRecoverySeed(envelope, const ['  MCEACHAN  ']),
          equals(recoverySeed));
      expect(decryptRecoverySeed(envelope, const ['Mc Eachan']),
          isNull,
          reason: 'internal whitespace IS preserved (collapses to one space, '
              'differs from "mceachan")');
    });

    test('wrong answers → decrypt returns null', () {
      final input = BuildEnvelopeInput(
        identityKey: identityKey,
        certId: certId,
        contactEmail: 'todd@semantos.me',
        questions: const ['Q1', 'Q2'],
        answers: const ['real-answer-a', 'real-answer-b'],
        recoverySeed: recoverySeed,
        saltOverride: salt,
        nonceOverride: nonce,
      );
      final envelope = (buildEnvelope(input) as BuildOk).envelope;

      expect(decryptRecoverySeed(envelope, const ['wrong', 'real-answer-b']),
          isNull);
      expect(decryptRecoverySeed(envelope, const ['real-answer-a', 'wrong']),
          isNull);
      expect(decryptRecoverySeed(envelope, const ['real-answer-b', 'real-answer-a']),
          isNull,
          reason: 'order matters — KEK is PBKDF2(concat(...)) which is order-dependent');
    });

    test('answer count mismatch → decrypt returns null', () {
      final input = BuildEnvelopeInput(
        identityKey: identityKey,
        certId: certId,
        contactEmail: 'todd@semantos.me',
        questions: const ['Q1', 'Q2', 'Q3'],
        answers: const [
          'unique-foxtrot-alpha',
          'unique-gamma-niner',
          'unique-zulu-keynote',
        ],
        recoverySeed: recoverySeed,
        saltOverride: salt,
        nonceOverride: nonce,
      );
      final envelope = (buildEnvelope(input) as BuildOk).envelope;
      expect(
          decryptRecoverySeed(
              envelope, const ['unique-foxtrot-alpha', 'unique-gamma-niner']),
          isNull);
      expect(
          decryptRecoverySeed(envelope, const [
            'unique-foxtrot-alpha',
            'unique-gamma-niner',
            'unique-zulu-keynote',
            'extra',
          ]),
          isNull);
    });

    test('JSON output is the canonical TS-mirror shape', () {
      // Answers must be substrings of NOTHING else in the envelope —
      // contactEmail, questions, certId hex, identityKey hex, the seed
      // hex, the salt hex. Picking unguessable phrases keeps invariant 1
      // (no plaintext answer in JSON) satisfiable.
      final input = BuildEnvelopeInput(
        identityKey: identityKey,
        certId: certId,
        contactEmail: 'todd@semantos.me',
        questions: const ['Q1'],
        answers: const ['unique-quokka-velvet'],
        recoverySeed: recoverySeed,
        saltOverride: salt,
        nonceOverride: nonce,
      );
      final envelope = (buildEnvelope(input) as BuildOk).envelope;
      final asJson = jsonDecode(envelope.toJsonString());
      expect(asJson, isA<Map>());
      expect(asJson['envelopeVersion'], 1);
      expect(asJson['algorithmVersion'], 2);
      expect(asJson['identityKey'], envelope.identityKeyHex);
      expect(asJson['certId'], envelope.certIdHex);
      expect(asJson['challengeBundle'], isA<Map>());
      expect(asJson['encryptedRecoverySeed'], isA<Map>());
      expect(asJson['derivationContexts'], isA<List>());
      expect(asJson['edgeRecipes'], isA<List>());
      expect(asJson['derivationStateSnapshot'], isA<Map>());
    });
  });

  group('PlexusRecoveryEnvelope invariants', () {
    test('rejects bad identityKey length', () {
      final input = BuildEnvelopeInput(
        identityKey: Uint8List(20),
        certId: certId,
        contactEmail: 'x@y',
        questions: const ['q'],
        answers: const ['a'],
        recoverySeed: recoverySeed,
      );
      expect(buildEnvelope(input), isA<BuildInvalidInput>());
    });

    test('rejects empty contactEmail', () {
      final input = BuildEnvelopeInput(
        identityKey: identityKey,
        certId: certId,
        contactEmail: '',
        questions: const ['q'],
        answers: const ['a'],
        recoverySeed: recoverySeed,
      );
      expect(buildEnvelope(input), isA<BuildInvalidInput>());
    });

    test('rejects answers length mismatch', () {
      final input = BuildEnvelopeInput(
        identityKey: identityKey,
        certId: certId,
        contactEmail: 'x@y',
        questions: const ['q1', 'q2'],
        answers: const ['a1'],
        recoverySeed: recoverySeed,
      );
      expect(buildEnvelope(input), isA<BuildInvalidInput>());
    });

    test('rejects wrong-length seed', () {
      final input = BuildEnvelopeInput(
        identityKey: identityKey,
        certId: certId,
        contactEmail: 'x@y',
        questions: const ['q'],
        answers: const ['a'],
        recoverySeed: Uint8List(32),
      );
      expect(buildEnvelope(input), isA<BuildInvalidInput>());
    });
  });

  group('normalizeAnswer', () {
    test('lowercases + collapses whitespace + trims', () {
      expect(normalizeAnswer('  Foo   Bar  '), 'foo bar');
      expect(normalizeAnswer('McEachan'), 'mceachan');
      expect(normalizeAnswer('\tHello\nWorld'), 'hello world');
      expect(normalizeAnswer(''), '');
    });
  });
}

```
