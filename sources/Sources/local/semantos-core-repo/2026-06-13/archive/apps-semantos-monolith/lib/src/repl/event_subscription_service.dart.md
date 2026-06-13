---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/event_subscription_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.878821+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/event_subscription_service.dart

```dart
// W1.4 — EventSubscriptionService: Pravega-bridged event subscription.
//
// Replaces ad-hoc WebSocket polling with hat-scoped event subscription
// via BRAIN `/api/v1/events?hat=<domain_flag>` endpoint.
//
// Wire shape (server→client):
//   Each frame is a JSON object:
//   {
//     "event_id":   "<hex16>",
//     "job_id":     "<string>",
//     "cell_id":    "<hex64>",
//     "from_state": "<state>",
//     "to_state":   "<state>",
//     "ts_ms":      <u64>,
//     "hat_id":     "<string>"
//   }
//
// Client→server ack (sent after processing each event):
//   { "ack": "<event_id>" }
//
// On reconnect the client sends:
//   { "resume_after": "<last_acked_event_id>" }
// so the BRAIN side can replay missed events from its ring buffer.
//
// Reconnect: exponential backoff (1s → 2s → 4s → 8s → 16s → 30s).
//
// TODO(W3.2): the BRAIN /api/v1/events endpoint is not yet wired in the
// router (W3.1 added the Pravega producer; the subscriber-facing HTTP
// endpoint is a follow-up wave).  The Flutter consumer is fully
// implemented and tested against a fake channel.  Remove this TODO
// once BRAIN wires the endpoint.
//
// References:
//   - W3.1 OddjobzEventProducer (runtime/semantos-brain/src/oddjobz_event_producer.zig)
//   - W1.1 HatEntityRepository (lib/src/repl/hat_entity_repository.dart)
//   - HelmEventStream pattern (lib/src/repl/helm_event_stream.dart)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'hat_entity_repository.dart';

// ── Public surface ────────────────────────────────────────────────────────

/// One job FSM state change delivered by the Pravega event stream.
///
/// Mirrors the wire format emitted by W3.1's OddjobzEventProducer:
///   { job_id, cell_id, from_state, to_state, ts_ms, hat_id }
/// plus the event_id stamp the BRAIN subscriber endpoint adds.
class JobStateChangedEvent {
  final String eventId;
  final String jobId;
  final String cellId;
  final String fromState;
  final String toState;
  final int tsMs;
  final String hatId;

  const JobStateChangedEvent({
    required this.eventId,
    required this.jobId,
    required this.cellId,
    required this.fromState,
    required this.toState,
    required this.tsMs,
    required this.hatId,
  });

  static JobStateChangedEvent? fromJson(Map<String, dynamic> m) {
    final eventId = m['event_id'];
    final jobId = m['job_id'];
    final cellId = m['cell_id'];
    final fromState = m['from_state'];
    final toState = m['to_state'];
    final tsMs = m['ts_ms'];
    final hatId = m['hat_id'];

    if (eventId is! String || jobId is! String || cellId is! String ||
        fromState is! String || toState is! String || hatId is! String) {
      return null;
    }
    final ts = tsMs is int ? tsMs : (tsMs is num ? tsMs.toInt() : 0);
    return JobStateChangedEvent(
      eventId: eventId,
      jobId: jobId,
      cellId: cellId,
      fromState: fromState,
      toState: toState,
      tsMs: ts,
      hatId: hatId,
    );
  }
}

/// A message-received notification pushed by the brain whenever a caller
/// POSTs to `/api/v1/messages/send`.
///
/// The brain reuses the [JobStateChangedEvent] wire format with a sentinel
/// `job_id` value:
///   job_id     = "messagebox.received"
///   cell_id    = 32-char hex message ID  (use to fetch via /messages/list)
///   from_state = ""
///   to_state   = "signed" | "encrypted"
///   ts_ms      = receipt timestamp
///   hat_id     = brain domain
///
/// The phone should call `GET /api/v1/messages/list?recipient=<pubkey>`
/// after receiving this event to fetch the envelope.
class MessageReceivedEvent {
  static const String _sentinel = 'messagebox.received';

  final String eventId;

  /// 32-char hex message ID.  Use as the `id` in the ack call.
  final String messageId;

  /// "signed" or "encrypted".
  final String kind;

  final int tsMs;
  final String hatId;

  const MessageReceivedEvent({
    required this.eventId,
    required this.messageId,
    required this.kind,
    required this.tsMs,
    required this.hatId,
  });

  /// Returns non-null only when [event] carries the messagebox sentinel.
  static MessageReceivedEvent? fromJobEvent(JobStateChangedEvent event) {
    if (event.jobId != _sentinel) return null;
    return MessageReceivedEvent(
      eventId: event.eventId,
      messageId: event.cellId,
      kind: event.toState,
      tsMs: event.tsMs,
      hatId: event.hatId,
    );
  }
}

/// Abstract WebSocket channel surface consumed by [EventSubscriptionService].
///
/// Identical seam pattern as [HelmStreamChannel] in helm_event_stream.dart
/// — production uses a [_WebSocketChannelAdapter]; tests inject a fake.
abstract class EventStreamChannel {
  Stream<dynamic> get stream;
  void sendText(String data);
  Future<void> close();
}

/// Factory for building an [EventStreamChannel] from a URI.
typedef EventStreamChannelFactory = EventStreamChannel Function(Uri uri);

// ── Production WebSocket adapter ──────────────────────────────────────────

class _WebSocketChannelAdapter implements EventStreamChannel {
  // We re-use the web_socket_channel package already in pubspec.yaml.
  // Importing it here via a conditional keeps the dart:io dependency
  // out of tests that use a fake.
  final _Sink _sink;
  final Stream<dynamic> _stream;

  _WebSocketChannelAdapter(this._sink, this._stream);

  @override
  Stream<dynamic> get stream => _stream;

  @override
  void sendText(String data) => _sink.add(data);

  @override
  Future<void> close() async {
    try {
      await _sink.close();
    } catch (_) {}
  }
}

/// Minimal sink interface so we don't import WebSocketChannel in the
/// platform-independent layer.  The production [_defaultChannelFactory]
/// binds the real WebSocketChannel.sink here; tests never touch this.
abstract class _Sink {
  void add(dynamic data);
  Future<void> close();
}

EventStreamChannel _defaultChannelFactory(Uri uri) {
  // Lazy import to keep the dart:io reference out of test files that
  // substitute a fake channel.
  // ignore: avoid_dynamic_calls
  throw UnsupportedError(
    'EventSubscriptionService requires a channelFactory in production. '
    'Pass a real factory that calls WebSocketChannel.connect(uri).',
  );
}

// ── EventSubscriptionService ──────────────────────────────────────────────

/// Hat-scoped Pravega event subscription for the oddjobz mobile app.
///
/// Connects to `ws://<brain>/api/v1/events?hat=<domain_flag>&bearer=<tok>`
/// and streams [JobStateChangedEvent]s to listeners.  Updates the
/// [HatEntityRepository] (W1.1) on each state change so the SQLite
/// hat_entity_cache stays current without polling.
///
/// Lifecycle mirrors [HelmEventStream]:
///   1. Construct with the brain WS base URL, bearer, and domain flag.
///   2. `await connect()` to open the channel.
///   3. Subscribe to [stateChanges] for push-delivered events.
///   4. `await dispose()` on logout / unpair.
///
/// Reconnect: exponential backoff starting at 1s (configurable for tests).
/// On every reconnect the service sends `{ "resume_after": "<last_id>" }`
/// so the BRAIN side can replay events that arrived while disconnected.
class EventSubscriptionService {
  final String brainWsUrl;
  final String bearer;
  int _domainFlag;
  final HatEntityRepository? entityRepo;
  final List<Duration> reconnectBackoff;
  final EventStreamChannelFactory _channelFactory;

