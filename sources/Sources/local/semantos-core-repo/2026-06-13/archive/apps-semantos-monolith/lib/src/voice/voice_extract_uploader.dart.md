---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/voice/voice_extract_uploader.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.865584+00:00
---

# archive/apps-semantos-monolith/lib/src/voice/voice_extract_uploader.dart

```dart
// D-O5m.followup-3 — voice-extract multipart uploader.
//
// POSTs a [VoiceCommandRecording] to the brain's
// `/api/v1/voice-extract` endpoint:
//
//     POST /api/v1/voice-extract
//     Content-Type: multipart/form-data; boundary=<token>
//     Authorization: Bearer <hex64>
//     Body parts:
//       - audio:         raw audio bytes
//       - transcript:    JSON-encoded signed Transcript
//       - metadata:      JSON {visit_id, hat_context, client_correlation_id}
//       - sir_candidate: (Phase 2, optional) JSON-encoded Intent
//                        produced on-device by sir_extractor.dart
//
// When `sir_candidate` is present the brain skips its L0->L1 producer
// adapter and runs L2-L4 only against the supplied Intent.  When
// absent, the brain runs the full Phase 1 pipeline.
//
// Response (200): IntentResult JSON the brain produced after running
// the runtime/intent/ pipeline against the transcript text.
//
// Failure modes mirror the typed-error vocabulary at
// `runtime/semantos-brain/src/voice_extract_http.zig` so the UI can render
// specific recovery prompts.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'sir_extractor.dart';
import 'voice_session_service.dart';

/// Wire-shape companion to the multipart `metadata` part.
class VoiceExtractMetadata {
  final String visitId;
  final String hatContext;
  final String clientCorrelationId;

  const VoiceExtractMetadata({
    required this.visitId,
    required this.hatContext,
    required this.clientCorrelationId,
  });

  Map<String, dynamic> toJson() => {
        'visit_id': visitId,
        'hat_context': hatContext,
        'client_correlation_id': clientCorrelationId,
      };
}

/// Result type — typed branches the UI / outbox switch on.
sealed class VoiceExtractResult {
  const VoiceExtractResult();
}

/// 200 — brain ran the pipeline; the body carries the IntentResult.
class VoiceExtractSuccess extends VoiceExtractResult {
  /// Decoded IntentResult JSON — pass-through (no Dart type yet so the
  /// substrate stays loose during Phase 1; Phase 2 introduces a typed
  /// IntentResultDart class).
  final Map<String, dynamic> intentResultJson;

  /// Operator-readable summary the UI surfaces in the "Done" state.
  /// Computed from the IntentResult — best-effort; falls back to a
  /// generic message if the pipeline didn't surface a usable hint.
  final String operatorSummary;

  const VoiceExtractSuccess({
    required this.intentResultJson,
    required this.operatorSummary,
  });
}

/// 401/422/503 — brain rejected the call. The reason field carries the
/// canonical error code (e.g. `signature_invalid`, `pipeline_failed`).
class VoiceExtractFailed extends VoiceExtractResult {
  final String reason;
  final int statusCode;
  final String? message;
  const VoiceExtractFailed({
    required this.reason,
    required this.statusCode,
    this.message,
  });
}

/// Network unreachable — caller should enqueue to the outbox.
class VoiceExtractNetworkError extends VoiceExtractResult {
  final String message;
  const VoiceExtractNetworkError(this.message);
}

abstract class VoiceExtractUploader {
  Future<VoiceExtractResult> upload({
    required Uint8List audioBytes,
    required String mimeType,
    required Transcript transcript,
    required VoiceExtractMetadata metadata,
    Map<String, dynamic>? sirCandidate,
  });
}

/// Production uploader — Dio multipart POST.
class DioVoiceExtractUploader implements VoiceExtractUploader {
  final Dio _http;
  final String _baseUrl;
  final String Function() _bearer;

  DioVoiceExtractUploader({
    required Dio http,
    required String baseUrl,
    required String Function() bearer,
  })  : _http = http,
        _baseUrl = baseUrl,
        _bearer = bearer;

  @override
  Future<VoiceExtractResult> upload({
    required Uint8List audioBytes,
    required String mimeType,
    required Transcript transcript,
    required VoiceExtractMetadata metadata,
    Map<String, dynamic>? sirCandidate,
  }) async {
    if (audioBytes.length > 5 * 1024 * 1024) {
      return const VoiceExtractFailed(
        reason: 'too_large',
        statusCode: 413,
        message: 'audio blob exceeds 5 MiB cap',
      );
    }
    final form = FormData();
    form.files.add(MapEntry(
      'audio',
      MultipartFile.fromBytes(
        audioBytes,
        filename: _filenameForMime(mimeType),
      ),
    ));
    form.fields.add(MapEntry('transcript', jsonEncode(transcript.toJson())));
    form.fields.add(MapEntry('metadata', jsonEncode(metadata.toJson())));
    if (sirCandidate != null) {
      // Phase 2 — when the on-device extractor produced a valid
      // Intent, ship it as the sir_candidate part.  Encoding goes
      // through the canonical Intent ordering so the wire bytes
      // match what the brain expects byte-for-byte (asserted by
      // the cross-language SIR roundtrip fixture).
      form.fields.add(MapEntry('sir_candidate',
          encodeCanonicalIntent(sirCandidate)));
    }
    try {
      // Voice-extract runs a bun transcription script on the brain — allow 60s.
      final resp = await _http.post<Map<String, dynamic>>(
        '$_baseUrl/api/v1/voice-extract',
        data: form,
        options: Options(
          headers: {'Authorization': 'Bearer ${_bearer()}'},
          responseType: ResponseType.json,
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final code = resp.statusCode ?? 0;
      if (code == 200) {
        final body = resp.data ?? const <String, dynamic>{};
        final summary = _summaryFromIntentResult(body);
        return VoiceExtractSuccess(
          intentResultJson: body,
          operatorSummary: summary,
        );
      }
      final body = resp.data ?? const <String, dynamic>{};
      return VoiceExtractFailed(
        reason: (body['error'] ?? 'unknown_error').toString(),
        statusCode: code,
        message: body['message']?.toString(),
      );
    } on DioException catch (e) {
      return VoiceExtractNetworkError(e.message ?? 'network error');
    }
  }

  static String _filenameForMime(String mime) {
    if (mime.contains('m4a') || mime.contains('mp4')) return 'voice.m4a';
    if (mime.contains('wav')) return 'voice.wav';
    if (mime.contains('opus')) return 'voice.opus';
    if (mime.contains('webm')) return 'voice.webm';
    return 'voice.bin';
  }

  /// Heuristic: surface a one-line summary for the UI's Done state.
  /// The brain's IntentResult shape (runtime/intent/src/types.ts
  /// IntentResult) carries `uiHint` / `cell` / `kernelResult` /
  /// `rejection` — pull whichever is most useful. If we can't find a
  /// helpful nugget we fall back to a generic message rather than
  /// surfacing the raw JSON.
  static String _summaryFromIntentResult(Map<String, dynamic> r) {
    if (r['ok'] == false) {
      final rej = r['rejection'];
      if (rej is Map) {
        final stage = rej['stage'] ?? '?';
        final code = rej['code'] ?? '?';
        return 'Rejected at $stage stage ($code)';
      }
      return 'Voice command rejected';
    }
    final cell = r['cell'];
    if (cell is Map) {
      final id = cell['id'];
      if (id is String && id.isNotEmpty) return 'Cell $id written';
    }
    final hint = r['uiHint'];
    if (hint is Map) {
      final p = hint['presentation'];
      if (p is String && p.isNotEmpty) return 'Voice command processed ($p)';
    }
    return 'Voice command processed';
  }
}


```
