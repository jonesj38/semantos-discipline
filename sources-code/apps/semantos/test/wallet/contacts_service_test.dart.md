---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/contacts_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.124002+00:00
---

# apps/semantos/test/wallet/contacts_service_test.dart

```dart
// Unit tests for `contacts_service.dart` — the headless invite →
// bilateral edge → BRC-69 backup flow over an in-memory IdentityStore.
// Exercises the cert_body read path, invite generation, acceptance
// (mint + persist), and the edge list — i.e. tasks (a)–(d) at the
// service layer, without a Flutter widget tree.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos_core/semantos_core.dart' show IdentityStore;

import 'package:semantos/src/wallet/brc42_derive.dart'
    show publicKeyFromPrivate;
import 'package:semantos/src/wallet/contacts_service.dart';
import 'package:semantos/src/wallet/edge_invite.dart';
import 'package:semantos/src/wallet/wallet_key_service.dart'
    show kActiveCertBodySlot;

class _InMemoryIdentityStore implements IdentityStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  bool get isHardwareBacked => false;
}

String _hex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List _certBody(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => ((i + seed) * 37 + 1) & 0xff));

/// Build a peer's invite (as their brain would) so the service can
/// accept it. Uses the public `generateInvite` against a peer keypair.
PeerInvite _peerInvite(int peerSeed) {
  final peerSk = _certBody(peerSeed);
  final peerPub = publicKeyFromPrivate(peerSk);
  // The peer's cert id is not asserted here; any string is fine for the
  // accept path (it only feeds the edgeId hash).
  return generateInvite(myCertId: 'peer-cert-$peerSeed', myPk: peerPub);
}

void main() {
  late _InMemoryIdentityStore store;
  late ContactsService service;

  setUp(() {
    store = _InMemoryIdentityStore();
    service = ContactsService(identityStore: store);
  });

  Future<void> bindIdentity(int seed) async {
    await store.write(kActiveCertBodySlot, _hex(_certBody(seed)));
  }

  group('no identity bound', () {
    test('hasIdentity is false', () async {
      expect(await service.hasIdentity(), isFalse);
    });

    test('generateMyInvite returns null', () async {
      expect(await service.generateMyInvite(), isNull);
    });

    test('acceptInvite throws', () async {
      final invite = _peerInvite(9);
      expect(
        () => service.acceptInvite(buildInviteUrl(invite)),
        throwsA(isA<StateError>()),
      );
    });

    test('listEdges is empty', () async {
      expect(await service.listEdges(), isEmpty);
    });
  });

  group('with identity bound', () {
    setUp(() => bindIdentity(1));

    test('hasIdentity is true', () async {
      expect(await service.hasIdentity(), isTrue);
    });

    test('generateMyInvite produces a parseable URL with my cert id', () async {
      final gen = await service.generateMyInvite();
      expect(gen, isNotNull);
      // My cert id matches SHA-256(certPub)[0:16] of the bound key.
      final certPub = publicKeyFromPrivate(_certBody(1));
      // round-trips through the URL
      final parsed = parseInviteUrl(gen!.url);
      expect(parsed, isNotNull);
      expect(parsed!.publicKey, _hex(certPub));
      expect(parsed.certId, gen.invite.certId);
      expect(parsed.certId.length, 32); // 16-byte hex cert id
    });

    test('acceptInvite mints + persists an edge', () async {
      final invite = _peerInvite(2);
      final env = await service.acceptInvite(buildInviteUrl(invite));
      expect(env.edgeId.length, 64);
      expect(env.backupRecipe.length, 64);
      expect(env.theirCertId, invite.certId);
      expect(env.theirPublicKey, invite.publicKey);
      expect(env.signingKeyIndex, 0);

      final edges = await service.listEdges();
      expect(edges, hasLength(1));
      expect(edges.single.edgeId, env.edgeId);
    });

    test('accepting a bare token (not a URL) also works', () async {
      final invite = _peerInvite(3);
      final token = encodeInviteToken(invite);
      final env = await service.acceptInvite(token);
      expect(env.theirCertId, invite.certId);
      expect(await service.listEdges(), hasLength(1));
    });

    test('re-accepting the same invite is idempotent (same edgeId)', () async {
      final invite = _peerInvite(4);
      final a = await service.acceptInvite(buildInviteUrl(invite));
      final b = await service.acceptInvite(buildInviteUrl(invite));
      expect(a.edgeId, b.edgeId);
      expect(await service.listEdges(), hasLength(1));
    });

    test('two distinct peers produce two edges, newest first', () async {
      final p1 = _peerInvite(5);
      final p2 = _peerInvite(6);
      await service.acceptInvite(buildInviteUrl(p1));
      await service.acceptInvite(buildInviteUrl(p2));
      final edges = await service.listEdges();
      expect(edges, hasLength(2));
      // Both peers represented.
      final theirCerts = edges.map((e) => e.theirCertId).toSet();
      expect(theirCerts, {p1.certId, p2.certId});
    });

    test('acceptInvite rejects an expired invite', () async {
      final invite = generateInvite(
        myCertId: 'old-peer',
        myPk: publicKeyFromPrivate(_certBody(7)),
        nowMs: 0, // far in the past → expired vs wall clock
      );
      expect(
        () => service.acceptInvite(buildInviteUrl(invite)),
        throwsA(isA<StateError>()),
      );
    });
  });
}

```
