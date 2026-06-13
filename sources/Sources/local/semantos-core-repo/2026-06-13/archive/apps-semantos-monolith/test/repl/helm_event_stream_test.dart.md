---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/helm_event_stream_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.920810+00:00
---

# archive/apps-semantos-monolith/test/repl/helm_event_stream_test.dart

```dart
// D-O5.followup-4 — HelmEventStream client test.
//
// Drives a hand-rolled in-memory HelmStreamChannel through the
// helm.subscribe send shape, the helm.event receive parse, the
// reconnect backoff, and the state-stream transitions.

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import 'package:semantos/src/repl/helm_event_stream.dart';

/// Simple in-memory HelmStreamChannel.  Tests can `serverSend` text
/// frames to drive the helm side, and inspect `sent` to verify what
/// the helm wrote.  `closeFromServer` simulates a transport hangup.
class _FakeChannel implements HelmStreamChannel {
  final StreamController<dynamic> _toClient = StreamController<dynamic>();
  final List<String> sent = <String>[];
  bool clientClosed = false;

  @override
  Stream<dynamic> get stream => _toClient.stream;

  @override
  void sendText(String data) {
    sent.add(data);
  }

  @override
  Future<void> close() async {
    clientClosed = true;
    if (!_toClient.isClosed) await _toClient.close();
  }

  void serverSend(String data) {
    if (!_toClient.isClosed) _toClient.add(data);
  }

  Future<void> closeFromServer() async {
    if (!_toClient.isClosed) await _toClient.close();
  }
}

void main() {
  group('HelmEventStream', () {
    late _FakeChannel ch;
    HelmStreamChannel makeChannel(Uri uri) {
      ch = _FakeChannel();
      return ch;
    }

    test('connect sends helm.subscribe with the configured topics', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs', 'customers'],
        channelFactory: makeChannel,
      );
      await stream.connect();
      // Allow the microtask that sends the subscribe to run.
      await Future<void>.delayed(Duration.zero);
      expect(ch.sent, hasLength(1));
      final body = json.decode(ch.sent[0]) as Map<String, dynamic>;
      expect(body['method'], equals('helm.subscribe'));
      expect(body['params'], isA<Map>());
      final params = body['params'] as Map;
      expect(params['topics'], equals(['jobs', 'customers']));

      await stream.dispose();
    });

    test('subscribe ack flips state to subscribed', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      final stateLog = <HelmEventStreamState>[];
      stream.stateStream.listen(stateLog.add);

      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'subscribed': true,
          'topics': ['jobs']
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(stream.state, equals(HelmEventStreamState.subscribed));
      expect(stateLog, contains(HelmEventStreamState.subscribed));

      await stream.dispose();
    });

    test('helm.event notification parsed into a HelmEvent', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      final events = <HelmEvent>[];
      stream.events.listen(events.add);

      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'job.transitioned',
          'data': {
            'id': 'job-001',
            'from': 'lead',
            'to': 'quoted',
            'transitioned_at': '2026-05-02T14:30:00Z',
          },
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events, hasLength(1));
      expect(events[0].type, equals('job.transitioned'));
      expect(events[0].data['id'], equals('job-001'));
      expect(events[0].data['from'], equals('lead'));
      expect(events[0].data['to'], equals('quoted'));

      await stream.dispose();
    });

    test('multiple events arrive in order', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      final events = <HelmEvent>[];
      stream.events.listen(events.add);

      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      for (var i = 0; i < 3; i++) {
        ch.serverSend(json.encode({
          'jsonrpc': '2.0',
          'method': 'helm.event',
          'params': {
            'type': 'job.transitioned',
            'data': {'id': 'job-$i'},
          },
        }));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events, hasLength(3));
      expect(events[0].data['id'], equals('job-0'));
      expect(events[1].data['id'], equals('job-1'));
      expect(events[2].data['id'], equals('job-2'));

      await stream.dispose();
    });

    test('non-event server frames are ignored', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      final events = <HelmEvent>[];
      stream.events.listen(events.add);

      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': 99,
        'result': {'foo': 'bar'},
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events, isEmpty);
      await stream.dispose();
    });

    test('malformed frames are dropped without crashing', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      final events = <HelmEvent>[];
      stream.events.listen(events.add);

      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      ch.serverSend('not-json');
      ch.serverSend(json.encode({'foo': 'bar'}));
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {'data': {}},
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events, isEmpty);
      await stream.dispose();
    });

    test('reconnect attempts a fresh connect when server closes', () async {
      var connectCount = 0;
      final channels = <_FakeChannel>[];
      HelmStreamChannel countingFactory(Uri uri) {
        connectCount += 1;
        final newCh = _FakeChannel();
        channels.add(newCh);
        return newCh;
      }

      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: countingFactory,
        reconnectBackoff: const [Duration(milliseconds: 1)],
      );
      final stateLog = <HelmEventStreamState>[];
      stream.stateStream.listen(stateLog.add);

      await stream.connect();
      await Future<void>.delayed(Duration.zero);
      expect(connectCount, equals(1));

      // Server hangs up — HelmEventStream transitions to reconnecting
      // and then attempts a fresh connect.
      await channels[0].closeFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(stateLog, contains(HelmEventStreamState.reconnecting));
      expect(connectCount, greaterThanOrEqualTo(2));

      await stream.dispose();
    });

    test('disconnect prevents further reconnect attempts', () async {
      var connectCount = 0;
      final channels = <_FakeChannel>[];
      HelmStreamChannel countingFactory(Uri uri) {
        connectCount += 1;
        final newCh = _FakeChannel();
        channels.add(newCh);
        return newCh;
      }

      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: countingFactory,
        reconnectBackoff: const [Duration(milliseconds: 1)],
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);
      expect(connectCount, equals(1));

      await stream.disconnect();
      // Server-side close after disconnect should NOT trigger a
      // reconnect.
      await channels[0].closeFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(connectCount, equals(1));
      expect(stream.state, equals(HelmEventStreamState.disconnected));

      await stream.dispose();
    });

    test('connect appends ?bearer= query string for browser-style auth', () async {
      Uri? capturedUri;
      HelmStreamChannel capturingFactory(Uri uri) {
        capturedUri = uri;
        return _FakeChannel();
      }
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'cafef00d' * 8,
        topics: const ['jobs'],
        channelFactory: capturingFactory,
      );
      await stream.connect();
      expect(capturedUri, isNotNull);
      expect(capturedUri!.queryParameters['bearer'], equals('cafef00d' * 8));
      await stream.dispose();
    });
  });

  group('HelmEventStream.fetchSince', () {
    late _FakeChannel ch;
    HelmStreamChannel makeChannel(Uri uri) {
      ch = _FakeChannel();
      return ch;
    }

    test('happy path — request shape + parsed result', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);
      // Discard the initial subscribe frame.
      ch.sent.clear();

      final fut = stream.fetchSince(sinceTs: 1_700_000_000, limit: 10);
      // Pump so the request frame is queued.
      await Future<void>.delayed(Duration.zero);
      expect(ch.sent, hasLength(1));
      final req = json.decode(ch.sent.single) as Map<String, dynamic>;
      expect(req['method'], equals('helm.fetch_since'));
      final params = req['params'] as Map;
      expect(params['since_ts'], equals(1_700_000_000));
      expect(params['limit'], equals(10));
      final reqId = req['id'];
      expect(reqId, isA<int>());

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': reqId,
        'result': {
          'events': [
            {
              'event_id': '0000000000000001',
              'ts': 1_700_000_001,
              'kind': 'lead.created',
              'payload': {'id': 'L1', 'customer_name': 'Alice'},
            },
            {
              'event_id': '0000000000000002',
              'ts': 1_700_000_002,
              'kind': 'job.transitioned',
              'payload': {'id': 'J1', 'from': 'lead', 'to': 'quoted'},
            },
          ],
          'next_cursor_ts': 1_700_000_002,
        },
      }));

      final result = await fut;
      expect(result.events, hasLength(2));
      expect(result.events[0].type, equals('lead.created'));
      expect(result.events[0].eventId, equals('0000000000000001'));
      expect(result.events[0].ts, equals(1_700_000_001));
      expect(result.events[0].data['id'], equals('L1'));
      expect(result.events[0].data['customer_name'], equals('Alice'));
      expect(result.events[1].type, equals('job.transitioned'));
      expect(result.events[1].data['from'], equals('lead'));
      expect(result.nextCursorTs, equals(1_700_000_002));

      await stream.dispose();
    });

    test('paging — second call uses next_cursor_ts as new since_ts',
        () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);
      ch.sent.clear();

      // Page 1 — limit=2, returns 2 events with next_cursor_ts=20.
      final p1 = stream.fetchSince(sinceTs: 0, limit: 2);
      await Future<void>.delayed(Duration.zero);
      final r1 = json.decode(ch.sent.single) as Map<String, dynamic>;
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': r1['id'],
        'result': {
          'events': [
            {
              'event_id': '0000000000000001',
              'ts': 10,
              'kind': 'lead.created',
              'payload': {'id': 'L1'},
            },
            {
              'event_id': '0000000000000002',
              'ts': 20,
              'kind': 'lead.created',
              'payload': {'id': 'L2'},
            },
          ],
          'next_cursor_ts': 20,
        },
      }));
      final result1 = await p1;
      expect(result1.events, hasLength(2));
      expect(result1.nextCursorTs, equals(20));

      // Page 2 — caller passes next_cursor_ts back as sinceTs.
      ch.sent.clear();
      final p2 = stream.fetchSince(sinceTs: result1.nextCursorTs, limit: 2);
      await Future<void>.delayed(Duration.zero);
      final r2 = json.decode(ch.sent.single) as Map<String, dynamic>;
      expect((r2['params'] as Map)['since_ts'], equals(20));
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': r2['id'],
        'result': {
          'events': [
            {
              'event_id': '0000000000000003',
              'ts': 30,
              'kind': 'lead.created',
              'payload': {'id': 'L3'},
            },
          ],
          'next_cursor_ts': 30,
        },
      }));
      final result2 = await p2;
      expect(result2.events, hasLength(1));
      expect(result2.events.first.eventId, equals('0000000000000003'));
      expect(result2.nextCursorTs, equals(30));

      await stream.dispose();
    });

    test('timeout — throws HelmFetchSinceTimeout when no reply arrives',
        () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);
      ch.sent.clear();

      // Don't reply — wait for the timeout.
      expect(
        stream.fetchSince(
          sinceTs: 0,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<HelmFetchSinceTimeout>()),
      );
      // Pump past the timeout.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await stream.dispose();
    });

    test('JSON-RPC error reply — throws HelmFetchSinceError', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);
      ch.sent.clear();

      final fut = stream.fetchSince(sinceTs: 0);
      await Future<void>.delayed(Duration.zero);
      final req = json.decode(ch.sent.single) as Map<String, dynamic>;
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': req['id'],
        'error': {
          'code': -32603,
          'message': 'helm broker unavailable on this server',
        },
      }));
      await expectLater(
        fut,
        throwsA(isA<HelmFetchSinceError>()
            .having((e) => e.code, 'code', equals(-32603))
            .having((e) => e.message, 'message', contains('broker'))),
      );

      await stream.dispose();
    });

    test('disconnect fails pending fetches', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final fut = stream.fetchSince(
        sinceTs: 0,
        timeout: const Duration(seconds: 30),
      );
      await Future<void>.delayed(Duration.zero);

      await stream.disconnect();
      await expectLater(fut, throwsA(isA<HelmFetchSinceError>()));
    });

    test('throws StateError when called before connect', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      expect(
        () => stream.fetchSince(sinceTs: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('negative sinceTs is clamped to 0 on the wire', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);
      ch.sent.clear();

      // Schedule the request, then immediately reply.
      final fut = stream.fetchSince(sinceTs: -100);
      await Future<void>.delayed(Duration.zero);
      final req = json.decode(ch.sent.single) as Map<String, dynamic>;
      expect((req['params'] as Map)['since_ts'], equals(0));
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': req['id'],
        'result': {'events': [], 'next_cursor_ts': 0},
      }));
      final result = await fut;
      expect(result.events, isEmpty);

      await stream.dispose();
    });
  });
}

```
