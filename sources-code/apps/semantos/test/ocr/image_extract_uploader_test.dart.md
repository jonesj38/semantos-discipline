---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/ocr/image_extract_uploader_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.131101+00:00
---

# apps/semantos/test/ocr/image_extract_uploader_test.dart

```dart
// Tests for the cartridge-neutral OCR image uploader.
//
// Uses a fake Dio HttpClientAdapter (mirrors test/brain_info_test.dart) to
// assert: success-path turn parsing, the client-side size/page guards (which
// short-circuit before any HTTP), error-status mapping, and network errors.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/ocr/image_extract_uploader.dart';

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
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      '{"turns":[],"rawText":"","pageCount":1}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      message: 'connection refused',
      type: DioExceptionType.connectionError,
    );
  }

  @override
  void close({bool force = false}) {}
}

DioImageExtractUploader _uploader(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return DioImageExtractUploader(
    http: dio,
    baseUrl: 'http://brain.test',
    bearer: () => 'a' * 64,
  );
}

OcrImage _img([int bytes = 8]) =>
    OcrImage(bytes: Uint8List(bytes), mimeType: 'image/jpeg');

void main() {
  test('200 → maps turns + rawText into ImageExtractSuccess', () async {
    final adapter = _FixedJsonAdapter(
      '{"turns":['
      '{"index":0,"speaker":"self","text":"I feel tense","sourcePageRef":"page:1"},'
      '{"index":1,"speaker":"self","text":"I release it","sourcePageRef":"page:1","confidence":0.9}'
      '],"rawText":"I feel tense\\n\\nI release it","pageCount":1}',
    );
    final res = await _uploader(adapter).upload(images: [_img()]);
    expect(res, isA<ImageExtractSuccess>());
    final ok = res as ImageExtractSuccess;
    expect(ok.turns, hasLength(2));
    expect(ok.turns[0].index, 0);
    expect(ok.turns[0].text, 'I feel tense');
    expect(ok.turns[0].sourcePageRef, 'page:1');
    expect(ok.turns[1].confidence, 0.9);
    expect(ok.rawText, 'I feel tense\n\nI release it');
    expect(ok.pageCount, 1);
  });

  test('empty image list → 400 without hitting the network', () async {
    final adapter = _FixedJsonAdapter('{}');
    final res = await _uploader(adapter).upload(images: const []);
    expect(res, isA<ImageExtractFailed>());
    expect((res as ImageExtractFailed).statusCode, 400);
    expect(adapter.calls, 0);
  });

  test('too many pages → 413 without hitting the network', () async {
    final adapter = _FixedJsonAdapter('{}');
    final res = await _uploader(adapter).upload(
      images: List.generate(kMaxPages + 1, (_) => _img()),
    );
    expect(res, isA<ImageExtractFailed>());
    expect((res as ImageExtractFailed).reason, 'too_large');
    expect(adapter.calls, 0);
  });

  test('oversized image → 413 without hitting the network', () async {
    final adapter = _FixedJsonAdapter('{}');
    final res =
        await _uploader(adapter).upload(images: [_img(kMaxImageBytes + 1)]);
    expect(res, isA<ImageExtractFailed>());
    expect((res as ImageExtractFailed).statusCode, 413);
    expect(adapter.calls, 0);
  });

  test('non-200 → ImageExtractFailed with the brain error code', () async {
    final adapter = _FixedJsonAdapter('{"error":"pipeline_failed"}', status: 422);
    final res = await _uploader(adapter).upload(images: [_img()]);
    expect(res, isA<ImageExtractFailed>());
    final f = res as ImageExtractFailed;
    expect(f.reason, 'pipeline_failed');
    expect(f.statusCode, 422);
  });

  test('network failure → ImageExtractNetworkError', () async {
    final res = await _uploader(_ThrowingAdapter()).upload(images: [_img()]);
    expect(res, isA<ImageExtractNetworkError>());
  });

  test('BYOK apiKey + model are sent as multipart fields when provided', () async {
    final adapter = _CapturingAdapter();
    await _uploader(adapter).upload(
      images: [_img()],
      apiKey: 'sk-byok-xyz',
      model: 'claude-haiku-4-5',
    );
    final fields = (adapter.lastOptions!.data as FormData).fields;
    expect(fields.any((e) => e.key == 'api_key' && e.value == 'sk-byok-xyz'), isTrue);
    expect(fields.any((e) => e.key == 'model' && e.value == 'claude-haiku-4-5'), isTrue);
  });

  test('omits BYOK fields when not provided', () async {
    final adapter = _CapturingAdapter();
    await _uploader(adapter).upload(images: [_img()]);
    final fields = (adapter.lastOptions!.data as FormData).fields;
    expect(fields.any((e) => e.key == 'api_key'), isFalse);
    expect(fields.any((e) => e.key == 'model'), isFalse);
  });
}

```
