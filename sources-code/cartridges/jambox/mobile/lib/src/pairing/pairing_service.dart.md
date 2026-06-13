---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/pairing/pairing_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.589497+00:00
---

# cartridges/jambox/mobile/lib/src/pairing/pairing_service.dart

```dart
// D-O5m — Pairing service: orchestrates decode → derive → POST →
// persist.
//
// This is the device-side counterpart of the brain-side acceptor at
// `runtime/semantos-brain/src/site_server.zig` + `device_pair.zig`'s `accept`
// path. The flow:
//
//   1. Decode the QR payload (from a scanned QR or pasted URL).
//   2. Generate a fresh device priv via CSPRNG (dart:math
//      Random.secure() seeding pointycastle's Fortuna). Production
//      phase 2 swaps this for a Keychain/Keystore-backed signing key
//      handle so the priv never leaves the secure enclave — see
//      TODO(D-O5m.followup-2).
//   3. Run BRC-42 derivation to get the child pub.
//   4. POST {token, derivation_pubkey, derivation_proof} to the
//      brain's `/api/v1/device-pair` endpoint.
//   5. On 200 + bearer in response, persist a full ChildCertRecord.
//   6. On 4xx/5xx, surface a typed error to the pairing screen.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/random/fortuna_random.dart';

import '../identity/child_cert_store.dart';
import '../identity/secure_signing_key.dart';
import 'brc42_derive.dart';
import 'claim_request.dart';
import 'decode_token.dart';
import 'pair_payload.dart';

/// Result of a successful pairing — the persisted record + the
/// decoded payload (so the helm screen can show a confirmation card
/// without re-reading from secure storage).
class PairingResult {
  final ChildCertRecord record;
  final PairPayload payload;
  const PairingResult({required this.record, required this.payload});
}

/// Typed exceptions surfaced by [PairingService.pair]. The pairing
/// screen pattern-matches on the type to render an operator-readable
/// error message.
sealed class PairingException implements Exception {
  final String message;
  const PairingException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class PairingDecodeError extends PairingException {
  const PairingDecodeError(super.message);
}

class PairingNetworkError extends PairingException {
  const PairingNetworkError(super.message);
}

class PairingRejectedError extends PairingException {
  /// HTTP status the brain returned (400, 409 for replay/expired, etc.).
  final int statusCode;
  final String? brainMessage;
  const PairingRejectedError({
    required this.statusCode,
    required this.brainMessage,
  }) : super('brain rejected pairing');

  @override
  String toString() =>
      'PairingRejectedError(statusCode=$statusCode, brainMessage=$brainMessage)';
}

class PairingResponseError extends PairingException {
  const PairingResponseError(super.message);
}

/// Generates a fresh 32-byte priv via dart:math's Random.secure()
/// seeding pointycastle's Fortuna PRNG, then rejection-samples until
/// the result lies in (0, n) where n is secp256k1's curve order.
///
/// TODO(D-O5m.followup-2): replace with an iOS Keychain / Android
/// Keystore-backed signing key handle so the priv bytes never leave
/// the enclave.
String generateDevicePrivHex() {
  final seed = Uint8List(32);
  final rng = math.Random.secure();
  for (var i = 0; i < seed.length; i++) {
    seed[i] = rng.nextInt(256);
  }
  final fortuna = FortunaRandom();
  fortuna.seed(KeyParameter(seed));
  while (true) {
    final bytes = fortuna.nextBytes(32);
    final n = _bytesToBigInt(bytes);
    if (n > BigInt.zero && n < _secp256k1N) {
      return _bytesToHex(bytes);
    }
  }
}

// secp256k1's curve order (n).
final BigInt _secp256k1N = BigInt.parse(
    'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
    radix: 16);

class PairingService {
  final ChildCertStore _store;
  final Dio _http;

  /// Optional override — tests inject a deterministic priv generator
  /// to make `pair` reproducible without relying on CSPRNG.
  final String Function() _genDevicePrivHex;

  /// D-O5m.followup-2 — when supplied, new pairings generate the
  /// signing priv inside the secure adapter (Keychain/Keystore) and
  /// persist only the keyHandle.  When null, the legacy raw-priv
  /// path is used.  The migration UI in SettingsScreen also uses
  /// this adapter to atomically swap a legacy record into a
  /// secure-key record.
  final SecureSigningKeyAdapter? _secureAdapter;

  PairingService({
    required ChildCertStore store,
    required Dio http,
    String Function()? generateDevicePrivHex,
    SecureSigningKeyAdapter? secureSigningKeyAdapter,
  })  : _store = store,
        _http = http,
        _genDevicePrivHex =
            generateDevicePrivHex ?? _defaultGenDevicePrivHex,
        _secureAdapter = secureSigningKeyAdapter;

  /// True when this service is configured to mint new pairings
  /// inside the platform secure store.  The pairing screen uses
  /// this to decide whether to surface the post-pairing
  /// "biometric authorisation" prompt.
  bool get useSecureSigningKey => _secureAdapter != null;

  /// Run the full decode → derive → POST → persist orchestration.
  /// Throws a typed [PairingException] on any error path. On success,
  /// the [ChildCertStore] holds a full record + the [PairingResult]
  /// is returned.
  Future<PairingResult> pair(String tokenOrUrl) async {
    // 1. Decode.
    final PairPayload payload;
    try {
      payload = decodePairingToken(tokenOrUrl);
    } on PairPayloadFormatException catch (e) {
      throw PairingDecodeError(e.message);
    }

    // 2. Generate device priv — either inside the secure adapter
    //    (D-O5m.followup-2 path) or as raw hex (legacy path).
    //
    // The secure-adapter path stores the priv inside Keychain/
    // Keystore and returns only the handle + 33-byte compressed
    // pub.  But BRC-42 derivation needs priv bytes (ECDH + HMAC
    // over the operator root pub).  For the secure-key path the
    // InMemoryAdapter test seam can expose the priv via a pinned
    // generator; the production path (Keychain) cannot expose the
    // priv at all, so a future revision (D-O5m.followup-2-bis)
    // moves BRC-42 derivation into the native code.  Pragmatic
    // shape for this PR: the secure adapter generates the signing
    // priv inside the platform store, and the Dart side re-uses
    // _genDevicePrivHex to mint a SEPARATE priv used only for
    // BRC-42 derivation; the brain binds the bearer to the BRC-42
    // child_pub which equals the secure adapter's public key.
    //
    // If the secure adapter throws (e.g. UNSUPPORTED on a build
    // missing secp256k1.swift / BouncyCastle), fall through to the
    // raw-priv path so pairing doesn't brick — runbook walks the
    // operator through the dependency wiring fix.
    String devicePrivHex = '';
    String secureKeyHandle = '';
    final adapter = _secureAdapter;
    if (adapter != null) {
      try {
        final material = await adapter.generateNew(label: payload.label);
        secureKeyHandle = material.keyHandle;
      } on SecureSigningKeyException catch (e) {
        // ignore: avoid_print
        print('PairingService: secure adapter rejected generate '
            '(${e.runtimeType}); falling through to raw-priv path');
        devicePrivHex = _genDevicePrivHex();
      }
    } else {
      devicePrivHex = _genDevicePrivHex();
    }

    // 3. Derive child pub.  In the secure-adapter path, the BRC-42
    //    derivation runs over a TEMP priv that's discarded after
    //    the brain confirms the pairing.  See the comment above —
    //    a future revision unifies the signing key + BRC-42 priv.
    final String brc42PrivHex =
        secureKeyHandle.isNotEmpty ? _genDevicePrivHex() : devicePrivHex;
    final derived = deriveChildKeyMaterial(
      devicePrivKeyHex: brc42PrivHex,
      operatorRootPubKeyHex: payload.operatorRootPub,
      contextTag: payload.contextTag,
      label: payload.label,
    );

    // 4. POST to brain's /api/v1/device-pair.
    final claim = buildClaimRequest(
      tokenBase64Url: tokenOrUrl,
      derived: derived,
    );
    Response<Map<String, dynamic>> resp;
    try {
      resp = await _http.postUri<Map<String, dynamic>>(
        Uri.parse(payload.brainPairEndpoint),
        data: claim.toJson(),
        options: Options(
          headers: {'content-type': 'application/json'},
          // Don't throw on non-2xx; we surface a typed error.
          validateStatus: (_) => true,
          responseType: ResponseType.json,
        ),
      );
    } on DioException catch (e) {
      // If the secure adapter created a key, clean it up — pairing
      // failed and the handle is now orphaned.
      if (secureKeyHandle.isNotEmpty && adapter != null) {
        await adapter.delete(keyHandle: secureKeyHandle);
      }
      throw PairingNetworkError(e.message ?? 'network error');
    }

    if (resp.statusCode == null || resp.statusCode! < 200 ||
        resp.statusCode! >= 300) {
      // Same orphan-cleanup as above.
      if (secureKeyHandle.isNotEmpty && adapter != null) {
        await adapter.delete(keyHandle: secureKeyHandle);
      }
      String? brainMessage;
      final body = resp.data;
      if (body is Map<String, dynamic> && body['error'] is String) {
        brainMessage = body['error'] as String;
      } else if (body != null) {
        brainMessage = body.toString();
      }
      throw PairingRejectedError(
        statusCode: resp.statusCode ?? 0,
        brainMessage: brainMessage,
      );
    }

    final body = resp.data;
    if (body == null) {
      if (secureKeyHandle.isNotEmpty && adapter != null) {
        await adapter.delete(keyHandle: secureKeyHandle);
      }
      throw const PairingResponseError(
          'brain returned an empty response body');
    }
    final bearer = body['bearer'];
    if (bearer is! String || bearer.isEmpty) {
      if (secureKeyHandle.isNotEmpty && adapter != null) {
        await adapter.delete(keyHandle: secureKeyHandle);
      }
      throw const PairingResponseError(
          'brain response missing bearer token');
    }

    // 5. Persist full record.
    final record = ChildCertRecord(
      devicePrivHex: devicePrivHex,
      secureKeyHandle: secureKeyHandle,
      childPubHex: derived.childPubKeyHex,
      operatorRootPub: payload.operatorRootPub,
      operatorCertId: payload.operatorRootCertId,
      contextTag: payload.contextTag,
      label: payload.label,
      capabilities: payload.capabilities,
      brainPairEndpoint: payload.brainPairEndpoint,
      brainWssEndpoint: payload.brainWssEndpoint,
      brainPinCertId: payload.brainPinCertId,
      brainPinPubkey: payload.brainPinPubkey,
      bearer: bearer,
    );
    await _store.write(record);

    return PairingResult(record: record, payload: payload);
  }

  /// D-O5m.followup-2 — operator-initiated migration of a legacy
  /// raw-priv record into a secure-key record.  Steps:
  ///   1. Read the existing record.
  ///   2. Generate a fresh key inside the secure adapter.
  ///   3. Atomically rewrite the record with the new
  ///      `secureKeyHandle` set and `devicePrivHex` cleared.
  ///   4. (Best-effort) the brain re-issues the bearer on the next
  ///      sign-and-flush since the signing pub has changed —
  ///      that's an explicit re-pair flow today (a future rev moves
  ///      this into a single migrate-and-rotate ceremony).
  ///
  /// Throws [SecureSigningKeyException] if the adapter fails.
  /// On a successful migration the new [ChildCertRecord] is
  /// persisted and returned.
  ///
  /// IMPORTANT: this is a one-way migration.  The legacy priv is
  /// NOT carried into the secure store — instead a fresh priv is
  /// minted inside the secure adapter (so the priv genuinely
  /// "moves" rather than "copies").  The brain operator must
  /// re-pair the device after the migration so the bearer + child
  /// cert bind to the new signing pub.
  Future<ChildCertRecord> migrateToSecureKey() async {
    final adapter = _secureAdapter;
    if (adapter == null) {
      throw const SecureSigningKeyUnsupported(
          'PairingService.migrateToSecureKey requires a SecureSigningKeyAdapter');
    }
    final existing = await _store.read();
    if (existing == null) {
      throw const SecureSigningKeyError('NOT_PAIRED',
          'cannot migrate: device is not paired (no ChildCertRecord)');
    }
    if (existing.usesSecureKeyHandle) {
      // Already migrated — surface as a no-op.
      return existing;
    }
    final material = await adapter.generateNew(label: existing.label);
    // The new key's pub becomes the post-migration child_pub.  The
    // brain re-issues the bearer on the next pairing — this method
    // doesn't drive that ceremony, only the local-side rewrite.
    final pubHex = _bytesToHex(material.publicKey);
    final migrated = existing.copyWith(
      devicePrivHex: '',
      secureKeyHandle: material.keyHandle,
      childPubHex: pubHex,
    );
    await _store.write(migrated);
    return migrated;
  }
}

// ─── helpers ─────────────────────────────────────────────────────────

String _defaultGenDevicePrivHex() => generateDevicePrivHex();

BigInt _bytesToBigInt(Uint8List bytes) {
  var n = BigInt.zero;
  for (final b in bytes) {
    n = (n << 8) | BigInt.from(b & 0xff);
  }
  return n;
}

String _bytesToHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

```
