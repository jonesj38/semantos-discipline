---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/brain/brain_http_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.112916+00:00
---

# apps/semantos/lib/src/brain/brain_http_client.dart

```dart
/// brain_http_client.dart — bearer-gated HTTP client for the canonical brain.
///
/// Wraps the BRC-100-equivalent endpoints on the brain HTTP surface that
/// the C7 V1 golden slice exercises:
///   - POST /api/v1/cells  → mint a canonical cell (verified GREEN
///                            against live brain at oddjobtodd.info on
///                            2026-05-28, see canon matrix C7-D).
///   - GET  /api/v1/cell/<cellId> → retrieve a persisted cell.
///
/// Other brain endpoints (REPL, voice-extract, list-cells, etc.) wire
/// in later ticks as their consumers land.
///
/// Caller responsibility: provide baseUrl + bearerToken from the
/// IdentityStore (per Q4 decision — IdentityStore owns custody; this
/// client only consumes them).
library;

import 'dart:convert';
import 'package:dio/dio.dart';

import '../dispatch/cell_minter.dart' show CellMinter;

/// Result of a successful `cells mint` call.
class MintCellResult {
  final String cellId;
  final String cartridgeId;
  final String cellType;
  final int persistedAt; // unix-ms

  const MintCellResult({
    required this.cellId,
    required this.cartridgeId,
    required this.cellType,
    required this.persistedAt,
  });

  factory MintCellResult.fromJson(Map<String, dynamic> json) => MintCellResult(
        cellId: json['cellId'] as String,
        cartridgeId: json['cartridgeId'] as String,
        cellType: json['cellType'] as String,
        persistedAt: json['persistedAt'] as int,
      );
}

/// Raised when the brain returns a structured error.
class BrainHttpError implements Exception {
  final int statusCode;
  final String error;
  final String? field;
  final String? expectedType;
  final String body;

  BrainHttpError({
    required this.statusCode,
    required this.error,
    this.field,
    this.expectedType,
    required this.body,
  });

  @override
  String toString() {
    final detail = field != null ? ' field=$field expected=$expectedType' : '';
    return 'BrainHttpError($statusCode $error$detail) body=$body';
  }
}

/// Bearer-gated HTTP client for the canonical brain.
///
/// Implements [CellMinter] so it remains a drop-in for the dispatcher; M1.7b
/// nonetheless points the dispatcher at BrainRpcClient's `cells.mint`. This
/// HTTP client stays only for read/info surfaces not yet migrated.
class BrainHttpClient implements CellMinter {
  final String baseUrl;
  final String bearerToken;
  final Dio _dio;

  BrainHttpClient({
    required this.baseUrl,
    required this.bearerToken,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  /// Mint a cell via the generic cells_mint_handler.
  ///
  /// Wire: `POST $baseUrl/api/v1/cells` with bearer auth.
  /// Body: `{typeHashHex, payload}`.
  /// Response: `{cellId, cartridgeId, cellType, persistedAt}`.
  @override
  Future<MintCellResult> mintCell({
    required String typeHashHex,
    required Map<String, dynamic> payload,
  }) async {
    if (typeHashHex.length != 64) {
      throw ArgumentError(
        'typeHashHex must be 64 hex chars (32 bytes), got ${typeHashHex.length}',
      );
    }
    return _postCells({
      'typeHashHex': typeHashHex,
      'payload': payload,
    });
  }

  /// Mint a cell with an operator signature (sovereign mint — C7-B Option A).
  ///
  /// Wire: `POST $baseUrl/api/v1/cells` with
  /// `{typeHashHex, payload, signatureHex, signerCertIdHex}`. The brain
  /// re-derives `sha256(canonicaliseCellPayload(payload))`, recovers the
  /// signer pubkey from the signature, and matches it against the
  /// `signerCertIdHex` cert before persisting (#828). A bad/unknown/
  /// unverifiable signature 401s, surfaced here as [BrainHttpError].
  ///
  /// [signatureHex] is the 64-byte (r‖s) compact signature as 128 hex chars
  /// — see `signMintPayloadHex` in dispatch/signed_mint.dart, which signs
  /// `canonicaliseCellPayload(payload)`. [signerCertIdHex] is the operator
  /// cert id the brain looks up.
  @override
  Future<MintCellResult> mintCellSigned({
    required String typeHashHex,
    required Map<String, dynamic> payload,
    required String signatureHex,
    required String signerCertIdHex,
  }) async {
    if (typeHashHex.length != 64) {
      throw ArgumentError(
        'typeHashHex must be 64 hex chars (32 bytes), got ${typeHashHex.length}',
      );
    }
    if (signatureHex.length != 128) {
      throw ArgumentError(
        'signatureHex must be 128 hex chars (64 bytes), got ${signatureHex.length}',
      );
    }
    return _postCells({
      'typeHashHex': typeHashHex,
      'payload': payload,
      'signatureHex': signatureHex,
      'signerCertIdHex': signerCertIdHex,
    });
  }

  /// POST a mint body to `/api/v1/cells` (bearer-gated) and map the response.
  /// Shared by [mintCell] (unsigned) + [mintCellSigned] (operator-signed) —
  /// the only difference is the extra `signatureHex`/`signerCertIdHex` fields.
  Future<MintCellResult> _postCells(Map<String, dynamic> body) async {
    final response = await _dio.post(
      '$baseUrl/api/v1/cells',
      data: body,
      options: Options(
        headers: {
          'Authorization': 'Bearer $bearerToken',
          'Content-Type': 'application/json',
        },
        validateStatus: (_) => true, // we inspect status manually
      ),
    );

    final data = response.data;
    final Map<String, dynamic> bodyMap = data is Map<String, dynamic>
        ? data
        : (data is String ? jsonDecode(data) as Map<String, dynamic> : <String, dynamic>{});

    // Brain returns 201 Created on successful POST /api/v1/cells mint
    // (proper REST semantics for "resource created"). Accept any 2xx;
    // only treat as error if status is non-2xx OR the body carries an
    // explicit `error` field.
    final status = response.statusCode ?? 0;
    final is2xx = status >= 200 && status < 300;
    if (!is2xx || bodyMap.containsKey('error')) {
      throw BrainHttpError(
        statusCode: status,
        error: (bodyMap['error'] ?? 'unknown_error').toString(),
        field: bodyMap['field']?.toString(),
        expectedType: bodyMap['expectedType']?.toString(),
        body: data.toString(),
      );
    }

    return MintCellResult.fromJson(bodyMap);
  }

  /// Retrieve a persisted cell's raw bytes by cell-id.
  /// Wire: `GET $baseUrl/api/v1/cell/<cellId>` with bearer auth.
  /// Response: raw 1024-byte canonical cell.
  Future<List<int>> getCell(String cellId) async {
    if (cellId.length != 64) {
      throw ArgumentError(
        'cellId must be 64 hex chars (32 bytes), got ${cellId.length}',
      );
    }
    final response = await _dio.get<List<int>>(
      '$baseUrl/api/v1/cell/$cellId',
      options: Options(
        headers: {'Authorization': 'Bearer $bearerToken'},
        responseType: ResponseType.bytes,
      ),
    );
    final bytes = response.data ?? <int>[];
    if (bytes.length != 1024) {
      throw StateError(
        'getCell: expected 1024-byte canonical cell, got ${bytes.length} bytes',
      );
    }
    return bytes;
  }

  /// C11 PR-C11-1 — Fetch the brain's identity snapshot for the
  /// helm "me" surface. Wire: `GET $baseUrl/api/v1/info` with bearer
  /// auth. The same endpoint used for cartridge discovery — it also
  /// carries the brain's pinned operator cert id + pubkey + the
  /// active hat associated with this bearer.
  ///
  /// Response shape (partial, fields the helm cares about):
  /// ```json
  /// {
  ///   "server_version": "brain 0.1.0-brain1",
  ///   "brain_pin_cert_id": "af90d1d6…",
  ///   "brain_pin_pubkey": "029cf8e4…",
  ///   "hat": { "id": "…", "name": "…", "cert_id": "" },
  ///   "cartridges": [ {"id": "betterment", "role": "domain", …} ]
  /// }
  /// ```
  Future<BrainInfo> getInfo() async {
    final response = await _dio.get(
      '$baseUrl/api/v1/info',
      options: Options(
        headers: {'Authorization': 'Bearer $bearerToken'},
        validateStatus: (_) => true,
      ),
    );
    final data = response.data;
    final Map<String, dynamic> bodyMap = data is Map<String, dynamic>
        ? data
        : (data is String
            ? jsonDecode(data) as Map<String, dynamic>
            : <String, dynamic>{});
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300 || bodyMap.containsKey('error')) {
      throw BrainHttpError(
        statusCode: status,
        error: (bodyMap['error'] ?? 'info_fetch_failed').toString(),
        body: data.toString(),
      );
    }
    return BrainInfo.fromJson(bodyMap);
  }
}

