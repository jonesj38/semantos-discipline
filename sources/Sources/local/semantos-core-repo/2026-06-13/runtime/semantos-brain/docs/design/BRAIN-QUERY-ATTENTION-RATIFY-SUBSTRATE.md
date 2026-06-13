---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/docs/design/BRAIN-QUERY-ATTENTION-RATIFY-SUBSTRATE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.277383+00:00
---

# BRAIN-QUERY-ATTENTION-RATIFY-SUBSTRATE — generalising the three middle-tier primitives

Status: **PARTIALLY SHIPPED** (C4 brain-carve, substrate-generalization track).
Author: C4 brain-carve, 2026-06-05.

- **query ✅ shipped** (#880 `cells_by_type` LMDB index + #882 generic `cell.query`
  + `cell_decoder_registry`). NOTE open-question #1 resolved the *other* way: Todd
  chose the `cells_by_type` index (8|8|8|8 typeHash templates), not the typed-view
  registry. The cartridge registers a **cell decoder** per typeHash; `cell.query`
  scans the type index → matches_filter → decode_one.
- **attention ✅ shipped** (#884 `attention.poll` + `attention_source_registry`),
  **namespace-scoped** per Todd: caller passes the in-scope namespaces; the brain
  filters + merges (betterment never bleeds into oddjobz). `attention_http`
  reconciliation deferred (open-question #3 still open).
- **ratify** → deepened into its own doc `BRAIN-RATIFY-SUBSTRATE.md` (PR-J5):
  graph-builder registry (open-question #4 resolved → option a, NOT generic-mint).

The sections below are the original 2026-06-05 proposal, kept for provenance.

## Context

query, ratify, and attention are **substrate primitives**, not oddjobz cartridge
code (Todd, 2026-06-05):

- **query** = the universal **find** trunk (read side of do/talk/find). The helm's
  `find …` + the generic `cell.query`.
- **ratify** = the LLM intent-extraction pipeline's ratification step — operators
  confirm low-confidence intent before it commits. Used across cartridges.
- **attention** = the helm-home notification/attention surface the *majority* of
  cartridges feed, scoped to the deployed cartridge.

So they STAY in the brain. But today they are **mis-named `oddjobz_*` and
hardwired to the four oddjobz typed stores** (sites/customers/jobs/attachments).
This track de-oddjobz's them: the brain keeps the generic primitive; the
cartridge contributes its domain piece via a registry — the SAME pattern the
carve already uses for routes (route_registry), mint contexts
(mint_context_registry), and stores (store_registry).

This is generalization, NOT a carve-to-cartridge: the generic primitives move
toward the substrate; the oddjobz-specific views/builders/sources move into the
oddjobz cartridge (where the three handler files already physically live —
`cartridges/oddjobz/brain/zig/src/oddjobz_{query,ratify,attention}_handler.zig`).

## The unifying pattern: generalize-via-registry

Each primitive splits into **generic shell (brain) + typed contribution
(cartridge, registered at boot)**:

| primitive | generic shell (stays/becomes substrate) | cartridge contributes (via a registry) |
|-----------|------------------------------------------|----------------------------------------|
| query   | `cell.query(typeHash, filter)` dispatch + JSON-RPC/REPL surface | a **query view** per cellType (the typed fan-out + encoder) |
| ratify  | the ratification queue: idempotency log, lookup-or-mint orchestration, BKDS sign, result shape | a **graph builder** (SIR → cells) per cartridge |
| attention | the poll/score/aggregate + helm-home surface | **attention sources** (signal producers) per cartridge |

The brain gains three registries on `CartridgeDeps` (analogous to the existing
ones); the oddjobz cartridge registers its view/builder/sources in `registerInto`;
the brain's `wss_backend.oddjobz_*` fields + the hardcoded `cell_query_handler`
wrap are replaced by generic registry dispatch.

## Current coupling (verified 2026-06-05)

All three handlers live in `cartridges/oddjobz/brain/zig/src/`; the generic
wrappers/consumers (`cell_query_handler.zig`, `wss_backend`, `attention_http.zig`)
live in brain `src/`. All are consumed via `wss_backend.oddjobz_{query,ratify,
attention}` (JSON-RPC) + the verb_registry ratify walker. serve wires them from
the `store_registry` (already cartridge-owned post-§6b).

### query
- `oddjobz_query_handler.QueryStores` names the 4 typed stores; 10 verbs
  (listSites/Customers, findJobsAtSite/ForCustomer, findAttachmentsForJob, get*).
  The cross-store JOINs use oddjobz ref fields (siteRef/customerRef/jobRef).
- `cell_query_handler` (brain) HARD-WRAPS it: `Handler{ .oddjobz = … }` + a
  `TYPE_HASH_REGISTRY` mapping `oddjobz.{customer,job,site,attachment}.v2` →
  entity tags → the oddjobz methods. **This is the generic-looking but
  oddjobz-hardcoded layer.**
- **Blocker:** the `CellStore` vtable has NO type index (only get-by-hash, owner,
  prev_state, anchor-txid/height). A generic "query all cells of typeHash X"
  needs either a new `cells_by_type` index on CellStore, OR the typed-view
  approach (cartridge keeps its typed stores as the query index).

### ratify
- `oddjobz_ratify_handler` (1363 lines): SIR payload → graph walk (site
  lookup-or-mint → customers → job → attachments) → BKDS sign → idempotent
  persist to `ratifications.jsonl`. The **orchestration** (parse, idempotency,
  lookup-or-mint, sign, result) is generic; the **per-cell-type mint + cell-id
  derivations** are oddjobz-specific (computeSiteCellId etc.).
- The generic mint path already exists (`cells_mint_handler` +
  `MintContextRegistry`) — a generic ratify could drive cartridge-registered
  graph builders rather than hardcoding the 4 oddjobz types.

### attention
- `oddjobz_attention_handler` (937 lines): reads `<data_dir>/oddjobz/messages.jsonl`
  + `dispatch-decisions.jsonl`; 3 verbs (listMessages, listDispatchDecisions,
  pollAttentionSignals). The poll is a 3-bucket weighted aggregate
  (ratification-required dispatches, recent messages, open jobs near due date).
  The **aggregation/scoring/surface** is generic; the **file paths + schemas +
  the jobs-due-date bucket** are oddjobz-specific.
- `attention_http.zig` (brain) serves `/api/v1/attention/*` but is currently NOT
  wired to oddjobz_attention — a second, independent attention surface to
  reconcile.

## Proposed generic shapes

### query — a cell-query view registry
- New leaf `query_view_registry.zig`: `QueryViewRegistry` = typeHash →
  `{ list(alloc) , get(alloc, ref), findBy(alloc, filter) → json }` vtable.
- `cell_query_handler` becomes generic: `cell.query(typeHash, filter)` looks up
  the view by typeHash + dispatches; no `.oddjobz` field, no hardcoded
  TYPE_HASH_REGISTRY (the cartridge registers its typeHashes + view).
- The oddjobz cartridge registers a view backed by its typed stores (the current
  fan-out logic, moved behind the vtable). Other cartridges (jambox) register
  theirs — the `cell.query` primitive serves all of them generically.
- `CartridgeDeps += query_view_registry`. `wss_backend.oddjobz_query` →
  `wss_backend.cell_query` only (the generic one); the `oddjobz.find_*` JSON-RPC
  methods become `cell.query` calls (or thin generic aliases).
- **Decision needed:** typed-view registry (above — cartridge's typed stores ARE
  the index, no CellStore change) vs adding a `cells_by_type` index to CellStore
  for a store-free generic query. Recommend the typed-view registry first (no new
  CellStore infra; reuses the §6b stores), with the cells_by_type index as a
  later optimisation.

### ratify — a graph-builder registry
- The brain keeps the generic ratification primitive: parse `{proposal_id,
  sir_program}`, idempotency log (`ratifications.jsonl`), BKDS sign, result. The
  per-cartridge **graph builder** (`SIR → minted cells`) is registered by the
  cartridge (`CartridgeDeps += ratify_builder_registry`, keyed by intent/program
  kind). oddjobz registers its current buildGraph; the brain's ratify verb routes
  to the registered builder.
- Reuse `MintContextRegistry`/the generic mint path for the actual cell minting
  where possible, so derivations live with the cartridge's cell types.

### attention — an attention-source registry
- The brain keeps the generic poll/score/aggregate + the helm-home surface
  (reconciled with `attention_http`). Cartridges register **attention sources**
  (`CartridgeDeps += attention_source_registry`): each source yields scored
  signals `{kind, score, ref, summary, expiresAt}`. oddjobz registers its 3
  sources (dispatch-needs-ratification, recent messages, jobs-near-due). The
  generic poller merges + ranks across all registered sources.
- Generalise the JSONL coupling: either a generic attention-event store
  (cartridges append events) or keep per-cartridge files behind the source
  vtable.

## Recommendation

Generalize-via-registry, **one primitive at a time** (each is independently
shippable + independently valuable), in this order (easiest → hardest):

1. **query** first — it's the most-used (find trunk), and the typed-view-registry
   shape needs no new CellStore infra (reuses the §6b stores behind a vtable).
   Biggest correctness win: the brain's `cell_query_handler` stops naming oddjobz.
2. **attention** — source registry + reconcile the two attention surfaces.
3. **ratify** — graph-builder registry (largest handler; touches the mint path).

Each follows the established seam recipe (new registry leaf → `CartridgeDeps` field
→ cartridge `registerInto` registers its contribution → delete the brain's
hardcoded `oddjobz_*` wiring → green).

## Open questions for Todd

1. **query index strategy:** typed-view registry (cartridge's stores are the
   query index — no CellStore change) vs a new `cells_by_type` index on CellStore
   (store-free generic query, bigger). Recommend the former first.
2. **`cell.query` vs `oddjobz.find_*`:** collapse the bespoke `oddjobz.find_jobs_*`
   JSON-RPC methods into the generic `cell.query(typeHash, filter)`, or keep thin
   named aliases for the helm's current calls?
3. **attention surfaces:** reconcile `attention_http` (/api/v1/attention) with the
   oddjobz_attention JSON-RPC verbs into one generic surface, or leave both?
4. **ratify vs generic mint:** should ratify drive the existing
   `MintContextRegistry`/generic-mint path, or stay a separate graph-builder
   registry?
5. **scope/order:** do all three, or just query (highest value) for now? And is
   this higher priority than the REPL-verb-command seam (#877) + the leads
   deletion?

## Appendix — affected files
- query: `cartridges/oddjobz/brain/zig/src/oddjobz_query_handler.zig`,
  `src/cell_query_handler.zig`, `src/wss_wallet/*` (oddjobz_query/cell_query),
  new `src/query_view_registry.zig`, `src/cartridge_seam.zig`,
  `cartridges/oddjobz/brain/zig/registration.zig`.
- ratify: `…/oddjobz_ratify_handler.zig`, the verb_registry ratify walker,
  `src/wss_wallet/*`, new `src/ratify_builder_registry.zig`.
- attention: `…/oddjobz_attention_handler.zig`, `src/attention_http.zig`,
  `src/wss_wallet/*`, new `src/attention_source_registry.zig`.
- shared: `src/cell_store.zig` (only if the cells_by_type index option is taken).
