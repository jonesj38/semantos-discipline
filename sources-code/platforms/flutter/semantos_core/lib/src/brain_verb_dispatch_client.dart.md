---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/brain_verb_dispatch_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.014088+00:00
---

# platforms/flutter/semantos_core/lib/src/brain_verb_dispatch_client.dart

```dart
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'verb_dispatch_client.dart';

/// [VerbDispatchClient] implementation that speaks JSON-RPC 2.0 over a
/// WebSocket connection to the brain's `/api/v1/wallet` endpoint.
///
/// One WebSocket per dispatch (Phase 1 transport — same shape as the
/// TypeScript-side `BrainRpcCellWriter` in
/// `runtime/legacy-ingest/src/cell-writer/brain-rpc.ts`). A future
/// optimisation can multiplex requests over one persistent socket; the
/// public interface stays unchanged.
///
/// Bearer auth: passed via the `?bearer=<hex64>` query-string fallback
/// the brain's WSS upgrade handler accepts (browsers can't set custom
/// headers on `new WebSocket(...)`, so the query-string path is the
/// cross-platform choice — see `cartridges/bsv-anchor-bundle/brain/zig/
/// src/wss_wallet.zig` line ~182).
///
/// Usage:
/// ```dart
/// final client = BrainVerbDispatchClient(
///   baseUrl: 'http://localhost:8424',
///   bearerToken: '<64-hex>',
/// );
/// final ack = await client.dispatch(
///   extensionId: 'tessera',
///   verb: 'tessera.harvest',
///   params: {'lotId': 'L1', 'grower': 'alice', 'volumeMl': 1000},
/// );
/// ```
class BrainVerbDispatchClient implements VerbDispatchClient {
  /// HTTP base URL of the brain (e.g. `http://localhost:8424` or
  /// `https://brain.example.com`). The client maps the scheme to its
  /// WebSocket equivalent: `http://…` → `ws://…`, `https://…` → `wss://…`.
  final String baseUrl;

  /// 64-hex bearer token (issued by `brain bearer issue`). Sent as a
  /// `?bearer=<token>` query-string parameter on the WS upgrade.
  final String bearerToken;

  /// Per-dispatch timeout. Defaults to 30 seconds.
  final Duration timeout;

  /// Optional override for the channel constructor — tests inject a
  /// fake to exercise request/response shapes without a real socket.
  final WebSocketChannel Function(Uri uri)? _channelFactory;

  /// Monotonically increasing request id. Each WS is one-shot so we
  /// could always use `1`, but a stable counter makes packet captures
  /// easier to read and matches the TS-side `BrainRpcCellWriter`.
  int _nextId = 0;

  BrainVerbDispatchClient({
    required this.baseUrl,
    required this.bearerToken,
    this.timeout = const Duration(seconds: 30),
    WebSocketChannel Function(Uri uri)? channelFactory,
  }) : _channelFactory = channelFactory;

  @override
  Future<Map<String, dynamic>> dispatch({
    required String extensionId,
    required String verb,
    Map<String, dynamic>? params,
  }) async {
    final id = ++_nextId;
    final request = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': 'verb.dispatch',
      'params': VerbDispatchRpc.dispatchParams(
        extensionId: extensionId,
        verb: verb,
        params: params,
      ),
    });

    final uri = _wsUri();
    final channel = (_channelFactory ?? WebSocketChannel.connect).call(uri);
    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription<dynamic> sub;

    Timer? timer;
    void finish(FutureOr<Map<String, dynamic>> Function() result) {
      if (completer.isCompleted) return;
      timer?.cancel();
      try {
        sub.cancel();
      } catch (_) {}
      try {
        channel.sink.close();
      } catch (_) {}
      Future.value(result()).then(completer.complete, onError: completer.completeError);
    }

    sub = channel.stream.listen(
      (message) {
        final raw = message is String ? message : utf8.decode(message as List<int>);
        try {
          // The brain emits exactly one JSON object per matched request;
          // discriminate by `id` so any unsolicited event traffic
          // (helm.event broadcasts on the same socket) is ignored.
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) return;
          if (decoded['id'] != id) return;
          finish(() => VerbDispatchRpc.decodeResult(raw));
        } catch (e) {
          finish(() => throw VerbDispatchException('decode failed: $e'));
        }
      },
      onError: (err) {
        finish(() => throw VerbDispatchException(
              'WSS error: $err',
              code: -32603,
            ));
      },
      onDone: () {
        if (completer.isCompleted) return;
        finish(() => throw const VerbDispatchException(
              'WSS closed before response',
              code: -32603,
            ));
      },
      cancelOnError: true,
    );

    timer = Timer(timeout, () {
      finish(() => throw VerbDispatchException(
            'verb.dispatch timed out after ${timeout.inSeconds}s',
            code: -32603,
          ));
    });

    try {
      channel.sink.add(request);
    } catch (e) {
      finish(() => throw VerbDispatchException(
            'WSS send failed: $e',
            code: -32603,
          ));
    }

    return completer.future;
  }

  /// Build the WSS URI: `<baseUrl>/api/v1/wallet?bearer=<token>`.
  /// `http://` → `ws://`, `https://` → `wss://`. Any non-http scheme
  /// (e.g. a ws:// URL passed directly) is preserved.
  Uri _wsUri() {
    final parsed = Uri.parse(baseUrl);
    final wsScheme = switch (parsed.scheme) {
      'http' => 'ws',
      'https' => 'wss',
      _ => parsed.scheme,
    };
    return parsed.replace(
      scheme: wsScheme,
      path: '${parsed.path}/api/v1/wallet'.replaceAll(RegExp(r'/+'), '/'),
      queryParameters: {
        ...parsed.queryParameters,
        'bearer': bearerToken,
      },
    );
  }
}

```
