---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/ODDJOBZ-CANONICALIZATION-HANDOFF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.737703+00:00
---

# Oddjobz Cell-Store Canonicalization — Handoff

**Status (2026-06-10): production cell store deduplicated & canonicalized, live and verified. Customer-ingest idempotency (§6.2) landed (ingest-side, awaiting deploy). One follow-up remains: the optional `cell.query` substrate reroute (§6.1) — the operator app reads via `find` today, so it is architecture-purity, not a blocker.**

This doc is cold-start ready: a fresh session should be able to understand the
oddjobz cell data model, reproduce the analysis, run/rollback the migration, and
finish the remaining work without re-deriving anything.

---

## 0. TL;DR

The goal (Todd): *"all canonical, ONE cell type, brain and PWA on the SAME cells,
no translation layer."*

- The prod entity store was **already one physical cell format** (256B-header
  substrate cells). The mess was **duplication** (a person/site re-minted once per
  job), **invoice-event noise** (Todd's own outbound emails ingested as jobs), and
  the **view-store `cellId` translation layer**.
- **DONE:** deduped + folded the live graph **6297 → 4598 cells** via
  `tools/oddjobz-canonicalize/canonicalize.py`, zero dangling refs, indices
  rebuilt. `find customers` is now **152** (was 1214). Rollback backups retained.
- **DONE (§6.2):** customer ingest is now idempotent (resolve-or-create by
  role-aware natural key in `runtime/legacy-ingest`) so the 152 don't regrow.
  Ingest-side only — no brain redeploy. (Sites + jobs already deduped.)
- **REMAINING:** reroute `cell.query` to read the substrate directly (§6.1) — the
  "no translation layer" purity goal. **Not a blocker:** the operator app reads
  via the `find` REPL verbs, not `cell.query` (see `operator_jobs_repository.dart`).

---

## 1. Where everything lives

| Thing | Location |
|---|---|
| Prod brain host | `ssh rbs` = `203.18.30.243` = `brain.oddjobtodd.info` |
| Brain binary | `/opt/semantos/brain` (systemd `semantos-shell.service`, User=semantos) |
| **Cell store (THE substrate)** | `/var/lib/semantos/entity_cells_lmdb` (LmdbCellStore) |
| Brain source on VPS | `/opt/semantos-core` (an *older* main + uncommitted prod edits — DON'T clobber) |
| Migration tools (built) | `/opt/semantos-core/runtime/semantos-brain/zig-out/bin/` (`brain-backfill-cell-indices`, `brain-migrate-entity-cells`, `lmdb-reader`) |
| Canonicalizer tool | `tools/oddjobz-canonicalize/canonicalize.py` (this repo) |
| Rollback backups | `/var/lib/semantos/entity_cells_lmdb.pre-canon-20260610-213745` and `.pre-backfill-20260610-202357` |

`python-lmdb` 1.4.1 and `bun` are available on the VPS for read-only census +
live WSS RPC tests. Run migration steps as **user `semantos`** (`sudo -u semantos`)
so file ownership stays correct.

---

## 2. The data model (forensic findings)

`entity_cells_lmdb` is the single LmdbCellStore; the typed view-stores
(jobs/customers/sites/attachments) are an **in-memory projection loaded from it at
boot**. Sub-DBs: `cells` (primary) + secondary indices
`cells_by_{type,owner,prev_state,anchor_status,anchor_txid,anchor_height,spent}`.

Six entity types (by `typeHash` prefix), pre-canon counts:

| typeHash | type | cells | canonical |
|---|---|---:|---:|
| `c0555cda…` | job | 374 | 287 work-orders + 36 standalone invoice-events |
| `eef2434c…` | customer | 1214 | **152** |
| `403aeb29…` | site | 713 | **127** |
| `fb1a23a8…` | attachment | 3988 | 3988 (2551 PDFs + 1437 photos; all carry `jobRef`) |
| `06c604b3…`, `06d0a049…` | voice/intent capture | 8 | 8 (untouched) |

**Customer role model** (drives billing): `tenant` 748, `agent` 299,
`property_manager` 120, **`site_owner` (landlord) 26**, `unknown` 21. Billing rule
(Todd): invoice the **landlord C/O the agency** when the job sheet discloses the
landlord (a `site_owner` exists for that site); otherwise invoice the agency
(e.g. Clever Property, Robert James Realty).

**Duplication root cause:** customer cells bake `linked_site_id` into the cell, so
the same person at N sites was minted N times (Tanya Healy ×130 = one Clever agent
across 130 sites; RJR ×13). Sites duplicate ~5.6×, customers ~9×. This is the
no-normalization-seam problem (see memory `semantos_canonical_schema_spine`).

---

## 3. The cell hash/encoding model (validated 6297/6297)

The canonical substrate cell is 1024 bytes: 256B header + payload. Encoder =
`runtime/semantos-brain/src/substrate_entity.zig` (`encodeEntity`). Validated
empirically against every prod cell:

```
content hash    = sha256(cell[:1024])         == the LMDB key (after 8-byte op_pkh prefix)
payload         = cell[256 : 256+payload_total]
payload_total   = u32 LE  @ offset 90         (all ≤ 767 here → inline only, no octave-1 escalation)
domain_payload_root @ offset 224 = sha256(payload)
owner_id        @ offset 62, 16 bytes         == all-zero on every cell (v0.1.0: no cert→owner mapping)
typeHash        @ offset 30, 32 bytes
op_pkh          = 8-byte key prefix           == all-zero (single-tenant default)
```

**References are content hashes.** `job.site_ref`, `job.customer_refs[].cell_id`,
`attachment.jobRef` all equal the target cell's LMDB key. The payload's own
`id`/`cellId` is a **separate logical id, NOT the content hash, and NOT a reference
target** — do not treat it as identity.

Consequence: editing a referenced cell changes its hash → a **dependency-ordered
cascade re-emission** (merge customers/sites → re-emit referring jobs → re-emit
their attachments).

---

## 4. The canonicalizer (`tools/oddjobz-canonicalize/canonicalize.py`)

Pure Python (no Zig build needed). Uses **edit-from-template**: it keeps each
changed cell's real brain-minted 256B header and only rewrites
`payload` + `payload_total`(@90) + `domain_payload_root`(@224), then rehashes.
Reference repointing is a **format-preserving 64-hex substring substitution** in
the payload bytes (same length → no reserialization risk).

**Dedup model (role-aware, site-first — order matters):**
1. **sites** by normalized address → survivors stable.
2. **customers**: `agent`/`property_manager` by `email|name` (ONE person across all
   sites); `site_owner` by `name`; `tenant` by `name + CANONICAL site` (sites MUST
   be deduped first, else tenants under-merge because their `linked_site_id` points
   at duplicate site cells); `other` by `name + canonical site`.
3. **jobs**: real work-orders kept (refs repointed); **invoice-event** jobs
   (no `customer_refs`, summary ~ "invoice" / `display_name`="todd price") are
   **folded** into the real work-order at the same canonical site (their
   attachments re-linked). Events with no parent work-order are **kept standalone**
   (36 of 87 — likely invoices for jobs from another channel).
4. **attachments** (leaves): `jobRef`/parent repointed via the *job_final* map
   (real + standalone-event re-emits) ∪ event-fold. Using `job_final` (not just the
   "changed real jobs" map) is what prevents standalone-event attachments dangling.

**Usage:**
```bash
canonicalize.py <lmdb_dir>           # dry-run: report only, no writes
canonicalize.py <lmdb_dir> --apply   # rewrite the primary `cells` DB in place
```
After `--apply`, the secondary indices are stale — clear them and re-run
`brain-backfill-cell-indices` to rebuild (see §5 step 4).

---

## 5. What was done on production (2026-06-10)

**(a) Index backfill** — `cells_by_type` was only populated for 306 of 6297 cells
(the rest written before that index existed), which is why `cell.query` saw almost
nothing. Cleared the index sub-DBs and ran `brain-backfill-cell-indices
--lmdb-dir=… --op-pkh=0000000000000000` → 6297/6297 indexed. (Note: that bin DOES
write `cells_by_type` inside `backfillSecondaryIndices`, despite stale doc-comments
listing only 4 indices.)

**(b) Canonicalization** — the reversible sequence (all as user `semantos`):
1. `systemctl stop semantos-shell`
2. `cp -a entity_cells_lmdb entity_cells_lmdb.pre-canon-<ts>`  (rollback backup)
3. `canonicalize.py /var/lib/semantos/entity_cells_lmdb --apply`
4. clear the 7 secondary-index sub-DBs (python-lmdb `txn.drop(db, delete=False)`),
   then `brain-backfill-cell-indices --lmdb-dir=…`
5. `systemctl start semantos-shell`

**Result:** customers 1214→152, sites 713→127, 51 invoice-events folded + 36
standalone, attachments 3988 all preserved (2966 repointed), **6297→4598 cells,
ZERO dangling references, indices rebuilt 4598/4598.**

**Verified live** over `ws://127.0.0.1:8080/api/v1/rpc?bearer=<…>` (frame:
`{"t":"req","id":"c1","method":"repl.eval","params":{"cmd":"find customers"}}`):
`find customers` → **152** (was 1214), `find jobs` → 243. The view-stores reload
from the canonicalized cells at boot, so `find` already serves deduped data.

**Rollback** (if ever needed): `systemctl stop semantos-shell` → `rm -rf
entity_cells_lmdb && cp -a entity_cells_lmdb.pre-canon-<ts> entity_cells_lmdb` →
`systemctl start semantos-shell`.

---

## 6. Remaining work

### 6.1 Reroute `cell.query` to read the substrate directly (kills the translation layer)

**Why it currently returns 0:** the oddjobz decoders
(`cartridges/oddjobz/brain/zig/registration.zig` ~line 209) register a custom
`enumerate` that walks the **view-store** records and emits only those with a
non-null `cellId`. The canonical cells carry no `cellId` payload field, so the
store's `by_cell_id` index is empty and both `enumerate` and `decode_one`'s
`getByCellId(hash)` miss → 0 rows. The store also has a tangled dual
legacy-loom / v2 decode path (`customers_store_lmdb.zig` ~line 520) that expects
`id`/`display_name`/`created_at`, not the canonical `name`/`role` payload.

**The handler already supports the substrate path:** `cell_query_handler.query`
falls back to `self.cell_store.cellsByType(type_hash)` when a decoder has **no**
`enumerate` callback. The index is now fully populated (§5a), so:

**Recommended change:**
- Drop the `enumerate` callbacks from the 4 oddjobz decoders → handler enumerates
  `cells_by_type` (content hashes).
- Replace `decode_one` with a **substrate decode**: load the cell from the cell
  store by content hash and return its payload JSON (inject `id` = content hash).
  This removes the view-store dependency entirely (true "no translation layer").
- For `matches_filter` (jobs/attachments), parse the loaded cell's payload for the
  filter fields instead of `store.getById`.
- **Align the app** to the canonical payload field names: the substrate customer
  payload uses `name` (not `display_name`), `phone`, `role`, `linked_site_id`.
  Update `apps/semantos` Find/Talk readers + the M1.8 generic renderer hints, OR
  keep a thin per-type field mapping in the decode.

This is a brain code change + app change + rebuild + prod redeploy — do it as a
focused, tested step, not a rushed edit. The app is **not blocked** in the
meantime: it reads canonical, deduped data today via the `find` verbs.

### 6.2 Idempotent ingest (so dupes don't regrow)

The Gmail/PDF ingest path must **resolve-or-create by natural key** instead of
always minting:
- agency agent → by `email`
- site → by `normalized_address`
- customer → by `role + name + canonical site`
- landlord (`site_owner`) → by `name`

Without this, the 152 creeps back toward 1214 on the next ingest. The same natural
keys are encoded in `canonicalize.py`'s clustering — reuse them.

**Status (2026-06-10): sites + jobs already deduped; customers now done too.**
- **Sites** dedupe on `lookup_key` (`site-dedupe.ts` → `sitesView.findByLookupKey`,
  brain-backed) and **jobs** on WO#/ref#/address (`job-dedupe.ts`, receipt-seeded
  live index) — both pre-existing.
- **Customers** were the gap: `reingest-worker.ts::mintCustomer` always minted.
  Closed by `runtime/legacy-ingest/src/customer-dedupe.ts` — role-aware
  resolve-or-create whose keys **mirror `canonicalize.py`'s `ckey` exactly**
  (`person:<email|name>` for agent/property_manager site-independently,
  `landlord:<name>` for site_owner, `<role>:<name>|<canonical-site>` else;
  `unkeyed:` = never deduped). The worker resolves each contact through an
  optional `customersDedupeView`; the `legacy reingest` verb seeds a live index
  from prior receipts and keeps it current within-run (same posture as jobs).
  Receipts now carry `customerLookupKeys` + `customerDispositions`; the verb
  reports `customersDeduped`. **Ingest-side only — no brain rebuild/redeploy.**
  Tests: `customer-dedupe.test.ts` (25 cases incl. the 130-site agent fan-out →
  1 cell) + 2 worker integration cases; package suite 845/845 green.
- **Remaining (optional hardening):** the `customersDedupeView` currently dedupes
  within-run + cross-run *via receipts*. To dedupe a fresh ingest against the
  **live 152 already in prod** (not just past worker runs), inject a brain-backed
  view the way `sitesView` is — needs a `customer.lookup(naturalKey)` brain verb
  (a brain change + redeploy). The seam is in place; only the brain-side lookup
  is missing.

#### 6.2-trace (2026-06-10, post-#967) — which path is live, and the shared blocker (now fixed)

A trace after #967 merged found the remaining picture is more entangled than
"two independent follow-ups." Three findings a fresh session needs:

1. **The LIVE ingest path has ZERO dedup wired.** `do ingest` →
   `oddjobz_ingest_handler.zig` spawns `cartridges/oddjobz/brain/src/legacy-ingest-handler.ts`
   **once per proposal**, and that handler wires `sitesView` as a no-op stub
   (`findByLookupKey: async () => null`), **no** `jobsDedupeView`, **no**
   `receiptStore`, **no** `customersDedupeView`. So #967's dedup (and the
   pre-existing site/job dedupe) only runs in the **batch** path
   (`legacy-ingest/src/verb.ts` `legacy reingest` CLI, consumed by
   `archive/apps-legacy-cli`). Per-proposal spawn ⇒ within-run dedup is moot and
   there's no receipt store ⇒ no cross-run dedup either. **To protect the 152 in
   the live path, the per-proposal handler needs a brain-backed view** (a
   synchronous `customer.lookup` over the WSS channel it already uses for
   `entity.encode`). (Todd: nothing is in production yet — still testing.)

