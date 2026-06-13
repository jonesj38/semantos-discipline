---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/attachments/attachment_builder.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.877601+00:00
---

# archive/apps-semantos-monolith/lib/src/attachments/attachment_builder.dart

```dart
// D-O5m.followup-8 capture+upload — Build a signed
// `oddjobz.attachment.v1` metadata cell from sensor inputs.
//
// Reference: extensions/oddjobz/src/cell-types/attachment.ts (the
//            canonical TS shape this builder mirrors); extensions/
//            oddjobz/src/cell-types/canonical-json.ts (the lexicographic-
//            key encoder this builder ports byte-for-byte);
//            apps/oddjobz-mobile/lib/src/identity/cell_signer.dart
//            (the ECDSA-secp256k1-sha256 signer that signs the
//            canonical bytes).
//
// Output of `buildSignedAttachment` is a `SignedAttachment` carrying:
//   - the unsigned payload as a Map<String, dynamic> (JSON-shaped)
//   - the canonical-JSON-encoded UTF-8 bytes (signature preimage)
//   - the 64-byte (r||s) ECDSA signature
//   - convenience fields (contentHash, contentSize, mimeType) for the
//     outbox flush handler that posts the multipart upload to the
//     brain
//
// The brain-side upload endpoint (runtime/semantos-brain/src/
// attachments_upload_http.zig) hashes the binary blob, asserts hash ==
// payload.contentHash, looks up the device's child cert by
// `capturedByCertId`, and verifies the signature against the cert's
// pubkey via the same recovery-loop scheme used in
// signed_bundle.zig::verifySignature.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:uuid/uuid.dart';

import '../identity/cell_signer.dart';

const Set<String> _validKinds = {'photo', 'voice_memo', 'gps_pin', 'file_other'};

/// Output of [buildSignedAttachment] — the metadata cell + its
/// signature + the convenience fields the outbox flush handler hands
/// to the multipart upload endpoint.
class SignedAttachment {
  /// The unsigned metadata cell as a JSON-shaped map. Field set
  /// matches `oddjobz.attachment.v1` verbatim (lexicographic order
  /// when canonicalised).
  final Map<String, dynamic> payload;

  /// Canonical-JSON-encoded UTF-8 bytes of [payload]. This is the
  /// signature preimage — what the brain re-canonicalises on receipt
  /// to verify the signature.
  final Uint8List payloadCanonicalBytes;

  /// 64-byte (r || s) ECDSA-secp256k1-sha256 signature over
  /// [payloadCanonicalBytes], normalised to low-s.
  final Uint8List signature;

  /// sha256 hex of the binary blob — matches `payload['contentHash']`.
  /// Surfaced as a top-level field so callers don't have to reach
  /// through the payload map.
  final String contentHash;

  /// Blob size in bytes — matches `payload['contentSize']`.
  final int contentSize;

  /// Mime type — matches `payload['mimeType']`.
  final String mimeType;

  const SignedAttachment({
    required this.payload,
    required this.payloadCanonicalBytes,
    required this.signature,
    required this.contentHash,
    required this.contentSize,
    required this.mimeType,
  });

  /// Encode as the JSON shape the multipart upload's `metadata` part
  /// carries. Matches the contract on
  /// `runtime/semantos-brain/src/attachments_upload_http.zig`: a `cell_payload`
  /// (the unsigned cell map) + a hex-encoded signature + the
  /// `captured_by_cert_id` (which is also already inside the payload
  /// but the brain reads it from the top-level for the cert lookup
  /// without needing to parse the payload first).
  String toUploadMetadataJson() {
    return json.encode({
      'cell_payload': payload,
      'signature_hex': _bytesToHex(signature),
      'captured_by_cert_id': payload['capturedByCertId'],
    });
  }
}

/// Build a signed `oddjobz.attachment.v1` metadata cell.
///
/// Inputs:
///   - [visitId]: parent Visit's UUID v4 — REQUIRED.
///   - [kind]: one of `photo | voice_memo | gps_pin | file_other`.
///   - [blobBytes]: the binary artifact bytes (e.g. raw JPEG bytes).
///   - [mimeType]: e.g. `image/jpeg`.
///   - [capturedAt]: ISO-8601 device-clock timestamp.
///   - [capturedByCertId]: 32 lowercase hex chars (16-byte cert id).
///   - [devicePrivBytes]: 32-byte priv from ChildCertStore.
///   - [caption]: optional operator caption (≤ 500 chars).
///   - [attachmentId]: optional override (defaults to a fresh UUID v4)
///     — wired so tests can pin the id for reproducible fixtures.
///
/// Output: a [SignedAttachment] ready to enqueue in the outbox.
SignedAttachment buildSignedAttachment({
  required String visitId,
  required String kind,
  required Uint8List blobBytes,
  required String mimeType,
  required String capturedAt,
  required String capturedByCertId,
  required Uint8List devicePrivBytes,
  String? caption,
  String? attachmentId,
}) {
  if (visitId.isEmpty) throw ArgumentError('visitId is required');
  if (!_validKinds.contains(kind)) {
    throw ArgumentError('kind must be one of $_validKinds, got $kind');
  }
  if (mimeType.isEmpty) throw ArgumentError('mimeType is required');
  if (capturedAt.isEmpty) throw ArgumentError('capturedAt is required');
  if (capturedByCertId.length != 32) {
    throw ArgumentError(
        'capturedByCertId must be 32 hex chars, got ${capturedByCertId.length}');
  }
  if (caption != null && caption.length > 500) {
    throw ArgumentError('caption exceeds 500 chars');
  }

  final id = attachmentId ?? const Uuid().v4();
  final contentHash = _sha256Hex(blobBytes);
  final contentSize = blobBytes.length;
  // createdAt is server-stamped on receipt; the unsigned cell still
  // carries a placeholder so the canonical bytes have the same shape
  // the brain will canonicalise after server-stamping the field. The
  // brain re-canonicalises after stamping; the device's signature
  // does NOT cover createdAt — see TS `oddjobz.attachment.v1` shape
  // where the cell carries createdAt but our wire envelope strips it
  // before signing. To mirror that, we omit `createdAt` from the
  // signed payload; the brain stamps + re-canonicalises after upload.
  final unsigned = <String, dynamic>{
    'attachmentId': id,
    'capturedAt': capturedAt,
    'capturedByCertId': capturedByCertId,
    'contentHash': contentHash,
    'contentSize': contentSize,
    'kind': kind,
    'mimeType': mimeType,
    'visitId': visitId,
  };
  if (caption != null && caption.isNotEmpty) {
    unsigned['caption'] = caption;
  }

  final canonicalBytes = encodeCanonicalJson(unsigned);
  final signature = signCellPayload(canonicalBytes, devicePrivBytes);

  return SignedAttachment(
    payload: unsigned,
    payloadCanonicalBytes: canonicalBytes,
    signature: signature,
    contentHash: contentHash,
    contentSize: contentSize,
    mimeType: mimeType,
  );
}

/// Canonical-JSON encoder — port of
/// `extensions/oddjobz/src/cell-types/canonical-json.ts`.  Produces
/// byte-identical UTF-8 output for structurally-equal values: object
/// keys lexicographic order, no whitespace, standard JSON string
/// escapes.  Round-trips through `dart:convert json.decode`.
Uint8List encodeCanonicalJson(Object? value) {
  return Uint8List.fromList(utf8.encode(_canonicalStringify(value)));
}

String _canonicalStringify(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) return value.toString();
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError(
          'canonical-json: non-finite number not allowed: $value');
    }
    // Match JS Number.prototype.toString round-trip — for whole-
    // valued doubles like 3.0 emit "3" (canonical-json.ts emits "3"
    // not "3.0").
    if (value == value.truncateToDouble() && value.abs() < 1e21) {
      return value.toInt().toString();
    }
    return value.toString();
  }
  if (value is String) return _stringEscape(value);
  if (value is List) {
    final parts = StringBuffer('[');
    var first = true;
    for (final item in value) {
      if (!first) parts.write(',');
      first = false;
      parts.write(_canonicalStringify(item));
    }
    parts.write(']');
    return parts.toString();
  }
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    final parts = StringBuffer('{');
    var first = true;
    for (final k in keys) {
      if (!first) parts.write(',');
      first = false;
      parts.write(_stringEscape(k));
      parts.write(':');
      parts.write(_canonicalStringify(value[k]));
    }
    parts.write('}');
    return parts.toString();
  }
  throw ArgumentError(
      'canonical-json: unsupported value of type ${value.runtimeType}');
}

String _stringEscape(String s) {
  final out = StringBuffer('"');
  for (var i = 0; i < s.length; i++) {
    final code = s.codeUnitAt(i);
    switch (code) {
      case 0x22:
        out.write('\\"');
        break;
      case 0x5c:
        out.write('\\\\');
        break;
      case 0x08:
        out.write('\\b');
        break;
      case 0x09:
        out.write('\\t');
        break;
      case 0x0a:
        out.write('\\n');
        break;
      case 0x0c:
        out.write('\\f');
        break;
      case 0x0d:
        out.write('\\r');
        break;
      default:
        if (code < 0x20) {
          out.write(
              '\\u${code.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(code);
        }
    }
  }
  out.write('"');
  return out.toString();
}

String _sha256Hex(Uint8List bytes) {
  final sha = SHA256Digest();
  final out = Uint8List(32);
  sha.update(bytes, 0, bytes.length);
  sha.doFinal(out, 0);
  return _bytesToHex(out);
}

String _bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

```
