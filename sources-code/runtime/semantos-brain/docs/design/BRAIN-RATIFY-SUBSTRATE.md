---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/docs/design/BRAIN-RATIFY-SUBSTRATE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.277095+00:00
---

# BRAIN-RATIFY-SUBSTRATE — generalising ratify into a substrate queue + per-cartridge graph builder

Status: **DESIGN / proposal** (C4 brain-carve, substrate-generalization track, PR-J5).
No code yet. Author: C4 brain-carve, 2026-06-06.
Supersedes the `ratify` section of `BRAIN-QUERY-ATTENTION-RATIFY-SUBSTRATE.md`
(query ✅ shipped #882/#880 via the `cells_by_type` index; attention ✅ shipped
#884 via the attention-source registry; this is the third + last primitive).

## Why ratify is substrate

ratify is the **commit/idempotency sink of the LLM intent-extraction pipeline**:
the extractor emits proposals with a confidence score; high-confidence →
auto-ratify, low-confidence → operator review dialog; either way the brain's
`ratify` verb is what turns a confirmed *intent* into committed, signed cells.
Todd: "the LLM agents operating against the intent extraction pipeline will be
presenting ratification dialogs regularly on low-confidence assumptions of what
the intent was." Every cartridge with an intent pipeline ratifies. So ratify
**stays in the brain** — but today it is mis-named `oddjobz_ratify_*` and
hardwired to the four oddjobz typed stores. This PR de-oddjobz's it via the same
generalize-via-registry pattern used for routes / mint-contexts / stores /
cell-decoders (query) / attention-sources (attention).

## Current shape (verified 2026-06-06)

`cartridges/oddjobz/brain/zig/src/oddjobz_ratify_handler.zig` (1363 LOC):

- **`Handler`** owns: `RatifyStores {sites, customers, jobs, attachments, hat_bkds}`,
  `log_path` (`<data_dir>/oddjobz/ratifications.jsonl`), an in-memory
  `ratifications: StringHashMap(GraphRecord)` cache, a `clock` (injected for
  determinism), a mutex.
- **`handleRatify(allocator, params_json)`**: parse `{proposal_id, sir_program,
  payload_hint}` → **idempotency cache hit ⇒ return the recorded graph, no store
  writes** → scan `sir_program.nodes[].action` for a ratifiable action →
  `buildGraph(payload_hint)` → `appendLog` + `recordGraph` → `RatifyResult`.
- **`buildGraph`**: site lookup-or-mint → customers (dedupe ladder
  phone→email→name+role+site) → job (always fresh) → attachments. Per-cell
  `compute*CellId` derivations (oddjobz type-hashes) + `signOne` (BKDS sign of the
  cellId) + typed-store `appendCreated`/`appendCreatedV2`/`appendV2`. Builds FK
  refs **in-walk** (siteRef → customerRefs[] → jobRef).
- **`ratifications.jsonl`**: one line per proposal = `{proposal_id, persisted_at,
  site, customers[], job, attachments[]}` — just the graph cellIds. `replay()` on
  init rebuilds the cache; malformed lines skipped (forward-compat).

**Consumers** (all method `oddjobz.ratify_proposal`):
- `wss_backend.oddjobz_ratify` field → `handleOddjobzRatifyProposal`
  (`handlers.zig:271`) + reactor twin (`reactor.zig:838`). Both serialise
  `{proposal_id, cellIds:{site,customers,job,attachments}, persistedAt}`.
  **Note:** `handlers.zig:282` already *falls back to the verb_registry walker*
  when `oddjobz_ratify` is null — the proof-path that builder-via-registry works.
- `oddjobz_ratify_walker` registers `{extension_id:"oddjobz", verb:"ratify_proposal",
  walker_fn, ctx}` into `verb_registry` (`verb.dispatch`).
- serve wires both from the `store_registry` (§6b cartridge-owned stores) + the
  data-dir-seeded `hat_bkds` signer (serve.zig:2345-2375).
- **Producer**: the TS ingest pipeline (`runtime/legacy-ingest/`): extractor →
  `policy.ts` (≥0.85 auto-ratify, <0.5 skip) → `reingest-worker` →
  `brain-rpc.ts` POSTs `oddjobz.ratify_proposal {proposal_id, sir_program,
  payload_hint}` over WSS. The queue+confidence logic lives TS-side today; the
  brain is purely the commit/idempotency sink.

**Used by oddjobz only** (jambox references the walker as a *template* in
comments; no ratify of its own).

## The key decision (umbrella open-question #4): graph-builder registry, NOT generic-mint

**Recommendation: option (a) — a graph-builder registry; the cartridge keeps its
typed-store mint behind the builder vtable.** NOT option (b) "drive the generic
mint path" (`MintContextRegistry`/`encodeFromTypeHash`).

Grounded in the code: `buildGraph` mints via the **four typed stores directly**
(`sites.appendCreated`, `customers.appendCreatedV2`, `jobs.appendCreatedV2`,
`atts.appendV2`) — **zero** reference to `cells_mint_handler` /
`MintContextRegistry` / `substrate_entity.encodeFromTypeHash`. Two properties of
the graph defeat the generic mint path:

1. **In-walk FK cross-references.** customer cellIds are computed, then folded
   into the job's `customerRefs[]`, then the job cellId folds into each
   attachment's `jobRef`. The generic mint path mints one cell from one typeHash +
   payload; it has no notion of a *graph* whose later cells reference earlier
   ones.
2. **Lookup-or-mint dedup ladders.** sites dedupe on a normalised lookup-key;
   customers on a phone→email→name+role+site ladder. That dedup is the oddjobz
   domain model, not a generic mint concern.

Re-expressing this as generic mint-context ops would be a large rewrite for no
carve benefit — the domain graph **is** oddjobz's. The clean seam: the brain owns
the **ratification queue** (proposal lifecycle); the cartridge owns the **graph
builder** (SIR + payload_hint → minted, signed cells → result blob).

This matches the J4 attention split exactly (brain = generic poll/merge;
cartridge = the signal producers).

## Proposed shape

### New leaf — `src/ratify_builder_registry.zig`
```
RatifyBuilder {
    namespace: []const u8,                 // selects the builder (= typeHash seg-1 ns)
    label: []const u8,
    ctx: *anyopaque,
    build: *const fn (ctx, allocator, params_json) anyerror![]u8,  // → result JSON blob
}
RatifyBuilderRegistry { entries:[N], len, add(), find(namespace) }
```
Keyed on **namespace**, consistent with attention (J4) + the `cells_by_type`
typeHash seg-1 namespace. The SIR program carries **no program-kind
discriminator** (only per-node `action` strings, all six → `job.v2` lead), so the
namespace must come from the dispatch envelope, not from inside the SIR.

### New generic handler — `src/ratify_queue_handler.zig`
The brain owns the proposal lifecycle, builder-agnostic:
```
Handler { registry, log_path, cache: StringHashMap([]u8 /*result blob*/), clock, mu }
submit(allocator, namespace, proposal_id, params_json) →
    cache.get(proposal_id) ?? (
        builder = registry.find(namespace) orelse error.no_builder;
        blob = builder.build(allocator, params_json);
        appendLog({proposal_id, persisted_at, namespace, result: blob});  // opaque
        cache.put(proposal_id, blob);
        blob
    )
```
**Idempotency log generalised** from the four oddjobz cellId buckets to
`{proposal_id, persisted_at, namespace, result:<opaque-json>}`. The existing
replay already tolerates schema drift (skips unknown/malformed lines), so this is
a clean forward-migration; old lines still replay into the cache by re-serialising
their cellIds into a result blob (or are simply ignored — a missed cache entry
just re-runs the dedup-safe builder; only the "always-fresh job" would duplicate,
so a one-time replay shim that maps the old shape → blob is worth keeping in J5a).

`CartridgeDeps += ratify_builder_registry`. serve builds
`ratify_queue_serve = Handler.init(&registry, data_dir, realClock)` +
`wss_backend.ratify = &ratify_queue_serve` (mirrors J4's attention wiring).

### oddjobz contribution (`registration.zig`)
Register one builder `{namespace:"oddjobz", build}` whose `build` is the current
`buildGraph` + `RatifyResult` serialise, behind the vtable. The builder closes
over the `RatifyStores` (read from `deps.store_registry`) + the BKDS signer. The
SIR-parse + buildGraph + signOne logic moves verbatim into the builder; only the
log/cache/replay leave (they become the brain's queue).

### Wire surface
- New generic method **`ratify.submit`** params `{namespace, proposal_id,
  sir_program, payload_hint}` → `ratify_queue.submit(namespace, proposal_id,
  params)` → result blob. `handleRatifySubmit` (handlers.zig) + reactor twin
  (mirrors J4's `attention.poll`).
- **`oddjobz.ratify_proposal` kept as a back-compat alias** → maps to
  `ratify.submit` with `namespace="oddjobz"`, so the TS ingest pipeline + helm
  keep working unchanged. The serialiser still emits the
  `{proposal_id, cellIds:{...}, persistedAt}` shape (the oddjobz builder's result
  blob IS that shape).

## PR breakdown

- **PR-J5a** (this track, non-breaking): introduce `ratify_builder_registry` +
  `ratify_queue_handler` (generic, owns the log/cache/replay incl. the old-shape
  replay shim) + `CartridgeDeps` field; split `oddjobz_ratify_handler` so
  buildGraph+sign become the registered builder while the queue logic moves to the
  brain; route **both** `oddjobz.ratify_proposal` (alias, ns=oddjobz) and the new
  `ratify.submit` through the one queue (single log owner); reactor twin; verb
  walker keeps working (or re-registers the builder). serve wiring, build.zig
  modules + test artifacts. **Wire-compatible** — TS ingest + helm untouched.
  Green gate (incl. the existing ratify conformance tests untouched).
- **PR-J5b** (deferred, needs Todd's ok — pipeline touch): migrate `brain-rpc.ts`
  + any helm caller from `oddjobz.ratify_proposal` to `ratify.submit`; then retire
  the alias + the `wss_backend.oddjobz_ratify` field + the standalone
  `oddjobz_ratify_walker` (the builder registry replaces it). Mirrors the J3
  deferral (front-end/pipeline migration gated on Todd).

## Decisions still needing Todd

1. **Builder key = namespace** (consistent w/ attention J4 + cells_by_type), with
   `oddjobz.ratify_proposal` as a back-compat alias mapping to ns=oddjobz. OK?
   (Alternative: key on extension_id from the verb_registry tuple — same effect,
   less consistent with the other two primitives.)
2. **Old-log replay shim** in J5a (map the four-bucket lines → a result blob so
   replayed proposals stay idempotent and don't re-mint a duplicate job), vs
   accept a one-time cache miss on pre-existing proposals. Recommend the shim
   (cheap, avoids duplicate jobs on restart). With zero real prod load
   (`v1_production_is_test_data`) the risk is low either way.
3. **J5b timing** — fold the TS-ingest migration into this track now, or defer
   until after the carve (like J3)? Recommend defer; J5a is the substrate win.
4. **leads / ratify deletion** stays a *separate* question (zero-prod-users
   go/no-go) — J5 generalises ratify, it does not delete anything.

## Appendix — affected files
- New: `src/ratify_builder_registry.zig`, `src/ratify_queue_handler.zig`.
- Edit: `src/cartridge_seam.zig` (+field), `src/cli/serve.zig` (registry var,
  queue init, wss_backend.ratify, deps), `build.zig` (modules + wiring + tests),
  `cartridges/oddjobz/brain/zig/src/oddjobz_ratify_handler.zig` (split: builder
  keeps buildGraph+sign, queue logic removed), `cartridges/oddjobz/brain/zig/
  registration.zig` (register builder), `cartridges/bsv-anchor-bundle/brain/zig/
  src/wss_wallet/{types,handlers,reactor}.zig` + `wss_wallet.zig` (ratify.submit
  + alias + reactor twin).
- J5b only: `runtime/legacy-ingest/.../brain-rpc.ts` (method rename), retire
  `oddjobz_ratify_walker` + `wss_backend.oddjobz_ratify`.