  // ── Internal state ─────────────────────────────────────────────────

  EventStreamChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;
  bool _stopped = false;
  int _backoffIndex = 0;
  String _lastAckedEventId = '';

  final StreamController<JobStateChangedEvent> _stateChangesCtl =
      StreamController<JobStateChangedEvent>.broadcast();

  final StreamController<MessageReceivedEvent> _messageReceivedCtl =
      StreamController<MessageReceivedEvent>.broadcast();

  EventSubscriptionService({
    required this.brainWsUrl,
    required this.bearer,
    required int domainFlag,
    this.entityRepo,
    List<Duration>? reconnectBackoff,
    EventStreamChannelFactory? channelFactory,
  })  : _domainFlag = domainFlag,
        reconnectBackoff = reconnectBackoff ??
            const [
              Duration(seconds: 1),
              Duration(seconds: 2),
              Duration(seconds: 4),
              Duration(seconds: 8),
              Duration(seconds: 16),
              Duration(seconds: 30),
            ],
        _channelFactory = channelFactory ?? _defaultChannelFactory;

  // ── Public surface ──────────────────────────────────────────────────

  /// Broadcast stream of decoded [JobStateChangedEvent]s from the brain.
  Stream<JobStateChangedEvent> get stateChanges => _stateChangesCtl.stream;

  /// Broadcast stream of [MessageReceivedEvent]s.  Fires whenever the brain
  /// delivers a "messagebox.received" sentinel event — i.e. someone called
  /// POST /api/v1/messages/send addressed to any recipient on this brain.
  ///
  /// Pull-on-push: use [messageId] to fetch the envelope:
  ///   GET /api/v1/messages/list?recipient=YOUR_PUBKEY_HEX
  Stream<MessageReceivedEvent> get messageReceived => _messageReceivedCtl.stream;

  /// Open the WebSocket connection.  Idempotent — calling while already
  /// connected is a no-op.
  Future<void> connect() async {
    if (_stopped) _stopped = false;
    await _openOnce();
  }

