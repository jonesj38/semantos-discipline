---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/helm_event_stream.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.882705+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/helm_event_stream.dart

```dart
// D-O5.followup-4 — WSS live-tick stream client (mobile-helm side).
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5 (live helm
// substrate).
//
// Wraps a `WebSocketChannel` against the brain's `/api/v1/wallet`
// endpoint with bearer auth, sends `helm.subscribe` once the upgrade
// completes, and emits parsed `helm.event` notifications to a Stream
// the rest of the app listens to.
//
// Wire shape (server→client notification):
//
//     {"jsonrpc":"2.0","method":"helm.event",
//      "params":{"type":"job.transitioned",
//                "data":{"id":"...", "from":"lead", "to":"quoted",
//                        "transitioned_at":"2026-05-02T..."}}}
//
// Reconnect strategy: exponential backoff (1s, 2s, 4s, 8s, max 30s)
// — we keep retrying forever; the outer app calls `disconnect()` on
// logout/unpair to stop the loop.  `state` is exposed as a Stream so
// UI can render a "live" / "reconnecting" indicator.

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';


/// Minimal channel surface HelmEventStream consumes — exposed as a
/// test seam so unit tests can build a fully in-memory pipe without
/// depending on `WebSocketChannel`'s constructor shape (which varies
/// across web_socket_channel versions and platforms).  Production
/// uses `_WebSocketChannelAdapter` below; tests inject their own.
abstract class HelmStreamChannel {
  /// Server→client byte/text frames.  Closes when the server hangs
  /// up; HelmEventStream treats `done` as a signal to reconnect.
  Stream<dynamic> get stream;

  /// Send a server-bound text frame.
  void sendText(String data);

  /// Close the channel (client side).
  Future<void> close();
}

/// Lifecycle state of the live-tick stream — surfaced to the UI for
/// the AppBar indicator dot.
enum HelmEventStreamState {
  disconnected,
  connecting,
  subscribed,
  reconnecting,
}

/// One event delivered by the brain's helm event broker.  The
/// substrate is type-agnostic — every emitter publishes a `type`
/// token (e.g. "job.transitioned") + an opaque `data` map; the helm
/// dispatches on `type`.  Adding new event sources doesn't require
/// HelmEventStream changes.
class HelmEvent {
  /// Stable event-type token, e.g. "job.transitioned".
  final String type;

  /// Decoded payload object.
  final Map<String, dynamic> data;

  /// Sovereign-push D.1 — the brain stamps every published event
  /// with a stable 16-hex `event_id`.  The live `helm.event` notify
  /// path doesn't surface this (the live stream pre-dates D.1) so
  /// the field is empty for events that arrived via subscribe;
  /// `helm.fetch_since` always populates it.  Used by the silent-
  /// push handler to dedupe local notifications against events the
  /// live stream already rendered.
  final String eventId;

  /// Sovereign-push D.1 — wall-clock timestamp the brain attached
  /// at publish time.  Empty (== 0) for live-stream events; always
  /// populated for fetch_since results.  The handler advances its
  /// last-seen cursor to the max ts of a fetch_since batch.
  final int ts;

  const HelmEvent({
    required this.type,
    required this.data,
    this.eventId = '',
    this.ts = 0,
  });
}

/// Sovereign-push D.2 — return shape for [HelmEventStream.fetchSince].
/// Mirrors the brain's response object 1:1 so the silent-push
/// handler can advance its cursor + render banners off a single
/// typed value.
class FetchSinceResult {
  /// Events newer than the request's `since_ts`, oldest first.
  /// Each [HelmEvent] carries its own [HelmEvent.eventId] +
  /// [HelmEvent.ts] so the handler can dedupe + advance the
  /// cursor without re-deriving them from `nextCursorTs`.
  final List<HelmEvent> events;

  /// The brain's cursor for the next page.  Equal to the input
  /// `since_ts` when the broker had nothing newer; equal to the
  /// last returned event's `ts` otherwise.  Callers requesting
  /// strictly newer events on the next page should pass this
  /// value verbatim back as the new `since_ts`.
  final int nextCursorTs;

  const FetchSinceResult({required this.events, required this.nextCursorTs});
}

/// Thrown when [HelmEventStream.fetchSince] doesn't see a response
/// within the configured timeout.  Surfaces to the silent-push
/// handler which logs + silently drops (the spec says no operator-
/// facing fetch-failed notifications — they retry on next foreground).
class HelmFetchSinceTimeout implements Exception {
  final Duration timeout;
  const HelmFetchSinceTimeout(this.timeout);
  @override
  String toString() =>
      'HelmFetchSinceTimeout: brain did not respond within $timeout';
}

/// Thrown when the brain returns a JSON-RPC error in response to
/// `helm.fetch_since`.  Carries the brain's code + message so log
/// aggregation can triage.  Code -32603 typically means the broker
/// is unavailable; -32602 means a malformed request (the client
/// didn't send `since_ts` correctly).
class HelmFetchSinceError implements Exception {
  final int code;
  final String message;
  const HelmFetchSinceError(this.code, this.message);
  @override
  String toString() => 'HelmFetchSinceError($code): $message';
}

/// D-DOG.1.0c Phase 3 F.1 — thrown when the brain returns a JSON-RPC
/// error reply to an `oddjobz.*` query verb.  Carries the brain's
/// code + message; the JobList screen swallows these and falls back
/// to the un-enriched row shape so a dropped enrichment doesn't
/// block the list from rendering.  Defined here (not in
/// `oddjobz_query_client.dart`) because [HelmEventStream]'s reply-
/// routing logic synthesises the exception when it sees a JSON-RPC
/// error envelope, and we'd otherwise have a circular import.
class OddjobzQueryError implements Exception {
  final int code;
  final String message;
  const OddjobzQueryError(this.code, this.message);
  @override
  String toString() => 'OddjobzQueryError($code): $message';
}

/// Factory for building a [HelmStreamChannel] from a URI.  Production
/// uses [_WebSocketChannelAdapter] (wrapping
/// `WebSocketChannel.connect`); tests inject a fake backed by a
/// `StreamController` so they can drive frames from inside the test
/// body.
typedef HelmStreamChannelFactory = HelmStreamChannel Function(Uri uri);

HelmStreamChannel _defaultChannelFactory(Uri uri) =>
    _WebSocketChannelAdapter(WebSocketChannel.connect(uri));

/// Production adapter: wraps a real WebSocketChannel into the
/// HelmStreamChannel surface HelmEventStream consumes.
class _WebSocketChannelAdapter implements HelmStreamChannel {
  final WebSocketChannel _ch;
  _WebSocketChannelAdapter(this._ch);

  @override
  Stream<dynamic> get stream => _ch.stream;

  @override
  void sendText(String data) => _ch.sink.add(data);

  @override
  Future<void> close() async {
    try {
      await _ch.sink.close();
    } catch (_) {
      // Already closed — ignore.
    }
  }
}

/// Live event stream bound to one (wssUrl, bearer, topics) triple.
///
/// Call `connect()` once at app boot post-pairing; the stream
/// reconnects automatically on transient failures.  Call
/// `disconnect()` on logout / unpair / app teardown to stop the
/// reconnect loop.
class HelmEventStream {
  /// `wss://<host>:<port>/api/v1/wallet`-shaped URL.  Schemes other
  /// than wss/ws pass through verbatim — callers are expected to
  /// pin the cert via the same path the REPL HTTP client does.
  final String wssUrl;

  /// 64-hex bearer token from ChildCertStore.  Sent both as a query-
  /// string fallback (`?bearer=<hex>`) AND as an `Authorization:
  /// Bearer ...` header where the WebSocket client supports custom
  /// headers.  The query-string fallback is what the Semantos Brain side
  /// recognises for browser clients (`runtime/semantos-brain/src/wss_wallet.zig`
  /// `parseBearerQuery`).
  final String bearer;

  /// Topics to subscribe to via `helm.subscribe`.  The brain side
  /// validates against a hard-coded set: jobs / customers / visits /
  /// quotes / invoices / attachments.
  final List<String> topics;

  /// Backoff schedule — 1s → 2s → 4s → 8s → 16s → 30s (capped).  Test
  /// override accepts a shorter sequence so the suite doesn't sleep.
  final List<Duration> reconnectBackoff;

  /// Test seam — production passes `WebSocketChannel.connect`.
  final HelmStreamChannelFactory _channelFactory;

  /// Internal state.
  HelmStreamChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  final StreamController<HelmEvent> _eventsCtl =
      StreamController<HelmEvent>.broadcast();
  final StreamController<HelmEventStreamState> _stateCtl =
      StreamController<HelmEventStreamState>.broadcast();
  HelmEventStreamState _state = HelmEventStreamState.disconnected;
  int _backoffIndex = 0;
  int _subscribeId = 1;
  bool _stopped = false;
  Timer? _reconnectTimer;
  // Sovereign-push D.2 — `helm.fetch_since` response routing.  The
  // verb is request/response (not subscribe/notify) so we need to
  // pair the brain's reply back to the awaiting Completer by id.
  // Map is small (typically 0–1 entries; the silent-push handler
  // serialises its calls) so a HashMap is fine.
  final Map<int, Completer<FetchSinceResult>> _pendingFetches = {};
  // D-DOG.1.0c Phase 3 F.1 — generic JSON-RPC reply routing for the
  // `oddjobz.*` query verbs.  Same pattern as `_pendingFetches` but
  // returns the raw `result` map so each query method can shape its
  // typed return.  Wave 2's site-pivot / customer-pivot screens will
  // also dispatch through here.  Errors surface as
  // [OddjobzQueryError] (declared in oddjobz_query_client.dart) via
  // the `Object` polymorphism — we use plain Map for the success
  // path and Exception subtypes for the error path so the consumer
  // can `await` and `catch` exactly the typed exceptions it cares
  // about.
  final Map<int, Completer<Map<String, dynamic>>> _pendingOddjobzQueries = {};
  // Tier 2P Phase B — oddjobz attention verbs return bare JSON arrays
  // (no named-key wrapper) as the JSON-RPC `result`.  A separate
  // pending map routes those replies back to List<dynamic> completers
  // without changing the existing Map-result contract above.
  final Map<int, Completer<List<dynamic>>> _pendingOddjobzListQueries = {};
  // Smoke-test pass #1, fix #13 — heartbeat timer.  Pokes a no-op
  // JSON-RPC frame at the Semantos Brain peer every 30s while subscribed.  If
  // the underlying TCP socket is dead, `sendText` either silently
  // queues into a buffer that the OS eventually rejects (RST → onDone)
  // or throws synchronously — both paths fall into _scheduleReconnect.
  Timer? _heartbeatTimer;
  static const _heartbeatInterval = Duration(seconds: 30);

  HelmEventStream({
    required this.wssUrl,
    required this.bearer,
    required this.topics,
    List<Duration>? reconnectBackoff,
    HelmStreamChannelFactory? channelFactory,
  })  : reconnectBackoff = reconnectBackoff ??
            const [
              Duration(seconds: 1),
              Duration(seconds: 2),
              Duration(seconds: 4),
              Duration(seconds: 8),
              Duration(seconds: 16),
              Duration(seconds: 30),
            ],
        _channelFactory = channelFactory ?? _defaultChannelFactory;

  /// Stream of decoded events from the brain.  The stream is
  /// broadcast — multiple listeners (JobsRepository, dashboard
  /// indicator, debug overlay) can subscribe simultaneously.
  Stream<HelmEvent> get events => _eventsCtl.stream;

  /// Stream of state transitions — UI renders a live/reconnecting
  /// dot from this.  Broadcast.  The current value is also available
  /// synchronously via [state].
  Stream<HelmEventStreamState> get stateStream => _stateCtl.stream;

  /// Synchronous read of the current lifecycle state.
  HelmEventStreamState get state => _state;

  /// Open the connection.  Idempotent — calling twice while already
  /// connected is a no-op.
  Future<void> connect() async {
    if (_state == HelmEventStreamState.connecting ||
        _state == HelmEventStreamState.subscribed) {
      return;
    }
    _stopped = false;
    await _openOnce();
  }

  /// Smoke-test pass #1, fix #13 — force-reconnect immediately,
  /// bypassing the exponential backoff wait.
  ///
  /// Use this when the app has external knowledge that the previous
  /// connection is dead (e.g. phone screen just woke from sleep).
  /// Cancels any pending backoff timer + tears down the existing
  /// channel + opens a fresh one.  Resets the backoff index so the
  /// NEXT failure starts from 1s again.
  Future<void> forceReconnect() async {
    if (_stopped) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _backoffIndex = 0;
    await _socketSub?.cancel();
    _socketSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await ch.close();
      } catch (_) {
        // already closed
      }
    }
    await _openOnce();
  }

  /// Sovereign-push D.2 — issue `helm.fetch_since` and await the
  /// brain's reply.
  ///
  /// Sent over the same WSS the live-event subscribe rides on, so
  /// the silent-push handler reuses the bearer-authenticated
  /// connection HelmEventStream maintains for the helm UI.
  ///
  /// [sinceTs] — request events strictly newer than this Unix-
  /// seconds cursor.  Defaults to 0 (fetch everything in the
  /// brain's recent ring).  Negative values are clamped to 0.
  /// [limit] — server-side cap is 256.  When omitted the brain
  /// applies its default.  Callers wanting more than the page cap
  /// must paginate via [FetchSinceResult.nextCursorTs].
  /// [timeout] — defaults to 10s; throws [HelmFetchSinceTimeout]
  /// if the brain doesn't reply in time.
  ///
  /// Throws:
  ///   - [StateError] if not connected (caller must `connect()`
  ///     first; the silent-push handler does so on every wake).
  ///   - [HelmFetchSinceTimeout] on no-reply.
  ///   - [HelmFetchSinceError] on a JSON-RPC error reply.
  Future<FetchSinceResult> fetchSince({
    int? sinceTs,
    int? limit,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final ch = _channel;
    if (ch == null) {
      throw StateError(
        'fetchSince requires an open WSS — call connect() first',
      );
    }
    final id = _subscribeId++;
    final completer = Completer<FetchSinceResult>();
    _pendingFetches[id] = completer;

    final params = <String, dynamic>{
      'since_ts': (sinceTs ?? 0) < 0 ? 0 : (sinceTs ?? 0),
    };
    if (limit != null && limit > 0) params['limit'] = limit;

    try {
      ch.sendText(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': 'helm.fetch_since',
        'params': params,
      }));
    } catch (e) {
      _pendingFetches.remove(id);
      rethrow;
    }

    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        _pendingFetches.remove(id);
        throw HelmFetchSinceTimeout(timeout);
      });
    } finally {
      _pendingFetches.remove(id);
    }
  }

  /// D-DOG.1.0c Phase 3 F.1 — issue an `oddjobz.*` query verb and
  /// await the brain's reply.  Used by [OddjobzQueryClient] to route
  /// `oddjobz.list_sites`, `oddjobz.list_customers`, etc. through the
  /// same WSS the live-event subscribe rides on.
  ///
  /// Returns the unwrapped JSON-RPC `result` map verbatim — caller
  /// shapes it into typed model objects.  Throws:
  ///   - [StateError] if the WSS isn't open;
  ///   - [TimeoutException] when the brain doesn't reply in time;
  ///   - [OddjobzQueryError] (from `oddjobz_query_client.dart`) on a
  ///     JSON-RPC error reply.
  Future<Map<String, dynamic>> callOddjobzQuery(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final ch = _channel;
    if (ch == null) {
      throw StateError(
        'callOddjobzQuery requires an open WSS — call connect() first',
      );
    }
    final id = _subscribeId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingOddjobzQueries[id] = completer;

    try {
      ch.sendText(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }));
    } catch (e) {
      _pendingOddjobzQueries.remove(id);
      rethrow;
    }

    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        _pendingOddjobzQueries.remove(id);
        throw TimeoutException(
          'oddjobz query "$method" timed out',
          timeout,
        );
      });
    } finally {
      _pendingOddjobzQueries.remove(id);
    }
  }

  /// Tier 2P Phase B — variant of [callOddjobzQuery] for verbs whose
  /// JSON-RPC `result` is a bare array rather than an object.
  /// (`oddjobz.list_messages`, `oddjobz.list_dispatch_decisions`,
  /// `oddjobz.poll_attention_signals` all return `[...]` directly.)
  ///
  /// Returns the decoded list verbatim; the caller casts / filters rows.
  /// Throws the same error types as [callOddjobzQuery].
  Future<List<dynamic>> callOddjobzQueryList(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final ch = _channel;
    if (ch == null) {
      throw StateError(
        'callOddjobzQueryList requires an open WSS — call connect() first',
      );
    }
    final id = _subscribeId++;
    final completer = Completer<List<dynamic>>();
    _pendingOddjobzListQueries[id] = completer;

    try {
      ch.sendText(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }));
    } catch (e) {
      _pendingOddjobzListQueries.remove(id);
      rethrow;
    }

    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        _pendingOddjobzListQueries.remove(id);
        throw TimeoutException(
          'oddjobz list query "$method" timed out',
          timeout,
        );
      });
    } finally {
      _pendingOddjobzListQueries.remove(id);
    }
  }

  /// Close the connection + stop the reconnect loop.  Idempotent.
  /// After this returns, the stream remains valid but no further
  /// events will be delivered until `connect()` is called again.
  Future<void> disconnect() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    await _socketSub?.cancel();
    _socketSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) await ch.close();
    _failPendingFetches('helm event stream disconnected');
    _setState(HelmEventStreamState.disconnected);
  }

  /// Release the broadcast controllers — call on app teardown.
  Future<void> dispose() async {
    await disconnect();
    await _eventsCtl.close();
    await _stateCtl.close();
  }

  // ─── Internals ─────────────────────────────────────────────────────

  Future<void> _openOnce() async {
    _setState(HelmEventStreamState.connecting);
    try {
      final uri = _appendBearerQuery(Uri.parse(wssUrl), bearer);
      final ch = _channelFactory(uri);
      _channel = ch;

      // Send helm.subscribe immediately — the brain's frame loop
      // accepts the subscribe right after the WS upgrade completes.
      // The web_socket_channel package buffers writes until the
      // upgrade succeeds, so this is safe.
      _subscribe();

      _socketSub = ch.stream.listen(
        _onFrame,
        onError: (Object e, StackTrace st) {
          _scheduleReconnect();
        },
        onDone: () {
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _subscribe() {
    final id = _subscribeId++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': 'helm.subscribe',
      'params': {'topics': topics},
    });
    _channel?.sendText(body);
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
      return;
    }
    if (parsed is! Map) return;
    final method = parsed['method'];

    // Sovereign-push D.2 — `helm.fetch_since` reply: a JSON-RPC
    // response (no `method`) carrying the events array + cursor,
    // OR a JSON-RPC error.  Route by id back to the awaiting
    // Completer.
    final rawId = parsed['id'];
    if (method == null && rawId is int && _pendingFetches.containsKey(rawId)) {
      final completer = _pendingFetches.remove(rawId);
      if (completer == null || completer.isCompleted) return;
      final err = parsed['error'];
      if (err is Map) {
        final code = err['code'] is int ? err['code'] as int : -1;
        final msg =
            err['message'] is String ? err['message'] as String : 'unknown';
        completer.completeError(HelmFetchSinceError(code, msg));
        return;
      }
      final result = parsed['result'];
      if (result is! Map) {
        completer.completeError(
          const HelmFetchSinceError(
              -32603, 'helm.fetch_since: malformed result'),
        );
        return;
      }
      final eventsRaw = result['events'];
      final cursorRaw = result['next_cursor_ts'];
      final events = <HelmEvent>[];
      if (eventsRaw is List) {
        for (final ev in eventsRaw) {
          if (ev is! Map) continue;
          final kind = ev['kind'];
          if (kind is! String) continue;
          final eventId = ev['event_id'];
          final ts = ev['ts'];
          final payload = ev['payload'];
          final dataMap = payload is Map<String, dynamic>
              ? payload
              : (payload is Map
                  ? Map<String, dynamic>.from(payload)
                  : <String, dynamic>{});
          events.add(HelmEvent(
            type: kind,
            data: dataMap,
            eventId: eventId is String ? eventId : '',
            ts: ts is int ? ts : 0,
          ));
        }
      }
      final cursor = cursorRaw is int ? cursorRaw : 0;
      completer.complete(
        FetchSinceResult(events: events, nextCursorTs: cursor),
      );
      return;
    }

    // D-DOG.1.0c Phase 3 F.1 — `oddjobz.*` query reply routing.
    // Same shape as fetch_since: id-keyed Completer, error envelope
    // surfaces as OddjobzQueryError, success unwraps `result`.
    if (method == null && rawId is int &&
        _pendingOddjobzQueries.containsKey(rawId)) {
      final completer = _pendingOddjobzQueries.remove(rawId);
      if (completer == null || completer.isCompleted) return;
      final err = parsed['error'];
      if (err is Map) {
        final code = err['code'] is int ? err['code'] as int : -1;
        final msg =
            err['message'] is String ? err['message'] as String : 'unknown';
        completer.completeError(OddjobzQueryError(code, msg));
        return;
      }
      final result = parsed['result'];
      if (result is Map<String, dynamic>) {
        completer.complete(result);
        return;
      }
      if (result is Map) {
        completer.complete(Map<String, dynamic>.from(result));
        return;
      }
      completer.completeError(
        const OddjobzQueryError(-32603, 'oddjobz query: malformed result'),
      );
      return;
    }

    // Tier 2P Phase B — `oddjobz.*` attention verb reply routing
    // (bare array result).  The attention handler returns `[...]`
    // directly as the JSON-RPC result, so result is a List, not a Map.
    if (method == null && rawId is int &&
        _pendingOddjobzListQueries.containsKey(rawId)) {
      final completer = _pendingOddjobzListQueries.remove(rawId);
      if (completer == null || completer.isCompleted) return;
      final err = parsed['error'];
      if (err is Map) {
        final code = err['code'] is int ? err['code'] as int : -1;
        final msg =
            err['message'] is String ? err['message'] as String : 'unknown';
        completer.completeError(OddjobzQueryError(code, msg));
        return;
      }
      final result = parsed['result'];
      if (result is List) {
        completer.complete(result);
        return;
      }
      completer.completeError(
        const OddjobzQueryError(-32603, 'oddjobz list query: malformed result'),
      );
      return;
    }

    // Subscribe ack — toggle into `subscribed` state on the first
    // result with `subscribed: true` (the Semantos Brain response shape).
    if (method == null && parsed['result'] is Map) {
      final result = parsed['result'] as Map;
      if (result['subscribed'] == true) {
        _backoffIndex = 0;
        _setState(HelmEventStreamState.subscribed);
      }
      return;
    }
    if (method == 'helm.event') {
      final params = parsed['params'];
      if (params is! Map) return;
      final type = params['type'];
      if (type is! String) return;
      final data = params['data'];
      final dataMap = data is Map<String, dynamic>
          ? data
          : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
      // Live `helm.event` notifications pre-date D.1's monotonic
      // (event_id, ts) stamping — they don't carry those fields on
      // the wire; the dedupe path uses fetch_since payloads.
      _eventsCtl.add(HelmEvent(type: type, data: dataMap));
    }
  }

  /// Sovereign-push D.2 — fail every still-pending fetch_since with
  /// a [HelmFetchSinceError].  Called on disconnect/dispose so the
  /// silent-push handler doesn't hang on a Future the brain will
  /// never reply to.  D-DOG.1.0c Phase 3 F.1 also drains any
  /// in-flight `oddjobz.*` queries with [OddjobzQueryError] so the
  /// JobList enrichment Futures don't hang past disconnect either.
  void _failPendingFetches(String reason) {
    if (_pendingFetches.isNotEmpty) {
      final completers = _pendingFetches.values.toList();
      _pendingFetches.clear();
      for (final c in completers) {
        if (!c.isCompleted) {
          c.completeError(HelmFetchSinceError(-32000, reason));
        }
      }
    }
    if (_pendingOddjobzQueries.isNotEmpty) {
      final completers = _pendingOddjobzQueries.values.toList();
      _pendingOddjobzQueries.clear();
      for (final c in completers) {
        if (!c.isCompleted) {
          c.completeError(OddjobzQueryError(-32000, reason));
        }
      }
    }
    if (_pendingOddjobzListQueries.isNotEmpty) {
      final completers = _pendingOddjobzListQueries.values.toList();
      _pendingOddjobzListQueries.clear();
      for (final c in completers) {
        if (!c.isCompleted) {
          c.completeError(OddjobzQueryError(-32000, reason));
        }
      }
    }
  }

  void _scheduleReconnect() {
    if (_stopped) {
      _setState(HelmEventStreamState.disconnected);
      return;
    }
    _setState(HelmEventStreamState.reconnecting);
    final wait = reconnectBackoff[
        _backoffIndex.clamp(0, reconnectBackoff.length - 1)];
    if (_backoffIndex < reconnectBackoff.length - 1) _backoffIndex += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(wait, () {
      if (_stopped) return;
      _openOnce();
    });
  }

  void _setState(HelmEventStreamState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateCtl.isClosed) _stateCtl.add(s);
    // Smoke-test pass #1, fix #13 — manage heartbeat lifecycle alongside
    // state.  Only run while subscribed; cancel in every other state.
    if (s == HelmEventStreamState.subscribed) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_stopped) return;
      // helm.ping is not a real method on brain — brain's frame loop will
      // respond with a method-not-found JSON-RPC error, which is
      // exactly the behaviour we want: a successful round-trip on a
      // live socket; an exception or onDone on a dead one.  We
      // intentionally pick a method we don't intend to expand later
      // so a future helm.ping doesn't accidentally cause side effects.
      try {
        _channel?.sendText(jsonEncode({
          'jsonrpc': '2.0',
          'id': _subscribeId++,
          'method': 'helm.heartbeat',
          'params': const <String, dynamic>{},
        }));
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}

/// Append `?bearer=<hex>` to the URI's query string.  Mirrors the
/// fallback the Semantos Brain side accepts for browser clients that can't
/// supply Authorization headers.
Uri _appendBearerQuery(Uri base, String bearer) {
  final qp = Map<String, dynamic>.from(base.queryParameters);
  qp['bearer'] = bearer;
  return base.replace(queryParameters: qp);
}

```
