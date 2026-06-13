---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/cert_body_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.107484+00:00
---

# apps/semantos/lib/src/wallet/cert_body_store.dart

```dart
// C11 PR-C11-4c — Cert body custody for the wallet renderer.
//
// Reference: docs/design/PLEXUS-ALIGNMENT.md §10.C — "flutter secure
// storage, but it needs to go through the storage adapter so it can
// be anywhere"; docs/design/WALLET-RENDERER-CONTRACT.md §5 (Dart
// responsibilities).
//
// The cert_body is the 32-byte secp256k1 private key behind the root
// identity cert. It is the secret that the secret-question recovery
// envelope (PR-C11-3) wraps via PBKDF2 + AES-256-GCM. At runtime the
// shell holds it in flutter_secure_storage, keyed by cert_id so a
// future multi-identity flow doesn't have to migrate slot names.
//
// Why hex (not raw bytes):
//   The SecureStore abstraction in `child_cert_store.dart` is
//   `String → String`. We hex-encode the priv so storage stays in
//   that shape. Decode at read time.
//
// Storage slot layout:
//   me.cert_body.v1.${certIdHex}    — 64-hex priv bytes
//
// We do NOT enumerate active cert_ids here — the contract for 4c is
// single-identity. PR-C11-6 (brain envelope cell) is where the
// schema grows to track multiple identities; this store is forward-
// compatible because the slot key is parameterised on cert_id.

import 'dart:typed_data';

import '../identity/child_cert_store.dart' show SecureStore;

/// SecureStore slot key prefix for cert bodies. Versioned so a
/// future format rev can co-exist during migration.
const String _kCertBodyPrefix = 'me.cert_body.v1.';

/// Length of the cert_body in bytes (secp256k1 private key).
const int kCertBodyLength = 32;

/// Owns cert_body custody on top of an arbitrary [SecureStore]. Each
/// instance is bound to a specific [certIdHex] so callers can't
/// accidentally read/write across identities.
class CertBodyStore {
  CertBodyStore({
    required this.certIdHex,
    required SecureStore store,
  })  : _store = store {
    _assertCertIdHex(certIdHex);
  }

  /// Hex-encoded cert id. 32 hex chars (16 bytes truncated SHA-256
  /// per the cell-header `ownerId` field). Validated at construction.
  final String certIdHex;

  final SecureStore _store;

  /// SecureStore key this store writes to. Exposed for diagnostics.
  String get storageKey => '$_kCertBodyPrefix$certIdHex';

  /// Returns true if a cert_body is currently stored for this identity.
  Future<bool> isPresent() async {
    final hex = await _store.read(storageKey);
    return hex != null && hex.length == kCertBodyLength * 2;
  }

  /// Read the cert_body. Returns null if absent.
  ///
  /// The returned bytes are a fresh copy; callers may zero them out
  /// after use. The internal SecureStore layer's reads still pass
  /// through Dart `String`, so cleartext lives in the immutable
  /// string heap until GC reclaims it. Treat returned bytes as
  /// best-effort sensitive, not enclave-grade.
  Future<Uint8List?> read() async {
    final hex = await _store.read(storageKey);
    if (hex == null) return null;
    return _decodeHex(hex);
  }

  /// Persist the cert_body. Length-checked; throws on mismatch.
  Future<void> write(Uint8List certBody) async {
    if (certBody.length != kCertBodyLength) {
      throw ArgumentError.value(certBody.length, 'certBody.length',
          'must be $kCertBodyLength bytes');
    }
    await _store.write(storageKey, _encodeHex(certBody));
  }

  /// Wipe the cert_body for this identity. Used on operator-initiated
  /// unpair + recovery-replace flows.
  Future<void> clear() async {
    await _store.delete(storageKey);
  }

  // ─────────────── helpers ───────────────

  static void _assertCertIdHex(String value) {
    if (value.length != 32) {
      throw ArgumentError.value(
          value.length, 'certIdHex.length', 'must be 32 hex chars');
    }
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      final ok = (c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x66) ||
          (c >= 0x41 && c <= 0x46);
      if (!ok) {
        throw ArgumentError.value(value, 'certIdHex',
            'must be hex (0-9 / a-f / A-F) at index $i');
      }
    }
  }

  static Uint8List _decodeHex(String hex) {
    if (hex.length.isOdd) {
      throw ArgumentError.value(hex.length, 'hex.length', 'must be even');
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _encodeHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

```
