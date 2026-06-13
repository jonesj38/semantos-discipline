---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/oddjobz_attention_client_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.919908+00:00
---

# archive/apps-semantos-monolith/test/repl/oddjobz_attention_client_test.dart

```dart
// Tier 2P Phase D.1 — OddjobzAttentionClient + HelmEventStream
// callOddjobzQueryList wire-shape tests.
//
// Drives a hand-rolled in-memory HelmStreamChannel through the three
// Phase B attention verbs (list_messages / list_dispatch_decisions /
// poll_attention_signals), the JSON-RPC error envelope path, and the
// defensive-parse / unknown-enum-value forward-compat paths.  Same
// mock pattern as oddjobz_query_client_test.dart.

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import 'package:semantos/src/repl/helm_event_stream.dart';
import 'package:semantos/src/repl/oddjobz_attention_client.dart';

// ── Fake channel (identical structure to query-client test) ──────────

class _FakeChannel implements HelmStreamChannel {
  final StreamController<dynamic> _toClient = StreamController<dynamic>();
  final List<String> sent = <String>[];
  bool clientClosed = false;

  @override
  Stream<dynamic> get stream => _toClient.stream;

  @override
  void sendText(String data) => sent.add(data);

  @override
  Future<void> close() async {
    clientClosed = true;
    if (!_toClient.isClosed) await _toClient.close();
  }

  void serverSend(String data) {
    if (!_toClient.isClosed) _toClient.add(data);
  }
}

// ── Test helpers ─────────────────────────────────────────────────────

void main() {
  late _FakeChannel ch;

  HelmStreamChannel makeChannel(Uri uri) {
    ch = _FakeChannel();
    return ch;
  }

  Future<HelmEventStream> connectStream() async {
    final stream = HelmEventStream(
      wssUrl: 'ws://example.test/api/v1/wallet',
      bearer: 'a' * 64,
      topics: const ['jobs'],
      channelFactory: makeChannel,
    );
    await stream.connect();
    await Future<void>.delayed(Duration.zero);
    return stream;
  }

  /// Find the most-recently sent frame with the given method, decode
  /// it, and return the frame map + RPC id.
  Map<String, dynamic> findFrame(String method) {
    final frame = ch.sent.lastWhere(
      (f) => (json.decode(f) as Map)['method'] == method,
    );
    return json.decode(frame) as Map<String, dynamic>;
  }

  group('OddjobzAttentionClient', () {
    // ─── 1. listMessages — no filters ──────────────────────────────

    test('listMessages() sends correct verb and parses rows', () async {
      final stream = await connectStream();
      final client = OddjobzAttentionClient(stream);

      final future = client.listMessages();
      final frame = findFrame('oddjobz.list_messages');
      final id = frame['id'] as int;

      // Params should be an empty map when no filters supplied.
      expect(frame['params'], equals(<String, dynamic>{}));

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'result': [
          {
            'patchId': 'patch-1',
            'providerId': 'meta',
            'sessionId': 'meta:messenger:page123:psid456',
            'channel': 'meta_messenger',
            'recipientId': 'page123',
            'role': 'customer',
            'text': 'Hello!',
            'timestamp': 1714003200000,
            'source': {
              'platform': 'messenger',
              'participantId': 'psid456',
              'senderId': 'psid456',
              'messageId': 'mid.111',
              'threadId': null,
              'conversationId': null,
            },
          },
          {
            'patchId': 'patch-2',
            'providerId': 'gmail',
            'sessionId': 'gmail:session:abc',
            'channel': 'gmail',
            'recipientId': 'hello@example.com',
            'role': 'operator',
            'text': 'On my way.',
            'timestamp': 1714003100000,
            'source': null,
          },
        ],
      }));

      final patches = await future;
      expect(patches, hasLength(2));

      final p0 = patches[0];
      expect(p0.patchId, equals('patch-1'));
      expect(p0.providerId, equals('meta'));
      expect(p0.channel, equals('meta_messenger'));
      expect(p0.role, equals('customer'));
      expect(p0.text, equals('Hello!'));
      expect(p0.timestamp, equals(1714003200000));
      expect(p0.source, isNotNull);
      expect(p0.source!.platform, equals('messenger'));
      expect(p0.source!.participantId, equals('psid456'));
      expect(p0.source!.messageId, equals('mid.111'));
      expect(p0.source!.threadId, isNull);

      final p1 = patches[1];
      expect(p1.patchId, equals('patch-2'));
      expect(p1.role, equals('operator'));
      expect(p1.source, isNull);

      await stream.dispose();
    });

    // ─── 2. listMessages — with filters ────────────────────────────

    test('listMessages(sinceMs, providerId) sends only non-null params',
        () async {
      final stream = await connectStream();
      final client = OddjobzAttentionClient(stream);

      final future =
          client.listMessages(sinceMs: 1714000000000, providerId: 'meta');
      final frame = findFrame('oddjobz.list_messages');
      final id = frame['id'] as int;
      final params = frame['params'] as Map;

      // sinceMs maps to 'since', providerId stays as-is.
      expect(params['since'], equals(1714000000000));
      expect(params['providerId'], equals('meta'));
      // sessionId and limit must NOT appear when not supplied.
      expect(params.containsKey('sessionId'), isFalse);
      expect(params.containsKey('limit'), isFalse);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'result': <dynamic>[],
      }));

      final patches = await future;
      expect(patches, isEmpty);

      await stream.dispose();
    });

    // ─── 3. listDispatchDecisions — enum → wire-string ──────────────

    test(
        'listDispatchDecisions(lane: broadcast, requiresRatification: true) '
        'serialises enums correctly and parses rows', () async {
      final stream = await connectStream();
      final client = OddjobzAttentionClient(stream);

      final future = client.listDispatchDecisions(
        lane: OddjobzDispatchLane.broadcast,
        requiresRatification: true,
      );
      final frame = findFrame('oddjobz.list_dispatch_decisions');
      final id = frame['id'] as int;
      final params = frame['params'] as Map;

      expect(params['lane'], equals('broadcast'));
      expect(params['requiresRatification'], isTrue);
      expect(params.containsKey('since'), isFalse);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'result': [
          {
            'sourcePatchId': 'patch-1',
            'lane': 'broadcast',
            'slot': 'talk.broadcast',
            'transport': 'multicast',
            'confidence': 0.85,
            'requiresRatification': true,
            'primaryTarget': {
              'type': 'broadcast-channel',
              'ref': 'channel-abc',
              'score': 0.72,
            },
            'writtenAt': 1714003300000,
          },
        ],
      }));

      final decisions = await future;
      expect(decisions, hasLength(1));

      final d = decisions[0];
      expect(d.sourcePatchId, equals('patch-1'));
      expect(d.lane, equals(OddjobzDispatchLane.broadcast));
      expect(d.slot, equals('talk.broadcast'));
      expect(d.transport, equals(OddjobzDispatchTransport.multicast));
      expect(d.confidence, closeTo(0.85, 0.001));
      expect(d.requiresRatification, isTrue);
      expect(d.primaryTarget.type,
          equals(OddjobzDispatchTargetType.broadcastChannel));
      expect(d.primaryTarget.ref, equals('channel-abc'));
      expect(d.primaryTarget.score, closeTo(0.72, 0.001));
      // writtenAt used as timestamp.
      expect(d.timestamp, equals(1714003300000));

      await stream.dispose();
    });

    // ─── 4. pollAttentionSignals — all kinds, raw round-trip ────────

    test('pollAttentionSignals parses each kind and round-trips raw map',
        () async {
      final stream = await connectStream();
      final client = OddjobzAttentionClient(stream);

      final future = client.pollAttentionSignals(limit: 25);
      final frame = findFrame('oddjobz.poll_attention_signals');
      final id = frame['id'] as int;
      expect((frame['params'] as Map)['limit'], equals(25));

      final rawDispatch = {
        'sourcePatchId': 'patch-1',
        'lane': 'direct',
        'requiresRatification': true,
      };
      final rawMessage = {
        'patchId': 'patch-2',
        'role': 'customer',
        'text': 'Hi there',
      };
      final rawJob = {
        'id': 'job-xyz',
        'customer_name': 'Acme Corp',
        'state': 'lead',
        'dueDate': '2026-05-10',
      };

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'result': [
          {
            'kind': 'dispatch',
            'score': 0.9,
            'ref': 'patch-1',
            'summary': 'Dispatch direct: Hi there',
            'expiresAt': null,
            'raw': rawDispatch,
          },
          {
            'kind': 'message',
            'score': 0.62,
            'ref': 'patch-2',
            'summary': 'Hi there',
            'raw': rawMessage,
          },
          {
            'kind': 'job',
            'score': 0.8,
            'ref': 'job-xyz',
            'summary': 'Job job-xyz: Acme Corp due 2026-05-10',
            'expiresAt': 1714099200000,
            'raw': rawJob,
          },
        ],
      }));

      final signals = await future;
      expect(signals, hasLength(3));

      final s0 = signals[0];
      expect(s0.kind, equals(OddjobzAttentionKind.dispatch));
      expect(s0.score, closeTo(0.9, 0.001));
      expect(s0.ref, equals('patch-1'));
      expect(s0.expiresAt, isNull);
      expect(s0.raw, equals(rawDispatch));

      final s1 = signals[1];
      expect(s1.kind, equals(OddjobzAttentionKind.message));
      expect(s1.score, closeTo(0.62, 0.001));
      expect(s1.summary, equals('Hi there'));
      expect(s1.raw, equals(rawMessage));

      final s2 = signals[2];
      expect(s2.kind, equals(OddjobzAttentionKind.job));
      expect(s2.expiresAt, equals(1714099200000));
      expect(s2.raw, equals(rawJob));

      await stream.dispose();
    });

    // ─── 5. Error path ──────────────────────────────────────────────

    test('JSON-RPC error envelope surfaces as OddjobzQueryError', () async {
      final stream = await connectStream();
      final client = OddjobzAttentionClient(stream);

      final future = client.listMessages();
      final frame = findFrame('oddjobz.list_messages');
      final id = frame['id'] as int;

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': -32603,
          'message': 'oddjobz attention: JSONL read error',
        },
      }));

      await expectLater(
        future,
        throwsA(isA<OddjobzQueryError>()
            .having((e) => e.code, 'code', equals(-32603))
            .having((e) => e.message, 'message',
                contains('JSONL read error'))),
      );

      await stream.dispose();
    });

    // ─── 6. Defensive parse — malformed rows + unknown enums ────────

    test('malformed rows are silently skipped via whereType', () async {
      final stream = await connectStream();
      final client = OddjobzAttentionClient(stream);

      final future = client.listMessages();
      final frame = findFrame('oddjobz.list_messages');
      final id = frame['id'] as int;

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'result': [
          'not a map',
          42,
          null,
          {
            'patchId': 'good-row',
            'providerId': 'meta',
            'sessionId': 's',
            'channel': 'meta_messenger',
            'recipientId': 'r',
            'role': 'customer',
            'text': 'ok',
            'timestamp': 1714003200000,
          },
        ],
      }));

      final patches = await future;
      // Non-map items silently dropped by whereType.
      expect(patches, hasLength(1));
      expect(patches[0].patchId, equals('good-row'));

      await stream.dispose();
    });

    test('unknown lane / transport / targetType values fall back to defaults',
        () async {
      final stream = await connectStream();
      final client = OddjobzAttentionClient(stream);

      final future = client.listDispatchDecisions();
      final frame = findFrame('oddjobz.list_dispatch_decisions');
      final id = frame['id'] as int;

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'result': [
          {
            'sourcePatchId': 'p1',
            'lane': 'future-unknown-lane',
            'slot': 'talk.unknown',
            'transport': 'future-transport',
            'confidence': 0.5,
            'requiresRatification': false,
            'primaryTarget': {
              'type': 'future-target-type',
              'ref': 'ref-1',
              'score': 0.5,
            },
            'timestamp': 1714003200000,
          },
        ],
      }));

      final decisions = await future;
      expect(decisions, hasLength(1));
      // Defaults: lane → self, transport → none, targetType → job.
      expect(decisions[0].lane, equals(OddjobzDispatchLane.self));
      expect(decisions[0].transport, equals(OddjobzDispatchTransport.none));
      expect(decisions[0].primaryTarget.type,
          equals(OddjobzDispatchTargetType.job));

      await stream.dispose();
    });

    // ─── 7. Unknown kind in pollAttentionSignals ─────────────────────

    test('unknown attention kind defaults to message', () async {
      final stream = await connectStream();
      final client = OddjobzAttentionClient(stream);

      final future = client.pollAttentionSignals();
      final frame = findFrame('oddjobz.poll_attention_signals');
      final id = frame['id'] as int;

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'result': [
          {
            'kind': 'future-kind',
            'score': 0.5,
            'ref': 'ref-x',
            'summary': 'some future signal',
            'raw': <String, dynamic>{},
          },
        ],
      }));

      final signals = await future;
      expect(signals, hasLength(1));
      expect(signals[0].kind, equals(OddjobzAttentionKind.message));

      await stream.dispose();
    });
  });
}

```
