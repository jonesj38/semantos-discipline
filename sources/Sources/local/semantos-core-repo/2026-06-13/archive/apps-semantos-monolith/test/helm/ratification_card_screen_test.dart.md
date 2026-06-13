---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/ratification_card_screen_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.925898+00:00
---

# archive/apps-semantos-monolith/test/helm/ratification_card_screen_test.dart

```dart
// D-O5m.followup-7 Phase B — RatificationCardController tests.
//
// Pure-Dart against the controller (the screen widget is a thin wrapper).
// Mirrors the test posture used elsewhere in the suite where pure-Dart
// state machines are factored out of widgets so the unit tests stay
// Flutter-SDK-free.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/ratification/ratification_card_controller.dart';
import 'package:semantos/src/ratification/ratification_queue_client.dart';
import 'package:semantos/src/repl/repl_client.dart';

void main() {
  group('RatificationCardController', () {
    test('initial state is noLeadId when lead_id is empty', () {
      final controller = RatificationCardController(
        client: _makeClient(_QueuedAdapter()),
        leadId: '',
      );
      expect(controller.phase, equals(RatificationCardPhase.noLeadId));
    });

    test('initial state is noLeadId when lead_id is null', () {
      final controller = RatificationCardController(
        client: _makeClient(_QueuedAdapter()),
        leadId: null,
      );
      expect(controller.phase, equals(RatificationCardPhase.noLeadId));
    });

    test('load() fetches the lead and transitions to ready', () async {
      final adapter = _QueuedAdapter()
        ..enqueue(_wrapResult(_leadJson(id: 'L1', state: 'pending')));
      final controller = RatificationCardController(
        client: _makeClient(adapter),
        leadId: 'L1',
      );
      await controller.load();
      expect(controller.phase, equals(RatificationCardPhase.ready));
      expect(controller.lead!.id, equals('L1'));
      expect(adapter.commands, equals(['find lead L1']));
    });

    test('load() surfaces loadError on a not_found envelope', () async {
      final adapter = _QueuedAdapter()
        ..enqueue(_wrapResult('{"error":"not_found","id":"L1"}'));
      final controller = RatificationCardController(
        client: _makeClient(adapter),
        leadId: 'L1',
      );
      await controller.load();
      expect(controller.phase, equals(RatificationCardPhase.loadError));
      expect(controller.errorMessage, contains('no longer exists'));
    });

    test('ratify() drives ratify lead + fires onCompleted', () async {
      final adapter = _QueuedAdapter()
        ..enqueue(_wrapResult(_leadJson(id: 'L1', state: 'pending')))
        ..enqueue(_wrapResult(_leadJson(id: 'L1', state: 'ratified')));
      RatificationCardOutcome? got;
      final controller = RatificationCardController(
        client: _makeClient(adapter),
        leadId: 'L1',
        onCompleted: (o) => got = o,
      );
      await controller.load();
      await controller.ratify();
      expect(controller.phase, equals(RatificationCardPhase.succeeded));
      expect(got, isA<RatificationCardRatified>());
      expect((got! as RatificationCardRatified).lead.status,
          equals('ratified'));
      expect(adapter.commands, equals(['find lead L1', 'ratify lead L1']));
    });

    test('reject() drives reject lead --reason + fires onCompleted',
        () async {
      final adapter = _QueuedAdapter()
        ..enqueue(_wrapResult(_leadJson(id: 'L1', state: 'pending')))
        ..enqueue(_wrapResult(_leadJson(id: 'L1', state: 'rejected')));
      RatificationCardOutcome? got;
      final controller = RatificationCardController(
        client: _makeClient(adapter),
        leadId: 'L1',
        onCompleted: (o) => got = o,
      );
      await controller.load();
      await controller.reject(RejectionReason.spam);
      expect(controller.phase, equals(RatificationCardPhase.succeeded));
      expect(got, isA<RatificationCardRejected>());
      expect((got! as RatificationCardRejected).reason,
          equals(RejectionReason.spam));
      expect(adapter.commands.last, equals('reject lead L1 --reason spam'));
    });

    test('defer() drives defer lead + fires onCompleted', () async {
      final adapter = _QueuedAdapter()
        ..enqueue(_wrapResult(_leadJson(id: 'L1', state: 'pending')))
        ..enqueue(_wrapResult(_leadJson(id: 'L1', state: 'deferred')));
      RatificationCardOutcome? got;
      final controller = RatificationCardController(
        client: _makeClient(adapter),
        leadId: 'L1',
        onCompleted: (o) => got = o,
      );
      await controller.load();
      await controller.defer();
      expect(controller.phase, equals(RatificationCardPhase.succeeded));
      expect(got, isA<RatificationCardDeferred>());
      expect(adapter.commands.last, equals('defer lead L1'));
    });

    test(
        'ratify error transitions to actionError + does NOT fire onCompleted',
        () async {
      final adapter = _QueuedAdapter()
        ..enqueue(_wrapResult(_leadJson(id: 'L1', state: 'pending')))
        ..enqueue(_wrapResult(
          '{"error":"wrong_cap","from":"pending","to":"ratified",'
          '"cap_required":"cap.oddjobz.write_customer"}',
        ));
      var fired = false;
      final controller = RatificationCardController(
        client: _makeClient(adapter),
        leadId: 'L1',
        onCompleted: (_) => fired = true,
      );
      await controller.load();
      await controller.ratify();
      expect(controller.phase, equals(RatificationCardPhase.actionError));
      expect(controller.errorMessage,
          contains('cap.oddjobz.write_customer'));
      expect(fired, isFalse);
    });
  });
}

RatificationQueueClient _makeClient(_QueuedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return RatificationQueueClient(
    ReplClient.withBearer(
      http: dio,
      baseUrl: 'https://example.test',
      bearer: 'a' * 64,
    ),
  );
}

String _wrapResult(String inner) => json.encode({
      'result': inner,
      'exit': 'continue',
    });

String _leadJson({required String id, required String state}) {
  return json.encode({
    'id': id,
    'customer_name': 'Alice',
    'phone': '',
    'email': '',
    'summary': 'Wants a hedge trim',
    'source': 'chat',
    'source_correlation_id': '',
    'status': state,
    'rejection_reason': '',
    'hat_id': '',
    'created_at': '2026-05-02T09:00:00Z',
    'updated_at': '2026-05-02T09:30:00Z',
  });
}

/// HTTP adapter that returns each enqueued body in order.  The test
/// also captures the `cmd` field of every request body so it can
/// assert which REPL line was dispatched.
class _QueuedAdapter implements HttpClientAdapter {
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
        // Ignore non-JSON.
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
