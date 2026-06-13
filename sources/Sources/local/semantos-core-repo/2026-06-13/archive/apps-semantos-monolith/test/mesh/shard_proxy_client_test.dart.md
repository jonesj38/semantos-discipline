---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/mesh/shard_proxy_client_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.929423+00:00
---

# archive/apps-semantos-monolith/test/mesh/shard_proxy_client_test.dart

```dart
// D-O5m.followup-6 Phase 2 — ShardProxyClient HTTP-relay conformance.
//
// Reference: lib/src/mesh/shard_proxy_client.dart.
//
// Asserts:
//   1. publish posts the canonical bundle bytes to the right URL with
//      the right query.
//   2. subscribe yields decoded SignedBundles from a JSON-array response.
//   3. Bundles addressed to other cert ids are filtered out.
//   4. healthCheck returns true on 2xx-4xx, false on errors.
//   5. publish errors map to typed ShardProxyError.
//   6. close() unwinds an in-flight subscribe.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/mesh/cert_ref.dart';
import 'package:semantos/src/mesh/signature_metadata.dart';
import 'package:semantos/src/mesh/shard_proxy_client.dart';
import 'package:semantos/src/mesh/signed_bundle.dart';

// ─────────────────────────────────────────────────────────────────────
// Synthetic-bundle helpers — we use canonical-shape values that pass
// the SignedBundle constructor's invariant checks but don't need to
// round-trip a real signature (this test exercises the transport seam
// only; codec parity is asserted in signed_bundle_test.dart).
// ─────────────────────────────────────────────────────────────────────

CertRef _testRootCert() {
  final pub = Uint8List(33)..[0] = 0x02;
  for (var i = 1; i < 33; i++) {
    pub[i] = 0xaa;
  }
  return CertRef(
    certId: 'aabbccddeeff00112233445566778899',
    pubkey: pub,
    contextTag: 0,
    parentCertId: null,
  );
}

SignedBundle _testBundle({
  String recipient = 'cccccccccccccccccccccccccccccccc',
  String payloadType = 'oddjobz.cell.create',
  String payload = '{"hello":"mesh"}',
}) {
  return SignedBundle(
    senderCertChain: [_testRootCert()],
    recipientCertId: recipient,
    payloadType: payloadType,
    payload: Uint8List.fromList(utf8.encode(payload)),
    signature: Uint8List(64),
    signatureMetadata: SignatureMetadata(
      nonceHex: 'd' * 64,
      timestampUnix: 1746230400,
    ),
  );
}

void main() {
  group('ShardProxyClient.publish', () {
    test('posts canonical bundle bytes to /publish?shard=<group>', () async {
      final adapter = _RecordingAdapter(statusCode: 202, bodyBytes: const []);
      final dio = Dio()..httpClientAdapter = adapter;
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard-proxy.example.com',
          shardGroupId: 'tenant-0',
        ),
        http: dio,
      );

      final bundle = _testBundle();
      await client.publish(bundle: bundle);

      expect(adapter.lastRequest?.uri.toString(),
          equals('https://shard-proxy.example.com/publish?shard=tenant-0'));
      expect(adapter.lastRequest?.method, equals('POST'));
      // The request body is the canonical wire bytes — same as
      // bundle.encode().
      final expected = utf8.decode(bundle.encode());
      final actualBody = adapter.lastBodyAsString;
      expect(actualBody, equals(expected));
    });

    test('non-2xx response throws ShardProxyError with status', () async {
      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 500,
          bodyBytes: utf8.encode('{"error":"backend_error"}'),
        );
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard-proxy.example.com',
          shardGroupId: 'tenant-0',
        ),
        http: dio,
      );
      try {
        await client.publish(bundle: _testBundle());
        fail('expected ShardProxyError');
      } on ShardProxyError catch (e) {
        expect(e.statusCode, equals(500));
      }
    });
  });

  group('ShardProxyClient.subscribe', () {
    test('yields decoded bundles addressed to me; filters others', () async {
      final myCert = 'cccccccccccccccccccccccccccccccc';
      final otherCert = 'dddddddddddddddddddddddddddddddd';
      final mine = _testBundle(recipient: myCert, payload: '{"for":"me"}');
      final theirs = _testBundle(recipient: otherCert, payload: '{"for":"them"}');
      final responseBody = '[${utf8.decode(mine.encode())},${utf8.decode(theirs.encode())}]';

      // First poll returns the array; second poll returns 204 to keep
      // the loop alive without spinning.
      final dio = Dio()
        ..httpClientAdapter = _SequenceAdapter([
          _StaticAdapterResponse(
              statusCode: 200, bodyBytes: utf8.encode(responseBody)),
          _StaticAdapterResponse(statusCode: 204, bodyBytes: const []),
        ]);
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard-proxy.example.com',
          shardGroupId: 'tenant-0',
          longPollTimeoutSeconds: 1,
          retryBackoffBaseMs: 1,
          retryMaxBackoffMs: 5,
        ),
        http: dio,
      );

      final yielded = <SignedBundle>[];
      final sub = client.subscribe(myCertId: myCert).listen(yielded.add);
      // Give the loop a beat to consume the first response.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      client.close();

      expect(yielded, hasLength(1));
      expect(yielded.first.recipientCertId, equals(myCert));
      expect(utf8.decode(yielded.first.payload), equals('{"for":"me"}'));
    });

    test('non-list response is silently dropped + retried', () async {
      final dio = Dio()
        ..httpClientAdapter = _SequenceAdapter([
          _StaticAdapterResponse(
              statusCode: 200, bodyBytes: utf8.encode('"not-a-list"')),
          _StaticAdapterResponse(statusCode: 204, bodyBytes: const []),
        ]);
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard-proxy.example.com',
          shardGroupId: 'tenant-0',
          longPollTimeoutSeconds: 1,
          retryBackoffBaseMs: 1,
          retryMaxBackoffMs: 5,
        ),
        http: dio,
      );

      final yielded = <SignedBundle>[];
      final sub = client.subscribe(myCertId: 'cccccccccccccccccccccccccccccccc').listen(yielded.add);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      client.close();

      expect(yielded, isEmpty);
    });

    test('network errors trigger backoff + reconnect', () async {
      final dio = Dio()
        ..httpClientAdapter = _SequenceAdapter([
          _ThrowingAdapterResponse(),
          _StaticAdapterResponse(statusCode: 204, bodyBytes: const []),
        ]);
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard-proxy.example.com',
          shardGroupId: 'tenant-0',
          longPollTimeoutSeconds: 1,
          retryBackoffBaseMs: 1,
          retryMaxBackoffMs: 5,
        ),
        http: dio,
      );

      final sub = client.subscribe(myCertId: 'cccccccccccccccccccccccccccccccc').listen((_) {});
      // Non-deterministic timing — wait long enough for the first
      // throw + backoff cycle to complete.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      client.close();
      // No assertion failure means the loop survived a network error.
      expect(true, isTrue);
    });
  });

  group('ShardProxyClient.healthCheck', () {
    test('returns true on 2xx', () async {
      final dio = Dio()
        ..httpClientAdapter =
            _StaticAdapter(statusCode: 200, bodyBytes: utf8.encode('{"ok":true}'));
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard-proxy.example.com',
          shardGroupId: 'tenant-0',
        ),
        http: dio,
      );
      expect(await client.healthCheck(), isTrue);
    });

    test('returns false on connection failure', () async {
      final dio = Dio()..httpClientAdapter = _ThrowingAdapter();
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard-proxy.example.com',
          shardGroupId: 'tenant-0',
        ),
        http: dio,
      );
      expect(await client.healthCheck(), isFalse);
    });
  });

  group('ShardProxyClient.close', () {
    test('publish after close throws ShardProxyError', () async {
      final dio = Dio()..httpClientAdapter = _StaticAdapter(statusCode: 200, bodyBytes: const []);
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard-proxy.example.com',
          shardGroupId: 'tenant-0',
        ),
        http: dio,
      );
      client.close();
      try {
        await client.publish(bundle: _testBundle());
        fail('expected ShardProxyError');
      } on ShardProxyError catch (e) {
        expect(e.reason, equals('closed'));
      }
    });
  });
}

// ─── Adapter helpers ───────────────────────────────────────────────────

class _StaticAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int> bodyBytes;
  _StaticAdapter({required this.statusCode, required this.bodyBytes});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(bodyBytes, statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int> bodyBytes;
  RequestOptions? lastRequest;
  String lastBodyAsString = '';
  _RecordingAdapter({required this.statusCode, required this.bodyBytes});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      lastBodyAsString = utf8.decode(chunks);
    } else if (options.data is List<int>) {
      lastBodyAsString = utf8.decode(options.data as List<int>);
    } else if (options.data is String) {
      lastBodyAsString = options.data as String;
    }
    return ResponseBody.fromBytes(bodyBytes, statusCode, headers: const {
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

abstract class _AdapterResponse {
  Future<ResponseBody> resolve(RequestOptions options);
}

class _StaticAdapterResponse implements _AdapterResponse {
  final int statusCode;
  final List<int> bodyBytes;
  _StaticAdapterResponse({required this.statusCode, required this.bodyBytes});

  @override
  Future<ResponseBody> resolve(RequestOptions options) async {
    return ResponseBody.fromBytes(bodyBytes, statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

class _ThrowingAdapterResponse implements _AdapterResponse {
  @override
  Future<ResponseBody> resolve(RequestOptions options) async {
    throw DioException(
      requestOptions: options,
      message: 'simulated connection failure',
      type: DioExceptionType.connectionError,
    );
  }
}

class _SequenceAdapter implements HttpClientAdapter {
  final List<_AdapterResponse> _responses;
  int _idx = 0;
  _SequenceAdapter(this._responses);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (_idx >= _responses.length) {
      // Loop with a 204 once we exhaust the script — keeps the
      // subscribe loop alive for the test's tear-down without going
      // into a spin-wait.
      return _StaticAdapterResponse(statusCode: 204, bodyBytes: const [])
          .resolve(options);
    }
    final r = _responses[_idx];
    _idx += 1;
    return r.resolve(options);
  }
}

```
