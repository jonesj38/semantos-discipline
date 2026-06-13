---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/voice/voice_session_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.867105+00:00
---

# archive/apps-semantos-monolith/lib/src/voice/voice_session_service.dart

```dart
// D-O5m.followup-3 Phase 1 — Dart port of the cert-bound voice-session
// contract from `runtime/intent/src/voice/voice-session.ts`.
//
// Reference: runtime/intent/src/voice/voice-session.ts (the canonical
//            TS contract — this file mirrors it verbatim);
//            runtime/intent/src/voice/preimage.ts (the canonical
//            preimage encoders this file ports);
//            apps/oddjobz-mobile/test/fixtures/voice-session-fixture.json
//            (cross-language parity proof — load-bearing).
//
// Three pure functions:
//
//   - createVoiceSession({certStore, nowMs}) → VoiceSession
//     Refuses with MissingCertError if no cert is bound.
//
//   - addTranscript({session, text, signer, sequence, nowMs}) → Transcript
//     Signs the canonical preimage with the device cell-signer; refuses
//     with VoiceContractError if the signer's keyId disagrees with
//     session.certId.
//
//   - verifyTranscript(transcript, devicePubBytes) → bool
//     Re-checks the signature against the canonical preimage. Used by
//     unit tests and (for diagnostics) by the offline outbox flush.
//     Production verification is done brain-side at the multipart
//     /api/v1/voice-extract endpoint.
//
// The byte-level encoding of `voiceSessionPreimage` and
// `canonicalTranscriptPreimage` MUST match the TS reference verbatim.
// `voice_session_service_test.dart` asserts this against the committed
// fixture JSON. Failing that, Dart-signed transcripts could be rejected
// by the brain's verifier (or, worse, accepted while encoding the
// wrong fields).

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import '../identity/cell_signer.dart';
import '../identity/child_cert_store.dart';

// ── Errors ─────────────────────────────────────────────────────────

/// Thrown when [createVoiceSession] cannot produce a session because
/// no BRC-52 cert is currently bound. Voice channels MUST be
/// cert-bound; there is no anonymous-voice fallback.
class MissingCertError implements Exception {
  final String message;
  final String code = 'VOICE_CERT_REQUIRED';
  const MissingCertError([
    this.message =
        'Voice session requires a bound BRC-52 cert; identity store returned null',
  ]);

  @override
  String toString() => 'MissingCertError: $message';
}

/// Thrown when a voice-contract invariant is violated by the caller —
/// e.g. signer keyId ≠ session.certId, or sequence < 0.
class VoiceContractError implements Exception {
  final String code;
  final String message;
  const VoiceContractError(this.code, this.message);

  @override
  String toString() => 'VoiceContractError($code): $message';
}

// ── Types ──────────────────────────────────────────────────────────

/// Cert-bound voice capture session. Mirrors the TS `VoiceSession`
/// shape exactly. The `id` is `SHA-256(certId || startedAt_be_u64)`
/// hex-encoded — deterministic in (cert_id, started_at).
class VoiceSession {
  /// 64-char lowercase hex of `SHA-256(certIdBytes(32) || startedAtMs_be_u64(8))`.
  final String id;

  /// Speaker's BRC-52 cert id (32 bytes, 64 hex chars).
  final String certId;

  /// 33-byte compressed secp256k1 pubkey from the cert subject (hex).
  final String subjectPublicKey;

  /// Milliseconds since epoch — fixed at session creation.
  final int startedAtMs;

  /// Optional opaque device id; carried for diagnostics only.
  final String? deviceId;

  const VoiceSession({
    required this.id,
    required this.certId,
    required this.subjectPublicKey,
    required this.startedAtMs,
    this.deviceId,
  });
}

/// Signature shape over a transcript canonical preimage. Matches the
/// TS `VoiceSignature` shape; `keyId` MUST equal the speaker's certId.
class VoiceSignature {
  final Uint8List bytes;
  final String algorithm;
  final String keyId;
  const VoiceSignature({
    required this.bytes,
    required this.algorithm,
    required this.keyId,
  });

  Map<String, dynamic> toJson() => {
        'bytes': _bytesToHex(bytes),
        'algorithm': algorithm,
        'keyId': keyId,
      };

  factory VoiceSignature.fromJson(Map<String, dynamic> j) => VoiceSignature(
        bytes: _hexToBytes(j['bytes'] as String),
        algorithm: j['algorithm'] as String,
        keyId: j['keyId'] as String,
      );
}

/// Signed segment of speech transcribed within a [VoiceSession].
/// Mirrors the TS `Transcript` shape exactly.
class Transcript {
  /// Per-transcript id; deterministic from (sessionId, sequence).
  final String id;
  final String sessionId;
  final String certId;
  final int sequence;
  final String text;
  final int timestampMs;
  final VoiceSignature signature;

  const Transcript({
    required this.id,
    required this.sessionId,
    required this.certId,
    required this.sequence,
    required this.text,
    required this.timestampMs,
    required this.signature,
  });

  /// JSON shape posted to /api/v1/voice-extract. The brain re-derives
  /// the canonical preimage from these fields and verifies signature
  /// against the cert's pubkey. Field names mirror the TS Transcript
  /// type exactly so the brain-side parser is one-to-one.
  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'certId': certId,
        'sequence': sequence,
        'text': text,
        'timestamp': timestampMs,
        'signature': signature.toJson(),
      };

  factory Transcript.fromJson(Map<String, dynamic> j) => Transcript(
        id: j['id'] as String,
        sessionId: j['sessionId'] as String,
        certId: j['certId'] as String,
        sequence: j['sequence'] as int,
        text: j['text'] as String,
        timestampMs: j['timestamp'] as int,
        signature:
            VoiceSignature.fromJson(j['signature'] as Map<String, dynamic>),
      );
}

// ── Canonical preimage encoders (parity with preimage.ts) ──────────

/// Build `cert_id_bytes(32) || started_at_be_u64(8)` = 40 bytes.
/// MUST be byte-identical to TS `voiceSessionPreimage`.
Uint8List voiceSessionPreimage(String certIdHex, int startedAtMs) {
  if (startedAtMs < 0) {
    throw ArgumentError(
        'voice: started_at must be non-negative, got $startedAtMs');
  }
  final certBytes = _hexToBytes(certIdHex);
  if (certBytes.length != 32) {
    throw ArgumentError(
        'voice: cert_id must be 32 bytes (64 hex chars), got ${certBytes.length}');
  }
  final out = Uint8List(40);
  out.setRange(0, 32, certBytes);
  // big-endian uint64 — matches TS `u64BE`.
  var v = startedAtMs;
  for (var i = 7; i >= 0; i--) {
    out[32 + i] = v & 0xff;
    v = v >> 8;
  }
  return out;
}

/// SHA-256 of [voiceSessionPreimage], hex-encoded. MUST equal TS
/// `deriveVoiceSessionId`.
String deriveVoiceSessionId(String certIdHex, int startedAtMs) {
  final pre = voiceSessionPreimage(certIdHex, startedAtMs);
  return _bytesToHex(_sha256(pre));
}

/// Build the deterministic JSON-with-sorted-keys preimage that a
/// transcript signature covers. MUST be byte-identical to TS
/// `canonicalTranscriptPreimage`.
///
/// Keys are alphabetical: certId, sequence, sessionId, text, timestamp.
/// JSON encoding has no whitespace (default `JsonEncoder` output) and
/// integers are emitted without trailing zeros — matches V8's
/// `JSON.stringify` byte-for-byte for integer-only numbers.
Uint8List canonicalTranscriptPreimage({
  required String sessionId,
  required String certId,
  required int sequence,
  required String text,
  required int timestampMs,
}) {
  // Build manually with sorted keys to match TS exactly. Dart's
  // `jsonEncode` would emit keys in insertion order; we use a
  // LinkedHashMap with explicit insertion order = sorted order.
  final ordered = <String, dynamic>{
    'certId': certId,
    'sequence': sequence,
    'sessionId': sessionId,
    'text': text,
    'timestamp': timestampMs,
  };
  final s = jsonEncode(ordered);
  return Uint8List.fromList(utf8.encode(s));
}

/// SHA-256 of `sessionId || ":" || sequence` UTF-8. MUST equal TS
/// `deriveTranscriptId`.
String deriveTranscriptId(String sessionId, int sequence) {
  if (sequence < 0) {
    throw ArgumentError(
        'voice: sequence must be non-negative, got $sequence');
  }
  final buf = utf8.encode('$sessionId:$sequence');
  return _bytesToHex(_sha256(Uint8List.fromList(buf)));
}

// ── Public API ─────────────────────────────────────────────────────

/// Function the caller supplies for signing transcript preimages. The
/// returned [VoiceSignature.keyId] MUST equal the speaker's certId.
typedef VoiceSigner = VoiceSignature Function(Uint8List preimage);

/// Build a [VoiceSigner] backed by the device's cell-signer. The
/// keyId is bound to [certId] at call time so the resulting signer
/// only ever produces signatures attributed to that cert.
VoiceSigner makeCellSignerVoiceSigner({
  required Uint8List devicePrivBytes,
  required String certId,
}) {
  return (Uint8List preimage) {
    final sig = signCellPayload(preimage, devicePrivBytes);
    return VoiceSignature(
      bytes: sig,
      algorithm: 'ecdsa-secp256k1-sha256-compact',
      keyId: certId,
    );
  };
}

/// Create a cert-bound [VoiceSession]. Throws [MissingCertError] if no
/// cert is bound on [certStore]; throws [VoiceContractError] if the
/// stored record has malformed cert/pubkey fields.
Future<VoiceSession> createVoiceSession({
  required ChildCertStore certStore,
  int? nowMs,
  String? deviceId,
}) async {
  final record = await certStore.read();
  if (record == null) {
    throw const MissingCertError();
  }
  // The mobile pairing flow currently treats `operatorCertId` as the
  // root cert binding. The voice contract requires the *speaker's*
  // cert id; for the device that is the BRC-42 child cert id which
  // we synthesise from the child pub. (When D-O5m.followup-2 lands
  // the proper cert-id derivation, swap this for the canonical
  // derivation.) For Phase 1 we use childPubHex's first 32 bytes
  // SHA-256 as a stable cert_id surrogate — see voice-shell-pipeline
  // glossary entry for the contract.
  final certIdBytes = _sha256(Uint8List.fromList(utf8.encode(record.childPubHex)));
  final certId = _bytesToHex(certIdBytes);
  final subjectPublicKey = record.childPubHex;
  if (certId.length != 64 || subjectPublicKey.isEmpty) {
    throw const VoiceContractError(
      'VOICE_CERT_INVALID',
      'cert store returned a record without a derivable certId or pubkey',
    );
  }
  final startedAtMs = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final id = deriveVoiceSessionId(certId, startedAtMs);
  return VoiceSession(
    id: id,
    certId: certId,
    subjectPublicKey: subjectPublicKey,
    startedAtMs: startedAtMs,
    deviceId: deviceId,
  );
}

/// Append a signed [Transcript] to [session]. Throws
/// [VoiceContractError] if [signer] returns a signature whose keyId
/// disagrees with `session.certId` (catches misconfigured signers
/// before the artifact reaches the verifier).
Transcript addTranscript({
  required VoiceSession session,
  required String text,
  required VoiceSigner signer,
  int sequence = 0,
  int? nowMs,
}) {
  if (sequence < 0) {
    throw VoiceContractError(
      'VOICE_SEQUENCE_INVALID',
      'sequence must be non-negative, got $sequence',
    );
  }
  final timestamp = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final preimage = canonicalTranscriptPreimage(
    sessionId: session.id,
    certId: session.certId,
    sequence: sequence,
    text: text,
    timestampMs: timestamp,
  );
  final signature = signer(preimage);
  if (signature.keyId != session.certId) {
    throw VoiceContractError(
      'VOICE_KEYID_MISMATCH',
      'signer keyId ${signature.keyId} does not match session certId ${session.certId}',
    );
  }
  final id = deriveTranscriptId(session.id, sequence);
  return Transcript(
    id: id,
    sessionId: session.id,
    certId: session.certId,
    sequence: sequence,
    text: text,
    timestampMs: timestamp,
    signature: signature,
  );
}

/// Re-check a transcript's cert binding and signature. Returns false
/// (never throws) on bad cert binding (signature.keyId ≠ certId) or
/// on bad signature. [devicePubBytes] is the 33-byte compressed
/// secp256k1 pubkey of the speaker.
bool verifyTranscript(Transcript transcript, Uint8List devicePubBytes) {
  if (transcript.signature.keyId != transcript.certId) return false;
  final preimage = canonicalTranscriptPreimage(
    sessionId: transcript.sessionId,
    certId: transcript.certId,
    sequence: transcript.sequence,
    text: transcript.text,
    timestampMs: transcript.timestampMs,
  );
  try {
    return verifyCellSignature(
      preimage,
      transcript.signature.bytes,
      devicePubBytes,
    );
  } catch (_) {
    return false;
  }
}

/// Convenience: re-derive the session id this transcript claims to
/// belong to and check it matches.
bool transcriptBelongsToSession(Transcript transcript, VoiceSession session) {
  if (transcript.sessionId != session.id) return false;
  if (transcript.certId != session.certId) return false;
  final expected = deriveVoiceSessionId(session.certId, session.startedAtMs);
  return expected == session.id;
}

// ── Hex helpers (local, kept off the public surface) ───────────────

Uint8List _sha256(Uint8List input) {
  final out = Uint8List(32);
  SHA256Digest()
    ..update(input, 0, input.length)
    ..doFinal(out, 0);
  return out;
}

Uint8List _hexToBytes(String hex) {
  if (hex.isEmpty) {
    throw ArgumentError('voice: hex string is empty');
  }
  if (hex.length % 2 != 0) {
    throw ArgumentError('voice: hex string has odd length ${hex.length}');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final ch = hex.substring(i * 2, i * 2 + 2);
    final v = int.tryParse(ch, radix: 16);
    if (v == null) {
      throw ArgumentError('voice: hex string contains non-hex char "$ch"');
    }
    out[i] = v;
  }
  return out;
}

String _bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

```
