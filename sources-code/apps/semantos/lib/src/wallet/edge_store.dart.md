---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/edge_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.105804+00:00
---

# apps/semantos/lib/src/wallet/edge_store.dart

```dart
// PWA contacts-PKI — local store of bilateral edge envelopes.
//
// Dart mirror of `cartridges/wallet-headers/brain/src/local-edge-store.ts`.
// An "edge" is a one-to-one cryptographic relationship with a peer:
// after accepting their invite, the wallet holds a [LocalEdgeEnvelope]
// recording who the peer is, which BKDS signing-key index the edge is
// at, and a BRC-69 backup recipe that proves the edge existed without
// revealing the ECDH shared secret.
//
// Storage shape (one slot, JSON array of envelope rows):
//
//   me.edges.v1   →   [ LocalEdgeEnvelope, ... ]
//
// The envelope schema is BYTE-COMPATIBLE with the brain's
// `LocalEdgeEnvelope` (same field names, same `edgeId` / `backupRecipe`
// derivation in `edge_invite.dart`) so an edge minted in the PWA and
// one minted in the brain are interchangeable — the cross-language KAT
// in `test/wallet/edge_kat_test.dart` pins that.
//
// Like the recipe store, the edge log is append-only at the edge level:
// you don't delete an edge once it's been used for a rotated payment
// (spending keys exist on-chain and recovery still needs the recipe to
// find them). `clear()` exists for the operator-initiated unpair path.

import 'dart:async';
import 'dart:convert';

import '../identity/child_cert_store.dart' show SecureStore;

/// SecureStore slot for the edge log. Versioned for future schema
/// migrations. (The brain uses the localStorage key
/// `wallet:edge-envelopes`; the PWA follows the shell's `me.*`
/// convention — the slot name is local-only and does not affect
/// cross-language interop, which is fixed by the envelope contents.)
const String kEdgeStoreSlot = 'me.edges.v1';

/// Default edge kind for a freshly accepted invite. Matches the brain's
/// `acceptInvite` default.
const String kEdgeTypeMessaging = 'MESSAGING';

/// A bilateral edge recipe stored locally.
///
/// Field names + semantics mirror the brain's `LocalEdgeEnvelope`
/// (`local-edge-store.ts`) exactly so the JSON round-trips across the
/// two implementations.
class LocalEdgeEnvelope {
  const LocalEdgeEnvelope({
    required this.edgeId,
    required this.myCertId,
    required this.theirCertId,
    required this.theirPublicKey,
    required this.signingKeyIndex,
    required this.edgeType,
    required this.backupRecipe,
    required this.createdAt,
  });

  /// SHA-256(myCertId ‖ theirCertId ‖ nonce) hex — deterministic edge id.
  final String edgeId;

  /// My root cert id (hex).
  final String myCertId;

  /// The peer's root cert id (hex).
  final String theirCertId;

  /// The peer's 33-byte compressed secp256k1 pubkey (hex).
  final String theirPublicKey;

  /// BKDS monotonic index the edge is currently at.
  final int signingKeyIndex;

  /// Edge kind (e.g. `MESSAGING`).
  final String edgeType;

  /// BRC-69 revelation recipe: hex HMAC that proves the edge existed
  /// without revealing the ECDH shared secret.
  final String backupRecipe;

  /// Creation timestamp (unix ms).
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'edgeId': edgeId,
        'myCertId': myCertId,
        'theirCertId': theirCertId,
        'theirPublicKey': theirPublicKey,
        'signingKeyIndex': signingKeyIndex,
        'edgeType': edgeType,
        'backupRecipe': backupRecipe,
        'createdAt': createdAt,
      };

  static LocalEdgeEnvelope fromJson(Map<String, dynamic> json) {
    return LocalEdgeEnvelope(
      edgeId: json['edgeId'] as String,
      myCertId: json['myCertId'] as String,
      theirCertId: json['theirCertId'] as String,
      theirPublicKey: json['theirPublicKey'] as String,
      signingKeyIndex: json['signingKeyIndex'] as int,
      edgeType: json['edgeType'] as String,
      backupRecipe: json['backupRecipe'] as String,
      createdAt: json['createdAt'] as int,
    );
  }

  LocalEdgeEnvelope withSigningKeyIndex(int next) => LocalEdgeEnvelope(
        edgeId: edgeId,
        myCertId: myCertId,
        theirCertId: theirCertId,
        theirPublicKey: theirPublicKey,
        signingKeyIndex: next,
        edgeType: edgeType,
        backupRecipe: backupRecipe,
        createdAt: createdAt,
      );
}

/// Per-instance lock serialising read-modify-write cycles, so two
/// concurrent `save`/`advance` calls can't clobber each other. Same
/// pattern as `RecipeStore._SerialLock`.
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

/// Append-or-replace log of edge envelopes over a [SecureStore].
class EdgeStore {
  EdgeStore(this._store);

  final SecureStore _store;
  final _SerialLock _lock = _SerialLock();

  /// Read every stored edge. Empty list when the slot is absent.
  /// Throws [FormatException] on corruption.
  Future<List<LocalEdgeEnvelope>> loadAll() async {
    final raw = await _store.read(kEdgeStoreSlot);
    return _decode(raw);
  }

  /// Persist [env], replacing any existing row with the same `edgeId`
  /// or appending if new. Idempotent for re-accept of the same invite.
  Future<void> save(LocalEdgeEnvelope env) async {
    await _lock.run(() async {
      final envelopes = _decode(await _store.read(kEdgeStoreSlot)).toList();
      final idx = envelopes.indexWhere((e) => e.edgeId == env.edgeId);
      if (idx >= 0) {
        envelopes[idx] = env;
      } else {
        envelopes.add(env);
      }
      await _writeAll(envelopes);
    });
  }

  /// Fetch a single edge by id, or null.
  Future<LocalEdgeEnvelope?> get(String edgeId) async {
    final envelopes = _decode(await _store.read(kEdgeStoreSlot));
    for (final e in envelopes) {
      if (e.edgeId == edgeId) return e;
    }
    return null;
  }

  /// Advance the BKDS signing-key index for an edge after a successful
  /// rotated payment. No-op if the edge is unknown.
  Future<void> advanceIndex(String edgeId) async {
    await _lock.run(() async {
      final envelopes = _decode(await _store.read(kEdgeStoreSlot)).toList();
      final idx = envelopes.indexWhere((e) => e.edgeId == edgeId);
      if (idx < 0) return;
      envelopes[idx] =
          envelopes[idx].withSigningKeyIndex(envelopes[idx].signingKeyIndex + 1);
      await _writeAll(envelopes);
    });
  }

  /// Most recent active edge to [theirCertId] (highest `createdAt`), or
  /// null when there is none.
  Future<LocalEdgeEnvelope?> findEdgeTo(String theirCertId) async {
    final envelopes = _decode(await _store.read(kEdgeStoreSlot))
        .where((e) => e.theirCertId == theirCertId)
        .toList();
    if (envelopes.isEmpty) return null;
    return envelopes
        .reduce((best, cur) => cur.createdAt > best.createdAt ? cur : best);
  }

  /// Wipe the edge log. Operator-initiated unpair only.
  Future<void> clear() async {
    await _lock.run(() async {
      await _store.delete(kEdgeStoreSlot);
    });
  }

  // ─────────────── helpers ───────────────

  List<LocalEdgeEnvelope> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final decoded = json.decode(raw);
    if (decoded is! List) {
      throw FormatException('edge-store: expected JSON array at $kEdgeStoreSlot');
    }
    return decoded
        .map((e) => LocalEdgeEnvelope.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeAll(List<LocalEdgeEnvelope> envelopes) async {
    final payload = json.encode(envelopes.map((e) => e.toJson()).toList());
    await _store.write(kEdgeStoreSlot, payload);
  }
}

```
