---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/ENTITY-CELL-DECOMMISSION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.695492+00:00
---

# Entity-cell decommission — audit + true-state reconciliation

**Version**: 0.1 (audit)
**Date**: 2026-05-25
**Status**: AUDIT — Path A prerequisite for [UNIFICATION-ROADMAP §11.10 v0.12](UNIFICATION-ROADMAP.md) order 2e (real executor wiring)
**Master document**: [`docs/spec/UNIFIED-CELL-FORMAT-MIGRATION.md`](../spec/UNIFIED-CELL-FORMAT-MIGRATION.md) (Wave 10 RM-110, dated 2026-05-15, with 2026-05-16 reconciliation)

---

## Headline (TL;DR)

**The entity_cell migration to canonical 256-byte cell format is ~95% done already** — same pattern as the Phase 29.5 / D-LIFT / pre-flight discoveries earlier this session. The work I scoped in tasks #20-24 is largely redundant; ground-truth is:

1. **`runtime/semantos-brain/src/substrate_entity.zig` is the canonical replacement** (RM-111 landed). Mirrors `core/cell-engine/src/constants.zig` HEADER_OFFSET_* exactly. Includes `LinearityClass`, per-entity `EntityTypeSpec` registry, encode/decode + legacy-format detection.

2. **Every entity store has DUAL paths today** (RM-114 batches landed):
   - **Primary**: `substrate_entity.encodeEntity(...)` when `buf.len <= 768`
   - **Fallback**: `entity_cell.encodeCell(tag, buf)` for fat payloads >768

3. **entity_cell.zig is LOAD-BEARING residual fallback**, not dead code. Worst-case fat payloads: sites ≈ 2.0 KB, attachments ≈ 1.7 KB — both exceed the substrate 768-byte payload budget.

4. **RM-117 (delete entity_cell.zig) is PARKED** behind the **octave-pointer subsystem** (`OctaveAddress{octave,slot,fragment_count}` + `OP_DEREF_POINTER`) — its own subsystem program, not a line item in this audit's scope.

