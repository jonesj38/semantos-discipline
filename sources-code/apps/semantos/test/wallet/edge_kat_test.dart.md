---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/edge_kat_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.123161+00:00
---

# apps/semantos/test/wallet/edge_kat_test.dart

```dart
// Cross-language Known-Answer Test: the PWA contacts-PKI edge flow
// produces BYTE-IDENTICAL invite tokens, edgeIds, ECDH shared secrets,
// and BRC-69 backup recipes to the brain (TS) for the same inputs.
//
// This is the interop gate. Without it the PWA could build a
// structurally-plausible edge that the brain (or a peer's brain-created
// edge) would not recognise.
//
// Vectors are generated against the EXACT functions the brain runs:
//   cartridges/wallet-headers/brain/src/peer-invite.ts
//   cartridges/wallet-headers/brain/src/ecdh-edge.ts
// via cartridges/wallet-headers/brain/scripts/gen-edge-kat.ts, committed
// as test/wallet/edge_kat.json. Regenerate with:
//   cd cartridges/wallet-headers/brain
//   bun run scripts/gen-edge-kat.ts > \
//     ../../../apps/semantos/test/wallet/edge_kat.json

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/wallet/edge_invite.dart';

Uint8List _fromHex(String h) {
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _hex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

void main() {
  group('brain ↔ PWA edge KAT (contacts-PKI interop)', () {
    final kat = jsonDecode(
            File('test/wallet/edge_kat.json').readAsStringSync())
        as Map<String, dynamic>;

    final mySk = _fromHex(kat['mySkHex'] as String);
    final myCertId = kat['myCertId'] as String;
    final theirPk = _fromHex(kat['theirPkHex'] as String);
    final theirCertId = kat['theirCertId'] as String;
    final nonce = kat['nonce'] as String;
    final timestamp = kat['timestamp'] as int;

    final inviteBlock = kat['invite'] as Map<String, dynamic>;
    final inviteFields = inviteBlock['invite'] as Map<String, dynamic>;

    // The invite a peer hands me, reconstructed from the fixture fields.
    final invite = PeerInvite(
      certId: inviteFields['certId'] as String,
      publicKey: inviteFields['publicKey'] as String,
      nonce: inviteFields['nonce'] as String,
      timestamp: inviteFields['timestamp'] as int,
    );

    test('invite token byte-matches encodeInviteToken', () {
      expect(encodeInviteToken(invite), inviteBlock['token']);
    });

    test('invite URL byte-matches buildInviteUrl', () {
      expect(buildInviteUrl(invite), inviteBlock['url']);
    });

    test('parseInviteUrl recovers the invite (no expiry at fixed now)', () {
      // Decode at a `now` just after the invite timestamp so the 24h TTL
      // doesn't reject the fixed-time fixture.
      final decoded = parseInviteUrl(
        inviteBlock['url'] as String,
        nowMs: timestamp + 1000,
      );
      expect(decoded, isNotNull);
      expect(decoded!.certId, theirCertId);
      expect(decoded.publicKey, kat['theirPkHex']);
      expect(decoded.nonce, nonce);
      expect(decoded.timestamp, timestamp);
    });

    test('edgeId byte-matches acceptInvite (index-independent)', () {
      final edges = kat['edges'] as List;
      final id = computeEdgeId(
        myCertId: myCertId,
        theirCertId: theirCertId,
        nonce: nonce,
      );
      for (final e in edges) {
        expect(id, (e as Map<String, dynamic>)['edgeId'],
            reason: 'edgeId mismatch');
      }
    });

    test('ECDH shared secret byte-matches deriveEdgeSharedSecret', () {
      for (final e in kat['edges'] as List) {
        final m = e as Map<String, dynamic>;
        final index = m['index'] as int;
        final ss = deriveEdgeSharedSecret(
          mySk: mySk,
          theirPk: theirPk,
          signingKeyIndex: index,
        );
        expect(_hex(ss), m['sharedSecretHex'],
            reason: 'shared-secret mismatch at index $index');
      }
    });

    test('BRC-69 backup recipe byte-matches buildEdgeBackupRecipe', () {
      for (final e in kat['edges'] as List) {
        final m = e as Map<String, dynamic>;
        final index = m['index'] as int;
        final edgeId = m['edgeId'] as String;
        final recipe = buildEdgeBackupRecipe(
          mySk: mySk,
          theirPk: theirPk,
          signingKeyIndex: index,
          edgeId: edgeId,
        );
        expect(recipe, m['backupRecipe'],
            reason: 'backup-recipe mismatch at index $index');
      }
    });

    test('createEdgeEnvelope reproduces the full brain envelope', () {
      for (final e in kat['edges'] as List) {
        final m = e as Map<String, dynamic>;
        final index = m['index'] as int;
        final env = createEdgeEnvelope(
          invite: invite,
          myCertId: myCertId,
          mySk: mySk,
          signingKeyIndex: index,
          nowMs: 0,
        );
        expect(env.edgeId, m['edgeId']);
        expect(env.backupRecipe, m['backupRecipe']);
        expect(env.theirCertId, m['theirCertId']);
        expect(env.theirPublicKey, m['theirPublicKey']);
        expect(env.edgeType, m['edgeType']);
        expect(env.myCertId, myCertId);
        expect(env.signingKeyIndex, index);
      }
    });
  });
}

```
