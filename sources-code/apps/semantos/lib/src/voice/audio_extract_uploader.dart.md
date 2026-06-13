---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/voice/audio_extract_uploader.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.110145+00:00
---

# apps/semantos/lib/src/voice/audio_extract_uploader.dart

```dart
// Betterment voice — audio-extract multipart uploader.
//
// Cartridge-neutral client for the brain's `/api/v1/audio-extract` endpoint
// (runtime/semantos-brain/src/audio_extract_http.zig). The betterment cartridge
// runs on the Flutter PWA, which can't run on-device inference, so a recorded
// voice note is uploaded to the brain, which transcribes it server-side via
// whisper.cpp and returns the text. Mirrors image_extract_uploader.dart.
//
//     POST /api/v1/audio-extract
//     Content-Type: multipart/form-data
//     Authorization: Bearer <hex64>
//     Body: one `audio` part (16kHz mono WAV) + optional `metadata`.
//
// Response (200): { turns:[{index,speaker,text}], rawText, source:"voice" }

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 16 MiB — matches DEFAULT_MAX_AUDIO_BYTES on the brain.
const int kMaxAudioBytes = 16 * 1024 * 1024;

class AudioExtractMetadata {
  final String? day;
  final String? clientCorrelationId;
  const AudioExtractMetadata({this.day, this.clientCorrelationId});

  Map<String, dynamic> toJson() => {
        if (day != null) 'day': day,
        if (clientCorrelationId != null) 'client_correlation_id': clientCorrelationId,
      };
}

sealed class AudioExtractResult {
  const AudioExtractResult();
}

class AudioExtractSuccess extends AudioExtractResult {
  final String rawText;
  const AudioExtractSuccess({required this.rawText});
}

class AudioExtractFailed extends AudioExtractResult {
  final String reason;
  final int statusCode;
  const AudioExtractFailed({required this.reason, required this.statusCode});
}

class AudioExtractNetworkError extends AudioExtractResult {
  final String message;
  const AudioExtractNetworkError(this.message);
}

abstract class AudioExtractUploader {
  Future<AudioExtractResult> upload({
    required Uint8List audioBytes,
    String mimeType = 'audio/wav',
    AudioExtractMetadata? metadata,
  });
}

/// Production uploader — Dio multipart POST.
class DioAudioExtractUploader implements AudioExtractUploader {
  final Dio _http;
  final String _baseUrl;
  final String Function() _bearer;

  DioAudioExtractUploader({
    required Dio http,
    required String baseUrl,
    required String Function() bearer,
  })  : _http = http,
        _baseUrl = baseUrl,
        _bearer = bearer;

  @override
  Future<AudioExtractResult> upload({
    required Uint8List audioBytes,
    String mimeType = 'audio/wav',
    AudioExtractMetadata? metadata,
  }) async {
    if (audioBytes.isEmpty) {
      return const AudioExtractFailed(reason: 'payload_invalid_format', statusCode: 400);
    }
    if (audioBytes.length > kMaxAudioBytes) {
      return const AudioExtractFailed(reason: 'too_large', statusCode: 413);
    }
    final form = FormData();
    form.files.add(MapEntry(
      'audio',
      MultipartFile.fromBytes(audioBytes, filename: 'voice.wav'),
    ));
    if (metadata != null) {
      form.fields.add(MapEntry('metadata', jsonEncode(metadata.toJson())));
    }
    try {
      final resp = await _http.post<Map<String, dynamic>>(
        '$_baseUrl/api/v1/audio-extract',
        data: form,
        options: Options(
          headers: {'Authorization': 'Bearer ${_bearer()}'},
          responseType: ResponseType.json,
          validateStatus: (_) => true,
          // Server-side whisper on the brain — allow generous time.
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
      final code = resp.statusCode ?? 0;
      final body = resp.data ?? const <String, dynamic>{};
      if (code == 200) {
        return AudioExtractSuccess(rawText: (body['rawText'] as String?) ?? '');
      }
      return AudioExtractFailed(
        reason: (body['error'] ?? 'unknown_error').toString(),
        statusCode: code,
      );
    } on DioException catch (e) {
      return AudioExtractNetworkError(e.message ?? 'network error');
    }
  }
}

```
