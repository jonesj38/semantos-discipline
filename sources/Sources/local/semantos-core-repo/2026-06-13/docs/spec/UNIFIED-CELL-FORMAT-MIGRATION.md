---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/spec/UNIFIED-CELL-FORMAT-MIGRATION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.743883+00:00
---

# Unified cell format migration — kill `entity_cell.zig`

**Status:** spec.  **Wave 10 RM-110.**  **Authors:** Wave 9 follow-up.  **Last updated:** 2026-05-15.

## Summary

`runtime/semantos-brain/src/entity_cell.zig` defines a homegrown 16-byte-header LMDB packing convention used by 8 oddjobz entity stores (customer, visit, quote, invoice, attachment, job, site, lead). It is **not** a substrate cell — the kernel cannot read it, it carries no linearity class, no type hash, no owner id, no parent / prev-state hash chain, no domain payload root. It shares only the word "cell" and a 1024-byte size with the real substrate cell format defined in `core/cell-engine/`.

This spec migrates all 8 entity stores to the substrate cell format and deletes `entity_cell.zig`. After this migration:

- Every entity carries `linearity_class` at header offset 16, kernel-enforceable via `OP_ASSERTLINEAR` / `OP_CHECKAFFINETYPE` / `OP_CHECKRELEVANTTYPE`.
- Every entity carries `type_hash` at header offset 30 (32 bytes), kernel-checkable via `OP_CHECKTYPEHASH`.
- Every entity carries `domain_flag` at header offset 24, kernel-checkable via `OP_CHECKDOMAINFLAG`.
- Every entity carries `owner_id` at header offset 62 (16 bytes) — the operator's hat reference, kernel-checkable via `OP_CHECKIDENTITY`.
- Every entity carries `timestamp` at header offset 78 (u64 ns).
- Every entity carries `domain_payload_root` at header offset 224 (32 bytes) — sha256 of the canonical payload, the integrity binding for the JSON content.
- The payload (the existing JSON body) lives in bytes 256..1023, a 768-byte budget.

## Why one format, not two

Two formats existing in parallel is a footgun: store code, conformance tests, migration tools, and human readers must continually disambiguate "which cell." Worse, the entity-cell format silently fails the kernel: a cell stored as entity-cell can't be read by `OP_CHECKDOMAINFLAG` (the byte at offset 24 is JSON content, not the domain flag), `OP_CHECKTYPEHASH` (no type hash), or any other Plexus opcode. Operations that "should" be substrate-enforced (a lead is consumed when quoted; a quote is consumed when invoiced; an invoice transitions to immutable RELEVANT once paid) cannot be expressed as 2-PDA scripts — they remain application-level rules in Zig.

## Wire format (target)

256-byte header + 768-byte payload = 1024-byte cell. Constants mirrored from `core/cell-engine/src/constants.zig`:

| Offset | Size | Field | Value / source |
|---:|---:|---|---|
| 0 | 4 | `magic_1` | `0xDEADBEEF` (LE u32) |
| 4 | 4 | `magic_2` | `0xCAFEBABE` (LE u32) |
| 16 | 1 | `linearity_class` | 1=LINEAR · 2=AFFINE · 3=RELEVANT · 4=DEBUG |
| 20 | 4 | `version` | `2` (current substrate version) (LE u32) |
| 24 | 4 | `domain_flag` | per-entity oddjobz domain flag (LE u32) |
| 28 | 2 | `ref_count` | initial = 0 (LE u16) |
| 30 | 32 | `type_hash` | sha256("`{whatPath}:{howSlug}:{instPath}`") |
| 62 | 16 | `owner_id` | first 16 bytes of operator's hat-id |
| 78 | 8 | `timestamp_ns` | nanosecond Unix timestamp at mint |
| 86 | 4 | `cell_count` | 1 (no continuation) (LE u32) |
| 90 | 4 | `payload_total` | length of JSON payload in bytes (LE u32) |
| 96 | 32 | `parent_hash` | zeroed at first mint; FSM transitions chain |
| 128 | 32 | `prev_state_hash` | zeroed at first mint; FSM transitions chain |
| 224 | 32 | `domain_payload_root` | sha256(payload_json) |
| 256 | 768 | `payload` | UTF-8 JSON entity body (zero-padded) |