**Implication for §11.10 order 2e (#12 real executor wiring): NOT BLOCKED.** Cells written via the primary `substrate_entity` path have the canonical 256-byte header the executor expects. The fat-payload `entity_cell` fallback path is rare + already understood as residual. #12 can proceed; the fallback path will continue to no-op against the executor until the octave-pointer subsystem replaces it.

---

## §1 Canonical 256-byte header layout

From [`core/cell-engine/src/cell.zig`](../../core/cell-engine/src/cell.zig) + [`core/cell-engine/src/constants.zig`](../../core/cell-engine/src/constants.zig):

| Offset | Size | Field | Type | Notes |
|---:|---:|---|---|---|
| 0 | 16 | `magic` | raw bytes | `DE AD BE EF CA FE BA BE 13 37 13 37 42 42 42 42` |
| 16 | 4 | `linearity` | u32 LE | 1=LINEAR · 2=AFFINE · 3=RELEVANT · 4=DEBUG (K1) |
| 20 | 4 | `version` | u32 LE | `2` = current substrate cell version |
| 24 | 4 | `flags` | u32 LE | aka `domain_flag` (K3 — kernel-checkable per-cartridge sovereignty namespace) |
| 28 | 2 | `ref_count` | u16 LE | initial 0 |
| 30 | 32 | `type_hash` | [32]u8 | `sha256("{type_path}:{how_slug}:{inst_path}")` (kernel-checkable) |
| 62 | 16 | `owner_id` | [16]u8 | first 16 bytes of operator hat-id |
| 78 | 8 | `timestamp` | u64 LE | nanoseconds since epoch at mint |
| 86 | 4 | `cell_count` | u32 LE | 1 (no continuation in MVP) |
| 90 | 4 | `total_size` / `payload_total` | u32 LE | JSON payload length |
| 94-95 | 2 | *unnamed reserved* | — | former commerce-phase / dimension (RM-032b stripped) |
| 96 | 32 | `parent_hash` | [32]u8 | zeroed at first mint; FSM transitions chain it |
| 128 | 32 | `prev_state_hash` | [32]u8 | zeroed at first mint; FSM transitions chain it |
| 160-223 | 64 | *unnamed reserved* | — | former OnChainBinding region (RM-042 stripped; anchoring is via separate AnchorAttestation cells per `@semantos/anchor-attestation`) |
| 224 | 32 | `domain_payload_root` | [32]u8 | `sha256(payload_json)` |
| 256 | 768 | `payload` | UTF-8 JSON | zero-padded |

**Total: 1024 bytes** = `core/cell-engine/src/constants.zig:CELL_SIZE`.

Constants in `substrate_entity.zig` lines 38-55 mirror these exactly. The replacement format is the canonical format — no separate "substrate cell" definition.

---

## §2 entity_cell call site inventory

Two formats coexist by design (per spec line 197-200). All call sites audited 2026-05-25:

### Brain-core (4 files)

| File | Path | Status | Notes |
|---|---|---|---|
| `cell_handler.zig` | `runtime/semantos-brain/src/cell_handler.zig` | **entity_cell only** | Generic `cell.create`; `ENTITY_TAG_GENERIC_CARTRIDGE = 0x10`; no substrate_entity dual path. **Pure legacy.** |
| `attachments_store_lmdb.zig` | `runtime/semantos-brain/src/attachments_store_lmdb.zig` | **dual path** | Primary substrate_entity; entity_cell fallback for buf > 768 |
| `contact_book_lmdb.zig` | `runtime/semantos-brain/src/contact_book_lmdb.zig` | **entity_cell only** (verify) | Tags `ENTITY_TAG_CONTACT = 0x0A`, `ENTITY_TAG_EDGE = 0x0B`; 3 encodeCell calls — needs deeper inspection to confirm whether substrate_entity dual path is wired |
| `sites_store_lmdb.zig` | `runtime/semantos-brain/src/sites_store_lmdb.zig` | **dual path** | Primary substrate_entity; entity_cell fallback for buf > 768 |

### Cartridges (7 files in `cartridges/oddjobz/brain/zig/src/`)

| File | Status |
|---|---|
| `customers_store_lmdb.zig` | dual path (verified — substrate_entity primary, entity_cell for >768 buf) |
| `estimates_store_lmdb.zig` | dual path (same pattern) |
| `invoices_store_lmdb.zig` | dual path (same pattern) |
| `jobs_store_lmdb_entity.zig` | dual path (same pattern; `jobs_store_lmdb.zig` is the cursor wrapper, not a writer) |
| `leads_store_lmdb.zig` | dual path (same pattern) |
| `quotes_store_lmdb.zig` | dual path (same pattern) |
| `visits_store_lmdb.zig` | dual path (same pattern) |

### Special-purpose

| File | Role |
|---|---|
| `runtime/semantos-brain/src/migrate_entity_cells/main.zig` | Migration tool — reads BOTH formats; required until residual entity_cell-formatted data on disk is migrated. Stays alive until RM-117 closure. |
| `runtime/semantos-brain/src/substrate_entity.zig` | The replacement itself + `looksLikeLegacyEntityCell()` detector for backward-compat reads |

### Total

- **11 active call-site files** (not 4 as my pre-tick estimate suggested)
- **Only 2 are pure-legacy without dual path**: `cell_handler.zig` + (probably) `contact_book_lmdb.zig`
- **The remaining 9 already do the canonical thing when payload fits**, falling back to entity_cell only for fat payloads

---

## §3 Per-store migration plan — **mostly already done**

Tasks #20-24 in TaskList scoped this as "migrate 4 stores to canonical format." **Ground truth reframes that:**

| Original task | Reality | Reframed |
|---|---|---|
| #20 — Migrate cell_handler.zig | **Real work** — no substrate_entity dual path today | Keep as scoped; ~half day |
| #21 — Migrate attachments_store_lmdb.zig | **Already done** (dual path exists) | Delete task or repurpose as "audit + confirm primary path is reached for typical payloads" |
| #22 — Migrate contact_book_lmdb.zig | **Real work** — needs dual-path wiring like the others, OR confirm it shouldn't have a fallback (contact payloads are small) | Keep as scoped, ~half day |
| #23 — Migrate sites_store_lmdb.zig | **Already done** (dual path exists) | Delete task or repurpose as "audit" |
| #24 — Delete entity_cell.zig | **PARKED behind octave-pointer subsystem** per spec line 198 | Replace with: "scope the octave-pointer subsystem as a separate program" |

**Net actual remaining work for Path A:**
- 1 PR for `cell_handler.zig` (add substrate_entity primary path)
- 1 PR for `contact_book_lmdb.zig` (add substrate_entity primary path)
- Both ~half day each

**Then #12 can proceed** without waiting for entity_cell deletion. Cells written through the primary path are kernel-readable; the fat-payload fallback is rare and already documented as residual.

---

## §4 The fat-payload problem (why entity_cell can't just be deleted)

Per [spec line 200](../spec/UNIFIED-CELL-FORMAT-MIGRATION.md):

> Worst-case serialized JSON is **sites ≈ 2.0 KB**, **attachments ≈ 1.7 KB** — both exceed 768, so the `entity_cell.encodeCell` >768 fallback in those two stores is **load-bearing**, not removable dead code.

The canonical substrate cell has a 768-byte payload budget (1024 - 256 header). Some entity payloads are larger. The cell-engine has a continuation mechanism (`CONTINUATION_HEADER_SIZE = 8`) but it isn't yet exercised by entity stores.

The spec's recommended replacement mechanism is **octave-slot storage + a single pointer cell**:
- `OctaveAddress{octave, slot, fragment_count}` + `OP_DEREF_POINTER`
- Precedent: `src/cell_registry.zig`, `src/escalation.zig:packPointerCell1`
- Its own subsystem program ([RM-118 marked CLOSED](../spec/UNIFIED-CELL-FORMAT-MIGRATION.md) but tracking the dependency)

Until that subsystem lands, the fat-payload fallback stays. That's fine — those cells just won't be kernel-evaluable by the real executor. The cells that DO go through the canonical path (the common case) ARE kernel-evaluable, which is what matters for #12.

---

## §5 Implications for §11.10 order 2e (#12 real executor wiring)

**Original assumption (Path A)**: entity_cell must be fully removed before executor wiring, because executor reads 256-byte header.

**Audit revises this**: substrate_entity is already the primary path. Cells written via substrate_entity have the 256-byte header the executor expects. The executor will read them correctly. **#12 is unblocked.**

What changes:
- **Path A unblocks #12 with much less work**: just the 2 pure-legacy stores (cell_handler + contact_book) need primary-path wiring. ~1 day total.
- **The "full entity_cell deletion" is reframed** as parked behind the octave-pointer subsystem. That's its own program — not a #12 prerequisite.
- **Fat-payload cells (rare)** won't be kernel-evaluable until octave-pointer lands. That's acceptable: those cells aren't policy-gated anyway (they're attachments / site config — bulk data).

