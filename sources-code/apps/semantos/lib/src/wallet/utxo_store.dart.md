---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/utxo_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.104680+00:00
---

# apps/semantos/lib/src/wallet/utxo_store.dart

```dart
// C11 PR-C11-7a — UTXO store (schema + persistence; funding wires up
// in 7c).
//
// References:
//   - docs/design/WALLET-RENDERER-CONTRACT.md §5 (Dart-side UTXO store)
//   - apps/semantos/lib/src/wallet/recipe_store.dart — the sibling
//     store; this file follows the same SecureStore-backed JSON-array
//     pattern + per-instance lock for read-modify-write.
//
// Schema (one row per output the wallet cares about):
//
//   {
//     "txid":       "<64-hex>",         // 32-byte tx hash, hex
//     "vout":       <int>,              // output index
//     "value":      <int>,              // sats (0 when status=watching)
//     "scriptHex":  "<hex>",            // scriptPubKey hex (locking script)
//     "address":    "<base58check>",    // P2PKH address derived from the recipe
//     "recipeId":   "<recipe-id>",      // recipe-store id
//     "index":      <int>,              // BRC-42 derivation index
//     "status":     "watching" | "confirmed" | "spent",
//     "addedAtMs":  <int>,              // ms since epoch
//     "updatedAtMs":<int>
//   }
//
// Lifecycle:
//   - `addWatching` — called from `WalletKeyService.deriveReceive`
//     when an address is allocated but no output exists yet.
//     `txid="", vout=-1, value=0`. PR-C11-7c will swap these into
//     `confirmed` rows when an address-scan / SPV walk finds them
//     funded.
//   - `recordConfirmed` — PR-C11-7c. Fills in (txid, vout, value,
//     scriptHex).
//   - `markSpent` — PR-C11-7b/c. Flips `status` to `spent` when an
//     output is consumed.
//
// Concurrency: same per-instance lock pattern as RecipeStore. The
// SecureStore layer underneath is not multi-process safe; the shell
// is single-process so the per-instance lock is sufficient.

import 'dart:async';
import 'dart:convert';

import '../identity/child_cert_store.dart' show SecureStore;

/// SecureStore slot. Versioned so a future schema migration can land
/// without nuking the operator's tracked outputs.
const String _kUtxosKey = 'me.utxos.v1';

/// Lifecycle state of a UTXO row.
enum UtxoStatus {
  /// Address allocated, no on-chain output yet. The recipe-store
  /// `highWater` is bumped at allocation time; the row exists so a
  /// future address-scan can flip it to `confirmed` without losing
  /// the recipe ↔ derivation-index binding.
  watching,

  /// An output funding this address has been observed on-chain and
  /// the row's (txid, vout, value, scriptHex) are populated.
  confirmed,

  /// The output has been spent in a tx the wallet built. Kept on
  /// disk so recovery can recognise the consumed history rather than
  /// re-emitting the same key.
  spent,
}

/// Which derivation scheme produced the key behind this output.
/// Recovery scanner uses this to pick the right primitive when
/// regenerating signing keys.
enum DerivationModel {
  /// PR-C11-7a — output addressed to a key from `WalletKeyService.deriveReceive`
  /// (self-derived under the wallet's tier-0 + spend context). Funded
  /// externally (faucet, exchange withdraw, etc.).
  self,

  /// PR-C11-7b — output addressed via BRC-29 from a counterparty.
  /// The recipient's spending key is `deriveBrc29ChildSk(myIdSk,
  /// senderIdentityKey, derivationPrefix, derivationSuffix)`. Row
  /// MUST carry `senderIdentityKey`, `derivationPrefix`,
  /// `derivationSuffix`, and (once 7c+ wires it) a `beefHex` so the
  /// receive is SPV-verifiable.
  brc29Edge,
}

/// One UTXO row, as persisted and as exported into the recovery
/// envelope's optional `utxoManifestRef`. PR-C11-7a established the
/// core schema; PR-C11-7b grows the BEEF + BRC-29 remittance fields
/// as optional add-ons so existing 7a rows decode unchanged.
class UtxoRow {
  const UtxoRow({
    required this.address,
    required this.recipeId,
    required this.index,
    required this.status,
    required this.addedAtMs,
    required this.updatedAtMs,
    this.txid = '',
    this.vout = -1,
    this.value = 0,
    this.scriptHex = '',
    // PR-C11-7b additions ↓ — all default to "absent / unknown" so
    // 7a-shaped rows round-trip unchanged.
    this.beefHex = '',
    this.spvVerifiedAtMs,
    this.derivationModel = DerivationModel.self,
    this.senderIdentityKey = '',
    this.derivationPrefix = '',
    this.derivationSuffix = '',
  });

  /// 64-hex tx hash for the funding output. Empty until the address
  /// is funded.
  final String txid;

  /// Output index inside the funding tx. `-1` until funded.
  final int vout;

  /// Output value in satoshis. `0` until funded.
  final int value;

  /// Locking script as hex. Empty until funded.
  final String scriptHex;

  /// P2PKH base58check address. Populated at allocation time.
  final String address;

