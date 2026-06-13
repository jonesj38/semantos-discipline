---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/wallet_key_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.106317+00:00
---

# apps/semantos/lib/src/wallet/wallet_key_service.dart

```dart
// C11 PR-C11-4f — Shell-singleton wallet key service.
//
// References:
//   - docs/design/WALLET-RENDERER-CONTRACT.md §5 (Dart responsibilities)
//   - apps/semantos/lib/src/wallet/wallet_bridge.dart — the renderer
//     UX consumer of this service (one of many possible)
//
// Why this exists:
//   PR-C11-4c shipped the wallet primitives (`CertBodyStore`,
//   `Tier0Cache`, `RecipeStore`) as standalone Dart modules. PR-C11-4e
//   wired them into the bridge, but ownership of the `Tier0Cache` lived
//   inside the bridge instance — which dies with the wallet sheet.
//   That's wrong for the architecture the renderer contract describes
//   (§5): the shell owns the keys, multiple consumers (renderer, REPL,
//   intent dispatch, cell anchoring) operate on the same key store.
//
//   This service promotes the wallet primitives to a long-lived shell
//   service. It hangs off `SemantosPlatform` next to the existing
//   `walletService` (which is the BRC-100 RPC adapter for an
//   already-built tx — a different layer). Any Dart caller in the
//   shell can derive receive addresses, sign-relevant child priv
//   keys, etc. headlessly, without driving the renderer.
//
//   The "drawer of postage stamps" mental model maps onto this
//   surface: each receive index is a fresh stamp, allocated
//   monotonically per context, derivable on demand from the root
//   cert. PR-C11-7 wires the actual dispensing (tx builder + UTXO
//   store + broadcast).

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pointycastle/digests/sha256.dart';
import 'package:semantos_core/semantos_core.dart' show IdentityStore;

import '../identity/cell_signer.dart' show signCellPayload;
import 'address.dart';
import 'brc42_derive.dart';
import 'derivation_domain.dart';
import 'identity_store_adapter.dart';
import 'recipe_store.dart';
import 'tier0_cache.dart';
import 'utxo_store.dart';

/// SecureStore slot for the active operator's cert_body. Single-
/// identity convention matches `ChallengeBundleStore` and the bridge
/// in PR-C11-4e. Multi-identity moves to `me.cert_body.v1.${certIdHex}`
/// (per `CertBodyStore`) when PR-C11-6 lands the brain envelope cell.
const String kActiveCertBodySlot = 'me.cert_body.v1';

/// Outcome of a receive-address allocation — the data a consumer
/// needs to display the address and record the recipe back into a
/// UTXO manifest in the future.
class WalletReceive {
  const WalletReceive({
    required this.recipeId,
    required this.index,
    required this.pubHex,
    required this.address,
    required this.contextLabel,
  });

  /// Recipe-store id (e.g. `vault/0/spend/oddjobz/payout`).
  final String recipeId;

  /// Monotonic index allocated for this receive. The (recipeId,
  /// index) pair uniquely identifies the derivation in the recovery
  /// envelope.
  final int index;

  /// 33-byte compressed pubkey, hex-encoded. Kept alongside the
  /// address for debug and for callers (recovery scanner, tx
  /// builder) that need the pubkey directly.
  final String pubHex;

  /// BSV P2PKH address (base58check). The string operators paste
  /// into payment UIs.
  final String address;

  /// Cartridge context label the caller supplied.
  final String contextLabel;
}

/// Shell-singleton wallet key service.
///
/// Construct once at boot, hand it through `SemantosPlatform.of(context)`,
/// and let it live for the session. Holds:
///   - The active cert_id derived from the cert_body.
///   - The `Tier0Cache` (with `dispose`-cleared scalars).
///   - The `RecipeStore` over the canonical `IdentityStore`.
///
/// Public surface:
///   - `loadIdentity()` — re-read cert_body from the store and refresh
///     the cached tier-0. Idempotent.
///   - `hasIdentity` / `certIdHex` / `tier0Pub` — current bound state.
///   - `deriveReceive(contextLabel)` — allocate next index, derive pub.
///     The headless equivalent of the renderer's address.request flow.
///   - `deriveAt(domain, index)` — fixed-index derive, no allocation.
///     For recovery scanner and debug surfaces.
///   - `writeDevRandomCertBody()` — dev affordance that writes a fresh
///     cert priv into the keystore. Used by the Me-sheet "Generate dev
///     cert" button while Plexus RaaS / pairing flows aren't yet
///     writing for us.
///   - `clearIdentity()` — wipe cert_body + drop the cache.
class WalletKeyService {
  WalletKeyService({required IdentityStore identityStore})
      : _identityStore = identityStore,
        _recipes =
            RecipeStore(IdentityStoreSecureStoreAdapter(identityStore)),
        _utxos =
            UtxoStore(IdentityStoreSecureStoreAdapter(identityStore));

  final IdentityStore _identityStore;
  final RecipeStore _recipes;
  final UtxoStore _utxos;

  Tier0Cache? _tier0;
  String? _certIdHex;
  bool _disposed = false;

  /// True when a cert_body has been loaded and the tier-0 cache is
  /// populated. The bridge and other consumers gate on this.
  bool get hasIdentity => _tier0 != null && !_disposed;

  /// First 16 bytes of SHA-256(certPub), hex-encoded. Null until
  /// [loadIdentity] succeeds.
  String? get certIdHex => _certIdHex;

  /// 33-byte compressed tier-0 pubkey, or null when no identity.
  Uint8List? get tier0Pub {
    final t = _tier0;
    if (t == null) return null;
    final sk = t.tier0Sk;
    try {
      return publicKeyFromPrivate(sk);
    } finally {
      sk.fillRange(0, sk.length, 0);
    }
  }

  /// C7-B sovereign mint — sign [message] with the operator's tier-0 (hat)
  /// key via the cell-signing scheme (ECDSA-secp256k1 over SHA-256, 64-byte
  /// r‖s, low-s). Returns null when no identity is loaded (caller falls back
  /// to an unsigned mint). The priv is zeroed immediately after signing
  /// (same get-use-zero discipline as [tier0Pub]). The brain (#828) verifies
  /// this signature against the operator cert before persisting.
  Uint8List? signWithOperatorKey(Uint8List message) {
    final t = _tier0;
    if (t == null || _disposed) return null;
    final sk = t.tier0Sk;
    try {
      return signCellPayload(message, sk);
    } finally {
      sk.fillRange(0, sk.length, 0);
    }
  }

  /// Direct accessor to the recipe store — for the recovery scanner
  /// and the bridge's `derivation.request` debug surface.
  RecipeStore get recipes => _recipes;

  /// Direct accessor to the UTXO store. PR-C11-7c (funding) +
  /// PR-C11-7d (recovery scanner) drive it; the renderer reads it
  /// to populate the UTXOs panel; the tx builder (PR-C11-7b) picks
  /// inputs from it.
  UtxoStore get utxos => _utxos;

  /// Read cert_body from the active slot and (re)build the tier-0
  /// cache. Safe to call multiple times. Returns true if an identity
  /// is bound after the call.
  Future<bool> loadIdentity() async {
    _ensureLive();
    final raw = await _identityStore.read(kActiveCertBodySlot);
    if (raw == null || raw.length != 64) {
      _tier0?.dispose();
      _tier0 = null;
      _certIdHex = null;
      return false;
    }
    final body = _hexDecode(raw);
    if (body == null) {
      _tier0?.dispose();
      _tier0 = null;
      _certIdHex = null;
      return false;
    }
    try {
      final certPub = publicKeyFromPrivate(body);
      _certIdHex = _hexEncode(SHA256Digest().process(certPub).sublist(0, 16));
      _tier0?.dispose();
      _tier0 = Tier0Cache.fromCertBody(body);
      debugPrint(
          '[wallet] [INFO] [wallet-key-service] identity loaded cert=$_certIdHex');
      return true;
    } finally {
      body.fillRange(0, body.length, 0);
    }
  }

  /// Allocate the next receive index under [contextLabel] and return
  /// the derived pubkey + P2PKH address + recipe metadata. Each call
  /// returns a fresh index AND inserts a `watching` row into the
  /// UTXO store so a future address-scan (PR-C11-7c) can flip it to
  /// `confirmed` without losing the recipe ↔ index binding.
  Future<WalletReceive> deriveReceive(String contextLabel) async {
    _ensureLive();
    final tier0 = _tier0;
    if (tier0 == null) {
      throw StateError('WalletKeyService: no identity bound');
    }
    if (contextLabel.isEmpty) {
      throw ArgumentError.value(
          contextLabel, 'contextLabel', 'must be non-empty');
    }
    final domain = DerivationDomain.spend(contextLabel);
    final allocation = await _recipes.allocateNextIndex(domain);
    final pub = tier0.deriveChildPub(domain, allocation.index);
    final addr = addressFromPub(pub);
    await _utxos.addWatching(
      address: addr,
      recipeId: allocation.rule.id,
      index: allocation.index,
    );
    return WalletReceive(
      recipeId: allocation.rule.id,
      index: allocation.index,
      pubHex: _hexEncode(pub),
      address: addr,
      contextLabel: contextLabel,
    );
  }

  /// Derive the child pub for a fixed (domain, index). Does NOT bump
  /// `highWater` — for the recovery scanner and debug derivation
  /// inspection only.
  ///
  /// L11 P6: identity-parented domains (`change` / `anchor`) derive
  /// DIRECTLY from the identity key (cert_body), re-read from the store
  /// on demand (we deliberately don't retain the root), so they
  /// byte-match the brain wallet (`deriveChangeSk` / `deriveCellAnchorSk`).
  /// tier-0-parented domains (`spend`) come from the cached tier-0.
  Future<Uint8List> deriveAt(DerivationDomain domain, int index) async {
    _ensureLive();
    final tier0 = _tier0;
    if (tier0 == null) {
      throw StateError('WalletKeyService: no identity bound');
    }
    if (domain.parentsOnIdentity) {
      return _deriveIdentityChildPub(domain, index);
    }
    return tier0.deriveChildPub(domain, index);
  }

  /// Derive the child pub for an identity-parented domain (change /
  /// anchor) directly off the identity key. Re-reads cert_body from the
  /// store, derives, and zeros every intermediate so the root key is
  /// never retained past the call (L11 P6 §2.1 hardening). The result
  /// is byte-identical to the brain's `deriveChangeSk` /
  /// `deriveCellAnchorSk` for the same (identityKey, index[, typeHash]).
  Future<Uint8List> _deriveIdentityChildPub(
      DerivationDomain domain, int index) async {
    final certBody = await _readCertBody();
    if (certBody == null) {
      throw StateError(
          'WalletKeyService: cert_body unavailable for identity-parented'
          ' derivation (${domain.label})');
    }
    try {
      final sk = deriveSelfChild(
        parentSk: certBody,
        protocolHash: domain.protocolHash,
        index: index,
        // L11.5 kdf-v3: change/anchor fold their canonical domain flag so the
        // key is byte-identical to the brain's deriveChangeSk / deriveCellAnchorSk.
        domainFlag: domain.domainFlag,
      );
      try {
        return publicKeyFromPrivate(sk);
      } finally {
        sk.fillRange(0, sk.length, 0);
      }
    } finally {
      certBody.fillRange(0, certBody.length, 0);
    }
  }

  /// Re-read the active cert_body from the store. Returns null when
  /// absent or malformed. Caller MUST zero the returned bytes after use.
  Future<Uint8List?> _readCertBody() async {
    final raw = await _identityStore.read(kActiveCertBodySlot);
    if (raw == null || raw.length != 64) return null;
    return _hexDecode(raw);
  }

  /// Write a freshly-generated 32-byte cert_body into the active
  /// slot and reload the tier-0 cache. Returns the new cert_id.
  ///
  /// **Development affordance.** The real cert_body writer is the
  /// pairing / Plexus-RaaS onboarding flow; this exists so the wallet
  /// can be shaken out end-to-end before that flow ships. Behind the
  /// Me sheet's "Generate dev cert (dev)" button.
  Future<String> writeDevRandomCertBody() async {
    _ensureLive();
    final rand = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = rand.nextInt(256);
    }
    // 32 zero bytes is a degenerate secp256k1 scalar; the rejection
    // sample is below realistic odds (2^-256) but we check anyway so
    // the dev path can't surface a confusing crash.
    var allZero = true;
    for (final b in bytes) {
      if (b != 0) {
        allZero = false;
        break;
      }
    }
    if (allZero) {
      bytes[31] = 1;
    }
    try {
      await _identityStore.write(kActiveCertBodySlot, _hexEncode(bytes));
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
    final ok = await loadIdentity();
    if (!ok) {
      throw StateError(
          'WalletKeyService.writeDevRandomCertBody: load failed post-write');
    }
    return _certIdHex!;
  }

  /// Wipe the active cert_body and drop the tier-0 cache. Operator-
  /// initiated unpair only.
  Future<void> clearIdentity() async {
    _ensureLive();
    await _identityStore.delete(kActiveCertBodySlot);
    _tier0?.dispose();
    _tier0 = null;
    _certIdHex = null;
  }

  /// Drop in-memory key material. Idempotent. Call from shell
  /// teardown.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tier0?.dispose();
    _tier0 = null;
    _certIdHex = null;
  }

  // ─────────────── helpers ───────────────

  void _ensureLive() {
    if (_disposed) {
      throw StateError('WalletKeyService: used after dispose');
    }
  }

  Uint8List? _hexDecode(String hex) {
    if (hex.length.isOdd) return null;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final b = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (b == null) return null;
      out[i] = b;
    }
    return out;
  }

  String _hexEncode(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

```
