---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/identity/secure_signing_key.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.595830+00:00
---

# cartridges/jambox/mobile/lib/src/identity/secure_signing_key.dart

```dart
// D-O5m.followup-2 — Secure-signing-key adapter abstraction.
//
// Two implementations:
//   - PlatformSecureSigningKeyAdapter — wraps a MethodChannel that
//     dispatches to the native iOS Swift (Keychain-backed) or
//     Android Kotlin (EncryptedSharedPreferences-backed) handler.
//     The Flutter import is gated to a separate file —
//     platform_secure_signing_key_adapter.dart — so this module
//     stays import-free of `package:flutter` and the unit-test
//     suite continues to run under `dart test` without a Flutter
//     SDK gate.
//   - InMemorySecureSigningKeyAdapter — pure-Dart, used by tests
//     and (as a fallback) by any build where the native channel
//     isn't wired in.  Uses pointycastle's secp256k1 primitives
//     (the same ones cell_signer.dart uses, so the wire shape is
//     guaranteed to match).
//
// Honest scope reminder (mirrored from the native code):
//   secp256k1 is NOT supported by iOS Secure Enclave (NIST P-256
//   only) or AndroidKeyStore EC keys (NIST curves only), so the
//   priv DOES briefly enter process memory during sign operations
//   — both natively (Keychain → process memory → libsecp256k1) and
//   in this Dart fallback (priv passed as Uint8List to pointycastle).
//   The migration is a meaningful security improvement (at-rest
//   encryption + biometric gating + key revocation via handle
//   delete) but is NOT a true "key never leaves enclave"
//   implementation.
//
// Sister files:
//   - apps/oddjobz-mobile/ios/Runner/SecureSigningKey.swift
//   - apps/oddjobz-mobile/android/app/src/main/kotlin/.../SecureSigningKey.kt
//   - apps/oddjobz-mobile/lib/src/identity/platform_secure_signing_key_adapter.dart

import 'dart:math' as math;
import 'dart:typed_data';

import 'cell_signer.dart' show signCellPayload, devicePubFromPriv;

/// Material returned by [SecureSigningKeyAdapter.generateNew].  The
/// `keyHandle` is an opaque platform reference (Keychain account
/// name on iOS, EncryptedSharedPreferences key suffix on Android,
/// or in-memory map key for the InMemoryAdapter).  The `publicKey`
/// is the 33-byte compressed-SEC1 secp256k1 pub.
class SecureKeyMaterial {
  /// Opaque platform reference.  Stored in ChildCertStore alongside
  /// the existing certId/childPub.
  final String keyHandle;

  /// 33-byte compressed-SEC1 secp256k1 pub.
  final Uint8List publicKey;

  /// Wall-clock time when the key was generated, for audit logging.
  final DateTime generatedAt;

  const SecureKeyMaterial({
    required this.keyHandle,
    required this.publicKey,
    required this.generatedAt,
  });
}

/// Typed exceptions surfaced by the adapter.  The migration UI
/// pattern-matches on the type to render an operator-readable
/// message.
sealed class SecureSigningKeyException implements Exception {
  final String message;
  const SecureSigningKeyException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// The native channel reported `UNSUPPORTED` — typically because
/// secp256k1.swift / BouncyCastle wasn't compiled into the build.
class SecureSigningKeyUnsupported extends SecureSigningKeyException {
  const SecureSigningKeyUnsupported(super.message);
}

/// The native channel reported `KEY_NOT_FOUND` — the keyHandle
/// doesn't refer to a stored key.  Often indicates a stale handle
/// after a Keychain/Keystore reset (e.g. factory restore).
class SecureSigningKeyNotFound extends SecureSigningKeyException {
  const SecureSigningKeyNotFound(super.message);
}

/// Generate / sign / delete returned an error.  Carries the native
/// error code for log triage.
class SecureSigningKeyError extends SecureSigningKeyException {
  /// One of the native ErrorCode tags
  /// (GENERATE_FAILED / SIGN_FAILED / DELETE_FAILED).
  final String code;
  const SecureSigningKeyError(this.code, String message) : super(message);
}

/// Adapter contract.  Implementations:
///   - `PlatformSecureSigningKeyAdapter` (production iOS/Android,
///     in `platform_secure_signing_key_adapter.dart`).
///   - `InMemorySecureSigningKeyAdapter` (tests + Dart fallback,
///     defined below).
abstract class SecureSigningKeyAdapter {
  /// Generate a new key inside the platform secure store.  Returns
  /// the keyHandle + 33-byte compressed pub.  The priv bytes are
  /// written to the native store and never returned.
  Future<SecureKeyMaterial> generateNew({required String label});

  /// Sign `message` with the priv at `keyHandle`.  Returns 64 raw
  /// bytes (r || s, low-s normalised) — same wire shape as
  /// `cell_signer.dart::signCellPayload`.
  Future<Uint8List> sign({
    required String keyHandle,
    required Uint8List message,
  });

  /// Remove the key at `keyHandle` from the secure store.
  /// Idempotent: no-op if the handle is unknown.
  Future<void> delete({required String keyHandle});

  /// True if a key is stored at `keyHandle`.  Cheap on iOS (does
  /// NOT trigger the biometric prompt) and Android (does NOT
  /// require the master key to be unlocked).
  Future<bool> exists({required String keyHandle});
}

/// Pure-Dart adapter — used by the unit-test suite (no Flutter SDK
/// gate) and as a fallback for builds where the native channel
/// isn't wired in.  Uses pointycastle's secp256k1 primitives via
/// the existing `cell_signer.dart::signCellPayload` so the wire
/// bytes are guaranteed byte-identical to a Dart raw-priv signature
/// over the same message.
///
/// Stores priv bytes in a Map keyed by handle — obviously NOT
/// secure for production use; the production seam is
/// `PlatformSecureSigningKeyAdapter`.
class InMemorySecureSigningKeyAdapter implements SecureSigningKeyAdapter {
  final Map<String, Uint8List> _privByHandle = {};
  final Map<String, String> _labelByHandle = {};
  final Map<String, DateTime> _generatedAtByHandle = {};
  int _seq = 0;

  /// Optional pinned generator so tests can produce deterministic
  /// privs.  Production builds never hit this; the InMemoryAdapter
  /// exists for tests + as a degraded fallback when the native
  /// channel isn't wired in.
  final Uint8List Function() _genPriv;

  /// Optional pinned clock so tests can pin `generatedAt`.
  final DateTime Function() _now;

  /// `seedHandles`: pre-loaded handle → priv mappings, used by the
  /// migration test to assert that an existing legacy raw-priv
  /// record can be re-keyed atomically into the secure adapter
  /// without leaking the priv back to Dart.
  InMemorySecureSigningKeyAdapter({
    Uint8List Function()? generatePriv,
    DateTime Function()? now,
    Map<String, Uint8List>? seedHandles,
  })  : _genPriv = generatePriv ?? _defaultGenPriv,
        _now = now ?? DateTime.now {
    if (seedHandles != null) {
      _privByHandle.addAll(seedHandles);
      for (final h in seedHandles.keys) {
        _labelByHandle[h] = '<seeded>';
        _generatedAtByHandle[h] = _now();
      }
    }
  }

  @override
  Future<SecureKeyMaterial> generateNew({required String label}) async {
    _seq++;
    final handle =
        'in-memory-handle-$_seq-${_now().microsecondsSinceEpoch}';
    final priv = _genPriv();
    _privByHandle[handle] = priv;
    _labelByHandle[handle] = label;
    final at = _now();
    _generatedAtByHandle[handle] = at;
    final pub = devicePubFromPriv(priv);
    return SecureKeyMaterial(
      keyHandle: handle,
      publicKey: pub,
      generatedAt: at,
    );
  }

  @override
  Future<Uint8List> sign({
    required String keyHandle,
    required Uint8List message,
  }) async {
    final priv = _privByHandle[keyHandle];
    if (priv == null) {
      throw const SecureSigningKeyNotFound(
          'no key stored at the requested handle (in-memory adapter)');
    }
    return signCellPayload(message, priv);
  }

  @override
  Future<void> delete({required String keyHandle}) async {
    _privByHandle.remove(keyHandle);
    _labelByHandle.remove(keyHandle);
    _generatedAtByHandle.remove(keyHandle);
  }

  @override
  Future<bool> exists({required String keyHandle}) async {
    return _privByHandle.containsKey(keyHandle);
  }

  /// Test-only: read back the label associated with `keyHandle`.
  /// Production code should not depend on this — the label is
  /// supplied at generation time and not used by the runtime sign
  /// path.
  String? testReadLabel(String keyHandle) => _labelByHandle[keyHandle];

  /// Test-only: produce a 33-byte compressed pub for an arbitrary
  /// handle.  Used by the migration tests to assert the pub
  /// corresponds to the priv that was seeded into the adapter.
  Uint8List? testReadPubKey(String keyHandle) {
    final priv = _privByHandle[keyHandle];
    if (priv == null) return null;
    return devicePubFromPriv(priv);
  }
}

/// Default priv generator for the InMemoryAdapter.  Uses
/// dart:math's Random.secure() (OS-CSPRNG-backed on every
/// platform) and rejection-samples until the result lies in
/// (0, n) where n is secp256k1's curve order.
Uint8List _defaultGenPriv() {
  final rng = math.Random.secure();
  while (true) {
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = rng.nextInt(256);
    }
    final n = _bytesToBigInt(out);
    if (n > BigInt.zero && n < _secp256k1N) {
      return out;
    }
  }
}

final BigInt _secp256k1N = BigInt.parse(
    'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
    radix: 16);

BigInt _bytesToBigInt(List<int> bytes) {
  var n = BigInt.zero;
  for (final b in bytes) {
    n = (n << 8) | BigInt.from(b & 0xff);
  }
  return n;
}

```