  /// Recipe-store id (e.g. `vault/0/spend/oddjobz/payout` for self
  /// outputs; `vault/0/peer/<counterpartyPubHex>` for BRC-29 edges
  /// in interim, or `vault/0/peer/<contactCertId>/<edgeId>` once
  /// PR-C11-8 lands the contacts layer).
  final String recipeId;

  /// BRC-42 derivation index inside [recipeId]. For self outputs:
  /// the index allocated by the recipe store. For BRC-29 edges:
  /// the `signingKeyIndex` on the contact's edge record.
  final int index;

  /// Lifecycle state.
  final UtxoStatus status;

  /// First-seen timestamp.
  final int addedAtMs;

  /// Last-state-change timestamp.
  final int updatedAtMs;

  // ─────────────── PR-C11-7b SPV + BRC-29 fields ───────────────

  /// BRC-95 Atomic BEEF for the funding tx + ancestors needed to
  /// SPV-verify the output. Required when [status] is `confirmed`
  /// AND the output came in via BRC-29 — otherwise the recipient
  /// has no proof the spending output is real.
  /// PR-C11-7c's BEEF validator reads this; the recovery scanner
  /// also needs it to rebuild after device wipe.
  final String beefHex;

  /// Wall-clock ms at which the BEEF was last validated against the
  /// header chain. Null if never validated. Set by 7c's validator.
  final int? spvVerifiedAtMs;

  /// Which derivation scheme produced this output's spending key.
  final DerivationModel derivationModel;

  /// BRC-29 sender identity pub (compressed hex). Empty for self
  /// outputs.
  final String senderIdentityKey;

  /// BRC-29 payment-wide prefix. Empty for self outputs.
  final String derivationPrefix;

  /// BRC-29 per-output suffix. Empty for self outputs.
  final String derivationSuffix;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'txid': txid,
      'vout': vout,
      'value': value,
      'scriptHex': scriptHex,
      'address': address,
      'recipeId': recipeId,
      'index': index,
      'status': status.name,
      'addedAtMs': addedAtMs,
      'updatedAtMs': updatedAtMs,
    };
    // Only emit 7b fields when they carry real data — keeps 7a-shaped
    // rows from gaining noise on disk. Decoder treats absent as
    // defaults.
    if (beefHex.isNotEmpty) m['beefHex'] = beefHex;
    if (spvVerifiedAtMs != null) m['spvVerifiedAtMs'] = spvVerifiedAtMs;
    if (derivationModel != DerivationModel.self) {
      m['derivationModel'] = derivationModel.name;
    }
    if (senderIdentityKey.isNotEmpty) {
      m['senderIdentityKey'] = senderIdentityKey;
    }
    if (derivationPrefix.isNotEmpty) {
      m['derivationPrefix'] = derivationPrefix;
    }
    if (derivationSuffix.isNotEmpty) {
      m['derivationSuffix'] = derivationSuffix;
    }
    return m;
  }

  static UtxoRow fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String;
    final status = UtxoStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => throw FormatException(
          'utxo-store: unknown status "$statusName"'),
    );
    final modelName = json['derivationModel'] as String?;
    final model = modelName == null
        ? DerivationModel.self
        : DerivationModel.values.firstWhere(
            (m) => m.name == modelName,
            orElse: () => throw FormatException(
                'utxo-store: unknown derivationModel "$modelName"'),
          );
    return UtxoRow(
      txid: (json['txid'] as String?) ?? '',
      vout: (json['vout'] as int?) ?? -1,
      value: (json['value'] as int?) ?? 0,
      scriptHex: (json['scriptHex'] as String?) ?? '',
      address: json['address'] as String,
      recipeId: json['recipeId'] as String,
      index: json['index'] as int,
      status: status,
      addedAtMs: json['addedAtMs'] as int,
      updatedAtMs: json['updatedAtMs'] as int,
      beefHex: (json['beefHex'] as String?) ?? '',
      spvVerifiedAtMs: json['spvVerifiedAtMs'] as int?,
      derivationModel: model,
      senderIdentityKey: (json['senderIdentityKey'] as String?) ?? '',
      derivationPrefix: (json['derivationPrefix'] as String?) ?? '',
      derivationSuffix: (json['derivationSuffix'] as String?) ?? '',
    );
  }

  UtxoRow copyWith({
    String? txid,
    int? vout,
    int? value,
    String? scriptHex,
    UtxoStatus? status,
    int? updatedAtMs,
    String? beefHex,
    int? spvVerifiedAtMs,
    DerivationModel? derivationModel,
    String? senderIdentityKey,
    String? derivationPrefix,
    String? derivationSuffix,
  }) =>
      UtxoRow(
        txid: txid ?? this.txid,
        vout: vout ?? this.vout,
        value: value ?? this.value,
        scriptHex: scriptHex ?? this.scriptHex,
        address: address,
        recipeId: recipeId,
        index: index,
        status: status ?? this.status,
        addedAtMs: addedAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        beefHex: beefHex ?? this.beefHex,
        spvVerifiedAtMs: spvVerifiedAtMs ?? this.spvVerifiedAtMs,
        derivationModel: derivationModel ?? this.derivationModel,
        senderIdentityKey: senderIdentityKey ?? this.senderIdentityKey,
        derivationPrefix: derivationPrefix ?? this.derivationPrefix,
        derivationSuffix: derivationSuffix ?? this.derivationSuffix,
      );

  /// Two rows for the same on-chain output are equal when txid+vout
  /// match (and both are non-empty). Watching rows are equal by
  /// (recipeId, index) since they have no on-chain anchor yet.
  bool sameOutputAs(UtxoRow other) {
    if (txid.isNotEmpty && other.txid.isNotEmpty) {
      return txid == other.txid && vout == other.vout;
    }
    return recipeId == other.recipeId && index == other.index;
  }
}