/// Subset of `/api/v1/info` the helm "me" surface displays.
class BrainInfo {
  /// e.g. "brain 0.1.0-brain1"
  final String serverVersion;

  /// Pinned operator root cert id (sha256(pubkey)[:16] hex per brain
  /// convention — 32 hex chars).
  final String pinCertId;

  /// Pinned operator root pubkey (66 hex chars compressed secp256k1).
  final String pinPubkey;

  /// Active hat metadata for THIS bearer token. Empty fields when the
  /// brain doesn't track per-bearer hats (older brains).
  final HatInfo hat;

  /// Cartridges this brain serves — surfaced as a count + names list
  /// in the "me" sheet's Identity row.
  final List<CartridgeInfo> cartridges;

  const BrainInfo({
    required this.serverVersion,
    required this.pinCertId,
    required this.pinPubkey,
    required this.hat,
    required this.cartridges,
  });

  factory BrainInfo.fromJson(Map<String, dynamic> json) {
    final hatJson = json['hat'];
    return BrainInfo(
      serverVersion: (json['server_version'] as String?) ?? '',
      pinCertId: (json['brain_pin_cert_id'] as String?) ?? '',
      pinPubkey: (json['brain_pin_pubkey'] as String?) ?? '',
      hat: hatJson is Map<String, dynamic>
          ? HatInfo.fromJson(hatJson)
          : const HatInfo(id: '', name: '', certId: ''),
      cartridges: (json['cartridges'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CartridgeInfo.fromJson)
          .toList(growable: false),
    );
  }
}

/// Hat metadata returned by `/api/v1/info`.
class HatInfo {
  final String id;
  final String name;
  final String certId;
  const HatInfo({required this.id, required this.name, required this.certId});

  factory HatInfo.fromJson(Map<String, dynamic> json) {
    return HatInfo(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      certId: (json['cert_id'] as String?) ?? '',
    );
  }

  bool get isEmpty => id.isEmpty && name.isEmpty;
}

/// Cartridge entry as returned by `/api/v1/info`.
class CartridgeInfo {
  final String id;
  final String role;
  final String experiencePackage;
  const CartridgeInfo({
    required this.id,
    required this.role,
    required this.experiencePackage,
  });

  factory CartridgeInfo.fromJson(Map<String, dynamic> json) {
    return CartridgeInfo(
      id: (json['id'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
      experiencePackage: (json['experiencePackage'] as String?) ?? '',
    );
  }
}

```
