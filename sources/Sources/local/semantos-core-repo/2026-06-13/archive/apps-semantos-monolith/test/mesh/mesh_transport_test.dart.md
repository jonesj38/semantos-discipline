---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/mesh/mesh_transport_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.929712+00:00
---

# archive/apps-semantos-monolith/test/mesh/mesh_transport_test.dart

```dart
// D-O5m.followup-6 Phase 2 — MeshTransport seam conformance.
//
// Reference: lib/src/mesh/mesh_transport.dart.
//
// Asserts:
//   1. ShardProxyMeshTransport.send happy path → MeshSent.
//   2. ShardProxyMeshTransport.send network error → MeshTransportUnavailable.
//   3. HttpReplFallbackTransport routes attachment → uploader.
//   4. HttpReplFallbackTransport routes voice-extract → voice uploader.
//   5. HttpReplFallbackTransport routes cell.create → REPL.
//   6. Factory: shard-proxy reachable → ShardProxyMeshTransport.
//   7. Factory: shard-proxy unreachable → fallback transport.
//   8. Factory: shard-proxy not configured → fallback transport.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/mesh/cert_ref.dart';
import 'package:semantos/src/mesh/mesh_transport.dart';
import 'package:semantos/src/mesh/shard_proxy_client.dart';
import 'package:semantos/src/mesh/signature_metadata.dart';
import 'package:semantos/src/mesh/signed_bundle.dart';
import 'package:semantos/src/outbox/outbox_service.dart';
import 'package:semantos/src/repl/repl_client.dart';
import 'package:semantos/src/repl/repl_errors.dart';

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
  String payloadType = 'oddjobz.cell.create',
  String payload = '{"cmd":"create job"}',
}) {
  return SignedBundle(
    senderCertChain: [_testRootCert()],
    recipientCertId: 'cccccccccccccccccccccccccccccccc',
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
  group('ShardProxyMeshTransport', () {
    test('send happy path returns MeshSent', () async {
      final dio = Dio()
        ..httpClientAdapter =
            _StaticAdapter(statusCode: 202, bodyBytes: const []);
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard.example.com',
          shardGroupId: 't',
        ),
        http: dio,
      );
      final transport = ShardProxyMeshTransport(
        client: client,
        myCertId: 'aabbccddeeff00112233445566778899',
      );
      final result = await transport.send(_testBundle());
      expect(result, isA<MeshSent>());
      expect(transport.label, equals('shard-proxy'));
    });

    test('send network error returns MeshTransportUnavailable', () async {
      final dio = Dio()..httpClientAdapter = _ThrowingAdapter();
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard.example.com',
          shardGroupId: 't',
        ),
        http: dio,
      );
      final transport = ShardProxyMeshTransport(
        client: client,
        myCertId: 'aabbccddeeff00112233445566778899',
      );
      final result = await transport.send(_testBundle());
      expect(result, isA<MeshTransportUnavailable>());
    });
  });

  group('HttpReplFallbackTransport', () {
    test('attachment payload_type routes to attachment uploader', () async {
      final uploader = _StubAttachmentUploader();
      final transport = HttpReplFallbackTransport(
        adapters: HttpReplFallbackAdapters(
          attachmentUploader: uploader,
          resolveAttachmentBlob: (_) => File('/dev/null'),
          extractMetadataJson: (_) => '{"meta":"data"}',
        ),
      );
      final bundle = _testBundle(
          payloadType: payloadTypeAttachmentCreate, payload: '{}');
      final result = await transport.send(bundle);
      expect(result, isA<MeshSent>());
      expect(uploader.calls, equals(1));
      expect(uploader.lastMetadata, equals('{"meta":"data"}'));
    });

    test('voice-extract payload_type routes to voice uploader', () async {
      final uploader = _StubVoiceUploader();
      final transport = HttpReplFallbackTransport(
        adapters: HttpReplFallbackAdapters(
          voiceUploader: uploader,
          resolveVoiceBlob: (_) => File('/dev/null'),
          extractMetadataJson: (_) => '{"transcript":"hi"}',
        ),
      );
      final bundle = _testBundle(
          payloadType: payloadTypeVoiceExtract, payload: '{}');
      final result = await transport.send(bundle);
      expect(result, isA<MeshSent>());
      expect(uploader.calls, equals(1));
    });

    test('cell.create payload_type routes to REPL', () async {
      final repl = _StubReplClient();
      final transport = HttpReplFallbackTransport(
        adapters: HttpReplFallbackAdapters(
          replClient: repl,
          extractReplCommand: (_) => 'create job alice',
        ),
      );
      final bundle = _testBundle(
          payloadType: payloadTypeCellCreate, payload: '{}');
      final result = await transport.send(bundle);
      expect(result, isA<MeshSent>());
      expect(repl.lastCommand, equals('create job alice'));
    });

    test('attachment kind without uploader returns Unavailable', () async {
      final transport = HttpReplFallbackTransport(
        adapters: const HttpReplFallbackAdapters(),
      );
      final bundle = _testBundle(
          payloadType: payloadTypeAttachmentCreate, payload: '{}');
      final result = await transport.send(bundle);
      expect(result, isA<MeshTransportUnavailable>());
      final unavail = result as MeshTransportUnavailable;
      expect(unavail.reason, contains('attachment'));
    });

    test('REPL 401 maps to MeshSendFailed with statusCode', () async {
      final repl = _StubReplClient(throwError: const ReplUnauthorisedError('bad'));
      final transport = HttpReplFallbackTransport(
        adapters: HttpReplFallbackAdapters(
          replClient: repl,
          extractReplCommand: (_) => 'cmd',
        ),
      );
      final bundle = _testBundle(payload: '{}');
      final result = await transport.send(bundle);
      expect(result, isA<MeshSendFailed>());
      expect((result as MeshSendFailed).statusCode, equals(401));
    });

    test('incoming() is empty stream', () async {
      final transport = HttpReplFallbackTransport(
        adapters: const HttpReplFallbackAdapters(),
      );
      final events = await transport.incoming().toList();
      expect(events, isEmpty);
      expect(transport.label, equals('http-repl-fallback'));
    });
  });

  group('MeshTransportFactory.select', () {
    test('shard-proxy not configured → fallback', () async {
      final result = await MeshTransportFactory.select(
        MeshTransportFactoryInputs(
          shardProxyEndpoint: null,
          shardGroupId: 't',
          myCertId: 'a' * 32,
          fallbackAdapters: const HttpReplFallbackAdapters(),
        ),
      );
      expect(result.transport, isA<HttpReplFallbackTransport>());
      expect(result.state.label, equals('http-repl-fallback'));
      expect(result.state.meshActive, isFalse);
    });

    test('shard-proxy reachable → ShardProxyMeshTransport', () async {
      final dio = Dio()
        ..httpClientAdapter =
            _StaticAdapter(statusCode: 200, bodyBytes: utf8.encode('{"ok":true}'));
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard.example.com',
          shardGroupId: 't',
        ),
        http: dio,
      );
      final result = await MeshTransportFactory.select(
        MeshTransportFactoryInputs(
          shardProxyEndpoint: 'https://shard.example.com',
          shardGroupId: 't',
          myCertId: 'a' * 32,
          fallbackAdapters: const HttpReplFallbackAdapters(),
          shardProxyClient: client,
        ),
      );
      expect(result.transport, isA<ShardProxyMeshTransport>());
      expect(result.state.meshActive, isTrue);
      expect(result.state.label, equals('shard-proxy'));
      expect(result.state.shardProxyEndpoint, equals('https://shard.example.com'));
    });

    test('shard-proxy unreachable → fallback', () async {
      final dio = Dio()..httpClientAdapter = _ThrowingAdapter();
      final client = ShardProxyClient(
        config: const ShardProxyConfig(
          baseUrl: 'https://shard.example.com',
          shardGroupId: 't',
        ),
        http: dio,
      );
      final result = await MeshTransportFactory.select(
        MeshTransportFactoryInputs(
          shardProxyEndpoint: 'https://shard.example.com',
          shardGroupId: 't',
          myCertId: 'a' * 32,
          fallbackAdapters: const HttpReplFallbackAdapters(),
          shardProxyClient: client,
        ),
      );
      expect(result.transport, isA<HttpReplFallbackTransport>());
      expect(result.state.label, equals('http-repl-fallback'));
      expect(result.state.meshActive, isFalse);
    });
  });
}

// ─── Stubs ────────────────────────────────────────────────────────────

class _StubAttachmentUploader implements AttachmentUploader {
  int calls = 0;
  String? lastMetadata;
  @override
  Future<AttachmentUploadResult> upload({
    required File blobFile,
    required String metadataJson,
  }) async {
    calls += 1;
    lastMetadata = metadataJson;
    return const AttachmentUploadResult(id: 'att-1', status: 'created');
  }
}

class _StubVoiceUploader implements VoiceExtractFlushUploader {
  int calls = 0;
  String? lastEnvelope;
  @override
  Future<void> upload({
    required File audioFile,
    required String envelopeJson,
  }) async {
    calls += 1;
    lastEnvelope = envelopeJson;
  }
}

class _StubReplClient implements ReplClient {
  String? lastCommand;
  final Object? throwError;
  _StubReplClient({this.throwError});

  @override
  Future<ReplOk> send(String cmd) async {
    lastCommand = cmd;
    if (throwError != null) {
      // Dart can throw any Object as an exception, but linter prefers
      // typed throws.  All callers in this test pass real exception
      // subtypes; cast accordingly.
      throw throwError!;
    }
    return const ReplOk(result: 'ok', exit: 'continue');
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

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
