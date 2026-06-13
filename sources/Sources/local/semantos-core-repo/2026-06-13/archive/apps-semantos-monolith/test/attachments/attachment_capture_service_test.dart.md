---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/attachments/attachment_capture_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.919264+00:00
---

# archive/apps-semantos-monolith/test/attachments/attachment_capture_service_test.dart

```dart
// D-O5m.followup-8 capture+upload — capture service unit tests.
//
// W1.2 — `uploader:` constructor parameter and `blobPath` field removed.
// Tests updated to use the new cell-envelope API:
//   - OutboxService no longer takes `uploader:` parameter
//   - OutboxEntry no longer has `blobPath` / `cellType` / `payloadJson`
//   - Attachment metadata is now the `payload` BLOB bytes (UTF-8 JSON)
//
// Wires real OutboxDb (in-memory sqflite_ffi) + ChildCertStore (in-
// memory secure store) with a stub camera picker + stub REPL adapter,
// and asserts the end-to-end flow:
//   - capture returns CaptureCancelled when picker returns null
//   - capture returns CaptureNotPaired when no cert is on disk
//   - capture enqueues an outbox row with the attachment metadata as payload
//   - after a successful flush the outbox is empty

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/attachments/attachment_capture_service.dart';
import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:semantos/src/outbox/outbox_db.dart';
import 'package:semantos/src/outbox/outbox_service.dart';
import 'package:semantos/src/repl/repl_client.dart';
import 'package:semantos/src/sensors/camera_capture.dart';

ChildCertRecord _seedCert() {
  final pub = '02' + ('00' * 32);
  return ChildCertRecord(
    devicePrivHex:
        'a1b2c3d4e5f600112233445566778899aabbccddeeff00112233445566778899',
    childPubHex: pub,
    operatorRootPub: pub,
    operatorCertId: '00112233445566778899aabbccddeeff',
    contextTag: 16,
    label: 'test-device',
    capabilities: ['cap.oddjobz.write_attachment'],
    brainPairEndpoint: 'https://oddjobtodd.test',
    brainWssEndpoint: 'wss://oddjobtodd.test/wallet',
    brainPinCertId: '00112233445566778899aabbccddeeff',
    brainPinPubkey: pub,
    bearer: 'b' * 64,
  );
}

Future<OutboxDb> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions());
  return OutboxDb.fromDatabase(db);
}

/// Dio adapter that returns 200 + ok JSON for every request.
class _OkAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(
        utf8.encode('{"result":"ok","exit":"continue"}'),
        200,
        headers: const {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
}

/// Dio adapter that always throws a network error.
class _ErrorAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'connection refused (stub)',
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('AttachmentCaptureService.captureAndEnqueue', () {
    late OutboxDb outboxDb;
    late ChildCertStore certStore;
    late OutboxService outboxService;
    late Directory tmpBlobsDir;

    setUp(() async {
      outboxDb = await _openInMemory();
      certStore = ChildCertStore(InMemorySecureStore());
      final dio = Dio()..httpClientAdapter = _OkAdapter();
      final repl = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://test',
        bearer: 'b' * 64,
      );
      // W1.2 — OutboxService no longer takes `uploader:` parameter.
      outboxService = OutboxService(db: outboxDb, repl: repl);
      tmpBlobsDir = await Directory.systemTemp.createTemp('outbox-blobs-test-');
    });

    tearDown(() async {
      await outboxDb.close();
      if (await tmpBlobsDir.exists()) {
        await tmpBlobsDir.delete(recursive: true);
      }
    });

    test('returns CaptureNotPaired when cert is absent', () async {
      final svc = AttachmentCaptureService(
        certStore: certStore,
        outboxDb: outboxDb,
        outboxService: outboxService,
        picker: () async => null,
        flushAdapter: (_) => null,
        blobsDirProvider: () async => tmpBlobsDir,
      );
      final outcome = await svc.captureAndEnqueue('v-1');
      expect(outcome, isA<CaptureNotPaired>());
    });

    test('returns CaptureCancelled when picker returns null', () async {
      await certStore.write(_seedCert());
      final svc = AttachmentCaptureService(
        certStore: certStore,
        outboxDb: outboxDb,
        outboxService: outboxService,
        picker: () async => null,
        flushAdapter: (_) => null,
        blobsDirProvider: () async => tmpBlobsDir,
      );
      final outcome = await svc.captureAndEnqueue('v-1');
      expect(outcome, isA<CaptureCancelled>());
    });

    test('captures + enqueues + flushes: returns CaptureQueuedAndSynced',
        () async {
      await certStore.write(_seedCert());
      final fakeBytes = Uint8List.fromList(utf8.encode('fake-photo-bytes'));
      final svc = AttachmentCaptureService(
        certStore: certStore,
        outboxDb: outboxDb,
        outboxService: outboxService,
        picker: () async => PickedPhoto(bytes: fakeBytes, mimeType: 'image/jpeg'),
        // W1.2 — flush adapter decodes payload bytes as a REPL command.
        flushAdapter: (entry) =>
            entry.payload != null ? utf8.decode(entry.payload!) : null,
        blobsDirProvider: () async => tmpBlobsDir,
        clock: () => DateTime.utc(2026, 5, 15, 14, 30),
      );

      final outcome = await svc.captureAndEnqueue('v-1');
      expect(outcome, isA<CaptureQueuedAndSynced>());
      // After a successful flush, the outbox is empty.
      expect(await outboxDb.count(), equals(0));
    });

    test('captures + enqueues but flush fails: returns CaptureQueuedOffline',
        () async {
      await certStore.write(_seedCert());
      // Build an outbox service backed by a failing Dio adapter.
      final failingDio = Dio()..httpClientAdapter = _ErrorAdapter();
      final failingRepl = ReplClient.withBearer(
        http: failingDio,
        baseUrl: 'https://test',
        bearer: 'b' * 64,
      );
      final svcOutbox = OutboxService(db: outboxDb, repl: failingRepl);
      final fakeBytes = Uint8List.fromList(utf8.encode('fake-photo'));
      final svc = AttachmentCaptureService(
        certStore: certStore,
        outboxDb: outboxDb,
        outboxService: svcOutbox,
        picker: () async => PickedPhoto(bytes: fakeBytes, mimeType: 'image/jpeg'),
        flushAdapter: (entry) =>
            entry.payload != null ? utf8.decode(entry.payload!) : null,
        blobsDirProvider: () async => tmpBlobsDir,
        clock: () => DateTime.utc(2026, 5, 15, 14, 30),
      );

      final outcome = await svc.captureAndEnqueue('v-1');
      expect(outcome, isA<CaptureQueuedOffline>());
      // The outbox row is still queued.
      expect(await outboxDb.count(), equals(1));
      // W1.2 — payload BLOB carries the upload metadata JSON.
      final rows = await outboxDb.peek();
      expect(rows.first.payload, isNotNull);
      final meta =
          json.decode(utf8.decode(rows.first.payload!)) as Map<String, dynamic>;
      expect(meta['cell_payload']['kind'], equals('photo'));
      expect(meta['cell_payload']['visitId'], equals('v-1'));
    });
  });
}

```
