---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/plexus/challenge_bundle_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.113576+00:00
---

# apps/semantos/lib/src/plexus/challenge_bundle_store.dart

```dart
/// challenge_bundle_store.dart — persistent storage for the
/// ChallengeBundle (salted hashes of the operator's secret-question
/// answers).
///
/// C11 PR-C11-3. The wallet-headers reference at
/// `cartridges/wallet-headers/brain/src/popup-create.ts` keeps an
/// equivalent record in browser localStorage; on the canonical
/// Flutter shell we use the same `IdentityStore` seam that already
/// holds the brain URL + bearer (per the C7 wiring decision).
///
/// What gets persisted:
///   - questions[]
///   - 32-byte salt (hex)
///   - sha256(salt || normalize(answer))×N (hex)
///   - kdfIterations (pinned at 100k)
///   - createdAt (RFC3339 — useful for "questions last updated"
///     surfaces in the Me sheet)
///
/// What does NOT get persisted: raw answers, the PBKDF2-derived KEK,
/// the recovery seed. The store is read-only after first save except
/// for an explicit overwrite (the Me sheet's "Update" path); there is
/// no in-place answer edit because that would require re-hashing
/// without knowing the previous answers, which is impossible.
library;

import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:semantos_core/semantos_core.dart' show IdentityStore;

import 'envelope.dart' show ChallengeBundle, kPbkdf2Iterations;

/// Versioned storage key — bump if the JSON shape changes.
const String kChallengeBundleStoreKey = 'me.challenge_bundle.v1';

/// Wraps an [IdentityStore] with typed read/write of the ChallengeBundle
/// + a tiny metadata blob (createdAt).
class ChallengeBundleStore {
  final IdentityStore _store;

  const ChallengeBundleStore(this._store);

  /// True if a complete bundle is persisted. Cheap — just checks the
  /// slot is non-empty.
  Future<bool> isSet() async {
    final raw = await _store.read(kChallengeBundleStoreKey);
    return raw != null && raw.isNotEmpty;
  }

  /// Read the persisted bundle. Returns null if absent or malformed.
  /// Malformed records are NOT auto-cleared — a future migration PR
  /// can surface them.
  Future<StoredChallengeBundle?> read() async {
    final raw = await _store.read(kChallengeBundleStoreKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final questions = (json['questions'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[];
      final saltHex = json['salt'] as String? ?? '';
      final answerHashes = (json['answerHashes'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[];
      final iterations =
          (json['kdfIterations'] as int?) ?? kPbkdf2Iterations;
      final createdAt = json['createdAt'] as String? ?? '';
      // Minimal sanity — counts must match. Anything else is the
      // envelope build's problem; we just round-trip.
      if (questions.isEmpty ||
          questions.length != answerHashes.length ||
          saltHex.length != 64) {
        return null;
      }
      return StoredChallengeBundle(
        bundle: ChallengeBundle(
          questions: questions,
          saltHex: saltHex,
          answerHashes: answerHashes,
          kdfIterations: iterations,
        ),
        createdAt: createdAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// Persist a fresh bundle. Overwrites any existing record.
  /// Caller supplies the [createdAt] timestamp so this module stays
  /// pure (no `DateTime.now()`) and tests stay deterministic.
  Future<void> write(ChallengeBundle bundle, {required String createdAt}) {
    final payload = {
      'questions': bundle.questions,
      'salt': bundle.saltHex,
      'answerHashes': bundle.answerHashes,
      'kdfIterations': bundle.kdfIterations,
      'createdAt': createdAt,
    };
    return _store.write(kChallengeBundleStoreKey, jsonEncode(payload));
  }

  /// Clear the stored bundle — operator-initiated reset only. Never
  /// fires automatically; a missing bundle is a valid state ("no
  /// questions set yet").
  Future<void> clear() => _store.delete(kChallengeBundleStoreKey);
}

/// A bundle plus its createdAt timestamp — what [ChallengeBundleStore.read]
/// returns to the Me sheet.
class StoredChallengeBundle {
  final ChallengeBundle bundle;
  final String createdAt;
  const StoredChallengeBundle({required this.bundle, required this.createdAt});
}

```
