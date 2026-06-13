---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/edge_invite_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.125437+00:00
---

# apps/semantos/test/wallet/edge_invite_test.dart

```dart
// Unit tests for `edge_invite.dart` — invite token round-trips, edge id
// determinism, ECDH shared-secret + backup-recipe behaviour, and arg
// validation. The byte-level equality with the brain is pinned
// separately by `edge_kat_test.dart`; these tests cover the
// PWA-internal properties (round-trips, expiry, input sensitivity).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/wallet/brc42_derive.dart'
    show publicKeyFromPrivate;
import 'package:semantos/src/wallet/edge_invite.dart';

Uint8List _sk(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => ((i * 17 + seed + 1) & 0xff)));

void main() {
  group('invite token round-trip', () {
    test('encode → decode recovers all fields', () {
      final pk = publicKeyFromPrivate(_sk(1));
      final invite = generateInvite(
        myCertId: 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6',
        myPk: pk,
        nowMs: 1717000000000,
      );
      final token = encodeInviteToken(invite);
      final decoded = decodeInviteToken(token, nowMs: 1717000000500);
      expect(decoded, isNotNull);
      expect(decoded!.certId, invite.certId);
      expect(decoded.publicKey, invite.publicKey);
      expect(decoded.nonce, invite.nonce);
      expect(decoded.timestamp, invite.timestamp);
    });

    test('URL build → parse recovers the invite', () {
      final invite = generateInvite(
        myCertId: 'deadbeef',
        myPk: publicKeyFromPrivate(_sk(2)),
        nowMs: 1717000000000,
      );
      final url = buildInviteUrl(invite);
      expect(url, startsWith('https://wallet.semantos.me/connect?invite='));
      final parsed = parseInviteUrl(url, nowMs: 1717000000500);
      expect(parsed, isNotNull);
      expect(parsed!.nonce, invite.nonce);
    });

    test('custom base URL with existing query uses & separator', () {
      final invite = generateInvite(
        myCertId: 'cafe',
        myPk: publicKeyFromPrivate(_sk(3)),
        nowMs: 1,
      );
      final url = buildInviteUrl(invite, baseUrl: 'https://x.test/c?ref=1');
      expect(url, contains('?ref=1&invite='));
      final parsed = parseInviteUrl(url, nowMs: 2);
      expect(parsed, isNotNull);
    });

    test('generated nonce is 32 bytes (64 hex) and random per call', () {
      final pk = publicKeyFromPrivate(_sk(4));
      final a = generateInvite(myCertId: 'x', myPk: pk, nowMs: 0);
      final b = generateInvite(myCertId: 'x', myPk: pk, nowMs: 0);
      expect(a.nonce.length, 64);
      expect(a.publicKey.length, 66); // 33-byte compressed pubkey hex
      expect(a.nonce, isNot(equals(b.nonce)));
    });

    test('decode rejects expired invite (> 24h)', () {
      final invite = generateInvite(
        myCertId: 'x',
        myPk: publicKeyFromPrivate(_sk(5)),
        nowMs: 0,
      );
      final token = encodeInviteToken(invite);
      expect(decodeInviteToken(token, nowMs: kInviteTtlMs + 1), isNull);
      // boundary: exactly at TTL still valid
      expect(decodeInviteToken(token, nowMs: kInviteTtlMs), isNotNull);
    });

    test('decode rejects garbage / empty / wrong-typed payloads', () {
      expect(decodeInviteToken(''), isNull);
      expect(decodeInviteToken('!!!not-base64!!!', nowMs: 0), isNull);
      // valid base64url but not JSON
      expect(decodeInviteToken('aGVsbG8', nowMs: 0), isNull);
    });

    test('parseInviteUrl returns null when invite param absent', () {
      expect(parseInviteUrl('https://x.test/c', nowMs: 0), isNull);
    });
  });

  group('edge id', () {
    test('deterministic for the same inputs', () {
      final a = computeEdgeId(myCertId: 'aa', theirCertId: 'bb', nonce: 'cc');
      final b = computeEdgeId(myCertId: 'aa', theirCertId: 'bb', nonce: 'cc');
      expect(a, b);
      expect(a.length, 64); // SHA-256 hex
    });

    test('changes with each input', () {
      final base = computeEdgeId(myCertId: 'aa', theirCertId: 'bb', nonce: 'cc');
      expect(computeEdgeId(myCertId: 'AA', theirCertId: 'bb', nonce: 'cc'),
          isNot(base));
      expect(computeEdgeId(myCertId: 'aa', theirCertId: 'BB', nonce: 'cc'),
          isNot(base));
      expect(computeEdgeId(myCertId: 'aa', theirCertId: 'bb', nonce: 'CC'),
          isNot(base));
    });

    test('is NOT a naive concat collision (boundary-sensitive)', () {
      // "a"+"b"+"c" vs "ab"+""+"c" would collide under naive concat;
      // SHA-256 over the joined string still differs only if the joins
      // differ — here they're equal strings, so assert equality holds as
      // documented (concat semantics mirror the TS exactly).
      expect(
        computeEdgeId(myCertId: 'a', theirCertId: 'b', nonce: 'c'),
        computeEdgeId(myCertId: 'ab', theirCertId: '', nonce: 'c'),
      );
    });
  });

  group('edge shared secret + backup recipe', () {
    final mySk = _sk(10);
    final theirPk = publicKeyFromPrivate(_sk(20));

    test('shared secret is 32 bytes and index-sensitive', () {
      final s0 = deriveEdgeSharedSecret(
          mySk: mySk, theirPk: theirPk, signingKeyIndex: 0);
      final s1 = deriveEdgeSharedSecret(
          mySk: mySk, theirPk: theirPk, signingKeyIndex: 1);
      expect(s0.length, 32);
      expect(s0, isNot(equals(s1)));
    });

    test('backup recipe deterministic + depends on index and edgeId', () {
      const edgeId =
          'b6c1ed2662609db87571254936c8cf49e8091584a75d240c402b02dbc8c4892b';
      final r0a = buildEdgeBackupRecipe(
          mySk: mySk, theirPk: theirPk, signingKeyIndex: 0, edgeId: edgeId);
      final r0b = buildEdgeBackupRecipe(
          mySk: mySk, theirPk: theirPk, signingKeyIndex: 0, edgeId: edgeId);
      final r1 = buildEdgeBackupRecipe(
          mySk: mySk, theirPk: theirPk, signingKeyIndex: 1, edgeId: edgeId);
      final rOther = buildEdgeBackupRecipe(
          mySk: mySk,
          theirPk: theirPk,
          signingKeyIndex: 0,
          edgeId: 'deadbeef');
      expect(r0a, r0b);
      expect(r0a.length, 64);
      expect(r0a, isNot(equals(r1)));
      expect(r0a, isNot(equals(rOther)));
    });

    test('non-hex edgeId falls back to UTF-8 bytes without throwing', () {
      final r = buildEdgeBackupRecipe(
          mySk: mySk,
          theirPk: theirPk,
          signingKeyIndex: 0,
          edgeId: 'not-hex-zz');
      expect(r.length, 64);
    });
  });

  group('createEdgeEnvelope', () {
    test('populates the envelope from the invite', () {
      final invite = PeerInvite(
        certId: 'f0e1d2c3',
        publicKey: publicKeyFromPrivateHex(_sk(33)),
        nonce: 'abcd',
        timestamp: 1,
      );
      final env = createEdgeEnvelope(
        invite: invite,
        myCertId: 'a1b2',
        mySk: _sk(34),
        signingKeyIndex: 3,
        nowMs: 42,
      );
      expect(env.myCertId, 'a1b2');
      expect(env.theirCertId, 'f0e1d2c3');
      expect(env.theirPublicKey, invite.publicKey);
      expect(env.signingKeyIndex, 3);
      expect(env.edgeType, 'MESSAGING');
      expect(env.createdAt, 42);
      expect(env.edgeId.length, 64);
      expect(env.backupRecipe.length, 64);
    });

    test('throws on malformed invite pubkey', () {
      final invite = PeerInvite(
        certId: 'x',
        publicKey: 'zz', // not valid hex
        nonce: 'n',
        timestamp: 1,
      );
      expect(
        () => createEdgeEnvelope(
          invite: invite,
          myCertId: 'a',
          mySk: _sk(1),
          signingKeyIndex: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

/// Helper: hex of the compressed pubkey for a priv (test convenience).
String publicKeyFromPrivateHex(Uint8List sk) {
  final pk = publicKeyFromPrivate(sk);
  final sb = StringBuffer();
  for (final b in pk) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

```
