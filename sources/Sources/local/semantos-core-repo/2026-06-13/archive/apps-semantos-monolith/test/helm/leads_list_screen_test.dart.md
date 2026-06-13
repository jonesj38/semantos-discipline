---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/leads_list_screen_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.928467+00:00
---

# archive/apps-semantos-monolith/test/helm/leads_list_screen_test.dart

```dart
// D-O5m.followup-7 Phase B — LeadsListScreen integration tests.
//
// The screen widget is a thin wrapper around RatificationQueueClient.
// findPending + a StreamSubscription over the cache-event stream.  The
// pure parser path is covered in
// test/ratification/ratification_queue_client_test.dart; this file
// asserts the integration shape — that the client's findPending sends
// the correct REPL line for both the no-hat and the hat-scoped paths,
// which is what the screen's _load() depends on.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/ratification/ratification_queue_client.dart';
import 'package:semantos/src/repl/repl_client.dart';

void main() {
  group('LeadsListScreen ←→ RatificationQueueClient integration', () {
    test('findPending(no hatId) issues `find leads --status pending`',
        () async {
      final adapter = _RecordingAdapter()..enqueue(_emptyArray());
      final client = _makeClient(adapter);
      final rows = await client.findPending();
      expect(rows, isEmpty);
      expect(adapter.commands.last, equals('find leads --status pending'));
    });

    test('findPending(hatId: ...) appends --hat <id>', () async {
      final adapter = _RecordingAdapter()..enqueue(_emptyArray());
      final client = _makeClient(adapter);
      await client.findPending(hatId: 'hat-mowing');
      expect(
        adapter.commands.last,
        equals('find leads --status pending --hat hat-mowing'),
      );
    });

    test('findPending decodes a 2-row response into typed PendingLead',
        () async {
      final body = json.encode([
        {
          'id': 'L1',
          'customer_name': 'Alice',
          'phone': '555-0100',
          'email': '',
          'summary': 'wants a hedge trim',
          'source': 'chat',
          'source_correlation_id': 'thread-7',
          'status': 'pending',
          'rejection_reason': '',
          'hat_id': '',
          'created_at': '2026-05-02T09:00:00Z',
          'updated_at': '2026-05-02T09:00:00Z',
        },
        {
          'id': 'L2',
          'customer_name': 'Bob',
          'phone': '',
          'email': 'bob@example.com',
          'summary': '',
          'source': 'voice',
          'source_correlation_id': '',
          'status': 'pending',
          'rejection_reason': '',
          'hat_id': '',
          'created_at': '2026-05-02T10:00:00Z',
          'updated_at': '2026-05-02T10:00:00Z',
        },
      ]);
      final adapter = _RecordingAdapter()..enqueue(_wrapResult(body));
      final client = _makeClient(adapter);
      final rows = await client.findPending();
      expect(rows, hasLength(2));
      expect(rows[0].customerName, equals('Alice'));
      expect(rows[0].source, equals('chat'));
      expect(rows[1].source, equals('voice'));
      expect(rows[1].email, equals('bob@example.com'));
    });
  });
}

RatificationQueueClient _makeClient(_RecordingAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return RatificationQueueClient(
    ReplClient.withBearer(
      http: dio,
      baseUrl: 'https://example.test',
      bearer: 'a' * 64,
    ),
  );
}

String _emptyArray() => _wrapResult('[]');

String _wrapResult(String inner) => json.encode({
      'result': inner,
      'exit': 'continue',
    });

class _RecordingAdapter implements HttpClientAdapter {
  final List<List<int>> _bodies = [];
  final List<String> commands = [];

  void enqueue(String body) => _bodies.add(utf8.encode(body));

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      final raw = await requestStream
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
      try {
        final decoded = json.decode(utf8.decode(raw));
        if (decoded is Map<String, dynamic> && decoded['cmd'] is String) {
          commands.add(decoded['cmd'] as String);
        }
      } catch (_) {
        // Ignore.
      }
    }
    final body = _bodies.isEmpty
        ? utf8.encode('{"result":"","exit":"continue"}')
        : _bodies.removeAt(0);
    return ResponseBody.fromBytes(body, 200, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

```
