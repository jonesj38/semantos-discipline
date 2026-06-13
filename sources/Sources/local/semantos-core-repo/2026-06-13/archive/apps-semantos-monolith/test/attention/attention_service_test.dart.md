---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/attention/attention_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.908310+00:00
---

# archive/apps-semantos-monolith/test/attention/attention_service_test.dart

```dart
// Tier 2P Phase D.2 — AttentionService unit tests.
//
// Drives AttentionService via a fake OddjobzAttentionClient and a fake
// HelmEventStream.  Tests cover:
//
//   1. Initial poll on startPolling() emits all three streams.
//   2. signals stream emits parsed OddjobzAttentionSignal list.
//   3. pendingRatifications emits only requiresRatification==true decisions.
//   4. messagesForJob filters by _jobToPatches map.
//   5. job.transitioned helm event triggers a refresh.
//   6. lead.created helm event triggers a refresh.
//   7. dispose() cancels the timer and closes streams.

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import 'package:semantos/src/repl/attention_service.dart';
import 'package:semantos/src/repl/helm_event_stream.dart';
import 'package:semantos/src/repl/oddjobz_attention_client.dart';

// ── Fake HelmStreamChannel ────────────────────────────────────────────────

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

  // Auto-reply to any pending JSON-RPC call identified by method.
  // Returns the last frame whose method matches [method].
  Map<String, dynamic>? lastFrameFor(String method) {
    for (final s in sent.reversed) {
      final decoded = json.decode(s) as Map<String, dynamic>;
      if (decoded['method'] == method) return decoded;
    }
    return null;
  }
}

// ── HelmEventStream factory ───────────────────────────────────────────────

_FakeChannel? _fakeChannel;

HelmStreamChannel _fakeChannelFactory(Uri uri) {
  _fakeChannel = _FakeChannel();
  return _fakeChannel!;
}

Future<HelmEventStream> _connectFakeStream() async {
  final stream = HelmEventStream(
    wssUrl: 'ws://example.test/api/v1/wallet',
    bearer: 'a' * 64,
    topics: const ['jobs'],
    channelFactory: _fakeChannelFactory,
  );
  await stream.connect();
  // Allow the subscription to settle.
  await Future<void>.delayed(Duration.zero);
  return stream;
}

// ── Wire helpers ──────────────────────────────────────────────────────────

/// Build a minimal OddjobzAttentionSignal JSON row.
Map<String, dynamic> _signalRow({
  String kind = 'message',
  double score = 0.5,
  String ref = 'ref-1',
  String summary = 'test',
}) =>
    {
      'kind': kind,
      'score': score,
      'ref': ref,
      'summary': summary,
      'raw': <String, dynamic>{},
    };

/// Build a minimal OddjobzDispatchDecision JSON row.
Map<String, dynamic> _decisionRow({
  String sourcePatchId = 'patch-1',
  bool requiresRatification = false,
  String targetType = 'job',
  String targetRef = 'job-abc',
}) =>
    {
      'sourcePatchId': sourcePatchId,
      'lane': 'direct',
      'slot': 'talk.direct',
      'transport': 'direct',
      'confidence': 0.8,
      'requiresRatification': requiresRatification,
      'primaryTarget': {
        'type': targetType,
        'ref': targetRef,
        'score': 0.8,
      },
      'timestamp': 1714003200000,
    };

/// Build a minimal OddjobzMessagePatch JSON row.
Map<String, dynamic> _messageRow({
  String patchId = 'patch-1',
  String role = 'customer',
  String text = 'Hello',
}) =>
    {
      'patchId': patchId,
      'providerId': 'meta',
      'sessionId': 'meta:messenger:page:psid',
      'channel': 'meta_messenger',
      'recipientId': 'page',
      'role': role,
      'text': text,
      'timestamp': 1714003200000,
    };

/// Reply to all three pending attention verbs in sequence.
/// [ch] is the fake channel; we decode the id from each sent frame.
void _replyAll(
  _FakeChannel ch, {
  List<Map<String, dynamic>> signals = const [],
  List<Map<String, dynamic>> messages = const [],
  List<Map<String, dynamic>> decisions = const [],
}) {
  // Find and reply to each method in the sent queue.
  for (final s in List<String>.from(ch.sent)) {
    final frame = json.decode(s) as Map<String, dynamic>;
    final id = frame['id'] as int;
    final method = frame['method'] as String;
    switch (method) {
      case 'oddjobz.poll_attention_signals':
        ch.serverSend(json.encode({
          'jsonrpc': '2.0',
          'id': id,
          'result': signals,
        }));
        break;
      case 'oddjobz.list_messages':
        ch.serverSend(json.encode({
          'jsonrpc': '2.0',
          'id': id,
          'result': messages,
        }));
        break;
      case 'oddjobz.list_dispatch_decisions':
        ch.serverSend(json.encode({
          'jsonrpc': '2.0',
          'id': id,
          'result': decisions,
        }));
        break;
    }
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  // ─── 1. startPolling() triggers an immediate poll ─────────────────────

  test('startPolling triggers immediate poll and signals stream emits', () async {
    final helmStream = await _connectFakeStream();
    final ch = _fakeChannel!;

    final client = OddjobzAttentionClient(helmStream);
    final svc = AttentionService(client: client);

    final signalsEmitted = <List<OddjobzAttentionSignal>>[];
    final sub = svc.signals.listen(signalsEmitted.add);

    svc.startPolling();

    // Let the poll RPCs be sent.
    await Future<void>.delayed(Duration.zero);

    _replyAll(ch, signals: [_signalRow()]);

    await Future<void>.delayed(Duration.zero);

    expect(signalsEmitted, isNotEmpty);
    expect(signalsEmitted.last, hasLength(1));
    expect(signalsEmitted.last[0].ref, equals('ref-1'));

    await sub.cancel();
    await svc.dispose();
    await helmStream.dispose();
  });

  // ─── 2. signals stream correctly parses all kind variants ────────────

  test('signals stream parses dispatch / message / job kinds', () async {
    final helmStream = await _connectFakeStream();
    final ch = _fakeChannel!;

    final client = OddjobzAttentionClient(helmStream);
    final svc = AttentionService(client: client);

    final received = <List<OddjobzAttentionSignal>>[];
    final sub = svc.signals.listen(received.add);

    svc.startPolling();
    await Future<void>.delayed(Duration.zero);

    _replyAll(ch, signals: [
      _signalRow(kind: 'dispatch', score: 0.9, ref: 'r-dispatch'),
      _signalRow(kind: 'message', score: 0.7, ref: 'r-message'),
      _signalRow(kind: 'job', score: 0.5, ref: 'r-job'),
    ]);

    await Future<void>.delayed(Duration.zero);

    expect(received.last, hasLength(3));
    expect(received.last[0].kind, equals(OddjobzAttentionKind.dispatch));
    expect(received.last[1].kind, equals(OddjobzAttentionKind.message));
    expect(received.last[2].kind, equals(OddjobzAttentionKind.job));

    await sub.cancel();
    await svc.dispose();
    await helmStream.dispose();
  });

  // ─── 3. pendingRatifications filters correctly ────────────────────────

  test('pendingRatifications emits only requiresRatification==true decisions',
      () async {
    final helmStream = await _connectFakeStream();
    final ch = _fakeChannel!;

    final client = OddjobzAttentionClient(helmStream);
    final svc = AttentionService(client: client);

    final ratifications = <List<OddjobzDispatchDecision>>[];
    final sub = svc.pendingRatifications.listen(ratifications.add);

    svc.startPolling();
    await Future<void>.delayed(Duration.zero);

    _replyAll(ch, decisions: [
      _decisionRow(
          sourcePatchId: 'p-rat', requiresRatification: true),
      _decisionRow(
          sourcePatchId: 'p-no-rat', requiresRatification: false),
    ]);

    await Future<void>.delayed(Duration.zero);

    expect(ratifications, isNotEmpty);
    final last = ratifications.last;
    expect(last, hasLength(1));
    expect(last[0].sourcePatchId, equals('p-rat'));
    expect(last[0].requiresRatification, isTrue);

    await sub.cancel();
    await svc.dispose();
    await helmStream.dispose();
  });

  // ─── 4. messagesForJob filters by _jobToPatches ───────────────────────

  test('messagesForJob returns messages whose dispatch targets the given job',
      () async {
    final helmStream = await _connectFakeStream();
    final ch = _fakeChannel!;

    final client = OddjobzAttentionClient(helmStream);
    final svc = AttentionService(client: client);

    final jobMessages = <List<OddjobzMessagePatch>>[];
    final sub = svc.messagesForJob('job-abc').listen(jobMessages.add);

    svc.startPolling();
    await Future<void>.delayed(Duration.zero);

    // Dispatch: patch-1 → job-abc, patch-2 → job-xyz
    // Messages: patch-1 (job-abc), patch-2 (job-xyz), patch-3 (no dispatch)
    _replyAll(
      ch,
      messages: [
        _messageRow(patchId: 'patch-1', text: 'For job-abc'),
        _messageRow(patchId: 'patch-2', text: 'For job-xyz'),
        _messageRow(patchId: 'patch-3', text: 'Orphan'),
      ],
      decisions: [
        _decisionRow(sourcePatchId: 'patch-1', targetRef: 'job-abc'),
        _decisionRow(sourcePatchId: 'patch-2', targetRef: 'job-xyz'),
      ],
    );

    await Future<void>.delayed(Duration.zero);

    expect(jobMessages, isNotEmpty);
    final filtered = jobMessages.last;
    expect(filtered, hasLength(1));
    expect(filtered[0].patchId, equals('patch-1'));
    expect(filtered[0].text, equals('For job-abc'));

    await sub.cancel();
    await svc.dispose();
    await helmStream.dispose();
  });

  // ─── 5. job.transitioned helm event triggers refresh ──────────────────

  test('job.transitioned event triggers an additional refresh', () async {
    final helmStream = await _connectFakeStream();
    final ch = _fakeChannel!;

    final client = OddjobzAttentionClient(helmStream);
    final svc = AttentionService(
      client: client,
      eventStream: helmStream,
    );

    final signalCounts = <int>[];
    final sub = svc.signals.listen((s) => signalCounts.add(s.length));

    // First poll via startPolling().
    svc.startPolling();
    await Future<void>.delayed(Duration.zero);
    _replyAll(ch, signals: [_signalRow()]);
    await Future<void>.delayed(Duration.zero);

    final emissionsAfterFirst = signalCounts.length;

    // Emit job.transitioned — should trigger another poll.
    ch.serverSend(json.encode({
      'jsonrpc': '2.0',
      'method': 'helm.event',
      'params': {
        'type': 'job.transitioned',
        'data': {'id': 'job-xyz', 'from': 'lead', 'to': 'quoted'},
      },
    }));

    await Future<void>.delayed(Duration.zero);
    _replyAll(ch, signals: [_signalRow(), _signalRow(ref: 'ref-2')]);
    await Future<void>.delayed(Duration.zero);

    // Should have at least one more emission than after the first poll.
    expect(signalCounts.length, greaterThan(emissionsAfterFirst));

    await sub.cancel();
    await svc.dispose();
    await helmStream.dispose();
  });

  // ─── 6. lead.created helm event triggers refresh ──────────────────────

  test('lead.created event triggers an additional refresh', () async {
    final helmStream = await _connectFakeStream();
    final ch = _fakeChannel!;

    final client = OddjobzAttentionClient(helmStream);
    final svc = AttentionService(
      client: client,
      eventStream: helmStream,
    );

    int emitCount = 0;
    final sub = svc.signals.listen((_) => emitCount++);

    svc.startPolling();
    await Future<void>.delayed(Duration.zero);
    _replyAll(ch);
    await Future<void>.delayed(Duration.zero);

    final afterFirst = emitCount;

    ch.serverSend(json.encode({
      'jsonrpc': '2.0',
      'method': 'helm.event',
      'params': {
        'type': 'lead.created',
        'data': {'lead_id': 'lead-001'},
      },
    }));

    await Future<void>.delayed(Duration.zero);
    _replyAll(ch, signals: [_signalRow()]);
    await Future<void>.delayed(Duration.zero);

    expect(emitCount, greaterThan(afterFirst));

    await sub.cancel();
    await svc.dispose();
    await helmStream.dispose();
  });

  // ─── 7. dispose() closes streams ──────────────────────────────────────

  test('dispose closes signals and pendingRatifications streams', () async {
    final helmStream = await _connectFakeStream();
    final client = OddjobzAttentionClient(helmStream);
    final svc = AttentionService(client: client);

    bool signalsDone = false;
    bool pendingDone = false;

    svc.signals.listen(null, onDone: () => signalsDone = true);
    svc.pendingRatifications
        .listen(null, onDone: () => pendingDone = true);

    await svc.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(signalsDone, isTrue);
    expect(pendingDone, isTrue);

    await helmStream.dispose();
  });
}

```
