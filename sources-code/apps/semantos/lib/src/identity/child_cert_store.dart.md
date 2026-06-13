---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/identity/child_cert_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.112273+00:00
---

# apps/semantos/lib/src/identity/child_cert_store.dart

```dart
// D-O5m — Persist + retrieve the device's BRC-42 child cert + brain
// endpoints + bearer token.
//
// In production iOS Keychain / Android Keystore via
// flutter_secure_storage; tests inject the in-memory variant. The
// secure-storage abstraction is keyed by string slot names (no
// `/path` semantics) and per-platform binds to the platform's
// secure-enclave-backed primitive.
//
// What we persist:
//   - device_priv_hex     : the device's identity priv (32 bytes hex).
//                            LEGACY storage path.  D-O5m.followup-2
//                            adds an alternate `secure_key_handle`
//                            field — when present, the priv lives in
//                            iOS Keychain / Android EncryptedSharedPrefs
//                            (with biometric gating + at-rest
//                            encryption) and `device_priv_hex` is
//                            absent.  Both shapes are supported for
//                            backward compatibility — the
//                            operator-initiated migration in the
//                            Settings screen rewrites a legacy record
//                            into a secure-key record.
//   - secure_key_handle   : opaque platform reference produced by
//                            the `SecureSigningKeyAdapter`.  Mutually
//                            exclusive with `device_priv_hex` for
//                            new pairings; legacy records have
//                            `device_priv_hex` only.
//   - child_pub_hex       : the BRC-42 child pub (audit identifier).
//   - operator_root_pub   : the operator's root pub (for re-derivation
//                            checks).
//   - operator_cert_id    : the operator's root cert id (32 hex).
//   - context_tag         : stored as decimal string.
//   - label               : the operator-supplied device label.
//   - capabilities        : JSON-encoded array.
//   - brain_pair_endpoint : the operator's brain HTTPS endpoint.
//   - brain_wss_endpoint  : the operator's brain WSS endpoint.
//   - brain_pin_cert_id   : pinned cert id (currently == operator_cert_id).
//   - brain_pin_pubkey    : pinned pubkey (currently == operator_root_pub).
//   - bearer              : 64-hex bearer token issued by the brain on
//                            successful pairing (gates POST /api/v1/repl).

import 'dart:convert';

/// Abstract storage seam — production uses
/// `FlutterSecureStoreAdapter` (in `flutter_secure_store_adapter.dart`,
/// which imports flutter_secure_storage) wired up at app boot in
/// `main.dart`. Tests inject `InMemorySecureStore` so the unit-test
/// suite runs under pure `dart test` (no Flutter SDK required).
///
/// The seam is intentionally kept import-clean of any Flutter package
/// imports — keep all flutter-secure-storage references behind the
/// adapter file so this module compiles standalone.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
  Future<Map<String, String>> readAll();
}

/// In-memory SecureStore — used by tests so we don't need a Flutter
/// MethodChannel + platform binary at unit-test time.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }

  @override
  Future<Map<String, String>> readAll() async => Map.from(_data);
}

/// Snapshot of the persisted child-cert state. Returned by
/// [ChildCertStore.read] for downstream surfaces (the helm REPL
/// client, the outbox flush handler) to compose with.
class ChildCertRecord {
  /// 64 hex chars — the device's identity priv.
  ///
  /// LEGACY field.  Empty string when the record uses the
  /// secure-key-handle path (D-O5m.followup-2).  Mutually exclusive
  /// with [secureKeyHandle] for new pairings.  Read sites that
  /// branch on the storage path use [usesSecureKeyHandle] —
  /// callers signing cells should consult that flag and route
  /// through `CellSigner` with the adapter when it's true.
  final String devicePrivHex;

  /// D-O5m.followup-2 — opaque platform reference for the
  /// Keychain/Keystore-backed signing key.  Empty string for
  /// legacy records that hold the priv as raw hex in
  /// [devicePrivHex].
  final String secureKeyHandle;

  /// 66 hex chars — the BRC-42 child pub (audit identifier).
  final String childPubHex;

  /// 66 hex chars — operator's root pub.
  final String operatorRootPub;

  /// 32 hex chars — operator's root cert id.
  final String operatorCertId;

  /// u8 — per-device contextTag for K3 isolation (spec v0.5 §4.4).
  final int contextTag;

  /// Operator-supplied label.
  final String label;

  /// Capability allowlist (e.g. ["cap.attach.photo", ...]).
  final List<String> capabilities;

  /// Production HTTPS endpoint the device POSTs cells to (and that
  /// the helm REPL bearer-gated calls hit at `/api/v1/repl`).
  final String brainPairEndpoint;

  /// Post-pair operations WSS endpoint.
  final String brainWssEndpoint;

  /// Pinned cert id — currently == operatorCertId.
  final String brainPinCertId;

  /// Pinned pubkey — currently == operatorRootPub.
  final String brainPinPubkey;

  /// 64-hex bearer token issued by the brain on successful pairing.
  /// Gates `POST /api/v1/repl`.
  final String bearer;

  const ChildCertRecord({
    required this.devicePrivHex,
    required this.childPubHex,
    required this.operatorRootPub,
    required this.operatorCertId,
    required this.contextTag,
    required this.label,
    required this.capabilities,
    required this.brainPairEndpoint,
    required this.brainWssEndpoint,
    required this.brainPinCertId,
    required this.brainPinPubkey,
    required this.bearer,
    this.secureKeyHandle = '',
  });

  /// True when the record's signing key lives in the platform
  /// secure store (Keychain/Keystore) rather than as raw hex.
  /// Cell signing call sites consult this to decide whether to
  /// route through `CellSigner` with the SecureSigningKeyAdapter
  /// or fall through to the legacy `signCellPayload(..., privBytes)`
  /// path.
  bool get usesSecureKeyHandle => secureKeyHandle.isNotEmpty;

  /// Construct a copy of this record with the supplied fields
  /// overridden.  Used by the migration flow to produce a fresh
  /// record with the new secureKeyHandle + an empty devicePrivHex.
  ChildCertRecord copyWith({
    String? devicePrivHex,
    String? secureKeyHandle,
    String? childPubHex,
    String? bearer,
  }) {
    return ChildCertRecord(
      devicePrivHex: devicePrivHex ?? this.devicePrivHex,
      secureKeyHandle: secureKeyHandle ?? this.secureKeyHandle,
      childPubHex: childPubHex ?? this.childPubHex,
      operatorRootPub: operatorRootPub,
      operatorCertId: operatorCertId,
      contextTag: contextTag,
      label: label,
      capabilities: capabilities,
      brainPairEndpoint: brainPairEndpoint,
      brainWssEndpoint: brainWssEndpoint,
      brainPinCertId: brainPinCertId,
      brainPinPubkey: brainPinPubkey,
      bearer: bearer ?? this.bearer,
    );
  }
}

/// Storage slot keys. Kept private + namespaced so the
/// FlutterSecureStorage shared keychain doesn't collide with
/// other apps' slots. Versioned to allow zero-downtime migration on a
/// future schema rev.
class _Keys {
  static const devicePrivHex = 'd-o5m.v1.device_priv_hex';
  static const childPubHex = 'd-o5m.v1.child_pub_hex';
  static const operatorRootPub = 'd-o5m.v1.operator_root_pub';
  static const operatorCertId = 'd-o5m.v1.operator_cert_id';
  static const contextTag = 'd-o5m.v1.context_tag';
  static const label = 'd-o5m.v1.label';
  static const capabilities = 'd-o5m.v1.capabilities';
  static const brainPairEndpoint = 'd-o5m.v1.brain_pair_endpoint';
  static const brainWssEndpoint = 'd-o5m.v1.brain_wss_endpoint';
  static const brainPinCertId = 'd-o5m.v1.brain_pin_cert_id';
  static const brainPinPubkey = 'd-o5m.v1.brain_pin_pubkey';
  static const bearer = 'd-o5m.v1.bearer';
  // D-O5m.followup-2 — opaque secure-key handle.  Co-exists with
  // `device_priv_hex` for backward compatibility; new pairings have
  // only this field set.
  static const secureKeyHandle = 'd-o5m.v1.secure_key_handle';

  static const allKeys = [
    devicePrivHex,
    childPubHex,
    operatorRootPub,
    operatorCertId,
    contextTag,
    label,
    capabilities,
    brainPairEndpoint,
    brainWssEndpoint,
    brainPinCertId,
    brainPinPubkey,
    bearer,
    secureKeyHandle,
  ];
}

/// Owns the persisted child-cert + brain-endpoint + bearer state.
/// Implements the canonical `child-cert-custody` surface.
class ChildCertStore {
  final SecureStore _store;

  ChildCertStore(this._store);

  /// True if a complete record is persisted (full pairing has
  /// completed). Cheap — does not deserialise the full record.
  ///
  /// A pairing is considered complete when the bearer is set AND
  /// the record holds a signing-key reference (either the legacy
  /// `device_priv_hex` or the D-O5m.followup-2 `secure_key_handle`).
  Future<bool> isPaired() async {
    final bearer = await _store.read(_Keys.bearer);
    if (bearer == null || bearer.isEmpty) return false;
    final priv = await _store.read(_Keys.devicePrivHex);
    final secureHandle = await _store.read(_Keys.secureKeyHandle);
    final hasPriv = priv != null && priv.isNotEmpty;
    final hasSecureHandle = secureHandle != null && secureHandle.isNotEmpty;
    return hasPriv || hasSecureHandle;
  }

  /// Read the full record, or null if not yet paired.
  Future<ChildCertRecord?> read() async {
    final bearer = await _store.read(_Keys.bearer);
    if (bearer == null || bearer.isEmpty) return null;
    final devicePrivHex = await _store.read(_Keys.devicePrivHex);
    final secureKeyHandle = await _store.read(_Keys.secureKeyHandle);
    final childPubHex = await _store.read(_Keys.childPubHex);
    final operatorRootPub = await _store.read(_Keys.operatorRootPub);
    final operatorCertId = await _store.read(_Keys.operatorCertId);
    final contextTagRaw = await _store.read(_Keys.contextTag);
    final label = await _store.read(_Keys.label);
    final capsRaw = await _store.read(_Keys.capabilities);
    final brainPairEndpoint = await _store.read(_Keys.brainPairEndpoint);
    final brainWssEndpoint = await _store.read(_Keys.brainWssEndpoint);
    final brainPinCertId = await _store.read(_Keys.brainPinCertId);
    final brainPinPubkey = await _store.read(_Keys.brainPinPubkey);
    // For backward compat, treat a missing devicePrivHex as a record
    // that's using the secure-key path: the secureKeyHandle slot
    // must be present.  A record with neither is a partial-pairing
    // and is treated as unpaired.
    final hasPriv = devicePrivHex != null && devicePrivHex.isNotEmpty;
    final hasSecureHandle =
        secureKeyHandle != null && secureKeyHandle.isNotEmpty;
    if ((!hasPriv && !hasSecureHandle) ||
        childPubHex == null ||
        operatorRootPub == null ||
        operatorCertId == null ||
        contextTagRaw == null ||
        label == null ||
        capsRaw == null ||
        brainPairEndpoint == null ||
        brainWssEndpoint == null ||
        brainPinCertId == null ||
        brainPinPubkey == null) {
      // Partial record — treat as unpaired. A future rev (D-O5m.followup-3)
      // could surface a "stuck-mid-pair" recovery UI; for the MVP we
      // just return null.
      return null;
    }
    final caps =
        (json.decode(capsRaw) as List).map((e) => e as String).toList();
    return ChildCertRecord(
      devicePrivHex: hasPriv ? devicePrivHex : '',
      secureKeyHandle: hasSecureHandle ? secureKeyHandle : '',
      childPubHex: childPubHex,
      operatorRootPub: operatorRootPub,
      operatorCertId: operatorCertId,
      contextTag: int.parse(contextTagRaw),
      label: label,
      capabilities: caps,
      brainPairEndpoint: brainPairEndpoint,
      brainWssEndpoint: brainWssEndpoint,
      brainPinCertId: brainPinCertId,
      brainPinPubkey: brainPinPubkey,
      bearer: bearer,
    );
  }

  /// Persist a full record. Called by the pairing service on
  /// successful brain-side accept.
  ///
  /// Writes both `device_priv_hex` and `secure_key_handle`; either
  /// (but not both at once for new pairings) may be the empty
  /// string.  The migration flow writes a record with `priv=''`
  /// and `secureKeyHandle=<handle>`; the same write() path handles
  /// both shapes uniformly.
  Future<void> write(ChildCertRecord record) async {
    await _store.write(_Keys.devicePrivHex, record.devicePrivHex);
    await _store.write(_Keys.secureKeyHandle, record.secureKeyHandle);
    await _store.write(_Keys.childPubHex, record.childPubHex);
    await _store.write(_Keys.operatorRootPub, record.operatorRootPub);
    await _store.write(_Keys.operatorCertId, record.operatorCertId);
    await _store.write(_Keys.contextTag, record.contextTag.toString());
    await _store.write(_Keys.label, record.label);
    await _store.write(
        _Keys.capabilities, json.encode(record.capabilities));
    await _store.write(_Keys.brainPairEndpoint, record.brainPairEndpoint);
    await _store.write(_Keys.brainWssEndpoint, record.brainWssEndpoint);
    await _store.write(_Keys.brainPinCertId, record.brainPinCertId);
    await _store.write(_Keys.brainPinPubkey, record.brainPinPubkey);
    await _store.write(_Keys.bearer, record.bearer);
  }

  /// Update just the bearer (rotation case). The brain may rotate the
  /// bearer on a session refresh; the rest of the record stays
  /// pinned to the original pairing.
  Future<void> updateBearer(String bearer) async {
    await _store.write(_Keys.bearer, bearer);
  }

  /// Wipe the full record — called on operator-initiated unpair or
  /// on a 401-after-cert-revoke from the brain.
  Future<void> clear() async {
    for (final key in _Keys.allKeys) {
      await _store.delete(key);
    }
  }
}

```
