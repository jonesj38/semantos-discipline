---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/voice/audio_extract_uploader_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.128013+00:00
---

# apps/semantos/test/voice/audio_extract_uploader_test.dart

```dart
// Tests for the brain audio-extract (voice → server-side whisper) uploader.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/voice/audio_extract_uploader.dart';

class _FixedJsonAdapter implements HttpClientAdapter {
  final String body;
  final int status;
  int calls = 0;
  _FixedJsonAdapter(this.body, {this.status = 200});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(body, status, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<dynamic>? c) async {
    throw DioException(requestOptions: o, message: 'offline', type: DioExceptionType.connectionError);
  }

  @override
  void close({bool force = false}) {}
}

DioAudioExtractUploader _uploader(HttpClientAdapter a) {
  final dio = Dio()..httpClientAdapter = a;
  return DioAudioExtractUploader(http: dio, baseUrl: 'http://brain.test', bearer: () => 'a' * 64);
}

Uint8List _wav([int n = 64]) => Uint8List(n);

void main() {
  test('200 → AudioExtractSuccess with the transcript', () async {
    final res = await _uploader(_FixedJsonAdapter(
      '{"turns":[{"index":0,"speaker":"self","text":"I release the week"}],"rawText":"I release the week","source":"voice"}',
    )).upload(audioBytes: _wav());
    expect(res, isA<AudioExtractSuccess>());
    expect((res as AudioExtractSuccess).rawText, 'I release the week');
  });

  test('empty audio → 400 without hitting the network', () async {
    final a = _FixedJsonAdapter('{}');
    final res = await _uploader(a).upload(audioBytes: Uint8List(0));
    expect(res, isA<AudioExtractFailed>());
    expect((res as AudioExtractFailed).statusCode, 400);
    expect(a.calls, 0);
  });

  test('oversized audio → 413 without hitting the network', () async {
    final a = _FixedJsonAdapter('{}');
    final res = await _uploader(a).upload(audioBytes: Uint8List(kMaxAudioBytes + 1));
    expect(res, isA<AudioExtractFailed>());
    expect((res as AudioExtractFailed).statusCode, 413);
    expect(a.calls, 0);
  });

  test('non-200 → AudioExtractFailed with the brain error', () async {
    final res = await _uploader(_FixedJsonAdapter('{"error":"pipeline_failed"}', status: 422))
        .upload(audioBytes: _wav());
    expect(res, isA<AudioExtractFailed>());
    final f = res as AudioExtractFailed;
    expect(f.reason, 'pipeline_failed');
    expect(f.statusCode, 422);
  });

  test('network failure → AudioExtractNetworkError', () async {
    final res = await _uploader(_ThrowingAdapter()).upload(audioBytes: _wav());
    expect(res, isA<AudioExtractNetworkError>());
  });
}

```
