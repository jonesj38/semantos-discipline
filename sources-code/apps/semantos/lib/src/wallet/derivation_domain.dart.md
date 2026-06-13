---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/derivation_domain.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.107796+00:00
---

# apps/semantos/lib/src/wallet/derivation_domain.dart

```dart
// C11 PR-C11-4c — Wallet derivation domains.
//
// Each domain pins a BRC-42 protocolHash that selects what tree the
// child key lives in. The wire bytes are derived deterministically
// from the domain's preimage string, so the same Dart shell, the
// same renderer, and a future CLI can all reproduce a derivation
// given just the (parent priv, domain, index) tuple.
//
// Reference: docs/design/WALLET-RENDERER-CONTRACT.md §2 (four-layer
// derivation tree).
//
// Domain catalog:
//
//   tier0                            — single root for the vault
//                                      (parent: root cert priv;     index 0)
//   spend/<context>/<n>              — per-utxo spending keys for a
//                                      cartridge context
//                                      (parent: tier-0;             index n)
//   change/<n>                       — change outputs
//                                      (parent: IDENTITY (cert_body); index n)
//   anchor/<typeHashHex>/<n>         — cell-anchor keys (MNCA path)
//                                      (parent: IDENTITY (cert_body); index n)
//   peer/<counterpartyPubHex>/<n>    — counterparty-scoped (PB=UTXO×G)
//                                      DEFERRED to PR-C11-7; the
//                                      `protocolHash` is reserved here
//                                      so the recipe-store schema
//                                      remains stable when 4c ships.
//
// L11 P6 (PWA ↔ brain unification): `change` and `anchor` now parent
// DIRECTLY on the identity key (cert_body) — not tier-0 — and pin the
// brain's exact protocolHash preimages, so the operator's PWA derives
// byte-identical change/anchor keys to the brain wallet (`ecdh42.ts`
// `deriveChangeSk` / `cell-anchor.ts` `deriveCellAnchorSk`). `tier0` +
// `spend` stay PWA-only (no brain counterpart) and keep their own tree.
// See docs/prd/PWA-BRAIN-WALLET-UNIFICATION.md §2.
//
// `protocolHash` is the first 16 bytes of SHA-256 of the preimage
// string. The preimage strings are an explicit contract — never
// reorder, never re-spell. A change here invalidates every existing
// derived key under the affected domain. The `change` / `anchor`
// preimages are pinned to the brain (`BRC-42-wallet-change` for change;
// `hex(typeHash)` for anchor) and MUST NOT drift — the cross-language
// KAT (`brain_wallet_kat_test.dart`) gates them.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// Canonical CHANGE domain flag (PLEXUS_RESERVED band), matching the brain's
/// `ecdh42.ts` `CHANGE_DOMAIN_FLAG` and `constants.json` `domainFlags.CHANGE`.
/// Folded into the change-key tweak under kdf-v3 (CW Lift L11.5).
const int kChangeDomainFlag = 0x0b;

/// Canonical domain flags (EXTENDED band) for the PWA-internal `tier0` and
/// `spend` derivation trees. Registered in `core/constants/constants.json`
/// (`domainFlags.WALLET_TIER0` / `WALLET_SPEND`) so the u32 namespace stays
/// collision-free system-wide, even though only the PWA derives under them
/// (no brain counterpart). Folded into the tweak under kdf-v3 (CW Lift L11.5);
/// the `spend` context label separates within the single `spend` domain.
const int kTier0DomainFlag = 257;
const int kSpendDomainFlag = 258;

/// Sovereign per-cell-type domain flag (client-defined range) — byte-identical
/// to the brain's `cell-anchor.ts` `domainFlagFromTypeHash`:
/// `0x00010000 | typeHash[0..2]`.
int domainFlagFromTypeHash(Uint8List typeHash) {
  if (typeHash.length != 32) {
    throw ArgumentError.value(
        typeHash.length, 'typeHash.length', 'must be 32 bytes');
  }
  return 0x00010000 |
      (typeHash[0] << 16) |
      (typeHash[1] << 8) |
      typeHash[2];
}

/// Domain selector for a BRC-42 self-derivation. Maps a logical
/// label (e.g. `vault/0/spend/oddjobz/payout`) to the 16-byte
/// `protocolHash` BRC-42 needs.
class DerivationDomain {
  const DerivationDomain._({
    required this.label,
    required this.scope,
    required this.preimage,
  });

  /// Recipe-store label. Stable identifier surfaced in the recovery
  /// envelope's `derivationRules[]`. The renderer-contract uses these
  /// verbatim.
  final String label;

  /// Logical category. Drives recovery scanner behaviour — `tier0`
  /// derives once at index 0, every other scope iterates indices up
  /// to `highWater`.
  final DerivationScope scope;

  /// String fed through `SHA-256(..)[0:16]` to produce the BRC-42
  /// `protocolHash`. Exposed for audit + cross-host parity checks.
  final String preimage;

  /// 16-byte BRC-42 protocolHash. Computed lazily; cached at
  /// first access.
  Uint8List get protocolHash =>
      Uint8List.sublistView(SHA256Digest().process(utf8.encode(preimage)), 0, 16);

  /// True when this domain's child keys derive DIRECTLY from the
  /// identity key (cert_body), matching the brain's identity-direct
  /// derivation (`deriveChangeSk` / `deriveCellAnchorSk`). The other
  /// PWA-only domains (`spend`) parent on tier-0; `tier0` itself is the
  /// cached identity child at index 0. `counterparty` is bilateral
  /// (edge ECDH) and never reaches this path. See L11 P6 §2.1.
  bool get parentsOnIdentity =>
      scope == DerivationScope.change || scope == DerivationScope.anchor;

  /// Canonical u32 domain flag this domain's keys are bound to under kdf-v3
  /// (CW Lift L11.5), or null for the bilateral `counterparty` domain (edge
  /// ECDH stays BRC-42 v1). Folded into the derivation tweak by
  /// `deriveSelfChild(domainFlag: …)`:
  ///   change → CHANGE flag (0x0b), matching `ecdh42.ts deriveChangeSk`.
  ///   anchor → domainFlagFromTypeHash(typeHash), matching
  ///            `cell-anchor.ts deriveCellAnchorSk`.
  ///   tier0  → WALLET_TIER0 (257); context (spend) → WALLET_SPEND (258).
  ///            PWA-internal (no brain counterpart); the spend context label
  ///            separates within the single spend domain.
  int? get domainFlag {
    switch (scope) {
      case DerivationScope.change:
        return kChangeDomainFlag;
      case DerivationScope.anchor:
        // preimage == hex(typeHash); flag = 0x00010000 | typeHash[0..2].
        final b0 = int.parse(preimage.substring(0, 2), radix: 16);
        final b1 = int.parse(preimage.substring(2, 4), radix: 16);
        final b2 = int.parse(preimage.substring(4, 6), radix: 16);
        return 0x00010000 | (b0 << 16) | (b1 << 8) | b2;
      case DerivationScope.tier0:
        return kTier0DomainFlag;
      case DerivationScope.context:
        return kSpendDomainFlag;
      case DerivationScope.counterparty:
        return null; // bilateral (BRC-42 edge ECDH) — stays kdf-v1
    }
  }

  // ─────────────── Catalog (the contract) ───────────────

  /// `tier0` — single root for the vault. Parent is the root cert
  /// priv; index is always 0.
  static const DerivationDomain tier0 = DerivationDomain._(
    label: 'vault/0',
    scope: DerivationScope.tier0,
    preimage: 'semantos-wallet-tier-0',
  );

  /// `change/<n>` — change outputs for self-directed leftover.
  ///
  /// L11 P6: parents on the identity key (cert_body) directly and pins
  /// the brain's change preimage so `deriveSegment(cert_body, invoice)`
  /// == brain `deriveChangeSk(identitySk, …)`. The preimage MUST equal
  /// `ecdh42.ts` `CHANGE_PROTOCOL_HASH` = SHA-256("BRC-42-wallet-change")
  /// [0:16]; the KAT asserts byte-equality.
  static const DerivationDomain change = DerivationDomain._(
    label: 'vault/0/change',
    scope: DerivationScope.change,
    preimage: 'BRC-42-wallet-change',
  );

  /// `spend/<context>/<n>` — per-utxo spending key for a cartridge
  /// context. The context label is operator-visible and recorded in
  /// the recipe-store row so recovery can list "which app's spend
  /// keys are we restoring".
  factory DerivationDomain.spend(String contextLabel) {
    _assertNonEmptyLabel(contextLabel, 'contextLabel');
    return DerivationDomain._(
      label: 'vault/0/spend/$contextLabel',
      scope: DerivationScope.context,
      preimage: 'semantos-wallet-spend:$contextLabel',
    );
  }

  /// `anchor/<typeHashHex>/<n>` — cell-anchor key for the MNCA on-chain
  /// path, keyed by the 32-byte cell `type_hash`.
  ///
  /// L11 P6: parents on the identity key (cert_body) directly and pins
  /// the brain's anchor preimage so `deriveSegment(cert_body, invoice)`
  /// == brain `deriveCellAnchorSk(identitySk, typeHash, …)`. The
  /// protocolHash is `SHA-256(hex(typeHash))[0:16]` — byte-identical to
  /// `cell-anchor.ts` `anchorProtocolHash`; achieved by setting the
  /// preimage to the lowercase hex of `typeHash`.
  factory DerivationDomain.anchor(Uint8List typeHash) {
    if (typeHash.length != 32) {
      throw ArgumentError.value(
          typeHash.length, 'typeHash.length', 'must be 32 bytes');
    }
    return DerivationDomain.anchorFromTypeHashHex(_hexLower(typeHash));
  }

  /// Rebuild an anchor domain from the stored lowercase-hex `type_hash`
  /// (the recipe-store `typeHash` field). Equivalent to
  /// [DerivationDomain.anchor] but skips the bytes round-trip — used by
  /// the bridge's `_domainFromRule`.
  factory DerivationDomain.anchorFromTypeHashHex(String typeHashHex) {
    if (typeHashHex.length != 64 || !_isLowerHex(typeHashHex)) {
      throw ArgumentError.value(typeHashHex, 'typeHashHex',
          'must be 64 lowercase hex chars (32-byte type_hash)');
    }
    return DerivationDomain._(
      label: 'vault/0/anchor/$typeHashHex',
      scope: DerivationScope.anchor,
      // preimage == hex(typeHash); SHA-256(utf8(preimage))[0:16] ==
      // cell-anchor.ts anchorProtocolHash(typeHash).
      preimage: typeHashHex,
    );
  }

  /// `peer/<counterpartyPubHex>/<n>` — counterparty-scoped (PB=UTXO×G).
  /// The protocolHash is reserved here so the recipe-store schema
  /// stays stable as of 4c; actual derivation is **not** implemented
  /// in this PR. Calling [protocolHash] is safe; calling
  /// `deriveSelfChild` with this domain would compute a self-ECDH
  /// scalar, which is not what the peer domain semantically means.
  /// PR-C11-7 wires the real edge-derivation path.
  factory DerivationDomain.peerReserved(String counterpartyPubHex) {
    _assertNonEmptyLabel(counterpartyPubHex, 'counterpartyPubHex');
    return DerivationDomain._(
      label: 'vault/0/peer/$counterpartyPubHex',
      scope: DerivationScope.counterparty,
      preimage: 'semantos-wallet-peer:$counterpartyPubHex',
    );
  }

  static void _assertNonEmptyLabel(String value, String name) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, name, 'must be non-empty');
    }
    // Note: `/` IS allowed in context / purpose labels — context
    // labels are hierarchical (e.g. `oddjobz/payout`,
    // `betterment/release`). The recipe-store label-stripping logic
    // takes everything after the fixed prefix, so an embedded `/`
    // round-trips fine.
  }

  /// Lowercase hex of [bytes]. Matches the brain's `bytesToHex` so the
  /// anchor preimage byte-matches `anchorProtocolHash`.
  static String _hexLower(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static bool _isLowerHex(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      final isDigit = c >= 0x30 && c <= 0x39; // 0-9
      final isLowerAf = c >= 0x61 && c <= 0x66; // a-f
      if (!isDigit && !isLowerAf) return false;
    }
    return true;
  }

  @override
  String toString() => 'DerivationDomain($label)';
}

/// The four kinds of derivation universes. Driven by the renderer
/// contract; persisted into recipe-store rows under `scope`.
enum DerivationScope {
  /// Single key at index 0. Recovery derives once.
  tier0,

  /// Per-cartridge spending keys. Recovery iterates `[0..highWater]`.
  context,

  /// Counterparty-scoped (PB = UTXO × G). PR-C11-7. Recovery walks
  /// counterparty list × `[0..highWater]`.
  counterparty,

  /// Cell-anchor keys (MNCA path). Recovery iterates per type_hash.
  anchor,

  /// Change outputs. Recovery iterates `[0..highWater]`.
  change,
}

```
