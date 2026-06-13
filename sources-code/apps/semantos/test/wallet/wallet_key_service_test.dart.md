---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/wallet_key_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.124856+00:00
---

# apps/semantos/test/wallet/wallet_key_service_test.dart

```dart
// C11 PR-C11-4f — Unit tests for `wallet_key_service.dart`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos_core/semantos_core.dart' show IdentityStore;

import 'package:semantos/src/wallet/brc42_derive.dart';
import 'package:semantos/src/wallet/derivation_domain.dart';
import 'package:semantos/src/wallet/wallet_key_service.dart';

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

String _hexEncode(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List _fakeCertBody(int seed) {
  return Uint8List.fromList(
      List<int>.generate(32, (i) => ((i + seed) * 37 + 1) & 0xff));
}

void main() {
  group('WalletKeyService.loadIdentity', () {
    test('returns false when no cert_body is stored', () async {
      final svc = WalletKeyService(identityStore: _InMemoryIdentityStore());
      expect(await svc.loadIdentity(), isFalse);
      expect(svc.hasIdentity, isFalse);
      expect(svc.certIdHex, isNull);
      expect(svc.tier0Pub, isNull);
      svc.dispose();
    });

    test('loads cert_body and derives tier-0', () async {
      final store = _InMemoryIdentityStore();
      final body = _fakeCertBody(1);
      await store.write(kActiveCertBodySlot, _hexEncode(body));
      final svc = WalletKeyService(identityStore: store);
      expect(await svc.loadIdentity(), isTrue);
      expect(svc.hasIdentity, isTrue);
      expect(svc.certIdHex, hasLength(32));
      expect(svc.tier0Pub!.length, 33);
      svc.dispose();
    });

    test('idempotent — second load returns the same identity', () async {
      final store = _InMemoryIdentityStore();
      await store.write(kActiveCertBodySlot, _hexEncode(_fakeCertBody(2)));
      final svc = WalletKeyService(identityStore: store);
      await svc.loadIdentity();
      final firstId = svc.certIdHex;
      await svc.loadIdentity();
      expect(svc.certIdHex, firstId);
      svc.dispose();
    });

    test('rejects malformed cert_body bytes — stays unloaded', () async {
      final store = _InMemoryIdentityStore();
      // Wrong length — must be exactly 64 hex chars.
      await store.write(kActiveCertBodySlot, 'deadbeef');
      final svc = WalletKeyService(identityStore: store);
      expect(await svc.loadIdentity(), isFalse);
      expect(svc.hasIdentity, isFalse);
      svc.dispose();
    });

    test('clearing then reloading produces a fresh empty state', () async {
      final store = _InMemoryIdentityStore();
      await store.write(kActiveCertBodySlot, _hexEncode(_fakeCertBody(3)));
      final svc = WalletKeyService(identityStore: store);
      await svc.loadIdentity();
      expect(svc.hasIdentity, isTrue);
      await svc.clearIdentity();
      expect(svc.hasIdentity, isFalse);
      expect(await svc.loadIdentity(), isFalse);
      svc.dispose();
    });
  });

  group('WalletKeyService.deriveReceive', () {
    test('throws without identity', () async {
      final svc = WalletKeyService(identityStore: _InMemoryIdentityStore());
      expect(
        () => svc.deriveReceive('oddjobz/payout'),
        throwsA(isA<StateError>()),
      );
      svc.dispose();
    });

    test('allocates monotonic indices per context', () async {
      final store = _InMemoryIdentityStore();
      await store.write(kActiveCertBodySlot, _hexEncode(_fakeCertBody(4)));
      final svc = WalletKeyService(identityStore: store);
      await svc.loadIdentity();
      final a = await svc.deriveReceive('oddjobz/payout');
      final b = await svc.deriveReceive('oddjobz/payout');
      final c = await svc.deriveReceive('oddjobz/payout');
      expect(a.index, 0);
      expect(b.index, 1);
      expect(c.index, 2);
      expect(a.recipeId, 'vault/0/spend/oddjobz/payout');
      expect(a.contextLabel, 'oddjobz/payout');
      expect(a.pubHex, hasLength(66));
      expect(a.pubHex, isNot(equals(b.pubHex)));
      // PR-C11-7a — address is the real P2PKH (base58check) on
      // mainnet by default.
      expect(a.address, startsWith('1'));
      expect(a.address, isNot(equals(b.address)));
      // Watching rows in the UTXO store track each allocation.
      final rows = await svc.utxos.readAll();
      expect(rows, hasLength(3));
      expect(rows.every((r) => r.status.name == 'watching'), isTrue);
      svc.dispose();
    });

    test('independent contexts allocate independent index streams',
        () async {
      final store = _InMemoryIdentityStore();
      await store.write(kActiveCertBodySlot, _hexEncode(_fakeCertBody(5)));
      final svc = WalletKeyService(identityStore: store);
      await svc.loadIdentity();
      final p1 = await svc.deriveReceive('oddjobz/payout');
      final r1 = await svc.deriveReceive('betterment/release');
      final p2 = await svc.deriveReceive('oddjobz/payout');
      expect(p1.index, 0);
      expect(r1.index, 0);
      expect(p2.index, 1);
      svc.dispose();
    });

    test('rejects empty contextLabel', () async {
      final store = _InMemoryIdentityStore();
      await store.write(kActiveCertBodySlot, _hexEncode(_fakeCertBody(6)));
      final svc = WalletKeyService(identityStore: store);
      await svc.loadIdentity();
      expect(
        () => svc.deriveReceive(''),
        throwsA(isA<ArgumentError>()),
      );
      svc.dispose();
    });
  });

  group('WalletKeyService.deriveAt', () {
    test('throws without identity', () async {
      final svc = WalletKeyService(identityStore: _InMemoryIdentityStore());
      await expectLater(
        svc.deriveAt(DerivationDomain.change, 0),
        throwsA(isA<StateError>()),
      );
      svc.dispose();
    });

    test('change parents on the identity key directly (L11 P6)', () async {
      // change/anchor derive from cert_body, NOT tier-0 — so the PWA's
      // change keys byte-match the brain wallet's deriveChangeSk.
      final store = _InMemoryIdentityStore();
      final body = _fakeCertBody(7);
      await store.write(kActiveCertBodySlot, _hexEncode(body));
      final svc = WalletKeyService(identityStore: store);
      await svc.loadIdentity();

      final svcPub = await svc.deriveAt(DerivationDomain.change, 5);

      // Expected: identity-direct derivation (cert_body → change child),
      // no tier-0 layer. L11.5 kdf-v3: fold the CHANGE flag.
      final expectedChildSk = deriveSelfChild(
        parentSk: body,
        protocolHash: DerivationDomain.change.protocolHash,
        index: 5,
        domainFlag: DerivationDomain.change.domainFlag,
      );
      final expectedPub = publicKeyFromPrivate(expectedChildSk);
      expect(svcPub, equals(expectedPub));

      // And it must NOT equal the old tier-0-parented derivation.
      final tier0Sk = deriveSelfChild(
        parentSk: body,
        protocolHash: DerivationDomain.tier0.protocolHash,
        index: 0,
      );
      final tier0Parented = publicKeyFromPrivate(deriveSelfChild(
        parentSk: tier0Sk,
        protocolHash: DerivationDomain.change.protocolHash,
        index: 5,
      ));
      expect(svcPub, isNot(equals(tier0Parented)));
      svc.dispose();
    });

    test('spend still parents on tier-0', () async {
      final store = _InMemoryIdentityStore();
      final body = _fakeCertBody(9);
      await store.write(kActiveCertBodySlot, _hexEncode(body));
      final svc = WalletKeyService(identityStore: store);
      await svc.loadIdentity();

      final spend = DerivationDomain.spend('oddjobz/payout');
      final svcPub = await svc.deriveAt(spend, 3);

      final tier0Sk = deriveSelfChild(
        parentSk: body,
        protocolHash: DerivationDomain.tier0.protocolHash,
        index: 0,
        domainFlag: DerivationDomain.tier0.domainFlag, // L11.5 kdf-v3
      );
      final expectedPub = publicKeyFromPrivate(deriveSelfChild(
        parentSk: tier0Sk,
        protocolHash: spend.protocolHash,
        index: 3,
        domainFlag: spend.domainFlag, // L11.5 kdf-v3 (WALLET_SPEND)
      ));
      expect(svcPub, equals(expectedPub));
      svc.dispose();
    });

    test('does not bump highWater (debug surface)', () async {
      final store = _InMemoryIdentityStore();
      await store.write(kActiveCertBodySlot, _hexEncode(_fakeCertBody(8)));
      final svc = WalletKeyService(identityStore: store);
      await svc.loadIdentity();
      await svc.deriveAt(DerivationDomain.spend('oddjobz/payout'), 0);
      await svc.deriveAt(DerivationDomain.spend('oddjobz/payout'), 1);
      // The recipe should not appear since deriveAt is non-allocating.
      final rules = await svc.recipes.readAll();
      expect(rules, isEmpty);
      svc.dispose();
    });
  });

  group('WalletKeyService.writeDevRandomCertBody', () {
    test('persists cert + reloads tier-0', () async {
      final store = _InMemoryIdentityStore();
      final svc = WalletKeyService(identityStore: store);
      final certIdHex = await svc.writeDevRandomCertBody();
      expect(certIdHex, hasLength(32));
      expect(svc.hasIdentity, isTrue);
      expect(svc.certIdHex, certIdHex);
      // The slot is populated and can be re-read.
      final stored = await store.read(kActiveCertBodySlot);
      expect(stored, isNotNull);
      expect(stored!.length, 64);
      svc.dispose();
    });

    test('subsequent generation overwrites the previous cert', () async {
      final svc = WalletKeyService(identityStore: _InMemoryIdentityStore());
      final id1 = await svc.writeDevRandomCertBody();
      final id2 = await svc.writeDevRandomCertBody();
      expect(id1, isNot(equals(id2)));
      expect(svc.certIdHex, id2);
      svc.dispose();
    });
  });

  group('WalletKeyService.dispose', () {
    test('throws on use after dispose', () async {
      final svc = WalletKeyService(identityStore: _InMemoryIdentityStore());
      svc.dispose();
      expect(svc.hasIdentity, isFalse);
      await expectLater(
        svc.deriveAt(DerivationDomain.change, 0),
        throwsA(isA<StateError>()),
      );
    });

    test('is idempotent', () async {
      final svc = WalletKeyService(identityStore: _InMemoryIdentityStore());
      svc.dispose();
      svc.dispose(); // must not throw
    });
  });
}

```
