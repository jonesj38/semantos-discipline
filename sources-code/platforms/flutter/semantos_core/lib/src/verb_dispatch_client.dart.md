---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/verb_dispatch_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.013798+00:00
---

# platforms/flutter/semantos_core/lib/src/verb_dispatch_client.dart

```dart
import 'dart:convert';

/// Brain-side verb.dispatch primitive — uniform write-seam for declared
/// extension action verbs.
///
/// Wraps the JSON-RPC method `verb.dispatch(extensionId, verb, params)`
/// exposed by the brain's WSS dispatcher (see
/// `runtime/semantos-brain/src/verb_dispatcher.zig` for the walker
/// registry; the legacy per-extension methods like
/// `oddjobz.ratify_proposal` keep working in parallel).
///
/// Experience packages compose this client-side via typed wrappers
/// (e.g. `OddjobzRatifyClient.ratify(proposalId, sirProgram)` builds on
/// `VerbDispatchClient.dispatch(extensionId: "oddjobz", verb: "ratify_proposal", params: {...})`).
/// New extensions get the write surface for free — no brain code change.
abstract class VerbDispatchClient {
  /// Dispatch a verb call. Returns the walker's JSON-decoded result.
  ///
  /// [params] is the walker-defined payload shape (an empty object is
  /// sent when [params] is null/missing).
  Future<Map<String, dynamic>> dispatch({
    required String extensionId,
    required String verb,
    Map<String, dynamic>? params,
  });
}

/// Errors thrown by VerbDispatchClient implementations.
///
/// Maps the brain-side JSON-RPC error codes:
///   -32601 walker_not_found       (no walker registered for this verb)
///   -32602 invalid_params         (walker rejected the params)
///   -32603 walker_failed / oom    (walker ran but returned an error)
class VerbDispatchException implements Exception {
  final String message;
  final int? code;
  const VerbDispatchException(this.message, {this.code});

  /// True when the brain has no walker for this (extensionId, verb).
  /// Suggests the extension isn't installed on this brain, or the
  /// walker registration failed at boot.
  bool get isWalkerNotFound => code == -32601;

  /// True when the walker rejected the params shape — payload bug,
  /// not a deployment issue.
  bool get isInvalidParams => code == -32602;

  @override
  String toString() => code != null
      ? 'VerbDispatchException($code): $message'
      : 'VerbDispatchException: $message';
}

/// JSON-RPC envelope helper. Transport code (WSS / HTTP) consumes these
/// to build outgoing requests and decode incoming responses.
class VerbDispatchRpc {
  /// Build the `verb.dispatch` JSON-RPC params object.
  static Map<String, dynamic> dispatchParams({
    required String extensionId,
    required String verb,
    Map<String, dynamic>? params,
  }) {
    return {
      'extensionId': extensionId,
      'verb': verb,
      if (params != null) 'params': params,
    };
  }

  /// Decode a brain JSON-RPC response body into the walker's result
  /// object. Throws [VerbDispatchException] on error responses.
  static Map<String, dynamic> decodeResult(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const VerbDispatchException('verb.dispatch response not a JSON object');
    }
    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      throw VerbDispatchException(
        (error['message'] as String?) ?? 'unknown error',
        code: error['code'] as int?,
      );
    }
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      throw const VerbDispatchException('verb.dispatch result missing or not an object');
    }
    return result;
  }
}

```