Unused header bytes are zeroed.

## Type-path registry

Eight oddjobz entity types, each with a canonical type path. The type_hash is `sha256("{type_path}:{how_slug}:{inst_path}")` per the existing convention in `oddjobz_ratify_handler.zig`. Four already exist; four are added.

| Entity tag (legacy) | Type path | How slug | Inst path |
|---|---|---|---|
| 0x01 customer | `oddjobz.customer` | `identify` | `inst.identity.customer-record.v2` |
| 0x02 visit | `oddjobz.visit` | `schedule` | `inst.work.site-visit.v2` |
| 0x03 quote | `oddjobz.quote` | `propose` | `inst.commercial.estimate.v2` |
| 0x04 invoice | `oddjobz.invoice` | `bill` | `inst.commercial.billable.v2` |
| 0x05 attachment | `oddjobz.attachment` | `capture` | `inst.evidence.site-artifact.v2` |
| 0x06 job | `oddjobz.job` | `worktrack` | `inst.work.job-record.v2` |
| 0x07 site | `oddjobz.site` | `locate` | `inst.location.work-site.v2` |
| 0x08 lead | `oddjobz.lead` | `ingest` | `inst.intake.lead-record.v2` |

Type hashes are computed at runtime in `substrate_entity.zig` (32 bytes of sha256 over the concatenated triple).

## Domain-flag mapping