2. **The null-`cellId` linchpin — now FIXED (PR #969).** Canonical customer cells
   load via the RM-119 ingest-shape path (`applyIngestCustomerPayload`), which
   left the in-memory record's `cellId` **null** — the shared blocker for BOTH
   the §6.2 brain-view (`findByDedupeKey` found the row but had no cell id to
   return) AND §6.1 (`enumerate`/`getByCellId` missed → 0 rows). A **read-only
   prod census** (`tools/oddjobz-canonicalize/census_cellid_invariant.py`) proved
   the invariant: job `customer_refs[].cell_id` resolve to a customer **content
   hash 261/261**, `site_ref` 233/233, and **0 of 152** canonical customers carry
   any logical `cellId`. So content hash = `sha256(cell)` = LMDB key is the
   unique-correct identity. PR #969 stamps `cellId = content hash` on canonical
   customer load (+ surfaces `siteRef`/`normalisedPhone`, indexes `by_cell_id`);
   full brain `zig build test` green. **Needs a brain redeploy to take effect.**

3. **Remaining after #969 (each a brain change + redeploy):**
   - **§6.1 full:** apply the *same* cellId-stamp to the jobs/sites/attachments
     stores (only customers done in #969); then `cell.query` resolves all four
     types. Then drop/skip the oddjobz `enumerate` callbacks so the handler uses
     the now-populated `cells_by_type` index, or keep them (they now emit the
     stamped cellIds). Mechanical — the pattern is proven.
   - **§6.2 live-path view:** add a `customer.lookup(naturalKey)→cellId` brain
     verb (now returns a real cellId post-#969) + wire a brain-backed
     `customersDedupeView` into the per-proposal `legacy-ingest-handler.ts`.
     NOTE a role-vocabulary mismatch to reconcile: the brain store's
     `CustomerRole` enum is `tenant|agent|owner|pm|sub_tradie|other`, while the
     TS ingest `ContactRole` (and `customer-dedupe.ts` keys) use
     `site_owner|tenant|property_manager|agent|contractor|witness|unknown`.

---

## 7. Reproduce the analysis (read-only, safe on a live env)

All census scripts open the env `readonly=True, lock=False` (never disturbs the
live writer). Key one-liners (run on the VPS):

```python
import lmdb, binascii, hashlib, collections
env = lmdb.open("/var/lib/semantos/entity_cells_lmdb", readonly=True, lock=False, max_dbs=64)
cells = env.open_db(b"cells", create=False)
# validate hash model:
with env.begin(db=cells) as t:
    for k, v in t.cursor():
        c = bytes(v[:1024]); pt = int.from_bytes(c[90:94], "little")
        assert hashlib.sha256(c).digest() == bytes(k[8:40])          # key == sha256(cell)
        assert hashlib.sha256(c[256:256+pt]).digest() == c[224:256]  # payload root
```

`typeHash` = `cell[30:62]`; `owner_id` = `cell[62:78]`; payload = `cell[256:256+pt]`.

---

## 8. Gotchas / ops

- **RPC frame is tagged:** `{"t":"req","id","method","params"}` over
  `ws://127.0.0.1:8080/api/v1/rpc?bearer=<token>`; replies `{"t":"res",...}` /
  `{"t":"err",...}`. A plain `{id,method,params}` frame gets `unsupported frame`.
  The job `cell.query` decoder requires a `filter`.
- **op_pkh = 0** everywhere (single-tenant). `brain-backfill-cell-indices` default
  `--op-pkh` is all-zero — matches.
- **owner_id = 0** on every cell (v0.1.0 has no cert→owner mapping; mint zero-fills).
  "Re-home under one owner cert" is a *separate, optional* hardening step — not
  needed for visibility, and everything is already uniformly one (null) owner.
- **VPS source tree** `/opt/semantos-core` is older main + has uncommitted prod
  changes; to rebuild the brain use a detached worktree off `origin/main`
  (`git worktree add --detach /tmp/sbuild origin/main`) — don't pull/clobber the
  prod checkout. zig 0.15.2 + system liblmdb are installed.
- **SECRETS to rotate:** `semantos-shell.service` env exposes `ANTHROPIC_API_KEY`,
  the `DATABASE_URL` password, and `ODDJOBZ_BRAIN_BEARER` (visible via
  `systemctl cat`). The API key has leaked into multiple session transcripts —
  **rotate it.** (Values intentionally omitted from this repo doc.)

---

## 9. Related

- Memory: `oddjobz_wss_rpc_rebuild` (the full WSS-RPC + parity + canonicalization
  narrative), `semantos_canonical_schema_spine`, `brain_pwa_endpoint_status`.
- Tracker: `docs/design/ODDJOBZ-WSS-RPC-TRACKER.md`.
- Tool: `tools/oddjobz-canonicalize/canonicalize.py`.
