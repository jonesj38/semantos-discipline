---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/tier0_cache.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.104044+00:00
---

# apps/semantos/lib/src/wallet/tier0_cache.dart

```dart
// C11 PR-C11-4c — Tier-0 vault key cache.
//
// Reference: docs/design/WALLET-RENDERER-CONTRACT.md §5.
//
// `tier0Sk = deriveSegment(rootCertPriv, "vault/0")`.
//
// The cert priv is short-lived: we read it from `CertBodyStore`, derive
// tier-0, and keep tier-0 around for the wallet sheet's lifetime. The
// cert priv itself drops out of scope as soon as derivation finishes —
// this cache deliberately does NOT retain the identity key.
//
// L11 P6: tier-0-parented domains (`spend`) cache by `(label, index)`.
// The identity-parented domains (`change` / `anchor`) derive DIRECTLY
// from the identity key (cert_body) to byte-match the brain wallet, so
// they are NOT served here — the cache holds only `tier0Sk`, not
// cert_body. `WalletKeyService` re-reads cert_body on demand for those
// (keeping the "don't retain the root" posture). This cache refuses
// `parentsOnIdentity` domains rather than silently deriving the wrong
// (tier-0-parented) key. See docs/prd/PWA-BRAIN-WALLET-UNIFICATION.md §2.1.
//
// Lifecycle:
//   - `Tier0Cache.fromCertBody(certBody)` — synchronous if you already
//     have the cert bytes (test/dev path).
//   - `Tier0Cache.loadFromStore(store)` — async factory that reads
//     cert_body via `CertBodyStore` then constructs the cache.
//   - `dispose()` — zeros the cached tier-0 scalar and per-child
//     caches. Call from `_WalletSheetState.dispose`.

import 'dart:typed_data';

import 'brc42_derive.dart';
import 'cert_body_store.dart';
import 'derivation_domain.dart';

/// Cached tier-0 key plus on-demand per-domain child derivation.
class Tier0Cache {
  Tier0Cache._(this._tier0Sk);

  /// 32-byte big-endian tier-0 secp256k1 private key. Lives until
  /// [dispose] is called.
  Uint8List _tier0Sk;

  /// Per-(label, index) child priv cache. Keyed by `"${domain.label}#$index"`.
  final Map<String, Uint8List> _children = {};

  bool _disposed = false;

  /// Construct directly from the cert_body bytes. Useful for tests.
  /// The cert_body is consumed only during this constructor call; the
  /// caller's reference is not retained.
  factory Tier0Cache.fromCertBody(Uint8List certBody) {
    if (certBody.length != kCertBodyLength) {
      throw ArgumentError.value(certBody.length, 'certBody.length',
          'must be $kCertBodyLength bytes');
    }
    final tier0 = deriveSelfChild(
      parentSk: certBody,
      protocolHash: DerivationDomain.tier0.protocolHash,
      index: 0,
      // L11.5 kdf-v3: bind to the WALLET_TIER0 domain flag.
      domainFlag: DerivationDomain.tier0.domainFlag,
    );
    return Tier0Cache._(tier0);
  }

  /// Load the cert_body from [store], derive tier-0, return the cache.
  /// Returns null if no cert_body is present.
  static Future<Tier0Cache?> loadFromStore(CertBodyStore store) async {
    final body = await store.read();
    if (body == null) return null;
    try {
      return Tier0Cache.fromCertBody(body);
    } finally {
      // Best-effort zero of the cert_body we just consumed. Dart
      // immutable string copies are out of reach but the typed bytes
      // here are ours to clear.
      body.fillRange(0, body.length, 0);
    }
  }

  /// Tier-0 priv. Cached. Throws if [dispose] has been called.
  Uint8List get tier0Sk {
    _ensureLive();
    // Return a defensive copy so callers can zero their copy without
    // wiping our cache.
    return Uint8List.fromList(_tier0Sk);
  }

  /// Derive (or return cached) child priv for the given domain and
  /// index. The cache is in-memory only.
  Uint8List deriveChild(DerivationDomain domain, int index) {
    _ensureLive();
    if (domain.scope == DerivationScope.counterparty) {
      // PR-C11-7 wires the actual counterparty ECDH; we refuse here
      // rather than silently produce a self-ECDH scalar that the
      // counterparty cannot spend.
      throw StateError(
        'Tier0Cache: counterparty-scoped derivation requires the edge'
        ' ECDH primitive (PR-C11-7). Domain=${domain.label} index=$index',
      );
    }
    if (domain.parentsOnIdentity) {
      // L11 P6: change/anchor parent on the identity key (cert_body) to
      // byte-match the brain wallet — this cache holds only tier0Sk, not
      // cert_body. WalletKeyService derives these from a fresh cert_body
      // read. Deriving them off tier-0 here would silently produce a
      // different (non-brain-matching) key, so we refuse.
      throw StateError(
        'Tier0Cache: ${domain.scope.name}-scoped derivation parents on the'
        ' identity key, not tier-0 (L11 P6). Use WalletKeyService.'
        ' Domain=${domain.label} index=$index',
      );
    }
    final key = '${domain.label}#$index';
    final hit = _children[key];
    if (hit != null) return Uint8List.fromList(hit);
    final derived = deriveSelfChild(
      parentSk: _tier0Sk,
      protocolHash: domain.protocolHash,
      index: index,
      // L11.5 kdf-v3: bind to the domain's flag (spend → WALLET_SPEND).
      domainFlag: domain.domainFlag,
    );
    _children[key] = derived;
    return Uint8List.fromList(derived);
  }

  /// Public key for a derived child, compressed (33 bytes).
  Uint8List deriveChildPub(DerivationDomain domain, int index) {
    final sk = deriveChild(domain, index);
    try {
      return publicKeyFromPrivate(sk);
    } finally {
      sk.fillRange(0, sk.length, 0);
    }
  }

  /// Zero the tier-0 scalar + all cached children. Idempotent.
  void dispose() {
    if (_disposed) return;
    _tier0Sk.fillRange(0, _tier0Sk.length, 0);
    for (final child in _children.values) {
      child.fillRange(0, child.length, 0);
    }
    _children.clear();
    _disposed = true;
  }

  void _ensureLive() {
    if (_disposed) {
      throw StateError('Tier0Cache: used after dispose');
    }
  }
}

```
