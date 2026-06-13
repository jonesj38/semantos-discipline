---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/repositories/cell_query_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.118986+00:00
---

# apps/semantos/lib/src/repositories/cell_query_repository.dart

```dart
/// cell_query_repository.dart — the GENERIC, type-agnostic read path over the
/// WSS RPC channel. One repository serves every cell type: it issues
/// `cell.query(<typeHash>)` and returns the decoded rows as raw maps, leaving
/// shape interpretation to the manifest-driven renderer.
///
/// This is the canonical-schema seam (memory: semantos_canonical_schema_spine):
/// the root cause of oddjobz "circling" was conflating source-shape = cell =
/// model = UI. Here reads stay generic — no per-type Dart model — so the FIND
/// tabs (customers/quotes/visits/invoices) and any future cartridge are
/// queryable for free. JobsRepository keeps a typed model only because the Home
/// view needs FSM-bucket logic on top of the raw rows.
library;

import '../rpc/brain_rpc_client.dart';

class CellQueryRepository {
  final RpcCaller _rpc;

  const CellQueryRepository(this._rpc);

  /// Query all cells of [typeHash] (optionally [filter]ed). Returns the decoded
  /// rows from the brain's collection envelope (`{"<collection>":[…]}`) as raw
  /// maps. The collection key varies per type (jobs/customers/quotes/…), so we
  /// take the sole list value rather than hard-coding a key.
  Future<List<Map<String, dynamic>>> list(
    String typeHash, {
    Map<String, dynamic>? filter,
  }) async {
    final envelope = await _rpc.cellQuery(typeHash, filter: filter);
    final rows = _collection(envelope);
    return rows
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  /// Pull the single collection array out of the `{"<collection>":[…]}`
  /// envelope. Returns [] when the envelope has no list value.
  static List<dynamic> _collection(Map<String, dynamic> envelope) {
    for (final v in envelope.values) {
      if (v is List) return v;
    }
    return const [];
  }
}

```