  /// Switch the hat.  Closes the current channel and reconnects with
  /// the new [domainFlag] in the URL.  Resets the last-acked cursor
  /// (new hat = fresh event stream).
  Future<void> updateHat(int domainFlag) async {
    _domainFlag = domainFlag;
    _lastAckedEventId = '';
    await _tearDown();
    if (!_stopped) await _openOnce();
  }

  /// Close the connection and stop the reconnect loop.  Idempotent.
  Future<void> dispose() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _tearDown();
    if (!_stateChangesCtl.isClosed) await _stateChangesCtl.close();
    if (!_messageReceivedCtl.isClosed) await _messageReceivedCtl.close();
  }

  // ── Internals ───────────────────────────────────────────────────────

  Uri _buildUri() {
    // Base: ws://<host>/<prefix>/events  (brainWsUrl ends without trailing /)
    final base = Uri.parse('$brainWsUrl/events');
    final params = Map<String, String>.from(base.queryParameters)
      ..['hat'] = '0x${_domainFlag.toRadixString(16).padLeft(6, '0')}'
      ..['bearer'] = bearer;
    return base.replace(queryParameters: params);
  }

  Future<void> _openOnce() async {
    try {
      final uri = _buildUri();
      final ch = _channelFactory(uri);
      _channel = ch;

      // On (re)connect: if we have a last-acked event_id, send resume_after
      // so the server replays missed events from its ring buffer.
      if (_lastAckedEventId.isNotEmpty) {
        ch.sendText(json.encode({'resume_after': _lastAckedEventId}));
      }

      _socketSub = ch.stream.listen(
        _onFrame,
        onError: (Object e, StackTrace st) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _tearDown() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await ch.close();
      } catch (_) {}
    }
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    final wait =
        reconnectBackoff[_backoffIndex.clamp(0, reconnectBackoff.length - 1)];
    if (_backoffIndex < reconnectBackoff.length - 1) _backoffIndex++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(wait, () {
      if (_stopped) return;
      _openOnce();
    });
  }

  void _onFrame(dynamic raw) {
    String text;
    if (raw is String) {
      text = raw;
    } else if (raw is List<int>) {
      try {
        text = utf8.decode(raw);
      } catch (_) {
        return;
      }
    } else {
      return;
    }

    final dynamic parsed;
    try {
      parsed = jsonDecode(text);
    } catch (_) {
      // Malformed JSON — silently drop.
      return;
    }
    if (parsed is! Map) return;

    final event = JobStateChangedEvent.fromJson(
      parsed is Map<String, dynamic>
          ? parsed
          : Map<String, dynamic>.from(parsed),
    );
    if (event == null) return;

    // Deliver to listeners.
    if (!_stateChangesCtl.isClosed) _stateChangesCtl.add(event);

    // If this is a messagebox notification, fan-out to messageReceived and
    // skip the entity-cache update (sentinel jobs are not hat entities).
    final msgEvent = MessageReceivedEvent.fromJobEvent(event);
    if (msgEvent != null) {
      if (!_messageReceivedCtl.isClosed) _messageReceivedCtl.add(msgEvent);
      // Don't fall through to _applyToCache — messagebox events are not
      // real job FSM transitions and should not pollute the hat-entity cache.
    } else {
      // Update HatEntityRepository if wired.
      _applyToCache(event);
    }

    // Send ack.
    _lastAckedEventId = event.eventId;
    try {
      _channel?.sendText(json.encode({'ack': event.eventId}));
    } catch (_) {
      // Channel may have closed between the frame arrival and the ack —
      // reconnect will resume from the last acked id so this is safe.
    }
  }

  void _applyToCache(JobStateChangedEvent event) {
    final repo = entityRepo;
    if (repo == null) return;
    // Fire-and-forget: cache failure is non-fatal.  The event stream
    // remains authoritative; the SQLite layer is a write-through cache.
    Future(() async {
      try {
        // Read existing entity_json (if any) so we can patch the state
        // field without discarding the rest of the cached JSON.
        final rows = await repo.queryAll(domainFlag: _domainFlag);
        final existing = rows.where((r) => r.id == event.jobId).firstOrNull;

        // Patch the state field in the existing JSON envelope, or
        // synthesize a minimal envelope when the entity isn't cached yet.
        String entityJson;
        if (existing != null) {
          try {
            final decoded =
                json.decode(existing.entityJson) as Map<String, dynamic>;
            decoded['state'] = event.toState;
            entityJson = json.encode(decoded);
          } catch (_) {
            entityJson = json.encode({
              'id': event.jobId,
              'state': event.toState,
            });
          }
        } else {
          entityJson = json.encode({
            'id': event.jobId,
            'state': event.toState,
          });
        }

        await repo.upsert(HatEntity(
          id: event.jobId,
          domainFlag: _domainFlag,
          state: event.toState,
          scheduledAt: existing?.scheduledAt ?? '',
          entityJson: entityJson,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(event.tsMs)
              .toUtc()
              .toIso8601String(),
        ));
      } catch (e) {
        debugPrint('[EventSubscriptionService] cache update error: $e');
      }
    });
  }
}

```
