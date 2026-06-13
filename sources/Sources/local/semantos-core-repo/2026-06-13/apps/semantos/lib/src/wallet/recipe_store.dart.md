---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/recipe_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.106846+00:00
---

# apps/semantos/lib/src/wallet/recipe_store.dart

```dart
// C11 PR-C11-4c — Derivation recipe store.
//
// References:
//   - docs/design/WALLET-RENDERER-CONTRACT.md §5 (Dart responsibilities) +
//     §6 (recovery envelope v2 schema)
//   - apps/semantos/lib/src/identity/child_cert_store.dart — `SecureStore`
//     abstraction reused here.
//
// The recipe store is the authoritative log of "which derivation
// rules has the wallet ever used, and how far along each one are we".
// Recovery walks the rule set, regenerates keys up to each rule's
// `highWater`, and either matches them against utxo manifests
// (PR-C11-7 future) or SPV-scans the chain.
//
// Storage shape:
//
//   me.recipes.v1   →   JSON array of DerivationRule rows
//
// Rule row schema:
//
//   {
//     "id":               "vault/0/spend/oddjobz/payout",
//     "scope":            "context",           // DerivationScope name
//     "label":            "vault/0/spend/oddjobz/payout",
//     "contextLabel":     "oddjobz/payout",    // present when scope==context
//     "counterpartyPub":  "02ab…",             // present when scope==counterparty
//     "typeHash":         "00112233…",         // 32-byte cell type_hash hex,
//                                              //   present when scope==anchor (L11 P6)
//     "kdfVersion":       "plexus-kdf-v2",     // per-domain KDF era (L11 P6)
//     "highWater":        47,                  // highest index issued; -1 = none yet
//     "createdAtMs":      1717000000000
//   }
//
// L11 P6 (PWA ↔ brain unification): the anchor scope is keyed by the
// cell `type_hash` (was a free `purpose` string) so the anchor
// protocolHash byte-matches the brain's `anchorProtocolHash`. Each row
// also records a `kdfVersion` — all implemented PWA domains are
// unilateral (deriveSegment) → `plexus-kdf-v2`; only the deferred
// counterparty scope is bilateral (BRC-42) → `plexus-kdf-v1`. A
// restoring device routes to the right derivation algorithm per row.
// Clean cutover: legacy `purpose`-keyed anchor rows are NOT read back
// (throwaway prototyping artefacts, no spend intent).
//
// `highWater` semantics:
//   - `-1` means the rule has been registered but no key has been
//     issued yet. `allocateNextIndex(...)` bumps it to 0 on first call.
//   - Otherwise it is the highest index that has been handed out via
//     `allocateNextIndex(...)`. Recovery rescans `[0..highWater]`.
//
// The store is append-only at the *rule* level — you don't delete a
// rule once it's been used, because spending keys exist on-chain and
// recovery still needs the recipe to find them. `clear()` exists for
// the operator-initiated unpair path; it wipes everything.

import 'dart:async';
import 'dart:convert';

import '../identity/child_cert_store.dart' show SecureStore;
import 'derivation_domain.dart';

/// SecureStore slot for the recipe log. Versioned for future
/// schema migrations.
const String _kRecipesKey = 'me.recipes.v1';

/// Canonical per-domain KDF version markers (mirror the brain's
/// `KdfVersion` in `cartridges/wallet-headers/brain/src/plexus/envelope.ts`
/// and the SDK `KdfVersion`).
///   `plexus-kdf-v1` — BRC-42 (bilateral; HMAC over an ECDH shared secret).
///   `plexus-kdf-v2` — EP3259724B1 `deriveSegment` (unilateral; SHA-256(invoice)).
///   `plexus-kdf-v3` — EP3259724B1 `deriveDomainSegment` (unilateral, domain-
///                     separated; SHA-256(u32_be(domainFlag) || invoice)).
const String kKdfVersionV1 = 'plexus-kdf-v1';
const String kKdfVersionV2 = 'plexus-kdf-v2';
const String kKdfVersionV3 = 'plexus-kdf-v3';

/// The canonical KDF for a derivation scope (L11 / L11.5). Mirrors the brain's
/// `kdfVersionForDomain`:
///   - `counterparty` (deferred, bilateral) → BRC-42 `plexus-kdf-v1`.
///   - every unilateral domain → domain-separated `plexus-kdf-v3` (L11.5: the
///     canonical domain flag is folded into the tweak). change/anchor match the
///     brain byte-for-byte; tier0/spend use the PWA-internal WALLET_TIER0 /
///     WALLET_SPEND flags (P6 — closes the last v2 production callers).
String kdfVersionForScope(DerivationScope scope) {
  switch (scope) {
    case DerivationScope.counterparty:
      return kKdfVersionV1;
    case DerivationScope.change:
    case DerivationScope.anchor:
    case DerivationScope.tier0:
    case DerivationScope.context:
      return kKdfVersionV3;
  }
}

/// A derivation rule row, as persisted and as exported into the
/// recovery envelope's `derivationRules[]`.
class DerivationRule {
  const DerivationRule({
    required this.id,
    required this.scope,
    required this.label,
    required this.highWater,
    required this.createdAtMs,
    required this.kdfVersion,
    this.contextLabel,
    this.counterpartyPub,
    this.typeHash,
  });

  /// Stable identifier — matches `label` for now; reserved as a
  /// separate field so a future rev could rename labels without
  /// touching ids.
  final String id;

  /// Derivation universe (tier-0 / context / counterparty / anchor / change).
  final DerivationScope scope;

  /// Recipe-store label (the renderer-contract recipe id).
  final String label;

  /// Highest index issued so far. `-1` until the first allocation.
  final int highWater;

  /// Creation timestamp (ms since epoch). Diagnostics only.
  final int createdAtMs;

  /// Cartridge context, when `scope == context`.
  final String? contextLabel;

  /// Counterparty pubkey, when `scope == counterparty`.
  final String? counterpartyPub;

  /// Cell `type_hash` (32-byte lowercase hex), when `scope == anchor`
  /// (L11 P6 — was a free `purpose` string). Selects the anchor
  /// protocolHash that byte-matches the brain's `anchorProtocolHash`.
  final String? typeHash;

  /// Per-domain KDF version (L11 P6). `plexus-kdf-v2` for the unilateral
  /// PWA domains; `plexus-kdf-v1` only for the deferred bilateral
  /// counterparty scope. A restoring device routes to the matching
  /// derivation algorithm.
  final String kdfVersion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'scope': scope.name,
        'label': label,
        'highWater': highWater,
        'createdAtMs': createdAtMs,
        'kdfVersion': kdfVersion,
        if (contextLabel != null) 'contextLabel': contextLabel,
        if (counterpartyPub != null) 'counterpartyPub': counterpartyPub,
        if (typeHash != null) 'typeHash': typeHash,
      };

  static DerivationRule fromJson(Map<String, dynamic> json) {
    final scopeName = json['scope'] as String;
    final scope = DerivationScope.values.firstWhere(
      (s) => s.name == scopeName,
      orElse: () => throw FormatException(
          'recipe-store: unknown scope "$scopeName"'),
    );
    return DerivationRule(
      id: json['id'] as String,
      scope: scope,
      label: json['label'] as String,
      highWater: json['highWater'] as int,
      createdAtMs: json['createdAtMs'] as int,
      // Legacy rows predate per-domain kdfVersion — default by scope so
      // they parse and route correctly.
      kdfVersion: json['kdfVersion'] as String? ?? kdfVersionForScope(scope),
      contextLabel: json['contextLabel'] as String?,
      counterpartyPub: json['counterpartyPub'] as String?,
      typeHash: json['typeHash'] as String?,
    );
  }

  DerivationRule withHighWater(int newHighWater) => DerivationRule(
        id: id,
        scope: scope,
        label: label,
        highWater: newHighWater,
        createdAtMs: createdAtMs,
        kdfVersion: kdfVersion,
        contextLabel: contextLabel,
        counterpartyPub: counterpartyPub,
        typeHash: typeHash,
      );
}

/// Per-instance lock to serialise read-modify-write cycles. Without
/// this, two concurrent `allocateNextIndex` calls could both read
/// `highWater = 47`, both return 48, and both persist 48 — colliding
/// the spending key. The lock is per-process; `flutter_secure_storage`
/// itself is not multi-process safe, which is fine for the shell.
class _SerialLock {
  Future<void> _last = Future<void>.value();

  Future<T> run<T>(Future<T> Function() body) async {
    final completer = Completer<void>();
    final previous = _last;
    _last = completer.future;
    try {
      await previous;
      return await body();
    } finally {
      completer.complete();
    }
  }
}

/// Append-only log of derivation rules + monotonic index allocator.
class RecipeStore {
  RecipeStore(this._store);

  final SecureStore _store;
  final _SerialLock _lock = _SerialLock();

  /// Read the current rule set. Returns an empty list if the slot is
  /// absent. Throws [FormatException] on corruption — caller decides
  /// whether to nuke + restart from envelope replay.
  Future<List<DerivationRule>> readAll() async {
    final raw = await _store.read(_kRecipesKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = json.decode(raw);
    if (decoded is! List) {
      throw FormatException(
          'recipe-store: expected JSON array at $_kRecipesKey');
    }
    return decoded
        .map((e) => DerivationRule.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Register a rule for the given domain if absent. Returns the rule.
  ///
  /// Idempotent — calling twice with the same domain returns the
  /// existing row without bumping `highWater` or `createdAtMs`.
  Future<DerivationRule> registerRule(DerivationDomain domain) async {
    return _lock.run(() async {
      final rules = await _readAllUnlocked();
      final existing = rules.where((r) => r.id == domain.label).firstOrNull;
      if (existing != null) return existing;
      final created = DerivationRule(
        id: domain.label,
        scope: domain.scope,
        label: domain.label,
        highWater: -1,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        kdfVersion: kdfVersionForScope(domain.scope),
        contextLabel: _contextLabelFor(domain),
        counterpartyPub: _counterpartyPubFor(domain),
        typeHash: _typeHashFor(domain),
      );
      await _writeAllUnlocked([...rules, created]);
      return created;
    });
  }

  /// Allocate the next index under [domain]. Registers the rule
  /// lazily on first call. Returns the issued index and the updated
  /// rule (with `highWater` = returned index).
  ///
  /// Index 0 is issued on the first call, 1 on the second, and so on.
  /// Concurrent calls are serialised; no two callers ever receive the
  /// same index for the same domain.
  Future<({int index, DerivationRule rule})> allocateNextIndex(
      DerivationDomain domain) async {
    return _lock.run(() async {
      final rules = await _readAllUnlocked();
      final idx = rules.indexWhere((r) => r.id == domain.label);
      late DerivationRule next;
      late int issuedIndex;
      if (idx == -1) {
        issuedIndex = 0;
        next = DerivationRule(
          id: domain.label,
          scope: domain.scope,
          label: domain.label,
          highWater: 0,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          kdfVersion: kdfVersionForScope(domain.scope),
          contextLabel: _contextLabelFor(domain),
          counterpartyPub: _counterpartyPubFor(domain),
          typeHash: _typeHashFor(domain),
        );
        await _writeAllUnlocked([...rules, next]);
      } else {
        final existing = rules[idx];
        issuedIndex = existing.highWater + 1;
        next = existing.withHighWater(issuedIndex);
        final updated = [...rules]..[idx] = next;
        await _writeAllUnlocked(updated);
      }
      return (index: issuedIndex, rule: next);
    });
  }

  /// Wipe the recipe log. Operator-initiated unpair only.
  Future<void> clear() async {
    await _lock.run(() async {
      await _store.delete(_kRecipesKey);
    });
  }

  // ─────────────── helpers ───────────────

  Future<List<DerivationRule>> _readAllUnlocked() async {
    final raw = await _store.read(_kRecipesKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = json.decode(raw);
    if (decoded is! List) {
      throw FormatException(
          'recipe-store: expected JSON array at $_kRecipesKey');
    }
    return decoded
        .map((e) => DerivationRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeAllUnlocked(List<DerivationRule> rules) async {
    final payload = json.encode(rules.map((r) => r.toJson()).toList());
    await _store.write(_kRecipesKey, payload);
  }

  /// Extract the cartridge context label from a context-scoped domain.
  /// The domain stores the label as part of its `.label` field
  /// (`vault/0/spend/<context>`); we strip the prefix here so the
  /// recipe row keeps it as a first-class field.
  static String? _contextLabelFor(DerivationDomain domain) {
    if (domain.scope != DerivationScope.context) return null;
    const prefix = 'vault/0/spend/';
    if (!domain.label.startsWith(prefix)) return null;
    return domain.label.substring(prefix.length);
  }

  static String? _counterpartyPubFor(DerivationDomain domain) {
    if (domain.scope != DerivationScope.counterparty) return null;
    const prefix = 'vault/0/peer/';
    if (!domain.label.startsWith(prefix)) return null;
    return domain.label.substring(prefix.length);
  }

  /// Extract the cell `type_hash` (lowercase hex) from an anchor-scoped
  /// domain. The domain stores it as the trailing segment of its label
  /// (`vault/0/anchor/<typeHashHex>`); recovery reconstructs the anchor
  /// protocolHash from it via `DerivationDomain.anchorFromTypeHashHex`.
  static String? _typeHashFor(DerivationDomain domain) {
    if (domain.scope != DerivationScope.anchor) return null;
    const prefix = 'vault/0/anchor/';
    if (!domain.label.startsWith(prefix)) return null;
    return domain.label.substring(prefix.length);
  }
}

extension on Iterable<DerivationRule> {
  DerivationRule? get firstOrNull => isEmpty ? null : first;
}

```
