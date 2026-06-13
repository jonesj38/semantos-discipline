---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/repl/jam_event_stream.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.596561+00:00
---

# cartridges/jambox/mobile/lib/src/repl/jam_event_stream.dart

```dart
// D-G.3 — Jam-room WSS event stream.
//
// Mirrors apps/oddjobz-mobile/lib/src/repl/helm_event_stream.dart but
// subscribes to room:{roomId}:state instead of helm channels.
//
// Wire shape (server→client notification):
//
//     {"jsonrpc":"2.0","method":"jam.event",
//      "params":{"type":"jam.scene.launch",
//                "data":{"sceneId":"...", "launchedBy":"...", ...}}}
//
// Reconnect strategy: same exponential backoff (1s→2s→4s→8s→16s→30s)
// as HelmEventStream.  Cells queued locally during loss are replayed
// on reconnect via the LocalCellQueue.
//
// Usage:
//   final stream = JamEventStream(
//     wssUrl: record.brainWssEndpoint,
//     bearer: record.bearer,
//     roomId: roomId,
//   );
//   await stream.connect();
//   stream.events.listen((ev) { ... });

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Minimal channel surface JamEventStream consumes.
/// Test seam — production uses _WebSocketChannelAdapter.
abstract class JamStreamChannel {
  Stream<dynamic> get stream;
  void sendText(String data);
  Future<void> close();
}

/// Lifecycle state of the jam event stream.
enum JamEventStreamState {
  disconnected,
  connecting,
  subscribed,
  reconnecting,
}

/// One event delivered from the jam room's cell-relay channel.
class JamEvent {
  /// Stable event-type token, e.g. "jam.scene.launch".
  final String type;

  /// Decoded payload object.
  final Map<String, dynamic> data;

  const JamEvent({required this.type, required this.data});
}

typedef JamStreamChannelFactory = JamStreamChannel Function(Uri uri);

JamStreamChannel _defaultChannelFactory(Uri uri) =>
    _WebSocketChannelAdapter(WebSocketChannel.connect(uri));

class _WebSocketChannelAdapter implements JamStreamChannel {
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
    } catch (_) {}
  }
}

/// Live jam event stream bound to one (wssUrl, bearer, roomId) triple.
///
/// Subscribes to `room:{roomId}:state` on connect. Reconnects automatically
/// on transient failures with exponential backoff.
///
/// Cells queued in the [LocalCellQueue] during disconnection are replayed
/// once the stream re-enters `subscribed` state.
class JamEventStream {
  final String wssUrl;
  final String bearer;
  final String roomId;
  final List<Duration> reconnectBackoff;
  final JamStreamChannelFactory _channelFactory;

  JamStreamChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  final StreamController<JamEvent> _eventsCtl =
      StreamController<JamEvent>.broadcast();
  final StreamController<JamEventStreamState> _stateCtl =
      StreamController<JamEventStreamState>.broadcast();
  JamEventStreamState _state = JamEventStreamState.disconnected;
  int _backoffIndex = 0;
  int _subscribeId = 1;
  bool _stopped = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  static const _heartbeatInterval = Duration(seconds: 30);

  /// Pending LoomAction dispatches queued during loss.
  final List<Map<String, dynamic>> _outboundQueue = [];

  JamEventStream({
    required this.wssUrl,
    required this.bearer,
    required this.roomId,
    List<Duration>? reconnectBackoff,
    JamStreamChannelFactory? channelFactory,
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

  /// Stream of decoded jam events from the cell-relay.
  Stream<JamEvent> get events => _eventsCtl.stream;

  /// Stream of state transitions for the UI reconnecting indicator.
  Stream<JamEventStreamState> get stateStream => _stateCtl.stream;

  /// Current lifecycle state.
  JamEventStreamState get state => _state;

  /// Connect and begin subscribing. Idempotent.
  Future<void> connect() async {
    if (_state == JamEventStreamState.connecting ||
        _state == JamEventStreamState.subscribed) {
      return;
    }
    _stopped = false;
    await _openOnce();
  }

  /// Force-reconnect immediately (e.g. after screen wake).
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
      } catch (_) {}
    }
    await _openOnce();
  }

  /// Dispatch a LoomAction to the room.  If not currently subscribed, the
  /// action is queued and replayed once the stream reconnects.
  void dispatch(Map<String, dynamic> action) {
    if (_state == JamEventStreamState.subscribed) {
      _send(action);
    } else {
      _outboundQueue.add(action);
    }
  }

  /// Close the connection + stop the reconnect loop. Idempotent.
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
    _setState(JamEventStreamState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _eventsCtl.close();
    await _stateCtl.close();
  }

  // ─── Internals ──────────────────────────────────────────────────────────────

  Future<void> _openOnce() async {
    _setState(JamEventStreamState.connecting);
    try {
      final uri = _appendBearerQuery(Uri.parse(wssUrl), bearer);
      final ch = _channelFactory(uri);
      _channel = ch;

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
      'method': 'jam.subscribe',
      'params': {
        'channel': 'room:$roomId:state',
      },
    });
    _channel?.sendText(body);
  }

  void _send(Map<String, dynamic> action) {
    final id = _subscribeId++;
    try {
      _channel?.sendText(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': 'jam.dispatch',
        'params': action,
      }));
    } catch (_) {
      _scheduleReconnect();
    }
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

    // Subscribe ack.
    if (method == null && parsed['result'] is Map) {
      final result = parsed['result'] as Map;
      if (result['subscribed'] == true) {
        _backoffIndex = 0;
        _setState(JamEventStreamState.subscribed);
        // Replay any queued outbound actions.
        for (final action in List.of(_outboundQueue)) {
          _send(action);
        }
        _outboundQueue.clear();
      }
      return;
    }

    if (method == 'jam.event') {
      final params = parsed['params'];
      if (params is! Map) return;
      final type = params['type'];
      if (type is! String) return;
      final data = params['data'];
      final dataMap = data is Map<String, dynamic>
          ? data
          : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
      _eventsCtl.add(JamEvent(type: type, data: dataMap));
    }
  }

  void _scheduleReconnect() {
    if (_stopped) {
      _setState(JamEventStreamState.disconnected);
      return;
    }
    _setState(JamEventStreamState.reconnecting);
    final wait =
        reconnectBackoff[_backoffIndex.clamp(0, reconnectBackoff.length - 1)];
    if (_backoffIndex < reconnectBackoff.length - 1) _backoffIndex += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(wait, () {
      if (_stopped) return;
      _openOnce();
    });
  }

  void _setState(JamEventStreamState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateCtl.isClosed) _stateCtl.add(s);
    if (s == JamEventStreamState.subscribed) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_stopped) return;
      try {
        _channel?.sendText(jsonEncode({
          'jsonrpc': '2.0',
          'id': _subscribeId++,
          'method': 'jam.heartbeat',
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

Uri _appendBearerQuery(Uri base, String bearer) {
  final qp = Map<String, dynamic>.from(base.queryParameters);
  qp['bearer'] = bearer;
  return base.replace(queryParameters: qp);
}

```
