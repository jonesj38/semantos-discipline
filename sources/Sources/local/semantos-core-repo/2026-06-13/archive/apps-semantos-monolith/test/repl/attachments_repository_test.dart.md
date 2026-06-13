---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/attachments_repository_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.922661+00:00
---

# archive/apps-semantos-monolith/test/repl/attachments_repository_test.dart

```dart
// D-O5m.followup-8 substrate — attachments_repository.dart parser test.
//
// Mirrors the test posture in `visits_repository_test.dart` minus the
// create + transition paths (Attachments are AFFINE-ish; this PR
// ships only the read substrate).  Asserts:
//   • parseAttachments consumes the JSON-array shape the Semantos Brain
//     dispatcher's `attachments.find` emits;
//   • parseAttachmentOne consumes both the success body + the typed
//     not_found envelope;
//   • formatBytes renders the right unit for the row label.
//
// D-O5.followup-4 client hooks — extended with an
// `AttachmentsRepository cacheEvents` group asserting attachment.created
// surfaces as an AttachmentsCacheEvent keyed by visit_id (the list view
// is visit-scoped so subscribers filter by parent).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/repl/attachments_repository.dart';
import 'package:semantos/src/repl/helm_event_stream.dart';
import 'package:semantos/src/repl/repl_client.dart';

void main() {
  group('parseAttachments', () {
    test('decodes a JSON-array response (dispatcher shape)', () {
      // Verbatim shape from `attachments_handler.zig::writeAttachmentJson`.
      final body = json.encode([
        {
          'id': 'att-001',
          'visit_id': 'v-001',
          'kind': 'photo',
          'content_hash': 'a' * 64,
          'content_size': 2457600,
          'mime_type': 'image/heic',
          'captured_at': '2026-05-15T14:30:00Z',
          'captured_by_cert_id': '00112233445566778899aabbccddeeff',
          'caption': '',
          'created_at': '2026-05-15T14:30:01Z',
        },
        {
          'id': 'att-002',
          'visit_id': 'v-001',
          'kind': 'voice_memo',
          'content_hash': 'b' * 64,
          'content_size': 184320,
          'mime_type': 'audio/m4a',
          'captured_at': '2026-05-15T14:32:00Z',
          'captured_by_cert_id': '00112233445566778899aabbccddeeff',
          'caption': 'Customer pointed at the eaves.',
          'created_at': '2026-05-15T14:32:01Z',
        },
      ]);
      final rows = parseAttachments(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('att-001'));
      expect(rows[0].visitId, equals('v-001'));
      expect(rows[0].kind, equals('photo'));
      expect(rows[0].contentSize, equals(2457600));
      expect(rows[0].mimeType, equals('image/heic'));
      expect(rows[1].kind, equals('voice_memo'));
      expect(rows[1].caption, equals('Customer pointed at the eaves.'));
    });

    test('returns empty list for empty / non-JSON / malformed responses', () {
      expect(parseAttachments(''), isEmpty);
      expect(parseAttachments('   \n   '), isEmpty);
      expect(parseAttachments('not json'), isEmpty);
      expect(parseAttachments('[bad json'), isEmpty);
    });
  });

  group('parseAttachmentOne', () {
    test('decodes the dispatcher single-attachment response shape', () {
      final body = json.encode({
        'id': 'att-003',
        'visit_id': 'v-002',
        'kind': 'gps_pin',
        'content_hash': 'c' * 64,
        'content_size': 64,
        'mime_type': 'application/json',
        'captured_at': '2026-05-15T14:35:00Z',
        'captured_by_cert_id': '00112233445566778899aabbccddeeff',
        'caption': 'Side gate access point.',
        'created_at': '2026-05-15T14:35:01Z',
      });
      final a = parseAttachmentOne(body);
      expect(a, isNotNull);
      expect(a!.id, equals('att-003'));
      expect(a.kind, equals('gps_pin'));
      expect(a.caption, equals('Side gate access point.'));
    });

    test('returns null for the typed not_found envelope', () {
      const body = '{"error":"not_found","id":"missing"}';
      expect(parseAttachmentOne(body), isNull);
    });

    test('returns null for empty / malformed responses', () {
      expect(parseAttachmentOne(''), isNull);
      expect(parseAttachmentOne('text'), isNull);
      expect(parseAttachmentOne('{bad'), isNull);
    });
  });

  group('formatBytes', () {
    test('renders sub-KB sizes as bytes', () {
      expect(formatBytes(0), equals('0 B'));
      expect(formatBytes(64), equals('64 B'));
      expect(formatBytes(1023), equals('1023 B'));
    });

    test('renders KB / MB / GB ranges with sensible precision', () {
      expect(formatBytes(1024), equals('1 KB'));
      expect(formatBytes(184320), equals('180 KB'));
      expect(formatBytes(2457600), equals('2.3 MB'));
      expect(formatBytes(1024 * 1024 * 1024), equals('1.0 GB'));
    });
  });

  // D-O5.followup-4 client hooks — drive an in-memory HelmEventStream
  // and assert the repo surfaces `attachment.created` as an
  // AttachmentsCacheEvent.  The cache event carries the parent
  // visit_id (NOT the attachment id) so VisitDetailScreen can filter
  // by visit — same posture as the Semantos Brain-side topic filtering.
  group('AttachmentsRepository cacheEvents', () {
    test('emits attachmentChanged keyed by visit_id on attachment.created',
        () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['attachments'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo =
          AttachmentsRepository(_stubReplClient(), eventStream: stream);
      final received = <AttachmentsCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'attachment.created',
          'data': {'id': 'att-001', 'visit_id': 'v-001', 'kind': 'photo'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));
      // Note: AttachmentsCacheEvent carries the parent visit_id so
      // VisitDetailScreen can filter by visit.
      expect(received.first.visitId, equals('v-001'));

      await repo.dispose();
      await stream.dispose();
    });

    test('ignores attachment.created with empty visit_id', () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['attachments'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo =
          AttachmentsRepository(_stubReplClient(), eventStream: stream);
      final received = <AttachmentsCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'attachment.created',
          'data': {'id': 'att-001', 'visit_id': '', 'kind': 'photo'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, isEmpty);

      await repo.dispose();
      await stream.dispose();
    });

    test('ignores unrelated event types', () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['attachments'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo =
          AttachmentsRepository(_stubReplClient(), eventStream: stream);
      final received = <AttachmentsCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'visit.created',
          'data': {'id': 'v-001'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, isEmpty);

      await repo.dispose();
      await stream.dispose();
    });

    test('dispose cancels the subscription (no further emissions)',
        () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['attachments'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo =
          AttachmentsRepository(_stubReplClient(), eventStream: stream);
      final received = <AttachmentsCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'attachment.created',
          'data': {'visit_id': 'v-001'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));

      await repo.dispose();
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'attachment.created',
          'data': {'visit_id': 'v-002'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));

      await stream.dispose();
    });
  });
}

class _FakeChannel implements HelmStreamChannel {
  final StreamController<dynamic> _toClient = StreamController<dynamic>();
  final List<String> sent = <String>[];

  @override
  Stream<dynamic> get stream => _toClient.stream;

  @override
  void sendText(String data) {
    sent.add(data);
  }

  @override
  Future<void> close() async {
    if (!_toClient.isClosed) await _toClient.close();
  }

  void serverSend(String data) {
    if (!_toClient.isClosed) _toClient.add(data);
  }
}

ReplClient _stubReplClient() {
  final dio = Dio()..httpClientAdapter = _NoopAdapter();
  return ReplClient.withBearer(
    http: dio,
    baseUrl: 'https://oddjobtodd.test',
    bearer: 'a' * 64,
  );
}

class _NoopAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(<int>[], 200);
  }
}

```
