---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/shell/interceptors/wallet_header_interceptor.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.903969+00:00
---

# archive/apps-semantos-monolith/lib/src/shell/interceptors/wallet_header_interceptor.dart

```dart
// Wallet-header Dio interceptor — BRC-52 capability disclosure.
//
// Every outbound API call carries:
//   Authorization: Bearer {bearer}          — existing auth gate
//   X-Brain-Cert: {childPubHex}             — BRC-42 child pub (identity)
//   X-Brain-Capabilities: {cap1,cap2,...}   — declared capability list
//
// This is the Phase-1 wallet-header surface.  Phase-2 (full BRC-52
// capability-proof signatures per request) requires the brain's cert
// verification endpoint to be live; the header names and claim shape
// defined here are forward-compatible with that transition.
//
// The interceptor is injected once at boot (after pairing) and removed
// if the operator unpairs.  The shell constructs a new Dio instance
// after each re-pair so this isn't a concern in practice.
//
// Why this interceptor and not just `ReplClient.withBearer`?
//   - `ReplClient` only attaches bearer to its own requests.
//   - The shell now has multiple clients (repl, mint, future SSE stream,
//     contact resolution).  A single Dio-level interceptor is the correct
//     layer — it's the "one throat to choke" for auth/identity headers.
//
// References:
//   - BRC-42: apps/semantos/lib/src/pairing/brc42_derive.dart
//   - BRC-52: docs/design/BRAIN-AUTH-MODEL.md §Phase-1b (parked)
//   - Per-request signing gap: memory `brain_auth_model_intent.md`

import 'package:dio/dio.dart';

/// Attaches BRC-52-flavoured identity headers to every Dio request.
///
/// Construct once per session after pairing and add to the Dio instance
/// that the shell passes into [ShellDeps].
class WalletHeaderInterceptor extends Interceptor {
  WalletHeaderInterceptor({
    required String bearer,
    required String childPubHex,
    required List<String> capabilities,
  })  : _bearer = bearer,
        _childPubHex = childPubHex,
        _capabilities = capabilities;

  final String _bearer;
  final String _childPubHex;
  final List<String> _capabilities;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    // Only inject on requests that don't already carry Authorization.
    // (Pairing and pre-auth flows set their own headers — don't stomp.)
    options.headers.putIfAbsent(
      'Authorization',
      () => 'Bearer $_bearer',
    );
    options.headers['X-Brain-Cert'] = _childPubHex;
    if (_capabilities.isNotEmpty) {
      options.headers['X-Brain-Capabilities'] = _capabilities.join(',');
    }
    handler.next(options);
  }
}

```
