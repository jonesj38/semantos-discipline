---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/voice/voice_extract_uploader_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.909279+00:00
---

# archive/apps-semantos-monolith/test/voice/voice_extract_uploader_test.dart

```dart
// D-O5m.followup-3 Phase 1 — voice_extract_uploader unit tests.
//
// Asserts the multipart POST shape + the typed result mapping.  Uses
// Dio's `httpClientAdapter` injection seam so the test runs without
// network.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/voice/voice_extract_uploader.dart';
import 'package:semantos/src/voice/voice_session_service.dart';

class _StubAdapter implements HttpClientAdapter {
  int statusCode;
  Map<String, dynamic> body;
  String? lastUrl;
  String? lastBearer;
  RequestOptions? lastOptions;
  String lastBody = '';
  bool throwsOnSend;

  _StubAdapter({
    this.statusCode = 200,
    this.body = const {'ok': true, 'cell': {'id': 'cell-x'}},
    this.throwsOnSend = false,
  });

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    if (throwsOnSend) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'connection refused',
      );
    }
    lastUrl = options.uri.toString();
    lastOptions = options;
    final auth = options.headers['Authorization'];
    if (auth is String) lastBearer = auth;
    // Drain the request stream and capture the multipart body so
    // tests can assert which parts were included.
    if (requestStream != null) {
      final chunks = <int>[];
      await for (final c in requestStream) {
        chunks.addAll(c);
      }
      lastBody = String.fromCharCodes(chunks);
    }
    final json = '{"ok":${body['ok']}'
        '${body['cell'] != null ? ',"cell":${_jsonEncodeMinimal(body['cell'])}' : ''}'
        '${body['error'] != null ? ',"error":"${body['error']}"' : ''}'
        '}';
    return ResponseBody.fromString(
      json,
      statusCode,
      headers: {'content-type': const ['application/json']},
    );
  }

  static String _jsonEncodeMinimal(Object? o) {
    if (o is Map) {
      final entries = o.entries
          .map((e) => '"${e.key}":${_jsonEncodeMinimal(e.value)}')
          .join(',');
      return '{$entries}';
    }
    if (o is String) return '"$o"';
    if (o == null) return 'null';
    return o.toString();
  }
}

Transcript _stubTranscript() {
  return Transcript(
    id: 't1',
    sessionId: 's1',
    certId: 'a' * 64,
    sequence: 0,
    text: 'job 12345 is invoiced',
    timestampMs: 1700000000000,
    signature: VoiceSignature(
      bytes: Uint8List(64),
      algorithm: 'ecdsa-secp256k1-sha256-compact',
      keyId: 'a' * 64,
    ),
  );
}

const _meta = VoiceExtractMetadata(
  visitId: 'v1',
  hatContext: 'operator',
  clientCorrelationId: 'corr-1',
);

void main() {
  group('DioVoiceExtractUploader', () {
    test('posts multipart and returns success on 200', () async {
      final dio = Dio();
      final stub = _StubAdapter(statusCode: 200, body: {
        'ok': true,
        'cell': {'id': 'voice-cell-corr-1'}
      });
      dio.httpClientAdapter = stub;
      final uploader = DioVoiceExtractUploader(
        http: dio,
        baseUrl: 'https://brain.local',
        bearer: () => 'b' * 64,
      );
      final r = await uploader.upload(
        audioBytes: Uint8List(2048),
        mimeType: 'audio/wav',
        transcript: _stubTranscript(),
        metadata: _meta,
      );
      expect(r, isA<VoiceExtractSuccess>());
      final s = r as VoiceExtractSuccess;
      expect(s.intentResultJson['ok'], isTrue);
      expect(s.operatorSummary, contains('voice-cell-corr-1'));
      expect(stub.lastUrl, equals('https://brain.local/api/v1/voice-extract'));
      expect(stub.lastBearer, equals('Bearer ${'b' * 64}'));
    });

    test('returns failed on 401 cert_unknown', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter(
        statusCode: 401,
        body: const {'ok': false, 'error': 'cert_unknown'},
      );
      final uploader = DioVoiceExtractUploader(
        http: dio,
        baseUrl: 'https://brain.local',
        bearer: () => 'b' * 64,
      );
      final r = await uploader.upload(
        audioBytes: Uint8List(2048),
        mimeType: 'audio/wav',
        transcript: _stubTranscript(),
        metadata: _meta,
      );
      expect(r, isA<VoiceExtractFailed>());
      final f = r as VoiceExtractFailed;
      expect(f.statusCode, equals(401));
      expect(f.reason, equals('cert_unknown'));
    });

    test('returns network error on Dio connection failure', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter(throwsOnSend: true);
      final uploader = DioVoiceExtractUploader(
        http: dio,
        baseUrl: 'https://brain.local',
        bearer: () => 'b' * 64,
      );
      final r = await uploader.upload(
        audioBytes: Uint8List(2048),
        mimeType: 'audio/wav',
        transcript: _stubTranscript(),
        metadata: _meta,
      );
      expect(r, isA<VoiceExtractNetworkError>());
    });

    test('rejects audio larger than 5 MiB', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter();
      final uploader = DioVoiceExtractUploader(
        http: dio,
        baseUrl: 'https://brain.local',
        bearer: () => 'b' * 64,
      );
      final r = await uploader.upload(
        audioBytes: Uint8List(6 * 1024 * 1024),
        mimeType: 'audio/wav',
        transcript: _stubTranscript(),
        metadata: _meta,
      );
      expect(r, isA<VoiceExtractFailed>());
      final f = r as VoiceExtractFailed;
      expect(f.statusCode, equals(413));
      expect(f.reason, equals('too_large'));
    });

    test('returns failed on 422 pipeline_failed', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter(
        statusCode: 422,
        body: const {'ok': false, 'error': 'pipeline_failed'},
      );
      final uploader = DioVoiceExtractUploader(
        http: dio,
        baseUrl: 'https://brain.local',
        bearer: () => 'b' * 64,
      );
      final r = await uploader.upload(
        audioBytes: Uint8List(2048),
        mimeType: 'audio/wav',
        transcript: _stubTranscript(),
        metadata: _meta,
      );
      expect(r, isA<VoiceExtractFailed>());
      expect((r as VoiceExtractFailed).reason, equals('pipeline_failed'));
    });

    // ── Phase 2 — sir_candidate multipart part ─────────────────────────

    test('Phase 2: includes sir_candidate part when supplied',
        () async {
      final dio = Dio();
      final stub = _StubAdapter(statusCode: 200, body: {
        'ok': true,
        'cell': {'id': 'voice-cell-corr-1'}
      });
      dio.httpClientAdapter = stub;
      final uploader = DioVoiceExtractUploader(
        http: dio,
        baseUrl: 'https://brain.local',
        bearer: () => 'b' * 64,
      );
      final candidate = <String, dynamic>{
        'id': 'i-001',
        'summary': 'job 12345 invoiced',
        'category': {'lexicon': 'trades', 'category': 'invoice'},
        'taxonomy': {'what': 'jobs', 'how': 'transition', 'why': 'close-out'},
        'action': 'invoice',
        'constraints': const [],
        'confidence': 0.9,
        'source': 'voice',
      };
      final r = await uploader.upload(
        audioBytes: Uint8List(2048),
        mimeType: 'audio/wav',
        transcript: _stubTranscript(),
        metadata: _meta,
        sirCandidate: candidate,
      );
      expect(r, isA<VoiceExtractSuccess>());
      expect(stub.lastBody, contains('name="sir_candidate"'));
      expect(stub.lastBody, contains('"action":"invoice"'));
    });

    test('Phase 2: omits sir_candidate part when null (Phase 1 fallback)',
        () async {
      final dio = Dio();
      final stub = _StubAdapter();
      dio.httpClientAdapter = stub;
      final uploader = DioVoiceExtractUploader(
        http: dio,
        baseUrl: 'https://brain.local',
        bearer: () => 'b' * 64,
      );
      final r = await uploader.upload(
        audioBytes: Uint8List(2048),
        mimeType: 'audio/wav',
        transcript: _stubTranscript(),
        metadata: _meta,
        // sirCandidate: null
      );
      expect(r, isA<VoiceExtractSuccess>());
      expect(stub.lastBody.contains('name="sir_candidate"'), isFalse);
    });

    test('Phase 2: sir_candidate body is canonicalised Intent JSON',
        () async {
      // Deliberately pass keys out of order; the wire payload must
      // be byte-identical to what the brain expects.
      final dio = Dio();
      final stub = _StubAdapter();
      dio.httpClientAdapter = stub;
      final uploader = DioVoiceExtractUploader(
        http: dio,
        baseUrl: 'https://brain.local',
        bearer: () => 'b' * 64,
      );
      final candidate = <String, dynamic>{
        'source': 'voice',
        'confidence': 0.9,
        'action': 'invoice',
        'constraints': const [],
        'taxonomy': {'what': 'jobs', 'how': 'transition', 'why': 'close-out'},
        'category': {'lexicon': 'trades', 'category': 'invoice'},
        'summary': 'job 12345 invoiced',
        'id': 'i-001',
      };
      await uploader.upload(
        audioBytes: Uint8List(2048),
        mimeType: 'audio/wav',
        transcript: _stubTranscript(),
        metadata: _meta,
        sirCandidate: candidate,
      );
      // Canonical order from sir_extractor.dart::canonicaliseIntent
      // -> id first, source last among populated.
      final body = stub.lastBody;
      final idx = body.indexOf('"id":"i-001"');
      final sourceIdx = body.indexOf('"source":"voice"');
      expect(idx, greaterThanOrEqualTo(0));
      expect(sourceIdx > idx, isTrue);
    });
  });
}

```
