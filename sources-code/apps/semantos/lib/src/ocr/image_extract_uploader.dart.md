---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/ocr/image_extract_uploader.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.119324+00:00
---

# apps/semantos/lib/src/ocr/image_extract_uploader.dart

```dart
// Betterment OCR — image-extract multipart uploader.
//
// Cartridge-neutral client for the brain's `/api/v1/image-extract` endpoint
// (runtime/semantos-brain/src/image_extract_http.zig). POSTs one or more page
// images and gets back the handwriting transcription structured as chronological
// turns + a joined rawText. Mirrors voice_extract_uploader.dart's shape (Dio
// multipart, bearer, 60s, typed sealed result).
//
//     POST /api/v1/image-extract
//     Content-Type: multipart/form-data; boundary=<token>
//     Authorization: Bearer <hex64>
//     Body parts: one `image` part per page (+ optional `metadata` JSON)
//
// Response (200): { turns: [{index, speaker, text, sourcePageRef, confidence?}],
//                   rawText, pageCount }

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 4 MiB — matches DEFAULT_MAX_IMAGE_BYTES on the brain. Clients downscale
/// (image_picker quality/maxWidth) so a page stays well under this.
const int kMaxImageBytes = 4 * 1024 * 1024;

/// Max pages per request — matches MAX_PAGES on the brain.
const int kMaxPages = 4;

/// One OCR-extracted turn (parallels the brain's ExtractedTurn / ReleaseTurn).
class OcrTurn {
  final int index;
  final String text;
  final String speaker;
  final String? sourcePageRef;
  final double? confidence;

  const OcrTurn({
    required this.index,
    required this.text,
    this.speaker = 'self',
    this.sourcePageRef,
    this.confidence,
  });

  factory OcrTurn.fromJson(Map<String, dynamic> j) => OcrTurn(
        index: (j['index'] as num?)?.toInt() ?? 0,
        text: (j['text'] as String?) ?? '',
        speaker: (j['speaker'] as String?) ?? 'self',
        sourcePageRef: j['sourcePageRef'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'speaker': speaker,
        'text': text,
        if (sourcePageRef != null) 'sourcePageRef': sourcePageRef,
        if (confidence != null) 'confidence': confidence,
      };
}

/// One page to upload: raw bytes + MIME type.
class OcrImage {
  final Uint8List bytes;
  final String mimeType;
  const OcrImage({required this.bytes, required this.mimeType});
}

/// Optional metadata part (e.g. local day, correlation id).
class ImageExtractMetadata {
  final String day;
  final String? clientCorrelationId;
  const ImageExtractMetadata({required this.day, this.clientCorrelationId});

  Map<String, dynamic> toJson() => {
        'day': day,
        if (clientCorrelationId != null)
          'client_correlation_id': clientCorrelationId,
      };
}

/// Typed result branches the UI switches on.
sealed class ImageExtractResult {
  const ImageExtractResult();
}

/// 200 — OCR succeeded; carries the extracted turns + joined transcript.
class ImageExtractSuccess extends ImageExtractResult {
  final List<OcrTurn> turns;
  final String rawText;
  final int pageCount;
  const ImageExtractSuccess({
    required this.turns,
    required this.rawText,
    required this.pageCount,
  });
}

/// 4xx/5xx — brain rejected the call (e.g. too_large, pipeline_failed,
/// bun_unavailable, bearer_invalid).
class ImageExtractFailed extends ImageExtractResult {
  final String reason;
  final int statusCode;
  final String? message;
  const ImageExtractFailed({
    required this.reason,
    required this.statusCode,
    this.message,
  });
}

/// Network unreachable.
class ImageExtractNetworkError extends ImageExtractResult {
  final String message;
  const ImageExtractNetworkError(this.message);
}

abstract class ImageExtractUploader {
  Future<ImageExtractResult> upload({
    required List<OcrImage> images,
    ImageExtractMetadata? metadata,
    // BYOK overrides (per-request). When set, sent as multipart `api_key`/`model`
    // so the brain runs the OCR subprocess with the operator's own key/model.
    // Never logged.
    String? apiKey,
    String? model,
  });
}

/// Production uploader — Dio multipart POST.
class DioImageExtractUploader implements ImageExtractUploader {
  final Dio _http;
  final String _baseUrl;
  final String Function() _bearer;

  DioImageExtractUploader({
    required Dio http,
    required String baseUrl,
    required String Function() bearer,
  })  : _http = http,
        _baseUrl = baseUrl,
        _bearer = bearer;

  @override
  Future<ImageExtractResult> upload({
    required List<OcrImage> images,
    ImageExtractMetadata? metadata,
    String? apiKey,
    String? model,
  }) async {
    if (images.isEmpty) {
      return const ImageExtractFailed(
        reason: 'payload_invalid_format',
        statusCode: 400,
        message: 'no images',
      );
    }
    if (images.length > kMaxPages) {
      return ImageExtractFailed(
        reason: 'too_large',
        statusCode: 413,
        message: 'too many pages (${images.length} > $kMaxPages)',
      );
    }
    for (final img in images) {
      if (img.bytes.length > kMaxImageBytes) {
        return const ImageExtractFailed(
          reason: 'too_large',
          statusCode: 413,
          message: 'image exceeds 4 MiB cap',
        );
      }
    }

    final form = FormData();
    for (var i = 0; i < images.length; i++) {
      form.files.add(MapEntry(
        'image',
        MultipartFile.fromBytes(
          images[i].bytes,
          filename: 'page${i + 1}.${_extForMime(images[i].mimeType)}',
        ),
      ));
    }
    if (metadata != null) {
      form.fields.add(MapEntry('metadata', jsonEncode(metadata.toJson())));
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      form.fields.add(MapEntry('api_key', apiKey));
    }
    if (model != null && model.isNotEmpty) {
      form.fields.add(MapEntry('model', model));
    }

    try {
      final resp = await _http.post<Map<String, dynamic>>(
        '$_baseUrl/api/v1/image-extract',
        data: form,
        options: Options(
          headers: {'Authorization': 'Bearer ${_bearer()}'},
          responseType: ResponseType.json,
          validateStatus: (_) => true,
          // Claude vision over the brain shell-out — allow generous time.
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final code = resp.statusCode ?? 0;
      final body = resp.data ?? const <String, dynamic>{};
      if (code == 200) {
        final rawTurns = (body['turns'] as List?) ?? const [];
        final turns = rawTurns
            .whereType<Map>()
            .map((m) => OcrTurn.fromJson(m.cast<String, dynamic>()))
            .toList();
        return ImageExtractSuccess(
          turns: turns,
          rawText: (body['rawText'] as String?) ?? '',
          pageCount: (body['pageCount'] as num?)?.toInt() ?? images.length,
        );
      }
      return ImageExtractFailed(
        reason: (body['error'] ?? 'unknown_error').toString(),
        statusCode: code,
        message: body['hint']?.toString() ?? body['message']?.toString(),
      );
    } on DioException catch (e) {
      return ImageExtractNetworkError(e.message ?? 'network error');
    }
  }

  static String _extForMime(String mime) {
    if (mime.contains('png')) return 'png';
    if (mime.contains('webp')) return 'webp';
    if (mime.contains('gif')) return 'gif';
    return 'jpg';
  }
}

```
