---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/repl_errors.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.881226+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/repl_errors.dart

```dart
// D-O5m — REPL HTTP error types.
//
// Mirror the TS error surface in
// `apps/loom-svelte/src/lib/repl-client.ts`. The mobile helm
// pattern-matches on these so it can:
//   - on UnauthorisedError: clear the persisted bearer + transition to
//     the pairing screen (the brain has revoked or rotated our cert);
//   - on ReplValidationError: surface the brain's message in-line in
//     the helm shell so the operator can correct their REPL line;
//   - on ReplBackendUnavailable: show a transient banner ("brain is
//     restarting — retry in a moment") without losing helm state.

/// Thrown on HTTP 401 from `POST /api/v1/repl`. The brain rejected
/// our bearer; the persisted cert is no longer valid for this
/// session. Typically maps to "operator revoked the device" or
/// "session expired".
class ReplUnauthorisedError implements Exception {
  final String reason;
  const ReplUnauthorisedError(this.reason);

  @override
  String toString() => 'ReplUnauthorisedError: $reason';
}

/// Thrown on HTTP 400 (validation failure). The brain rejected the
/// REPL line for shape reasons (unknown verb, malformed args, etc.).
///
/// D-O5m.followup-5 K1 conflict UI — when the brain returns a typed
/// JSON body (the canonical 400 shape), the full parsed body is
/// preserved on [body] so the outbox flush handler can extract typed
/// fields (the `error` wire kind, `from` for state_moved_on, etc.).
class ReplValidationError implements Exception {
  final String message;
  final Map<String, Object?>? body;
  const ReplValidationError(this.message, {this.body});

  @override
  String toString() => 'ReplValidationError: $message';
}

/// Thrown on HTTP 503 — REPL backend is intentionally not enabled in
/// this serve mode (e.g. the brain is in a restricted serve config),
/// or the brain is mid-restart.
class ReplBackendUnavailable implements Exception {
  final String message;
  const ReplBackendUnavailable(this.message);

  @override
  String toString() => 'ReplBackendUnavailable: $message';
}

/// Catch-all for non-2xx, non-recognised statuses + parse failures.
class ReplError implements Exception {
  final String message;
  const ReplError(this.message);

  @override
  String toString() => 'ReplError: $message';
}

```
