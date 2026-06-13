---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/tier0_cache_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.125153+00:00
---

# apps/semantos/test/wallet/tier0_cache_test.dart

```dart
// C11 PR-C11-4c — Unit tests for `tier0_cache.dart`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:semantos/src/wallet/brc42_derive.dart';
import 'package:semantos/src/wallet/cert_body_store.dart';
import 'package:semantos/src/wallet/derivation_domain.dart';
import 'package:semantos/src/wallet/tier0_cache.dart';

Uint8List _fakeCertBody(int seed) {
  // Deterministic non-zero 32 bytes — not a real cert, just enough
  // to drive the BRC-42 plumbing.
  return Uint8List.fromList(
      List<int>.generate(32, (i) => ((i + seed) * 37 + 1) & 0xff));
}

void main() {
  group('Tier0Cache.fromCertBody', () {
    test('tier-0 is deterministic for the same cert', () {
      final body = _fakeCertBody(1);
      final a = Tier0Cache.fromCertBody(body);
      final b = Tier0Cache.fromCertBody(body);
      expect(a.tier0Sk, equals(b.tier0Sk));
      a.dispose();
      b.dispose();
    });

    test('different certs yield different tier-0', () {
      final a = Tier0Cache.fromCertBody(_fakeCertBody(1));
      final b = Tier0Cache.fromCertBody(_fakeCertBody(2));
      expect(a.tier0Sk, isNot(equals(b.tier0Sk)));
      a.dispose();
      b.dispose();
    });

    test('matches direct deriveSelfChild against the cert', () {
      final body = _fakeCertBody(3);
      final cache = Tier0Cache.fromCertBody(body);
      final expected = deriveSelfChild(
        parentSk: body,
        protocolHash: DerivationDomain.tier0.protocolHash,
        index: 0,
        domainFlag: DerivationDomain.tier0.domainFlag, // L11.5 kdf-v3
      );
      expect(cache.tier0Sk, equals(expected));
      cache.dispose();
    });

    test('rejects wrong-length cert_body', () {
      expect(
        () => Tier0Cache.fromCertBody(Uint8List(31)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Tier0Cache.deriveChild', () {
    test('caches per (domain, index)', () {
      final cache = Tier0Cache.fromCertBody(_fakeCertBody(1));
      final spend = DerivationDomain.spend('oddjobz/payout');
      final a = cache.deriveChild(spend, 0);
      final b = cache.deriveChild(spend, 0);
      expect(a, equals(b));
      cache.dispose();
    });

    test('different domains/indices yield different children', () {
      final cache = Tier0Cache.fromCertBody(_fakeCertBody(1));
      final payout = DerivationDomain.spend('oddjobz/payout');
      final release = DerivationDomain.spend('betterment/release');
      final payout0 = cache.deriveChild(payout, 0);
      final payout1 = cache.deriveChild(payout, 1);
      final release0 = cache.deriveChild(release, 0);
      expect(payout0, isNot(equals(payout1)));
      expect(payout0, isNot(equals(release0)));
      cache.dispose();
    });

    test('counterparty domain refuses (deferred to PR-C11-7)', () {
      final cache = Tier0Cache.fromCertBody(_fakeCertBody(1));
      expect(
        () => cache.deriveChild(
            DerivationDomain.peerReserved('02ab' * 16), 0),
        throwsA(isA<StateError>()),
      );
      cache.dispose();
    });

    test('refuses identity-parented domains (change/anchor) — L11 P6', () {
      // change/anchor derive from cert_body directly, not tier-0; the
      // cache holds only tier0Sk so it must refuse rather than silently
      // produce a non-brain-matching key.
      final cache = Tier0Cache.fromCertBody(_fakeCertBody(1));
      final typeHash = Uint8List.fromList(List<int>.generate(32, (i) => i));
      expect(
        () => cache.deriveChild(DerivationDomain.change, 0),
        throwsA(isA<StateError>()),
      );
      expect(
        () => cache.deriveChild(DerivationDomain.anchor(typeHash), 0),
        throwsA(isA<StateError>()),
      );
      cache.dispose();
    });

    test('throws after dispose', () {
      final cache = Tier0Cache.fromCertBody(_fakeCertBody(1));
      cache.dispose();
      expect(
        () => cache.tier0Sk,
        throwsA(isA<StateError>()),
      );
      expect(
        () => cache.deriveChild(DerivationDomain.spend('oddjobz/payout'), 0),
        throwsA(isA<StateError>()),
      );
    });

    test('dispose is idempotent', () {
      final cache = Tier0Cache.fromCertBody(_fakeCertBody(1));
      cache.dispose();
      cache.dispose(); // must not throw
    });
  });

  group('Tier0Cache.loadFromStore', () {
    const certIdHex = '06d0a049e88a982b0000000000000000';

    test('returns null when cert_body is absent', () async {
      final store =
          CertBodyStore(certIdHex: certIdHex, store: InMemorySecureStore());
      final cache = await Tier0Cache.loadFromStore(store);
      expect(cache, isNull);
    });

    test('reads cert_body and derives tier-0', () async {
      final secure = InMemorySecureStore();
      final store = CertBodyStore(certIdHex: certIdHex, store: secure);
      final body = _fakeCertBody(7);
      await store.write(body);
      final cache = await Tier0Cache.loadFromStore(store);
      expect(cache, isNotNull);
      final direct = Tier0Cache.fromCertBody(body);
      expect(cache!.tier0Sk, equals(direct.tier0Sk));
      cache.dispose();
      direct.dispose();
    });
  });
}

```
