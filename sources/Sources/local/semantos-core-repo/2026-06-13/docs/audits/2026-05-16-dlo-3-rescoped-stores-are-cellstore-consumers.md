---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/audits/2026-05-16-dlo-3-rescoped-stores-are-cellstore-consumers.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.749768+00:00
---

# DLO.3 audit — domain entity stores consume CellStore, not LMDB directly

**Date**: 2026-05-16
**Status**: DECISION-PENDING-7 surfaced; DLO.3 rescoped from "refactor stores to consume StorageAdapter" to "lift stores into cartridge wholesale".

---

## Finding

`docs/prd/D-LIFT-ODDJOBZ.md` §Deliverables / DLO.3 scopes **"Per-store StorageAdapter migration"** — refactor each of the 6 domain entity stores (jobs, quotes, invoices, customers, leads, visits) to take a `StorageAdapter` constructor parameter instead of opening LMDB directly.

Audit result: **the stores don't open LMDB directly to begin with.** All 6 are thin wrappers over `cell_store_mod.CellStore` (brain's higher-level cell-storage substrate). The actual LMDB call sites are two layers down, inside `lmdb_cell_store.zig`.

Architecture is:

```
Cartridge code (oddjobz_*.zig, handlers, cli, intent_action_router)
       ↓ consume API
6 domain entity stores (jobs_store_lmdb, quotes_store_lmdb, …)
       ↓ consume CellStore
cell_store_mod.CellStore (brain substrate)
       ↓ vtable
lmdb/cell_store_lmdb.zig (brain substrate; LMDB-backed CellStore impl)
       ↓ LMDB calls
LMDB
```

Stores don't see LMDB at all. They encode entities into 1024-byte cells via `entity_cell.encodeCell`, write to `CellStore.put()`, scan via `CellStore.cursorOpen() + cursorPull()` filtering by domain flag or entity tag.

## Evidence

All 6 files import `cell_store`:

```
$ grep -l "cell_store" runtime/semantos-brain/src/{jobs,quotes,invoices,customers,leads,visits}_store_lmdb.zig
runtime/semantos-brain/src/jobs_store_lmdb.zig
runtime/semantos-brain/src/quotes_store_lmdb.zig
runtime/semantos-brain/src/invoices_store_lmdb.zig
runtime/semantos-brain/src/customers_store_lmdb.zig
runtime/semantos-brain/src/leads_store_lmdb.zig
runtime/semantos-brain/src/visits_store_lmdb.zig
```

None of them `@import("lmdb")` directly.

`jobs_store_lmdb.zig` header doc confirms: *"Wraps LmdbCellStore. put_job(cell) upserts a 1024-byte cell that MUST carry the Oddjobz job domain flag at cell header offset 24"*.

`quotes_store_lmdb.zig` header doc confirms: *"Each quote entity is serialised as a JSON payload packed into a 1024-byte cell via entity_cell.encodeCell and written to LmdbCellStore."*

LOC totals: jobs(108) + quotes(509) + invoices(572) + customers(770) + leads(945) + visits(529) = 3,433 LOC of cartridge-shaped store code, all consuming CellStore.

## What this means for DLO.3 scope

The PRD's plan ("refactor each store to take a StorageAdapter parameter") was based on an inaccurate model of the existing architecture. The right migration is **not** to inject StorageAdapter into the stores; it's to **lift the stores wholesale into the cartridge** (`extensions/oddjobz/zig/src/`) where they keep consuming brain-provided CellStore via a stable import.

In the corrected framing:
- Cartridge code → cartridge's own stores (extensions/oddjobz/zig/src/jobs_store_lmdb.zig etc.) → CellStore (brain substrate via @import)
- StorageAdapter (DLO.3a + DLO.3b.1, already shipped) becomes a **future** substrate consumption seam for CellStore itself (a later refactor), not for these stores directly.
- The cartridge's relationship to substrate stays clean: cartridge consumes CellStore (existing stable interface); brain owns CellStore + its LMDB-backed impl.

## DECISION-PENDING-7

Resolution options:

(a) **Rescope DLO.3 as a file-move lift** — move the 6 entity-store files from `runtime/semantos-brain/src/` to `extensions/oddjobz/zig/src/`; update brain-core import paths; the stores keep consuming CellStore unchanged. This is the natural carve given existing architecture. Effort: ~1 week (each file is mechanical; ~3,433 LOC moved).

(b) **Refactor CellStore to consume StorageAdapter first** (post-DLO.3), then the stores transitively benefit. Bigger substrate refactor (CellStore has many consumers beyond oddjobz); separate PRD-worthy work item.

(c) **Define a new CellStorageAdapter interface** that wraps CellStore. Cartridges consume CellStorageAdapter; brain provides CellStore-backed impl. Equivalent to (b) but with an explicit cartridge-facing seam.

Recommendation: **(a) for DLO.3**. The cartridge boundary is correctly drawn at the entity-store layer; the carve is a file move + import path update; preserves V1 production semantics; doesn't require touching brain-core CellStore. (b)/(c) become follow-up substrate work, possibly never needed (cartridges holding a CellStore reference is fine if CellStore is stable substrate).

## What's preserved from prior DLO.3 work

- `runtime/semantos-brain/src/storage_adapter.zig` (e77671f) — the vtable interface stays useful as substrate primitive that any future cartridge with key/value needs can consume. Memory-backed impl ships for testing.
- `runtime/semantos-brain/src/lmdb_storage_adapter.zig` (10feed0) — LMDB-backed impl stays useful for the same future cartridges. Not consumed by oddjobz, but ready for bsv-anchor-bundle's output store + derivation state if those decide to use it.

Neither is wasted work. Both are substrate primitives. The misscoped consumer was DLO.3b.2 (jobs_store_lmdb refactor); rescoping DLO.3 means DLO.3b.2 dissolves into "move the file."

## Consequences for remaining DLO timeline

| Original DLO | Rescoped action | Effort change |
|---|---|---|
| DLO.3a interface mirror | ✅ shipped (e77671f) | done |
| DLO.3b.1 LMDB impl | ✅ shipped (10feed0) | done |
| DLO.3b.2 jobs refactor | → File-move jobs_store_lmdb to cartridge | ~1 day (down from ~3 days) |
| DLO.3c-g remaining stores | → File-move 5 more stores | ~3 days (down from ~2 weeks) |
| **DLO.3 total remaining** | **~1 week** | **(down from ~3 weeks)** |

The rescope removes ~2 weeks from the oddjobz carve timeline. Net better than the original plan because the file moves are mechanical and the StorageAdapter primitives are now banked for future use.

## References

- `runtime/semantos-brain/src/jobs_store_lmdb.zig` (108 LOC, CellStore consumer)
- `runtime/semantos-brain/src/quotes_store_lmdb.zig` (509 LOC, CellStore consumer)
- `runtime/semantos-brain/src/{invoices,customers,leads,visits}_store_lmdb.zig` (2,816 LOC combined, all CellStore consumers)
- `runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig` (brain substrate; LMDB-backed CellStore impl)
- `docs/prd/D-LIFT-ODDJOBZ.md` §Deliverables / DLO.3 (now rescoped per this audit)
- Commits e77671f + 10feed0 (StorageAdapter primitives — preserved as substrate scaffold)
