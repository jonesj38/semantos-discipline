---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/repl_client_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.923821+00:00
---

# archive/apps-semantos-monolith/test/repl/repl_client_test.dart

```dart
// D-O5m — repl_client.dart conformance test.
//
// Covers all four HTTP outcomes the Semantos Brain REPL surfaces (per
// runtime/semantos-brain/src/repl_http.zig + the loom-svelte client semantics):
//
//   - 200 OK  → ReplOk{result, exit}
//   - 401     → ReplUnauthorisedError
//   - 400     → ReplValidationError
//   - 503     → ReplBackendUnavailable
//
// Plus a network-error path (DioException) and the bearer-header
// propagation assertion.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/repl/repl_client.dart';
import 'package:semantos/src/repl/repl_errors.dart';

void main() {
  group('ReplClient.send', () {
    test('200 OK returns ReplOk with result + exit', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(json.encode({
          'result': 'job-1\tAlice\tlead\t2026-05-03',
          'exit': 'continue',
        })),
      );
      final dio = Dio()..httpClientAdapter = adapter;

      final client = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'a' * 64,
      );
      final resp = await client.send('find jobs');

      expect(resp.result, equals('job-1\tAlice\tlead\t2026-05-03'));
      expect(resp.exit, equals('continue'));
      expect(adapter.lastRequest?.uri.toString(),
          equals('https://oddjobtodd.info/api/v1/repl'));
      expect(adapter.lastRequest?.headers['authorization'],
          equals('Bearer ${'a' * 64}'));
    });

    test('401 throws ReplUnauthorisedError', () async {
      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 401,
          body: utf8.encode(
              json.encode({'error': 'session token rejected'})),
        );
      final client = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'b' * 64,
      );

      try {
        await client.send('find jobs');
        fail('expected ReplUnauthorisedError');
      } on ReplUnauthorisedError catch (e) {
        expect(e.reason, contains('session token rejected'));
      }
    });

    test('400 throws ReplValidationError with brain message', () async {
      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 400,
          body: utf8.encode(
              json.encode({'error': 'unknown verb: thunder'})),
        );
      final client = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'c' * 64,
      );

      try {
        await client.send('thunder');
        fail('expected ReplValidationError');
      } on ReplValidationError catch (e) {
        expect(e.message, contains('unknown verb'));
      }
    });

    test('503 throws ReplBackendUnavailable', () async {
      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 503,
          body: utf8.encode(json.encode({
            'error': 'REPL backend not enabled in this serve mode',
          })),
        );
      final client = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'd' * 64,
      );

      try {
        await client.send('status');
        fail('expected ReplBackendUnavailable');
      } on ReplBackendUnavailable catch (e) {
        expect(e.message, contains('not enabled'));
      }
    });

    test('connection error throws ReplError', () async {
      final dio = Dio()..httpClientAdapter = _ThrowingAdapter();
      final client = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'e' * 64,
      );
      try {
        await client.send('status');
        fail('expected ReplError');
      } on ReplError catch (e) {
        expect(e.message, contains('network error'));
      }
    });

    test('omits Authorization header when bearer is null', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(
            json.encode({'result': 'ok', 'exit': 'continue'})),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final client = ReplClient(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearerSource: () => null,
      );
      await client.send('status');
      expect(adapter.lastRequest?.headers['authorization'], isNull);
    });
  });
}

// ─── test helpers ────────────────────────────────────────────────────

class _StaticAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int> body;
  _StaticAdapter({required this.statusCode, required this.body});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(body, statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int> body;
  RequestOptions? lastRequest;
  _RecordingAdapter({required this.statusCode, required this.body});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromBytes(body, statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      message: 'simulated connection failure',
      type: DioExceptionType.connectionError,
    );
  }
}

```
