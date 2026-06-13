---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/rpc/rpc_methods.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.114496+00:00
---

# apps/semantos/lib/src/rpc/rpc_methods.dart

```dart
/// rpc_methods.dart — method-name constants for the unified WSS RPC channel
/// (`/api/v1/rpc`). Mirrors the Zig side: substrate methods are pre-registered
/// by `cmdServe` on the brain's `RpcRegistry`; cartridges add their own dotted
/// names. Keep this in lockstep with the brain's registration + RPC_METHOD
/// policies — it is the client half of the frozen contract.
library;

/// Substrate (brain-native) RPC methods.
class RpcMethods {
  RpcMethods._();

  /// Typed projection over the cell DAG by typeHash → `{"<collection>":[…]}`.
  /// No extra capability beyond a valid upgrade (read-open).
  static const String cellQuery = 'cell.query';

  /// Single cell by ref → `{"<singular>": {…}|null}`.
  static const String cellGet = 'cell.get';

  /// FSM verb dispatch via the in-process REPL → `{"result":…,"exit":…}`.
  /// Requires the operator capability (`cap.brain.admin`) on the brain.
  static const String replEval = 'repl.eval';

  /// Generic signed/unsigned cell mint.
  static const String cellsMint = 'cells.mint';

  // Subscription lifecycle (server→client push); wired in M2.
  static const String subscribe = 'subscribe';
  static const String unsubscribe = 'unsubscribe';
  static const String resume = 'resume';
}

```