---

## §6 Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| **R1.** `contact_book_lmdb.zig` audit reveals substrate_entity wiring already exists and the legacy calls are read-only — task already done | Medium | Verify with deeper read before scoping #22 work |
| **R2.** `cell_handler.zig` is generic and lacks the `tag → spec` mapping the per-store stores use (each `_store_lmdb` knows it's writing TAG_CUSTOMER etc.) — generic path needs a different spec resolution | High | The cell_handler envelope carries `cell_payload` as opaque JSON with a `cartridge_id` + `type_name` field per its header doc. Use those to look up the right `EntityTypeSpec` from `substrate_entity`'s registry. If no spec is registered for the given cartridge/type, the call falls back to entity_cell (logged as "unregistered type" warning). |
| **R3.** Fat-payload fallback exercised more often than expected once cell_handler grows real callers — the 768-byte budget pinches | Low | Most generic cells are small JSON. Bridget's NP OS schema sizes look bounded. If it becomes an issue, accelerate the octave-pointer subsystem. |
| **R4.** Existing tests pass under dual-path because they happen to send small payloads; large-payload paths are silently exercising entity_cell with no test coverage | Medium | Audit test fixtures during the per-store migration PRs. Add a >768 byte test case per store. |
| **R5.** `runtime/semantos-brain/src/migrate_entity_cells/main.zig` is now over-scoped — it expects to migrate entity_cell-formatted persisted data on rbs, but no production callers per Todd | Low | Keep the tool; it'll be useful when the octave-pointer subsystem lands and we want to migrate the residual fat-payload cells. |

---

## §7 Recommended next sequencing

1. **Tick 13 (PR-A)**: Add substrate_entity primary path to `cell_handler.zig`. Generic spec-resolution via cartridge_id + type_name → `substrate_entity.specByTag()` or registered spec lookup. ~half day.
2. **Tick 14 (PR-B)**: Audit + add substrate_entity to `contact_book_lmdb.zig` (likely small JSON, no fat-payload fallback needed but include for consistency). ~half day.
3. **Tick 15 onwards**: Unblocked — proceed with §11.10 order 2e (#12) per `PRE-FLIGHT-EXECUTOR-WIRING.md`. Cells written through the primary path will be kernel-readable.
4. **Separate program (not in §11.10 scope)**: Scope the octave-pointer subsystem to retire the fat-payload fallback. RM-118 was closed prematurely; bring it back as a fresh program when octave-storage is ready.

---

## §8 Task list reframe (for autonomous loop)

Suggested changes to TaskList:

- **#19** (this audit) → mark completed when PR merges
- **#20** (migrate cell_handler) — KEEP, scoped to "add substrate_entity primary path + fallback" (1 PR, ~half day)
- **#21** (migrate attachments_store_lmdb) — DELETE; already has dual path. Confirmed by spec line 197 + grep.
- **#22** (migrate contact_book_lmdb) — KEEP, possibly trivially completes if substrate_entity wiring already exists
- **#23** (migrate sites_store_lmdb) — DELETE; already has dual path
- **#24** (delete entity_cell.zig) — DELETE/RESCOPE; parked behind octave-pointer subsystem per spec
- **#12** (real executor wiring) — UNBLOCK; can proceed after #20 + #22 land

New tasks to consider:
- **#26**: Octave-pointer subsystem program — bring back RM-118 as its own multi-PR program to retire the fat-payload fallback. Separate from §11.10.

---

## §9 What needs Todd's input

Per loop rules — decisions before launching tick 13:

1. **Confirm the reframe**: cell_handler + contact_book are the only real remaining work; the other "tasks" delete themselves once verified. ✓ or revise?
2. **Generic cell_handler spec resolution (R2)**: when an opaque `cell.create` call comes in with arbitrary cartridge_id + type_name, should we:
   - **(a)** Require pre-registered specs in `substrate_entity` registry. If unregistered, fall back to entity_cell with a warning.
   - **(b)** Synthesize a spec on-the-fly (hash the type_name string for type_hash; use a generic domain_flag for unregistered cartridges).
   - **(c)** Reject unregistered types entirely (force schema-first registration).
   Recommendation: **(a)** — preserves forward-compat for cartridges that haven't registered (Bridget's NP OS while she's building) without silently degrading the substrate format.
3. **Octave-pointer subsystem priority**: This audit recommends treating it as a separate program. Bridget's NP OS may want fat-payload Grant/ReportingObligation cells eventually; if she needs them soon, accelerate. Otherwise defer.
