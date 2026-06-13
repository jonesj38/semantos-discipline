---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/self/self_flow_minter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.868392+00:00
---

# archive/apps-semantos-monolith/lib/src/self/self_flow_minter.dart

```dart
// BRAIN-GENERIC-MINT-VERB M4 — concrete SelfFlowMinter implementation.
//
// Replaces the `debugPrint` stub in `helm/home_screen.dart` with a real
// brain POST.  Mirrors the `DioAttachmentUploader` pattern in
// `outbox/outbox_service.dart`: constructor takes Dio + baseUrl +
// bearer-callback; emits `Authorization: Bearer ${_bearer()}` on every
// request.
//
// Wire (matches `cells_mint_http.zig` + the design doc):
//
//   POST <baseUrl>/api/v1/cells
//   Authorization: Bearer <hex64>
//   Content-Type: application/json
//   Body: {"typeHashHex":"<64hex>","payload":{...fields}}
//
//   201 → {"cellId":"...","cartridgeId":"...","cellType":"...","persistedAt":<ms>}
//   400 → bad request           → SelfMintBadRequestError
//   401 → bearer rejected       → SelfMintUnauthorisedError
//   403 → capability denied     → SelfMintCapabilityError
//   404 → unknown typeHash      → SelfMintUnknownTypeHashError
//   413 → payload too large     → SelfMintPayloadTooLargeError
//   500+ → server failure       → SelfMintServerError
//
// The minter computes `typeHashHex` locally from `cellTypeName` via
// `selfCellTypeNameToHashHex` (Dart mirror of the kernel buildTypeHash).
// This keeps the call site simple — flows reference cellTypes by name,
// not by 64-hex — at the cost of needing the static triples map in
// `self_type_hash.dart` to stay in sync with cartridge.json.
//
// Tests can substitute a stub `SelfCellMinter` to verify SnackBar +
// haptic feedback without a real brain.

import 'dart:async';
import 'package:dio/dio.dart';

import 'self_type_hash.dart';

/// Abstract surface — tests inject stubs that record what would be
/// minted.  Production wiring uses [DioSelfCellMinter].
abstract class SelfCellMinter {
  /// Mint a cell of the given cellTypeName with the supplied fields.
  /// Returns the persisted `cellId` (sha256 of the cell bytes, 64 hex
  /// chars) on success.  Throws a typed `SelfMint…Error` on failure.
  Future<SelfMintResult> mint({
    required String cellTypeName,
    required Map<String, String> fields,
  });
}

/// Successful mint — echoes the brain's 201 body so callers can correlate
/// with downstream events (`cells.<cartridge-id>.minted` NATS subject).
class SelfMintResult {
  final String cellId;
  final String cartridgeId;
  final String cellType;
  final int persistedAt;
  const SelfMintResult({
    required this.cellId,
    required this.cartridgeId,
    required this.cellType,
    required this.persistedAt,
  });
}

// ── Typed error hierarchy ────────────────────────────────────────────

/// Base class for every typed self-mint failure.  Callers can
/// pattern-match on subclasses for UI-level error rendering.
abstract class SelfMintError implements Exception {
  final String message;
  const SelfMintError(this.message);
  @override
  String toString() => 'SelfMintError($runtimeType): $message';
}

class SelfMintBadRequestError extends SelfMintError {
  const SelfMintBadRequestError(super.message);
}

class SelfMintUnauthorisedError extends SelfMintError {
  const SelfMintUnauthorisedError(super.message);
}

class SelfMintCapabilityError extends SelfMintError {
  const SelfMintCapabilityError(super.message);
}

class SelfMintUnknownTypeHashError extends SelfMintError {
  const SelfMintUnknownTypeHashError(super.message);
}

class SelfMintPayloadTooLargeError extends SelfMintError {
  const SelfMintPayloadTooLargeError(super.message);
}

class SelfMintServerError extends SelfMintError {
  final int? statusCode;
  const SelfMintServerError(super.message, {this.statusCode});
}

class SelfMintTransportError extends SelfMintError {
  const SelfMintTransportError(super.message);
}

// ── Production Dio-backed implementation ─────────────────────────────

class DioSelfCellMinter implements SelfCellMinter {
  final Dio _http;
  final String _baseUrl;
  final String Function() _bearer;

  DioSelfCellMinter({
    required Dio http,
    required String baseUrl,
    required String Function() bearer,
  })  : _http = http,
        _baseUrl = baseUrl,
        _bearer = bearer;

  @override
  Future<SelfMintResult> mint({
    required String cellTypeName,
    required Map<String, String> fields,
  }) async {
    final String hashHex;
    try {
      hashHex = selfCellTypeNameToHashHex(cellTypeName);
    } on ArgumentError catch (e) {
      // Unknown cellTypeName at the Dart side — surface as a typed
      // error so the UI can show a useful diagnostic. This happens when
      // a flow definition references a cellTypeName not yet added to
      // selfCellTypeTriples.
      throw SelfMintUnknownTypeHashError(
        'unknown cellTypeName $cellTypeName: ${e.message}',
      );
    }

    final body = <String, dynamic>{
      'typeHashHex': hashHex,
      'payload': fields,
    };

    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _http.post<Map<String, dynamic>>(
        '$_baseUrl/api/v1/cells',
        data: body,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${_bearer()}',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw SelfMintTransportError('network error: ${e.message ?? e}');
    }

    final status = resp.statusCode ?? 0;
    final respBody = resp.data ?? const <String, dynamic>{};

    switch (status) {
      case 201:
        return SelfMintResult(
          cellId: (respBody['cellId'] ?? '').toString(),
          cartridgeId: (respBody['cartridgeId'] ?? '').toString(),
          cellType: (respBody['cellType'] ?? cellTypeName).toString(),
          persistedAt: (respBody['persistedAt'] is int)
              ? respBody['persistedAt'] as int
              : 0,
        );
      case 400:
        throw SelfMintBadRequestError(_errString(respBody, 'bad_request'));
      case 401:
        throw SelfMintUnauthorisedError(
          _errString(respBody, 'bearer_invalid'),
        );
      case 403:
        throw SelfMintCapabilityError(
          _errString(respBody, 'capability_denied'),
        );
      case 404:
        throw SelfMintUnknownTypeHashError(
          _errString(respBody, 'unknown_type_hash'),
        );
      case 413:
        throw SelfMintPayloadTooLargeError(
          _errString(respBody, 'payload_too_large'),
        );
      default:
        throw SelfMintServerError(
          _errString(respBody, 'server_error'),
          statusCode: status,
        );
    }
  }

  static String _errString(Map<String, dynamic> body, String fallback) {
    final err = body['error']?.toString();
    final hint = body['hint']?.toString();
    if (err == null || err.isEmpty) return fallback;
    if (hint == null || hint.isEmpty) return err;
    return '$err: $hint';
  }
}

```
