---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/rpc/rpc_error.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.114216+00:00
---

# apps/semantos/lib/src/rpc/rpc_error.dart

```dart
/// rpc_error.dart — typed error surfaced by an `err` frame on the WSS RPC
/// channel, plus the server→client `push` envelope. Codes mirror the brain:
/// unauthorized | forbidden | bad_request | unknown_method | not_found |
/// internal.
library;

class RpcError implements Exception {
  final String code;
  final String message;

  /// The request id this error answers (null for connection-level errors).
  final String? id;

  const RpcError({required this.code, required this.message, this.id});

  bool get isUnauthorized => code == 'unauthorized';
  bool get isForbidden => code == 'forbidden';
  bool get isUnknownMethod => code == 'unknown_method';
  bool get isNotFound => code == 'not_found';
  bool get isBadRequest => code == 'bad_request';

  @override
  String toString() => 'RpcError($code${id != null ? ' id=$id' : ''}): $message';
}

/// A server-initiated `push` frame (subscription delivery, M2+).
class RpcPush {
  final String? sub;
  final String channel;
  final Map<String, dynamic> payload;

  const RpcPush({this.sub, required this.channel, required this.payload});
}

```