/// Per-instance lock to serialise read-modify-write cycles. Lifted
/// verbatim from `RecipeStore` for consistency.
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

/// SecureStore-backed UTXO log. CRUD-style; the funding source
/// (address scan, SPV walk, brain helper) wires in PR-C11-7c.
class UtxoStore {
  UtxoStore(this._store);

  final SecureStore _store;
  final _SerialLock _lock = _SerialLock();

  /// Read every row. Throws [FormatException] on corruption — callers
  /// can choose to nuke and rebuild from recipe-walk on recovery.
  Future<List<UtxoRow>> readAll() async {
    final raw = await _store.read(_kUtxosKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = json.decode(raw);
    if (decoded is! List) {
      throw FormatException(
          'utxo-store: expected JSON array at $_kUtxosKey');
    }
    return decoded
        .map((e) => UtxoRow.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Add a watching row. Idempotent — if a row with the same
  /// (recipeId, index) already exists, returns it unchanged.
  Future<UtxoRow> addWatching({
    required String address,
    required String recipeId,
    required int index,
  }) async {
    return _lock.run(() async {
      final rows = await _readAllUnlocked();
      final existing = rows
          .where((r) => r.recipeId == recipeId && r.index == index)
          .firstOrNull;
      if (existing != null) return existing;
      final now = DateTime.now().millisecondsSinceEpoch;
      final row = UtxoRow(
        address: address,
        recipeId: recipeId,
        index: index,
        status: UtxoStatus.watching,
        addedAtMs: now,
        updatedAtMs: now,
      );
      await _writeAllUnlocked([...rows, row]);
      return row;
    });
  }

  /// PR-C11-7c — flip a watching row to confirmed. No-op if the row
  /// isn't present. Returns the resulting row (or null if absent).
  Future<UtxoRow?> recordConfirmed({
    required String recipeId,
    required int index,
    required String txid,
    required int vout,
    required int value,
    required String scriptHex,
  }) async {
    return _lock.run(() async {
      final rows = await _readAllUnlocked();
      final idx = rows.indexWhere(
          (r) => r.recipeId == recipeId && r.index == index);
      if (idx < 0) return null;
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = rows[idx].copyWith(
        txid: txid,
        vout: vout,
        value: value,
        scriptHex: scriptHex,
        status: UtxoStatus.confirmed,
        updatedAtMs: now,
      );
      final next = [...rows]..[idx] = updated;
      await _writeAllUnlocked(next);
      return updated;
    });
  }

  /// PR-C11-7b/c — flip a confirmed row to spent. Matches by (txid,
  /// vout). Returns the resulting row (or null if absent).
  Future<UtxoRow?> markSpent({
    required String txid,
    required int vout,
  }) async {
    return _lock.run(() async {
      final rows = await _readAllUnlocked();
      final idx = rows.indexWhere((r) => r.txid == txid && r.vout == vout);
      if (idx < 0) return null;
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = rows[idx]
          .copyWith(status: UtxoStatus.spent, updatedAtMs: now);
      final next = [...rows]..[idx] = updated;
      await _writeAllUnlocked(next);
      return updated;
    });
  }

  /// Filter helper. Used by the renderer to populate the UTXOs panel
  /// and (in 7b/c) by the tx builder to pick spendable inputs.
  Future<List<UtxoRow>> rowsWhere(bool Function(UtxoRow) test) async {
    final rows = await readAll();
    return rows.where(test).toList(growable: false);
  }

  /// Wipe everything. Operator-initiated unpair only.
  Future<void> clear() async {
    await _lock.run(() async {
      await _store.delete(_kUtxosKey);
    });
  }

  // ─────────────── helpers ───────────────

  Future<List<UtxoRow>> _readAllUnlocked() async {
    final raw = await _store.read(_kUtxosKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = json.decode(raw);
    if (decoded is! List) {
      throw FormatException(
          'utxo-store: expected JSON array at $_kUtxosKey');
    }
    return decoded
        .map((e) => UtxoRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeAllUnlocked(List<UtxoRow> rows) async {
    final payload = json.encode(rows.map((r) => r.toJson()).toList());
    await _store.write(_kUtxosKey, payload);
  }
}

extension on Iterable<UtxoRow> {
  UtxoRow? get firstOrNull => isEmpty ? null : first;
}

```