Existing `extensions/oddjobz/src/capabilities.ts` already allocates one read-capability flag per entity. We reuse those as the cell-level domain flag (the kernel's `OP_CHECKDOMAINFLAG` doesn't distinguish "this is a read capability" from "this is the cell's domain" — they're the same 32-bit slot in the namespace). This is what `jobs_store_lmdb.zig::ODDJOBZ_JOB_DOMAIN_FLAG = 0x00010107` already does for jobs.

| Entity | Domain flag (LE u32) |
|---|---:|
| customer | `0x00010108` (cap.oddjobz.read_customers) |
| visit | `0x00010109` (cap.oddjobz.read_visits) |
| quote | `0x0001010B` (cap.oddjobz.read_quotes) |
| invoice | `0x0001010C` (cap.oddjobz.read_invoices, new) |
| attachment | `0x0001010D` (cap.oddjobz.read_attachments, new) |
| job | `0x00010107` (cap.oddjobz.read_jobs) |
| site | `0x0001010E` (cap.oddjobz.read_sites, new) |
| lead | `0x0001010F` (cap.oddjobz.read_leads, new) |

The four new caps register as part of RM-112; if a different slot is preferred, this table updates and consumers re-derive at module load.

## Linearity-class mapping

The entity's current FSM state determines its linearity at mint time. Transitions that change FSM state mint a new cell with the appropriate linearity, chaining via `prev_state_hash`.

| Entity | State | Linearity |
|---|---|---|
| Lead | `pending` | AFFINE |
| Lead | `ratified` · `rejected` | RELEVANT |
| Job | `lead` | AFFINE |
| Job | `quoted` · `scheduled` · `in_progress` · `invoiced` · `paid` | LINEAR |
| Job | `completed` · `closed` | RELEVANT |
| Quote | `open` | LINEAR |
| Quote | `accepted` · `declined` · `expired` | RELEVANT |
| Invoice | `issued` · `partial` | LINEAR |
| Invoice | `paid` · `void` | RELEVANT |
| Visit | `scheduled` | LINEAR |
| Visit | `completed` · `no_show` | RELEVANT |
| Customer | `active` | AFFINE |
| Customer | `archived` | RELEVANT |
| Site | `active` | AFFINE |
| Site | `archived` | RELEVANT |
| Attachment | (immutable, no states) | RELEVANT |

## Per-store rewrite checklist (RM-114)

Each `*_store_lmdb.zig` performs the same three-step swap:

1. Replace `entity_cell.encodeCell(TAG, json)` with
   `substrate_entity.encodeEntity(.{ .tag = TAG, .linearity = derivedLinearity(record), .owner_id = hat_owner_id, .payload_json = json })`.
2. Replace `entity_cell.cellEntityTag(cell)` / `entity_cell.cellPayload(cell)` with `substrate_entity.decodeEntity(cell)` which returns a struct carrying `tag`, `linearity`, `domain_flag`, `type_hash`, `owner_id`, `timestamp_ns`, `payload` slice.
3. Update the filter that walks LMDB cursors to match on `type_hash` (or `domain_flag`, which is faster) instead of `entity_tag`. `type_hash` matching is the canonical substrate way; `domain_flag` matching is acceptable as a fast pre-filter.

Affected files (8 stores + handlers):

- `runtime/semantos-brain/src/customers_store_lmdb.zig`
- `runtime/semantos-brain/src/visits_store_lmdb.zig`
- `runtime/semantos-brain/src/quotes_store_lmdb.zig`
- `runtime/semantos-brain/src/invoices_store_lmdb.zig`
- `runtime/semantos-brain/src/attachments_store_lmdb.zig`
- `runtime/semantos-brain/src/jobs_store_lmdb_entity.zig` (the cursor-only variant)
- `runtime/semantos-brain/src/sites_store_lmdb.zig`
- `runtime/semantos-brain/src/leads_store_lmdb.zig`

Plus the handlers that decode cells inline (if any). Survey before each commit.

## Payload-budget audit

Entity_cell allowed 1008 bytes of JSON; substrate cells allow 768. Need to verify each entity's current max JSON size fits. If any exceed, that entity gets split via the substrate's existing continuation-cell chain (`CONTINUATION_HEADER_SIZE = 8`, `CONTINUATION_PAYLOAD_SIZE = 1016`, chained via header offset 90 `payload_total`). For Wave 10's MVP, **only** continuation-enable entities whose audit shows they actually need it; ones that fit in 768 stay single-cell.

Audit:

| Entity | Current MAX (entity_cell era) | Budget after migration | Action |
|---|---:|---:|---|
| Customer | ~500-800 B typical | 768 | likely fits; audit needed |
| Visit | ~400-600 B typical | 768 | fits |
| Quote | ~600 B typical | 768 | fits |
| Invoice | ~500 B typical | 768 | fits |
| Attachment | ~250 B (metadata only) | 768 | fits |
| Job | ~1.5-3 KiB observed | 768 | **needs continuation** |
| Site | ~800-1.5 KiB observed | 768 | **needs continuation** |
| Lead | ~600 B typical | 768 | fits |

Jobs and sites are the two that need continuation-cell chains.  This is fine — the substrate already supports it; we just exercise the existing chain mechanism for the first time on entity payloads.

## Migration tool (RM-115)

`tools/migrate-entity-cells/main.zig` (CLI binary built by zig build):

1. Open the target LMDB env read-write.
2. Cursor-scan every cell.
3. For each cell: peek bytes 0..4 (LE u32). If equal to `0xDEADBEEF` (substrate magic), skip — already migrated. Otherwise treat as legacy `entity_cell` format.
4. Decode legacy: read `entity_tag`, `payload_len`, slice the JSON payload.
5. Map `entity_tag → type_spec`, derive `linearity` from a payload-JSON inspection (state field), build a substrate cell with the same JSON payload and the matched type_spec + linearity + owner_id (from hat context passed via CLI arg).
6. Atomic LMDB swap: delete old key, put new cell under the same key.
7. Log: `migrated: <count>, skipped: <count>, errors: <count>`.

Idempotent. Safe to re-run.

CLI usage:

```
migrate-entity-cells --lmdb /var/lib/semantos/intent_cells_lmdb \
                    --hat <hatId-32-hex> \
                    --dry-run            # default: --no-dry-run to actually write
```

## Conformance test sweep (RM-116)

Every test that hand-constructs an entity cell (`entity_cell.encodeCell(...)` or peers at bytes 0..16 of a cell) needs updating to use `substrate_entity.encodeEntity(...)` or the new decoder. Search target:

```
grep -rln "entity_cell\.\(encodeCell\|cellEntityTag\|cellPayload\)" runtime/semantos-brain/tests
```

Tests can usually compress to a single helper-call once `substrate_entity` is the single source of truth.

## Deploy order on rbs

1. Land RM-111 (`substrate_entity.zig`) — readers know both formats, writers still emit legacy. No behavior change.
2. Land RM-114 batches by entity (jobs first for visible win) — writers emit substrate, readers prefer substrate but fall back to legacy.
3. Build the migration tool (RM-115). Run with `--dry-run` against a snapshot of rbs's LMDB env; verify counts.
4. Run `--no-dry-run` against rbs LMDB. Confirm. Verify reads still work (now they all hit the substrate path).
5. Land RM-117 (delete `entity_cell.zig`). Brain rebuild + redeploy.

## Open questions

- **Per-entity domain flag allocation** — table above proposes 4 new flag slots (`0x0001010C..0x0001010F`). Confirm none collide with existing capability flags in `extensions/oddjobz/src/capabilities.ts`.
- **FSM transition chains** — when a lead becomes a job (lead → job → quoted), do we chain via `prev_state_hash` only within an entity tag, or across (lead.prev → job.prev → quote.prev)? Default: within a single entity tag's lifecycle. Cross-entity chains via the entity-graph references (e.g. `job.leadRef`).
- **Continuation cells for jobs/sites** — the existing `CONTINUATION_HEADER_SIZE = 8` chain isn't yet exercised by entity stores. RM-114 for jobs and sites prototypes this — if it surfaces issues, they may need their own RM.

---

## 2026-05-16 reconciliation (post D-RTC.4) — read before acting on this doc

This is a point-in-time design artifact. Two things changed after RM-110–RM-116 landed; the authoritative current state is the RM-117/RM-118 entries in `docs/SCG-AND-PHASE-H-ROADMAP.md`:

1. **D-RTC.4 deleted 6 of the 8 RM-114 stores** (`jobs`, `customers`, `leads`, `quotes`, `invoices`, `visits` `_store_lmdb`) and centralized entity encoding in `runtime/semantos-brain/src/entity_encode_walker.zig`, which **enforces `payload_json ≤ 768`**. Only `sites_store_lmdb` + `attachments_store_lmdb` (+ `migrate_entity_cells`) still use `entity_cell`. The payload-budget audit table above is stale for the deleted stores.
2. **Fat-payload handling is a subsystem project, not a wrapper — RM-118 is CLOSED.** `core/cell-engine/src/multicell.zig` operates on a single contiguous `N×1024` buffer; the entity store (`src/lmdb/cell_store_lmdb.zig`) is one 1024-byte cell per `sha256(cell)` key and cannot hold or regroup an `N×1024` blob. So `multicell` **cannot back entity storage** — wrapping it is a dead end. The correct mechanism is octave-slot storage + a single pointer cell (`OctaveAddress{octave,slot,fragment_count}` + `OP_DEREF_POINTER`; precedent: `src/cell_registry.zig`, `src/escalation.zig:packPointerCell1`) — its own subsystem, not a line item here. See the RM-118 entry in `docs/SCG-AND-PHASE-H-ROADMAP.md` for the full closed-out rationale.

Bound-check (2026-05-16): worst-case serialized JSON is **sites ≈ 2.0 KB**, **attachments ≈ 1.7 KB** — both exceed 768, so the `entity_cell.encodeCell` >768 fallback in those two stores is **load-bearing**, not removable dead code. It remains the documented backstop; RM-117 (delete `entity_cell.zig`) stays parked behind the octave-pointer subsystem + the rbs migration run.
