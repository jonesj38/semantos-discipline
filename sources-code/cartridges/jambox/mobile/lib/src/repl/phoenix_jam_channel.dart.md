---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/repl/phoenix_jam_channel.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.596871+00:00
---

# cartridges/jambox/mobile/lib/src/repl/phoenix_jam_channel.dart

```dart
// Phoenix channel client for the jam room.
//
// Speaks the Phoenix v2 wire protocol (JSON arrays) over WebSocket.
// Connects to wss://world.semantos.me/jam/websocket and joins jam:<roomId>.
//
// Wire format — each message is a 5-element JSON array:
//   [join_ref, ref, topic, event, payload]
//
// Emitted events (via [events] stream):
//   type: 'snapshot'       — late-join replay; data has 'cells': List
//   type: 'drum'           — live cell push; data: {track, steps}
//   type: 'bpm'            — BPM broadcast; data: {bpm: number}
//   type: 'trigger'        — one-shot trigger; data: {kind, track, vel}
//   type: 'presence_state' — full presence map (on join)
//   type: 'presence_diff'  — {joins, leaves} diff
//
// Usage:
//   final ch = PhoenixJamChannel(
//     worldUrl: 'wss://world.semantos.me',
//     roomId: 'lobby',
//     handle: 'alice',
//   );
//   await ch.connect();
//   ch.events.listen((ev) { ... });
//   ch.commitCell({'kind': 'drum', 'track': 'kick', 'steps': [...]});
//   ch.sendBpm(128.0);

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

// ── Event types ───────────────────────────────────────────────────────────────

/// One event delivered from the Phoenix jam channel.
class PhoenixJamEvent {
  final String type;
  final Map<String, dynamic> data;
  const PhoenixJamEvent({required this.type, required this.data});
}

/// Peer info from Phoenix Presence.
class JamPeerInfo {
  final String id;
  final String handle;
  const JamPeerInfo({required this.id, required this.handle});
}

// ── State ─────────────────────────────────────────────────────────────────────

enum PhoenixJamState {
  disconnected,
  connecting,
  joined,
  reconnecting,
}

// ── Internals ─────────────────────────────────────────────────────────────────

typedef _ChannelFactory = WebSocketChannel Function(Uri uri);

WebSocketChannel _defaultFactory(Uri uri) => WebSocketChannel.connect(uri);

// ── PhoenixJamChannel ─────────────────────────────────────────────────────────

class PhoenixJamChannel {
  final String worldUrl;
  final String roomId;
  final String handle;
  final List<Duration> reconnectBackoff;
  final _ChannelFactory _factory;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;

  final _eventsCtl = StreamController<PhoenixJamEvent>.broadcast();
  final _stateCtl  = StreamController<PhoenixJamState>.broadcast();
  final _peersCtl  = StreamController<List<JamPeerInfo>>.broadcast();

  PhoenixJamState _state = PhoenixJamState.disconnected;
  bool _stopped = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  // Phoenix protocol counters.
  int _ref = 0;
  String? _joinRef;       // fixed for the lifetime of one join
  String get _topic => 'jam:$roomId';

  // Queued outbound pushes during reconnect.
  final List<Map<String, dynamic>> _outboundQueue = [];

  // Current presence map: peerId → metadata.
  final Map<String, dynamic> _presenceMap = {};

  static const _wsPath = '/jam/websocket';
  static const _vsn    = '2.0.0';
  static const _hbInterval = Duration(seconds: 30);

  static const _defaultBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  PhoenixJamChannel({
    required this.worldUrl,
    required this.roomId,
    required this.handle,
    List<Duration>? reconnectBackoff,
    _ChannelFactory? factory,
  })  : reconnectBackoff = reconnectBackoff ?? _defaultBackoff,
        _factory = factory ?? _defaultFactory;

  // ── Public API ──────────────────────────────────────────────────────────────

  Stream<PhoenixJamEvent>   get events     => _eventsCtl.stream;
  Stream<PhoenixJamState>   get stateStream => _stateCtl.stream;
  Stream<List<JamPeerInfo>> get peersStream  => _peersCtl.stream;
  PhoenixJamState           get state        => _state;

  /// Connect and join the room channel. Idempotent.
  Future<void> connect() async {
    if (_state == PhoenixJamState.connecting ||
        _state == PhoenixJamState.joined) return;
    _stopped = false;
    await _openOnce();
  }

  /// Force an immediate reconnect (e.g. after app foreground).
  Future<void> forceReconnect() async {
    if (_stopped) return;
    _reconnectTimer?.cancel();
    _backoffIdx = 0;
    await _teardown();
    await _openOnce();
  }

  /// Push a cell to the channel (drum steps, bpm, etc.).
  /// Server expects event "commit" with {"cell": <cell>} wrapper.
  /// Queued if not currently joined; replayed on reconnect.
  void commitCell(Map<String, dynamic> cell) {
    final payload = {'cell': cell};
    if (_state == PhoenixJamState.joined) {
      _push('commit', payload);
    } else {
      _outboundQueue.add({'__event': 'commit', '__payload': payload});
    }
  }

  /// Broadcast a BPM change.
  /// Server expects event "set_bpm" with {"bpm": <int>}.
  void sendBpm(double bpm) {
    final payload = {'bpm': bpm.round()};
    if (_state == PhoenixJamState.joined) {
      _push('set_bpm', payload);
    } else {
      _outboundQueue.add({'__event': 'set_bpm', '__payload': payload});
    }
  }

  /// Send a one-shot trigger (e.g. pad tap outside sequencer).
  void sendTrigger(Map<String, dynamic> trigger) {
    if (_state == PhoenixJamState.joined) {
      _push('trigger', trigger);
    } else {
      _outboundQueue.add({'__event': 'trigger', '__payload': trigger});
    }
  }

  /// Disconnect and stop reconnect loop. Idempotent.
  Future<void> disconnect() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    await _teardown();
    _setState(PhoenixJamState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _eventsCtl.close();
    await _stateCtl.close();
    await _peersCtl.close();
  }

  // ── Connection lifecycle ────────────────────────────────────────────────────

  int _backoffIdx = 0;

  Future<void> _openOnce() async {
    _setState(PhoenixJamState.connecting);
    try {
      final base = worldUrl.replaceFirst(RegExp(r'^http'), 'ws');
      final uri  = Uri.parse('$base$_wsPath').replace(
        queryParameters: {
          'vsn':    _vsn,
          'handle': handle,
        },
      );
      _ws    = _factory(uri);
      _wsSub = _ws!.stream.listen(
        _onFrame,
        onError: (Object _, StackTrace __) => _scheduleReconnect(),
        onDone:  () => _scheduleReconnect(),
        cancelOnError: false,
      );
      // Send phx_join
      _joinRef = _nextRef();
      _sendRaw([_joinRef, _nextRef(), _topic, 'phx_join', {'handle': handle}]);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _teardown() async {
    await _wsSub?.cancel();
    _wsSub = null;
    try { await _ws?.sink.close(); } catch (_) {}
    _ws = null;
    _joinRef = null;
  }

  void _scheduleReconnect() {
    if (_stopped) {
      _setState(PhoenixJamState.disconnected);
      return;
    }
    _setState(PhoenixJamState.reconnecting);
    _stopHeartbeat();
    final wait = reconnectBackoff[_backoffIdx.clamp(0, reconnectBackoff.length - 1)];
    if (_backoffIdx < reconnectBackoff.length - 1) _backoffIdx++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(wait, () {
      if (_stopped) return;
      _teardown().then((_) => _openOnce());
    });
  }

  void _setState(PhoenixJamState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateCtl.isClosed) _stateCtl.add(s);
    if (s == PhoenixJamState.joined) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }
  }

  // ── Frame handling ──────────────────────────────────────────────────────────

  void _onFrame(dynamic raw) {
    String text;
    if (raw is String) {
      text = raw;
    } else if (raw is List<int>) {
      try { text = utf8.decode(raw); } catch (_) { return; }
    } else {
      return;
    }

    final dynamic parsed;
    try { parsed = jsonDecode(text); } catch (_) { return; }
    if (parsed is! List || parsed.length != 5) return;

    // [join_ref, ref, topic, event, payload]
    final msgJoinRef = parsed[0] as String?;
    // final msgRef     = parsed[1];
    final msgTopic   = parsed[2] as String?;
    final msgEvent   = parsed[3] as String?;
    final msgPayload = parsed[4];

    if (msgTopic == null || msgEvent == null) return;

    // ── Heartbeat reply ────────────────────────────────────────────────────────
    if (msgTopic == 'phoenix' && msgEvent == 'phx_reply') return;

    // ── Phoenix channel messages for our topic ─────────────────────────────────
    if (msgTopic != _topic) return;

    switch (msgEvent) {
      // Join ack
      case 'phx_reply':
        final payload = msgPayload is Map ? msgPayload : {};
        if (payload['status'] == 'ok' && msgJoinRef == _joinRef) {
          _backoffIdx = 0;
          _setState(PhoenixJamState.joined);
          // Flush outbound queue — items are {__event, __payload, ...}
          for (final item in List.of(_outboundQueue)) {
            final event   = item['__event']   as String? ?? 'commit';
            final payload = item['__payload'] as Map<String, dynamic>?
                ?? Map<String, dynamic>.from(item)
                  ..remove('__event')
                  ..remove('__payload');
            _push(event, payload);
          }
          _outboundQueue.clear();
        }

      // Join error
      case 'phx_error':
        _scheduleReconnect();

      // Server-side close
      case 'phx_close':
        _scheduleReconnect();

      // Late-join snapshot: list of cells
      case 'snapshot':
        final data = _toMap(msgPayload);
        _eventsCtl.add(PhoenixJamEvent(type: 'snapshot', data: data));

      // Live cell push (drum, bpm, etc.)
      case 'cell':
        final data = _toMap(msgPayload);
        final kind = data['kind'] as String? ?? 'unknown';
        _eventsCtl.add(PhoenixJamEvent(type: kind, data: data));

      // BPM broadcast
      case 'bpm':
        _eventsCtl.add(PhoenixJamEvent(type: 'bpm', data: _toMap(msgPayload)));

      // One-shot trigger
      case 'trigger':
        _eventsCtl.add(PhoenixJamEvent(type: 'trigger', data: _toMap(msgPayload)));

      // Presence — full state on join
      case 'presence_state':
        if (msgPayload is Map) {
          final m = _toMap(msgPayload);
          _presenceMap.clear();
          _presenceMap.addAll(m);
          _emitPresence();
          _eventsCtl.add(PhoenixJamEvent(type: 'presence_state', data: m));
        }

      // Presence diff
      case 'presence_diff':
        if (msgPayload is Map) {
          final m      = _toMap(msgPayload);
          final joins  = msgPayload['joins'];
          final leaves = msgPayload['leaves'];
          if (joins  is Map) _presenceMap.addAll(_toMap(joins));
          if (leaves is Map) { for (final k in leaves.keys) _presenceMap.remove(k); }
          _emitPresence();
          _eventsCtl.add(PhoenixJamEvent(type: 'presence_diff', data: m));
        }
    }
  }

  static Map<String, dynamic> _toMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  void _emitPresence() {
    final peers = _presenceMap.entries.map((e) {
      final meta  = _toMap(e.value);
      final metas = meta['metas'];
      final first = (metas is List && metas.isNotEmpty) ? metas.first : meta;
      final h = (first is Map ? first['handle'] : null) as String? ?? e.key;
      return JamPeerInfo(id: e.key, handle: h);
    }).toList();
    if (!_peersCtl.isClosed) _peersCtl.add(peers);
  }

  // ── Wire helpers ────────────────────────────────────────────────────────────

  String _nextRef() => (++_ref).toString();

  void _push(String event, Map<String, dynamic> payload) {
    _sendRaw([null, _nextRef(), _topic, event, payload]);
  }

  void _sendRaw(List<dynamic> msg) {
    try {
      _ws?.sink.add(jsonEncode(msg));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  // ── Heartbeat ───────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_hbInterval, (_) {
      if (_stopped) return;
      _sendRaw([null, _nextRef(), 'phoenix', 'heartbeat', <String, dynamic>{}]);
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}

```
