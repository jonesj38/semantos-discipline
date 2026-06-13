---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/event_subscription_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.920516+00:00
---

# archive/apps-semantos-monolith/test/repl/event_subscription_service_test.dart

```dart
// W1.4 — EventSubscriptionService tests (red → green).
//
// Covers:
//   1. Connects to ws://<host>/api/v1/events?hat=<domain_flag>
//   2. Receives a job.state_changed event, notifies listeners
//   3. Updates HatEntityRepository when a job state change arrives
//   4. Reconnects on disconnect, resumes from last event_id
//   5. Hat change triggers resubscription on new URL
//   6. dispose() cancels the subscription and closes streams
//
// BRAIN endpoint status:
//   The /api/v1/events WebSocket is not yet wired in the BRAIN router
//   (W3.1 added the Pravega producer; the subscriber-facing HTTP
//   endpoint is a follow-up).  Tests drive a fake channel so the
//   Flutter consumer can be fully implemented and tested in isolation.
//   TODO(W3.2): remove this note once BRAIN wires the endpoint.
//
// Wire shape (server→client notification):
//   Each frame is a JSON object:
//     {
//       "event_id": "<hex16>",
//       "job_id":   "<string>",
//       "cell_id":  "<hex64>",
//       "from_state":"<state>",
//       "to_state":  "<state>",
//       "ts_ms":     <u64>,
//       "hat_id":    "<string>"
//     }
//
// Client→server ack (sent after processing each event):
//   { "ack": "<event_id>" }
//
// Reconnect: on disconnect the service waits for the configured
// backoff then reconnects.  On reconnect it sends:
//   { "resume_after": "<last_acked_event_id>" }
// so the server can replay missed events.

import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/repl/event_subscription_service.dart';
import 'package:semantos/src/repl/hat_entity_repository.dart';

// ── Fake WebSocket channel ────────────────────────────────────────────────

class _FakeEventChannel implements EventStreamChannel {
  final StreamController<dynamic> _toClient =
      StreamController<dynamic>.broadcast();
  final List<String> sent = <String>[];
  bool clientClosed = false;

  Uri? lastUri;

  @override
  Stream<dynamic> get stream => _toClient.stream;

  @override
  void sendText(String data) => sent.add(data);

  @override
  Future<void> close() async {
    clientClosed = true;
    if (!_toClient.isClosed) await _toClient.close();
  }

  void serverSend(Map<String, dynamic> frame) {
    if (!_toClient.isClosed) _toClient.add(json.encode(frame));
  }

  Future<void> closeFromServer() async {
    if (!_toClient.isClosed) await _toClient.close();
  }

  /// Return the last decoded JSON frame sent by the client, or null.
  Map<String, dynamic>? lastSent() {
    if (sent.isEmpty) return null;
    return json.decode(sent.last) as Map<String, dynamic>;
  }
}

// ── Channel factory ───────────────────────────────────────────────────────

class _FakeChannelFactory {
  final List<_FakeEventChannel> created = [];
  Uri? lastUri;

  EventStreamChannel call(Uri uri) {
    lastUri = uri;
    final ch = _FakeEventChannel()..lastUri = uri;
    created.add(ch);
    return ch;
  }

  _FakeEventChannel get latest => created.last;
}

// ── In-memory HatEntityRepository helper ─────────────────────────────────

Future<HatEntityRepository> _openInMemoryRepo() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(),
  );
  return HatEntityRepository.fromDatabase(db);
}

// ── A minimal job state event ─────────────────────────────────────────────

Map<String, dynamic> _jobStateEvent({
  String eventId = 'ev-0001',
  String jobId = 'job-abc',
  String cellId = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  String fromState = 'lead',
  String toState = 'quoted',
  int tsMs = 1714003200000,
  String hatId = 'hat-001',
}) =>
    {
      'event_id': eventId,
      'job_id': jobId,
      'cell_id': cellId,
      'from_state': fromState,
      'to_state': toState,
      'ts_ms': tsMs,
      'hat_id': hatId,
    };

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  // ─── 1. Connects to the correct URL ───────────────────────────────────

  test('connect opens ws://<host>/api/v1/events?hat=<domain_flag>', () async {
    final factory = _FakeChannelFactory();
    final svc = EventSubscriptionService(
      brainWsUrl: 'ws://brain.example/api/v1',
      bearer: 'b' * 64,
      domainFlag: 0x000101,
      channelFactory: factory.call,
      reconnectBackoff: const [Duration(milliseconds: 1)],
    );

    await svc.connect();
    await Future<void>.delayed(Duration.zero);

    expect(factory.lastUri, isNotNull);
    final uri = factory.lastUri!;
    expect(uri.path, equals('/api/v1/events'));
    expect(uri.queryParameters['hat'], equals('0x000101'));
    // Bearer is appended as a query param (same pattern as HelmEventStream).
    expect(uri.queryParameters['bearer'], equals('b' * 64));

    await svc.dispose();
  });

  // ─── 2. Receives an event, notifies listeners ─────────────────────────

  test('event from server is delivered to stateChanges stream', () async {
    final factory = _FakeChannelFactory();
    final svc = EventSubscriptionService(
      brainWsUrl: 'ws://brain.example/api/v1',
      bearer: 'b' * 64,
      domainFlag: 0x000101,
      channelFactory: factory.call,
      reconnectBackoff: const [Duration(milliseconds: 1)],
    );

    await svc.connect();
    await Future<void>.delayed(Duration.zero);

    final received = <JobStateChangedEvent>[];
    final sub = svc.stateChanges.listen(received.add);

    factory.latest.serverSend(_jobStateEvent(
      eventId: 'ev-0042',
      jobId: 'job-xyz',
      fromState: 'quoted',
      toState: 'scheduled',
    ));

    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    final ev = received.first;
    expect(ev.eventId, equals('ev-0042'));
    expect(ev.jobId, equals('job-xyz'));
    expect(ev.fromState, equals('quoted'));
    expect(ev.toState, equals('scheduled'));

    await sub.cancel();
    await svc.dispose();
  });

  // ─── 3. Event updates HatEntityRepository ────────────────────────────

  test('job state change event upserts new state into HatEntityRepository',
      () async {
    final repo = await _openInMemoryRepo();

    // Pre-seed the entity so the update has something to work with.
    await repo.upsert(HatEntity(
      id: 'job-abc',
      domainFlag: 0x000101,
      state: 'lead',
      scheduledAt: '',
      entityJson: '{"id":"job-abc","state":"lead"}',
      updatedAt: '2026-05-09T00:00:00Z',
    ));

    final factory = _FakeChannelFactory();
    final svc = EventSubscriptionService(
      brainWsUrl: 'ws://brain.example/api/v1',
      bearer: 'b' * 64,
      domainFlag: 0x000101,
      entityRepo: repo,
      channelFactory: factory.call,
      reconnectBackoff: const [Duration(milliseconds: 1)],
    );

    await svc.connect();
    await Future<void>.delayed(Duration.zero);

    factory.latest.serverSend(_jobStateEvent(
      eventId: 'ev-0001',
      jobId: 'job-abc',
      fromState: 'lead',
      toState: 'quoted',
    ));

    // Allow the async upsert to settle.
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final rows = await repo.queryAll(domainFlag: 0x000101);
    expect(rows, hasLength(1));
    expect(rows.first.state, equals('quoted'));

    await svc.dispose();
    await repo.close();
  });

  // ─── 4. Sends ack after processing each event ─────────────────────────

  test('service sends ack frame after processing an event', () async {
    final factory = _FakeChannelFactory();
    final svc = EventSubscriptionService(
      brainWsUrl: 'ws://brain.example/api/v1',
      bearer: 'b' * 64,
      domainFlag: 0x000101,
      channelFactory: factory.call,
      reconnectBackoff: const [Duration(milliseconds: 1)],
    );

    await svc.connect();
    await Future<void>.delayed(Duration.zero);

    factory.latest.serverSend(_jobStateEvent(eventId: 'ev-007'));

    await Future<void>.delayed(Duration.zero);

    final ch = factory.latest;
    expect(ch.sent, isNotEmpty);
    final ack = ch.lastSent();
    expect(ack, isNotNull);
    expect(ack!['ack'], equals('ev-007'));

    await svc.dispose();
  });

  // ─── 5. Reconnects and sends resume_after on reconnect ────────────────

  test('on disconnect, reconnects and sends resume_after with last event_id',
      () async {
    final factory = _FakeChannelFactory();
    final svc = EventSubscriptionService(
      brainWsUrl: 'ws://brain.example/api/v1',
      bearer: 'b' * 64,
      domainFlag: 0x000101,
      channelFactory: factory.call,
      reconnectBackoff: const [Duration(milliseconds: 1)],
    );

    await svc.connect();
    await Future<void>.delayed(Duration.zero);

    // Process one event so the service records a last-acked event_id.
    factory.latest.serverSend(_jobStateEvent(eventId: 'ev-abc'));
    await Future<void>.delayed(Duration.zero);

    // Simulate server disconnect.
    await factory.latest.closeFromServer();

    // Wait for reconnect (backoff is 1ms in test).
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // Expect a second channel was created (reconnect happened).
    expect(factory.created.length, greaterThanOrEqualTo(2));

    // The new channel should have received a resume_after frame.
    final newCh = factory.latest;
    final resumeFrame = newCh.sent
        .map((s) => json.decode(s) as Map<String, dynamic>)
        .where((f) => f.containsKey('resume_after'))
        .firstOrNull;
    expect(resumeFrame, isNotNull);
    expect(resumeFrame!['resume_after'], equals('ev-abc'));

    await svc.dispose();
  });

  // ─── 6. Hat change triggers resubscription ───────────────────────────

  test('updateHat closes old channel and reconnects with new hat in URL',
      () async {
    final factory = _FakeChannelFactory();
    final svc = EventSubscriptionService(
      brainWsUrl: 'ws://brain.example/api/v1',
      bearer: 'b' * 64,
      domainFlag: 0x000101,
      channelFactory: factory.call,
      reconnectBackoff: const [Duration(milliseconds: 1)],
    );

    await svc.connect();
    await Future<void>.delayed(Duration.zero);

    final firstChannel = factory.latest;

    // Switch hat.
    await svc.updateHat(0x000202);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // First channel should be closed.
    expect(firstChannel.clientClosed, isTrue);

    // A new channel should exist with the new hat.
    expect(factory.created.length, greaterThanOrEqualTo(2));
    final newUri = factory.lastUri!;
    expect(newUri.queryParameters['hat'], equals('0x000202'));

    await svc.dispose();
  });

  // ─── 7. dispose() stops reconnect loop ───────────────────────────────

  test('dispose closes the channel and stops reconnect', () async {
    final factory = _FakeChannelFactory();
    final svc = EventSubscriptionService(
      brainWsUrl: 'ws://brain.example/api/v1',
      bearer: 'b' * 64,
      domainFlag: 0x000101,
      channelFactory: factory.call,
      reconnectBackoff: const [Duration(milliseconds: 1)],
    );

    await svc.connect();
    await Future<void>.delayed(Duration.zero);

    final countBefore = factory.created.length;

    await svc.dispose();

    // Simulate server closing — should NOT trigger a new reconnect.
    if (factory.latest._toClient.hasListener) {
      factory.latest.serverSend(_jobStateEvent());
    }

    await Future<void>.delayed(const Duration(milliseconds: 20));

    // No new channels should have been created.
    expect(factory.created.length, equals(countBefore));
  });

  // ─── 8. Malformed frames are silently dropped ─────────────────────────

  test('malformed JSON frame does not throw and is silently ignored',
      () async {
    final factory = _FakeChannelFactory();
    final received = <JobStateChangedEvent>[];
    final svc = EventSubscriptionService(
      brainWsUrl: 'ws://brain.example/api/v1',
      bearer: 'b' * 64,
      domainFlag: 0x000101,
      channelFactory: factory.call,
      reconnectBackoff: const [Duration(milliseconds: 1)],
    );

    await svc.connect();
    await Future<void>.delayed(Duration.zero);

    final sub = svc.stateChanges.listen(received.add);

    // Send garbage.
    factory.latest.sendText('not valid json{{{');
    factory.latest._toClient.add('not valid json{{{');

    // Then a valid event.
    factory.latest.serverSend(_jobStateEvent(eventId: 'ev-clean'));

    await Future<void>.delayed(Duration.zero);

    // Only the valid event should have been delivered.
    expect(received, hasLength(1));
    expect(received.first.eventId, equals('ev-clean'));

    await sub.cancel();
    await svc.dispose();
  });
}

```
