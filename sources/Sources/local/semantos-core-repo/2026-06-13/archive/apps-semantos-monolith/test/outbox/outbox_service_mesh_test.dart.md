---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/outbox/outbox_service_mesh_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.907090+00:00
---

# archive/apps-semantos-monolith/test/outbox/outbox_service_mesh_test.dart

```dart
// D-O5m.followup-6 Phase 2 — OutboxService.flushViaMesh conformance.
//
// Reference: lib/src/outbox/outbox_service.dart::flushViaMesh +
// lib/src/outbox/mesh_outbox_builder.dart.
//
// W1.2 — all entries now map to payloadTypeCellCreate regardless of
// the old cell_type field (which is gone).  Assertions updated to match
// the new routing rule.
//
// Asserts:
//   1. Any cell envelope entry → payload_type = oddjobz.cell.create.
//   2. Payload bytes are forwarded verbatim from entry.payload.
//   3. Mocked transport: send happy path → entry dequeued.
//   4. Mocked transport: MeshSendFailed (statusCode=401) → unauthorised.
//   5. Mocked transport: MeshTransportUnavailable → entry stays queued
//      with networkError failure recorded.
//   6. Incoming bundle is forwarded to onIncomingBundle handler.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/mesh/cert_ref.dart';
import 'package:semantos/src/mesh/mesh_transport.dart';
import 'package:semantos/src/mesh/signature_metadata.dart';
import 'package:semantos/src/mesh/signed_bundle.dart';
import 'package:semantos/src/outbox/mesh_outbox_builder.dart';
import 'package:semantos/src/outbox/outbox_db.dart';
import 'package:semantos/src/outbox/outbox_service.dart';
import 'package:semantos/src/repl/repl_client.dart';

Future<OutboxDb> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions());
  return OutboxDb.fromDatabase(db);
}

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

MeshIdentityContext _testIdentity() => MeshIdentityContext(
      senderCertChain: [_testRootCert()],
      brainRootCertId: 'cccccccccccccccccccccccccccccccc',
      // 32 bytes of random-looking but constant private key.  Real
      // signing uses cell_signer's deterministic-k ECDSA.
      leafPrivateKey: Uint8List.fromList(List.generate(32, (i) => 0x40 + i)),
    );

Uint8List _cellId32(String s) {
  final b = utf8.encode(s);
  final out = Uint8List(32);
  out.setRange(0, b.length.clamp(0, 32), b);
  return out;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('mesh_outbox_builder (W1.2)', () {
    test('any cell envelope entry maps to oddjobz.cell.create', () async {
      final db = await _openInMemory();
      final payload = Uint8List.fromList(utf8.encode('{"attachmentId":"att-1"}'));
      final id = await db.enqueue(
        cellId: _cellId32('att-1'),
        domainFlag: 0x000101,
        payload: payload,
      );
      final entry = (await db.peek()).firstWhere((e) => e.id == id);
      final bundle = buildBundleFromOutboxEntry(
        entry: entry,
        identity: _testIdentity(),
        nonceProvider: () => 'd' * 64,
        clockProvider: () => 1746230400,
      );
      // W1.2 — all entries route to cell.create regardless of envelope kind.
      expect(bundle.payloadType, equals(payloadTypeCellCreate));
      expect(bundle.payload, equals(payload));
      expect(bundle.recipientCertId, equals('cccccccccccccccccccccccccccccccc'));
      // Signature must be filled in (non-zero).
      expect(bundle.signature.any((b) => b != 0), isTrue);
      await db.close();
    });

    test('voice envelope entry also maps to oddjobz.cell.create', () async {
      final db = await _openInMemory();
      final payload = Uint8List.fromList(utf8.encode('{"transcript":"hi"}'));
      final id = await db.enqueue(
        cellId: _cellId32('voice-1'),
        domainFlag: 0x000101,
        payload: payload,
      );
      final entry = (await db.peek()).firstWhere((e) => e.id == id);
      final bundle = buildBundleFromOutboxEntry(
        entry: entry,
        identity: _testIdentity(),
        nonceProvider: () => 'e' * 64,
        clockProvider: () => 1746230400,
      );
      expect(bundle.payloadType, equals(payloadTypeCellCreate));
      await db.close();
    });

    test('null payload produces empty bundle payload', () async {
      final db = await _openInMemory();
      final id = await db.enqueue(
        cellId: _cellId32('job-9'),
        domainFlag: 0x000101,
        payload: null,
      );
      final entry = (await db.peek()).firstWhere((e) => e.id == id);
      final bundle = buildBundleFromOutboxEntry(
        entry: entry,
        identity: _testIdentity(),
        nonceProvider: () => 'f' * 64,
        clockProvider: () => 1746230400,
      );
      expect(bundle.payloadType, equals(payloadTypeCellCreate));
      expect(bundle.payload, isEmpty);
      await db.close();
    });
  });

  group('OutboxService.flushViaMesh', () {
    test('happy path: each entry is sent + dequeued', () async {
      final db = await _openInMemory();
      await db.enqueue(
          cellId: _cellId32('j1'),
          domainFlag: 0x000101,
          payload: Uint8List.fromList(utf8.encode('{"id":"j1"}')));
      await db.enqueue(
          cellId: _cellId32('j2'),
          domainFlag: 0x000101,
          payload: Uint8List.fromList(utf8.encode('{"id":"j2"}')));

      final transport = _StubMeshTransport(result: const MeshSent());
      final svc = OutboxService(
        db: db,
        repl: ReplClient.withBearer(
          http: Dio(),
          baseUrl: 'http://example',
          bearer: '0' * 64,
        ),
        meshTransport: transport,
        meshIdentity: _testIdentity(),
      );

      final summary = await svc.flushViaMesh();
      expect(summary.succeeded, equals(2));
      expect(summary.unauthorised, isFalse);
      expect(transport.sendCount, equals(2));
      expect(await db.count(), equals(0));
      await svc.dispose();
      await db.close();
    });

    test('MeshTransportUnavailable: entries stay queued with networkError', () async {
      final db = await _openInMemory();
      await db.enqueue(
          cellId: _cellId32('j1'),
          domainFlag: 0x000101,
          payload: Uint8List.fromList(utf8.encode('{"id":"j1"}')));

      final transport = _StubMeshTransport(
          result: const MeshTransportUnavailable(reason: 'offline'));
      final svc = OutboxService(
        db: db,
        repl: ReplClient.withBearer(
          http: Dio(),
          baseUrl: 'http://example',
          bearer: '0' * 64,
        ),
        meshTransport: transport,
        meshIdentity: _testIdentity(),
      );

      final summary = await svc.flushViaMesh();
      expect(summary.succeeded, equals(0));
      expect(summary.retryable, equals(1));
      expect(await db.count(), equals(1));
      final failed = await db.peekFailed();
      expect(failed, hasLength(1));
      expect(failed.first.kind, equals(OutboxFailureKind.networkError));
      await svc.dispose();
      await db.close();
    });

    test('MeshSendFailed 401 sets unauthorised + halts batch', () async {
      final db = await _openInMemory();
      await db.enqueue(
          cellId: _cellId32('j1'),
          domainFlag: 0x000101,
          payload: Uint8List.fromList(utf8.encode('{"id":"j1"}')));
      await db.enqueue(
          cellId: _cellId32('j2'),
          domainFlag: 0x000101,
          payload: Uint8List.fromList(utf8.encode('{"id":"j2"}')));

      final transport = _StubMeshTransport(
          result: const MeshSendFailed(reason: 'bearer rejected', statusCode: 401));
      final svc = OutboxService(
        db: db,
        repl: ReplClient.withBearer(
          http: Dio(),
          baseUrl: 'http://example',
          bearer: '0' * 64,
        ),
        meshTransport: transport,
        meshIdentity: _testIdentity(),
      );

      final summary = await svc.flushViaMesh();
      expect(summary.unauthorised, isTrue);
      // Halt at the first 401 → only one send call.
      expect(transport.sendCount, equals(1));
      // The first entry's failure is recorded.
      final failed = await db.peekFailed();
      expect(failed, hasLength(1));
      expect(failed.first.kind, equals(OutboxFailureKind.unauthorised));
      await svc.dispose();
      await db.close();
    });

    test('MeshSendFailed non-401 records validationFailed', () async {
      final db = await _openInMemory();
      await db.enqueue(
          cellId: _cellId32('j1'),
          domainFlag: 0x000101,
          payload: Uint8List.fromList(utf8.encode('{"id":"j1"}')));

      final transport = _StubMeshTransport(
          result: const MeshSendFailed(reason: 'shape error', statusCode: 400));
      final svc = OutboxService(
        db: db,
        repl: ReplClient.withBearer(
          http: Dio(),
          baseUrl: 'http://example',
          bearer: '0' * 64,
        ),
        meshTransport: transport,
        meshIdentity: _testIdentity(),
      );

      final summary = await svc.flushViaMesh();
      expect(summary.validationFailed, equals(1));
      expect(await db.count(), equals(1));
      await svc.dispose();
      await db.close();
    });

    test('throws when constructed without identity', () async {
      final db = await _openInMemory();
      expect(
        () => OutboxService(
          db: db,
          repl: ReplClient.withBearer(
            http: Dio(),
            baseUrl: 'http://example',
            bearer: '0' * 64,
          ),
          meshTransport: _StubMeshTransport(result: const MeshSent()),
        ),
        throwsArgumentError,
      );
      await db.close();
    });

    test('incoming bundle stream forwards to handler', () async {
      final db = await _openInMemory();
      final receivedBundles = <SignedBundle>[];
      final ctl = StreamController<SignedBundle>();
      final transport = _StubMeshTransport(
        result: const MeshSent(),
        incomingStream: ctl.stream,
      );
      final svc = OutboxService(
        db: db,
        repl: ReplClient.withBearer(
          http: Dio(),
          baseUrl: 'http://example',
          bearer: '0' * 64,
        ),
        meshTransport: transport,
        meshIdentity: _testIdentity(),
        onIncomingBundle: receivedBundles.add,
      );

      // Inject an incoming bundle.
      final incoming = SignedBundle(
        senderCertChain: [_testRootCert()],
        recipientCertId: 'cccccccccccccccccccccccccccccccc',
        payloadType: 'helm.event',
        payload: Uint8List.fromList(utf8.encode('{"event":"hi"}')),
        signature: Uint8List(64),
        signatureMetadata: SignatureMetadata(
          nonceHex: 'd' * 64,
          timestampUnix: 1746230400,
        ),
      );
      ctl.add(incoming);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(receivedBundles, hasLength(1));
      expect(receivedBundles.first.payloadType, equals('helm.event'));

      await ctl.close();
      await svc.dispose();
      await db.close();
    });
  });
}

class _StubMeshTransport implements MeshTransport {
  final MeshSendResult result;
  final Stream<SignedBundle>? incomingStream;
  int sendCount = 0;

  _StubMeshTransport({required this.result, this.incomingStream});

  @override
  String get label => 'stub';

  @override
  Future<MeshSendResult> send(SignedBundle bundle) async {
    sendCount += 1;
    return result;
  }

  @override
  Stream<SignedBundle> incoming() =>
      incomingStream ?? const Stream<SignedBundle>.empty();

  @override
  Future<void> close() async {}
}

```
