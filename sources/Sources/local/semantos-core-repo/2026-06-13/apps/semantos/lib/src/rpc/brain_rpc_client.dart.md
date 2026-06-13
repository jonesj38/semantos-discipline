---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/rpc/brain_rpc_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.113915+00:00
---

# apps/semantos/lib/src/rpc/brain_rpc_client.dart

```dart
/// brain_rpc_client.dart — the single client for the brain's unified WSS RPC
/// channel (`/api/v1/rpc`). Replaces the per-call HTTP clients
/// (brain_http_client.dart, oddjobz_experience/operator/brain_client.dart):
/// reads (`cell.query`), FSM verbs (`repl.eval`), mint, conversation, voice,
/// and server→client push all ride ONE socket with request-id correlation.
///
/// Cross-platform: uses the platform-agnostic `WebSocketChannel.connect`, with
/// the bearer in a `?bearer=` query param (browsers can't set WS handshake
/// headers; the brain accepts the query fallback). Native builds may later move
/// to header auth via a custom connector.
///
/// M0 scope: connect + auth at upgrade, `call(method, params)` with id
/// correlation + `err`-frame → RpcError mapping, and a broadcast `pushes`
/// stream. Reconnect/resume hardening + subscription helpers land in M2/M5.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../dispatch/cell_minter.dart';
import 'rpc_error.dart';
import 'rpc_methods.dart';

/// Injectable channel factory (lets tests supply an in-memory duplex channel).
typedef RpcChannelConnector = WebSocketChannel Function(Uri uri);

/// The RPC surface repositories depend on. BrainRpcClient implements it;
/// tests supply a fake so repositories are exercised without a live socket.
abstract interface class RpcCaller {
  Future<Map<String, dynamic>> call(String method, [Map<String, dynamic>? params]);
  Future<Map<String, dynamic>> cellQuery(String typeHash, {Map<String, dynamic>? filter});
  Future<String> replEval(String cmd);
}

class BrainRpcClient implements RpcCaller, CellMinter {
  /// HTTP(S) base URL of the brain, e.g. `https://brain.example.com` — the
  /// scheme is mapped to ws/wss and the path replaced with `/api/v1/rpc`.
  final String baseUrl;
  final String bearer;
  final RpcChannelConnector _connect;

  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  int _seq = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<RpcPush> _pushes = StreamController<RpcPush>.broadcast();
  bool _closed = false;

  BrainRpcClient({
    required this.baseUrl,
    required this.bearer,
    RpcChannelConnector? connector,
  }) : _connect = connector ?? WebSocketChannel.connect;

  /// Server→client push frames (subscription deliveries).
  Stream<RpcPush> get pushes => _pushes.stream;

  bool get isConnected => _ch != null && !_closed;

  /// The ws(s) upgrade URI with the bearer query fallback.
  @visibleForTesting
  Uri get rpcUri {
    final b = Uri.parse(baseUrl);
    final secure = b.scheme == 'https' || b.scheme == 'wss';
    final scheme = secure ? 'wss' : 'ws';
    // Dart's Uri has no registered default port for the ws/wss schemes, so a
    // port-less https base URL would render as `wss://host:0/...` after the
    // scheme swap (b.port == 0). Pin the port explicitly: keep an explicit
    // non-zero port, otherwise fall back to the secure/insecure default.
    final port = (b.hasPort && b.port != 0) ? b.port : (secure ? 443 : 80);
    return b.replace(
      scheme: scheme,
      port: port,
      path: '/api/v1/rpc',
      queryParameters: {'bearer': bearer},
    );
  }

  /// Open the socket and start the receive loop. Awaits the handshake so a
  /// rejected upgrade (e.g. 401) surfaces here rather than on the first call.
  Future<void> connect() async {
    if (_ch != null) return;
    final ch = _connect(rpcUri);
    await ch.ready;
    _ch = ch;
    _sub = ch.stream.listen(
      (data) => handleRawFrame(data is String ? data : utf8.decode(data as List<int>)),
      onError: _failAllPending,
      onDone: () => _failAllPending(
        const RpcError(code: 'internal', message: 'socket closed'),
      ),
    );
  }

  /// Invoke an RPC method and await its `result` object. Throws [RpcError] on
  /// an `err` frame or a dropped connection.
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final ch = _ch;
    if (ch == null || _closed) {
      throw StateError('BrainRpcClient.call before connect() / after close()');
    }
    _seq += 1;
    final id = 'c$_seq';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    ch.sink.add(jsonEncode({
      't': 'req',
      'id': id,
      'method': method,
      'params': ?params,
    }));
    return completer.future;
  }

  // ── Convenience wrappers for the M0 substrate methods ────────────────────

  /// `cell.query` → the decoder's collection envelope (e.g. `{"jobs":[…]}`).
  @override
  Future<Map<String, dynamic>> cellQuery(
    String typeHash, {
    Map<String, dynamic>? filter,
  }) =>
      call(RpcMethods.cellQuery, {
        'typeHash': typeHash,
        'filter': ?filter,
      });

  /// `repl.eval` → the raw REPL output string (unwraps `{result,exit}`).
  @override
  Future<String> replEval(String cmd) async {
    final r = await call(RpcMethods.replEval, {'cmd': cmd});
    return (r['result'] as String? ?? '').trim();
  }

  // ── M1.7b — generic cell mint over the unified channel (CellMinter) ───────
  // Replaces the legacy POST /api/v1/cells path: the dispatcher mints through
  // `cells.mint`, which the brain backs with the SAME mintCellCore the HTTP
  // route uses (so behaviour can't drift). The request envelope is identical
  // to the old HTTP body, and the result is the same {cellId,cartridgeId,
  // cellType,persistedAt}. A brain rejection arrives as an err frame → RpcError.

  /// `cells.mint` (unsigned) — body `{typeHashHex, payload}`.
  @override
  Future<MintCellResult> mintCell({
    required String typeHashHex,
    required Map<String, dynamic> payload,
  }) =>
      _mint({'typeHashHex': typeHashHex, 'payload': payload});

  /// `cells.mint` (operator-signed) — adds `{signatureHex, signerCertIdHex}`.
  @override
  Future<MintCellResult> mintCellSigned({
    required String typeHashHex,
    required Map<String, dynamic> payload,
    required String signatureHex,
    required String signerCertIdHex,
  }) =>
      _mint({
        'typeHashHex': typeHashHex,
        'payload': payload,
        'signatureHex': signatureHex,
        'signerCertIdHex': signerCertIdHex,
      });

  Future<MintCellResult> _mint(Map<String, dynamic> params) async {
    final res = await call(RpcMethods.cellsMint, params);
    return MintCellResult.fromJson(res);
  }

  /// Register a pending request id and return its future, WITHOUT a socket —
  /// lets tests drive [handleRawFrame] for correlation/error-mapping coverage.
  @visibleForTesting
  Future<Map<String, dynamic>> awaitPendingForTest(String id) {
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    return c.future;
  }

  /// Route a parsed frame to its pending completer / push stream. Exposed for
  /// tests (the receive loop calls it for every inbound message).
  @visibleForTesting
  void handleRawFrame(String data) {
    final Map<String, dynamic> frame;
    try {
      frame = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return; // ignore non-JSON / non-object frames
    }
    switch (frame['t']) {
      case 'res':
        final c = _pending.remove(frame['id']);
        c?.complete(
          (frame['result'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        );
      case 'err':
        final c = _pending.remove(frame['id']);
        c?.completeError(RpcError(
          code: frame['code'] as String? ?? 'internal',
          message: frame['message'] as String? ?? '',
          id: frame['id'] as String?,
        ));
      case 'push':
        _pushes.add(RpcPush(
          sub: frame['sub'] as String?,
          channel: frame['channel'] as String? ?? '',
          payload: (frame['payload'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        ));
    }
  }

  void _failAllPending(Object error, [StackTrace? _]) {
    final err = error is RpcError
        ? error
        : RpcError(code: 'internal', message: error.toString());
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(err);
    }
    _pending.clear();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    await _ch?.sink.close();
    _failAllPending(const RpcError(code: 'internal', message: 'client closed'));
    await _pushes.close();
    _ch = null;
  }
}

```
