---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/oddjobz_rpc.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.466269+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/oddjobz_rpc.dart

```dart
/// Minimal RPC seam required by the OddJobz field operator surfaces.
///
/// Semantos provides an adapter at the shell boundary; OddJobz UI/repositories
/// depend only on this cartridge-owned interface, not on shell internals.
abstract interface class OddjobzRpc {
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? params,
  ]);
  Future<Map<String, dynamic>> cellQuery(
    String typeHash, {
    Map<String, dynamic>? filter,
  });
  Future<String> replEval(String cmd);
}

```
