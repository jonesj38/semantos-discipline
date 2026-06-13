---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/UNIVERSAL-CARTRIDGE-BOOT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.741310+00:00
---

# Universal Cartridge Boot Sequence — Design

Status: **proposal / review artifact** (no shared-boot-path code edited).
Author pass: 2026-05-19. Companion to
`docs/design/CANONICAL-CARTRIDGE-MODEL.md` (the model — esp. §5 C7
`brain.surface`); resolves the boot-path deferrals named in
`docs/CHESS-DOUBLING-CUBE-TRACKING.md` §1 and
`docs/canon/commissions/wave-tessera.md` §7/§9 (tessera V0.3 boot
threading + V0.5 octave-at-boot).

## 0. Headline

The brain boots cartridge walkers/stores via **N hand-edited blocks
scattered across three sites in `runtime/semantos-brain/src/cli/serve.zig`**.
Every new cartridge (jambox, oddjobz-ratify, the substrate walkers, and
now chess + tessera) repeats the same three edits in a shared,
review-sensitive file. This doc proposes replacing those N×3 hand-edits
with **one generic boot pass over one declarative table**, driven by the
cartridge manifest contract that already exists (C7
`brain.surface`/`brain.verbsModule`/`verbs[]`). It also fixes a
lifetime hazard, makes the (intentional) compilation-substrate gate
explicit and adds the marketplace **entitlement** gate the model needs,
and folds the deferred chess/tessera boot wiring and tessera's V0.5
octave-at-boot into the same uniform sequence.

This is the universal answer to a question that keeps recurring
per-cartridge: *"how does a multi-cartridge brain instance load all its
cartridges at boot?"*

## 1. Current state (verified, file:line)

Boot entrypoint: `main.zig:86` → `cli.zig:102` → **`cli/serve.zig`
`cmdServe` (~343–2613)**. Ordered boot: arg/manifest parse →
HatRegistry → site config → SiteServer → DynamicRuntime → helm broker →
(optional) REPL dispatcher → **cartridge stores & walkers** → wss
`Backend` wiring (~1638–1764) → HTTP listen loop.

**Per-cartridge registration is fully hardcoded — 3 sites each:**

1. **`@import`** at the top of `serve.zig` (e.g.
   `const jambox_walkers_mod = @import("jambox_walkers");`).
2. **Store + State init** as `cmdServe` **stack-locals** (~862–875),
   e.g. `jam_clip_state_store_serve = …Store.init(allocator, realClock)`
   then `var jambox_walker_state: …State = .{ … &store }`.
3. **`registerAll`/`registerInto`** into the verb_dispatcher Registry
   (~1686–1742), then `wss_backend.verb_registry = &verb_registry_serve.?`.

`wss_wallet.Backend`
(`cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet/types.zig:61`)
exposes the generic seam `verb_registry: ?*verb_dispatcher.Registry`
(plus legacy per-handler optional pointers: `oddjobz_ratify`,
`oddjobz_query`, `cell_query`, `oddjobz_attention`,
`manifest_registry`).

Cartridges registered this way today: `jambox` (registerAll, 2 verbs),
`oddjobz_ratify` (registerInto), `entity.encode`, `overdue_jobs`,
`pipeline_gaps` (substrate, shared cell store). **chess** and
**tessera** are code-complete + module-wired in `build.zig` +
`test-substrate` green, but **NOT** boot-wired — deferred for review
precisely because step 2/3 touch this shared file.

The manifest already declares the contract a generic boot would need —
`brain.surface: "walkers"`, `brain.verbsModule` (the Zig `@import`
name), `verbs[]` (CANONICAL-CARTRIDGE-MODEL §5 C7) — but
`extension_manifest_loader.zig` only uses it for read-only
manifest.list/install/uninstall. **Nothing drives boot from it.**

## 2. Problems with the status quo (named, not hidden)

1. **N×3 hand-edits in a shared, review-gated file.** This is *why*
   chess and tessera are stuck: the work is trivial but lands in
   `serve.zig` where parallel sessions collide and every edit needs
   review. The cost scales with cartridge count — the opposite of the
   "drop a cartridge, it just works" cc4 goal.
2. **Stack-local lifetime hazard ("deeper than module wiring").** The
   stores/States are `cmdServe` stack-locals; their addresses are
   captured by `wss_backend.verb_registry` walker `ctx` pointers and
   must stay valid for the entire HTTP listen loop. Each cartridge
   re-derives this by hand; one scope mistake = use-after-scope in a
   live request path.
3. **Registration is gated on `--enable-repl` — and that gate is
   *intentional*, not a bug** (corrected per Todd 2026-05-19). Semantos
   is a conversation-first OS: **the REPL is the substrate that compiles
   conversation into executables.** Cartridge verbs becoming routable
   exactly when that compilation substrate is up is the *designed*
   semantics, not accidental coupling. The problem is therefore **not**
   "remove the gate" but: (a) the gate is currently *implicit* in a flag
   name (`--enable-repl`) rather than a named capability
   ("conversation-compilation host"), and (b) there is no second,
   per-cartridge gate for the **marketplace** model (cartridges are
   authored and sold; functionality must be restrictable absent a
   provided license/entitlement). A universal boot must preserve the
   compilation-substrate gate and add a principled per-cartridge
   entitlement gate — not decouple registration from the substrate.
4. **Manifest ↔ boot drift.** C7 declares `brain.verbsModule` + `verbs[]`
   but boot ignores them; the real registration is the hand-edited
   `registerAll`. Two sources of truth that can silently diverge.
5. **Cells/octave has no seam at all.** tessera V0.5's "register cell
   types into the octave registry at brain boot" has no pre-boot path
   because there is no *boot* path either — chess/oddjobz do no
   cartridge→octave registration. It must be designed, not mirrored.

## 3. Design — the universal boot sequence

### 3.1 Constraint: Zig module identity is comptime

Zig has no runtime `dlopen` of arbitrary cartridge modules in this
build. Module identities (`@import("chess_walkers")`) are comptime. So
the universal mechanism is **not** a runtime "scan manifests, load
modules" loop (that arrives later, §5 P5, only once dynamic loading
exists). It is a single **comptime cartridge boot table** — one
declarative entry per cartridge — replacing the three scattered
hand-edits with one table row.

### 3.2 The cartridge boot table

One entry per walker/cell cartridge:

```
CartridgeBoot{
  id:            "chess",
  surface:       .walkers,           // C7 brain.surface
  StoreType:     chess_game_store.Store,
  initStore:     fn(alloc, clock) StoreType,     // or .none
  StateType:     chess_walkers.State,
  makeState:     fn(*StoreType) StateType,
  registerVerbs: chess_walkers.registerAll,      // (*Registry,*State)!void
  registerCells: null,                           // or tessera_cells hook
}
```

### 3.3 `CartridgeRuntime` — fixes the lifetime hazard uniformly

`bootCartridges` **heap-allocates** each Store/State into a
`CartridgeRuntime` arena owned for the `wss_backend` lifetime and
`deinit`-ed at shutdown. This eliminates per-cartridge stack-local
scope reasoning — the #2 hazard — for *all* cartridges at once. This
is the core architectural win; deduplication is secondary.

### 3.4 The single generic pass

```
fn bootCartridges(alloc, registry: *Registry, deps: BootDeps)
      !*CartridgeRuntime
// for each entry in CARTRIDGE_BOOT_TABLE:
//   store = entry.initStore(alloc, deps.clock)         (heap, owned)
//   state = entry.makeState(store)                      (heap, owned)
//   if entry.registerVerbs:  entry.registerVerbs(registry, state)
//   if entry.registerCells:  entry.registerCells(deps.octave_registry)
// return runtime  (owns every store/state; one deinit)
```

`serve.zig` shrinks from N×3 edits to **one call** +
`wss_backend.verb_registry = &runtime.registry`. Adding a cartridge
never touches `serve.zig` again — only the table.

### 3.5 Two principled gates (compilation substrate + entitlement)

`bootCartridges` is invoked from the **same compilation-substrate
condition as today** (the `--enable-repl`/conversation-compilation
host) — behavior is *preserved*, not changed. The improvement is to
make that gate *named and explicit* and to add a second, per-cartridge
gate for the marketplace model:

```
fn bootCartridges(alloc, registry, octave_registry, deps) !*CartridgeRuntime
  for entry in CARTRIDGE_BOOT_TABLE:
    // gate 1: compilation substrate (same condition as today;
    //   the caller only invokes bootCartridges when the brain is a
    //   conversation-compilation host — preserved, just hoisted)
    // gate 2: per-cartridge entitlement
    switch (deps.entitlement(entry.id)) {     // default: .granted
      .granted    => construct + registerVerbs/registerCells,
      .restricted => register a stub that returns
                     {ok:false,reason:"license_required"} for each
                     declared verb (cartridge is visible but inert),
      .absent     => skip entirely,
    }
```

`deps.entitlement` is a **hook, not a system** — this PR ships it
defaulting to `.granted` for every bundled cartridge (zero behavior
change) with the seam in place. The actual licensing/marketplace
mechanism (who issues entitlements, BRC-style license cells, the
"restricted = visible-but-inert" UX, revocation) is a **named
follow-up design**, not built here. The point is the universal boot
sequence is where that gate *lives*, so the marketplace model has a
single, principled enforcement point instead of per-cartridge ad-hoc
checks.

### 3.6 Cells fold-in (resolves tessera V0.5) — CORRECTED 2026-05-20

**Earlier drafts of this section (and §6 D4) were wrong: P3 does NOT
need a kernel cell-type/octave API.** Verified against the code on
`origin/main` (post-#454):

- The generic typed-cell mint path already exists end-to-end:
  `entity.encode` (verb_dispatcher walker) → `substrate_entity` encodes
  the 1024-byte cell → `cell_store.put` persists. **Octave escalation
  is already the default path** — payloads >768 B transparently go to
  the octave-1 content store (`content_store_local_fs` +
  `substrate_entity.encodeEntityEscalating`); no kernel change, no
  "octave-aware registration" needed. The >1KB reality is handled.
- `tessera_cells.zig` already produces correct headers (type-hash,
  linearity, domain-flag at the exact kernel offsets, kernel-validated).

The **actual** gap is one thing, and it is the *same anti-pattern this
whole design removes for walkers*: `substrate_entity.specByTag(tag)` is
a **hardcoded brain-core `switch`** over oddjobz's 9 entity tags
(`else => null`). A cartridge's cell types are mintable through
`entity.encode` only if their `EntityTypeSpec` (`tag, type_path,
how_slug, inst_path, domain_flag`) is known to that switch — and adding
tessera's there is impossible (`runtime/semantos-brain/src/` →
`no-tessera-in-brain-core` gate).

So P3 = **do for cell-type SPECs exactly what cartridge_boot did for
walkers**: (1) make SPEC lookup registry-backed (additive: the existing
hardcoded switch first, then a runtime-registered SPEC table —
behaviour-identical for oddjobz's 9); (2) add a `registerCells` pass to
`cartridge_boot.zig` (out-of-src) that registers each cartridge's
`EntityTypeSpec`s at boot, derived from its `*_cells.zig` data
(tessera_cells already has name/linearity/typeHash/domainFlag); (3)
tessera/chess/oddjobz contribute their SPECs via the table. **No kernel
primitive. No octave-API change.** Greenfield preserved: SPEC data
lives in `tessera_cells.zig` + the out-of-src boot table;
`substrate_entity` only gains a generic `register(spec)` — zero
cartridge names in `src/`. Concrete plan: §8.

### 3.7 Manifest-driven end-state

The table is **code-generated from `cartridge.json`**
(`brain.verbsModule` + `verbs[]`), a `tools/` step mirroring
`tools/cartridge-manifest/generate.ts`, with a drift gate
(`tests/gates/cartridge-boot-table-consistency.test.ts`, analogue of
`manifest-consistency.test.ts`). End-state: drop a `cartridge.json` +
brain module → regenerate → it boots. Zero `serve.zig` edits, zero
manifest/boot drift (problem #4 closed).

## 4. Greenfield tension (must be surfaced, not papered over)

`tests/gates/no-tessera-in-brain-core.test.ts` fails if the literal
`tessera` appears under `runtime/semantos-brain/src/`. A comptime boot
table living at `runtime/semantos-brain/src/cartridge_boot_table.zig`
that does `@import("tessera_walkers")` **would contain `tessera`** and
break the gate — exactly as it would for the hand-edited `serve.zig`
path today (which is why chess/tessera are deferred, not just unwired).
`build.zig` is exempt only because it is *outside* `src/`.

Options (a §6 decision): (i) the generated table lives **outside
`src/`** (alongside `build.zig`), the analogue that already works;
(ii) the no-X-in-brain-core gate contract is revised to exempt the
**generated loader manifest** specifically (it is generic loader infra,
not hand-baked cartridge logic — the same justification that exempts
`build.zig`'s `b.path("../../cartridges/<id>/…")`); (iii) the table is
data (a `.zon`/JSON the loader reads) with module binding via a
comptime indirection that never spells a cartridge id in `src/`.
Recommendation: **(i)+(ii)** — place generated table outside `src/`
and codify the "generated generic-loader manifest is exempt" rule in
the gate, mirroring the build.zig precedent.

## 5. Migration path (phased; each phase shippable + independently reviewable)

- **P0** — this doc; ratify §6 decisions.
- **P1** — introduce `CartridgeRuntime` + `bootCartridges` + the table
  type; migrate **jambox only** into it (behavior-identical;
  jambox is the lowest-risk proof). `serve.zig` net change: jambox's
  3 edits → 1 table row + 1 call. Verifiable: existing jambox verb
  tests + `test-substrate` unchanged.
- **P2** — fold **chess + tessera** into the table. *This is the
  concrete resolution of the deferred boot-path items.* Both are
  already module-wired + green; P2 is purely "add two table rows,"
  reviewed once, not N hand-edits. Compilation-substrate gate
  **preserved** (§3.5); entitlement hook seam added, default `.granted`.
- **P3** — fold the substrate walkers (`entity.encode`, `overdue_jobs`,
  `pipeline_gaps`) and `oddjobz_ratify`; add the `registerCells` hook
  and land tessera V0.5 octave-at-boot through it.
- **P4** — codegen the table from `cartridge.json` + drift gate.
- **P5** (future, gated on DLO.x) — runtime dynamic loading for
  user-installed cartridges; the comptime table remains the
  bundled-cartridge path.

Each phase touches `serve.zig` once, reviewed, never in an autonomous
loop (it is the shared brain boot path).

## 6. Decisions — RATIFIED (Todd 2026-05-19)

1. **Compilation-substrate gate: PRESERVE, do not decouple.** The
   `--enable-repl` condition is intentional — the REPL is how
   conversation is compiled into executables in this conversation-first
   OS. Cartridge registration stays gated on the compilation-substrate
   condition (same behavior as today, just hoisted into the generic
   pass and named). **New requirement:** add a per-cartridge
   *entitlement* gate for the marketplace model (cartridges are
   authored & sold; restrict functionality absent a license). Ship it
   as a hook defaulting to `.granted` (§3.5); the licensing mechanism
   itself is a separate follow-up design.
2. **Greenfield placement: (i)+(ii).** Generated boot table lives
   **outside `src/`** (sibling to `build.zig`) AND the
   no-X-in-brain-core gate contract is amended to exempt the generated
   generic-loader manifest, mirroring the `build.zig` precedent. (Owned
   recommendation — Todd deferred placement to this design.)
3. **Phasing & executor: P1+P2 as one reviewed PR, prepared by me.**
   jambox proof + chess/tessera fold-in together (shared seam). This is
   a reviewed PR on the shared boot path — NOT autonomous loop work.
4. **Octave/cells API — REVISED 2026-05-20: NO kernel API is required.**
   The earlier "kernel cell-type/octave registration API needed" answer
   was wrong (it was inferred, not code-checked). Verified against
   `origin/main` (post-#454): octave escalation for >768 B payloads is
   already the default mint path (`entity.encode` →
   `substrate_entity.encodeEntityEscalating` → octave-1 content store);
   `tessera_cells.zig` already emits kernel-correct headers. The real
   P3 gap is the hardcoded brain-core `substrate_entity.specByTag`
   switch — the *same* per-cartridge-hardcoded anti-pattern this design
   removes for walkers. P3 is therefore a **registry generalization +
   a `registerCells` boot pass**, structurally identical to P1/P2, not
   a kernel spike. See §3.6 (corrected) and §8 (concrete plan).

## 6b. Marketplace / licensing dimension (named follow-up — not built here)

Cartridges are a **marketplace**: third parties author and sell them;
the OS must be able to restrict a cartridge's functionality unless a
license/entitlement is provided. The universal boot sequence is the
**single principled enforcement point** for this (gate 2, §3.5) —
without it, licensing would be N ad-hoc per-cartridge checks (the same
anti-pattern this whole design removes for registration). Scope
explicitly deferred to its own design: entitlement issuance/representation
(likely a BRC-style license cell bound to operator identity),
verification at boot, the "restricted ⇒ visible-but-inert" shell UX,
revocation, and offline grace. The P1+P2 PR only lands the *seam*
(`deps.entitlement(id) -> .granted|.restricted|.absent`, default
`.granted`), so no behavior changes and the marketplace work has a
home to slot into.

## 7. Why this is the right shape

It is the runtime realization of the already-ratified C7
`brain.surface` contract: the manifest *says* what a cartridge's brain
surface is; this makes the boot *honor that declaration generically*
instead of re-encoding it by hand per cartridge. It turns "add a
cartridge" from "edit the shared brain boot path in three places, get
review, mind the lifetimes" into "add a row (eventually: just ship the
manifest)." chess and tessera stop being special deferred cases and
become the first two table rows.

## 8. P3 — concrete plan: cartridge cell-types through the generic mint path

Status: plan / review artifact (no code edited). Grounded in
`origin/main` post-#454. **No kernel change. No octave-API change.**

### 8.1 What already works (verified, do not rebuild)

The generic typed-cell mint path is complete end-to-end:

- `entity.encode` (a `verb_dispatcher` walker, `entity_encode_walker.zig`)
  takes `{tag, linearity, owner_id_hex, payload_json, timestamp_ns?}`.
- It resolves the `EntityTypeSpec` via `substrate_entity.specByTag(tag)`
  (type-hash is brain-side, never the caller's), encodes the 1024-byte
  cell, and **escalates >768 B payloads to the octave-1 content store**
  automatically (`encodeEntityEscalating` + `content_store_local_fs`);
  ≤768 B stays inline. The ">1KB ⇒ octave-1" reality is already the
  default — nothing to add.
- `cell_store.put(&cell)` persists; the walker is null-store resilient
  (returns `cell_id` for dry-run).
- `tessera_cells.zig` already emits headers (type-hash, linearity,
  domain-flag) at the exact kernel offsets, kernel-validated.

### 8.2 The only gap

`substrate_entity.specByTag(tag)` is a hardcoded `switch` over oddjobz's
9 tags (`TAG_CUSTOMER…TAG_ESTIMATE`, `else => null`), in
`runtime/semantos-brain/src/` — so (a) tessera's cell types are unknown
to the mint path and (b) they **cannot** be added there (greenfield
gate). `EntityTypeSpec` a cartridge must contribute is small and
already derivable from `tessera_cells.zig`:

```
EntityTypeSpec{ tag:u32, type_path:[]const u8, how_slug:[]const u8,
                inst_path:[]const u8, domain_flag:u32 }
```

`type_path` = the cell name ("tessera.bottle"); `domain_flag` =
`tessera_cells.domainFlag(t)` (already computed); `tag` = a tessera tag
block (allocate `TAG_TESSERA_BASE` off the 0x000104xx page already
reserved for tessera in constants.json — no oddjobz-tag collision);
`how_slug`/`inst_path` = the type-hash triple per the tessera canon
(authored alongside the cells, the analogue of oddjobz's
`"locate"/"inst.location.work-site.v2"`).

### 8.3 The change (mirrors P1/P2 exactly)

1. **`substrate_entity`: switch → registry-backed lookup, additive.**
   Keep the hardcoded `switch` as the first arm (oddjobz's 9 unchanged,
   behaviour-identical); on `else`, fall through to a process
   `SpecRegistry` (a `std.AutoHashMap(u32, EntityTypeSpec)`). Add
   `pub fn register(reg: *SpecRegistry, spec: EntityTypeSpec) !void`
   (collision-checked, idempotent — same shape as `cell_registry`/the
   verb Registry). `specByTag` consults switch-then-registry. The file
   gains a generic `register` + lookup; **zero cartridge names added**.
2. **`cartridge_boot.zig` (out-of-src): add the `registerCells` pass.**
   `Spec` already has `surface`; add an optional
   `register_cells: ?*const fn (*SpecRegistry) anyerror!void`. The
   universal pass calls it under the same entitlement gate as
   `registerVerbs`. Each cartridge's spec exposes its
   `EntityTypeSpec[]` built from its `*_cells.zig` data
   (`TesseraSpec.registerCells` → loops `tessera_cells.ALL`, derives the
   `EntityTypeSpec` per type). SPEC data lives in `tessera_cells.zig` +
   the out-of-src table — greenfield preserved.
3. **serve.zig: one added line** — construct the `SpecRegistry`
   alongside the verb Registry and thread it into `cartridge_boot`'s
   pass (same spot/gate as `registerInto`) and into the `entity.encode`
   walker State. No new shared-boot-path shape; it rides the P1/P2 seam.
4. **tessera walkers mint for real (the chess-Phase-2 analogue).** The
   in-memory `tessera_store` transitions add a real cell mint: dispatch
   to `entity.encode` (or call the encode path directly) with the
   tessera `tag` + `tessera_cells` linearity. This is per-verb,
   incremental, and behind the V0.5/V1 work — `tessera_store` stays as
   the typed FSM; minting is the persistence side.

### 8.4 Greenfield, octave, verification

- Greenfield: `grep -r tessera runtime/semantos-brain/src` stays 0 —
  `substrate_entity` only gains generic `register`/registry; all
  tessera SPEC data is in `tessera_cells.zig` + out-of-src table.
- Octave: untouched. Escalation is already automatic; tessera payloads
  >768 B ride the existing octave-1 path with no special handling.
- Verify: `substrate_entity` inline tests (switch arm unchanged +
  registry arm), a registry collision/idempotency test, a
  `cartridge_boot` test asserting tessera's 10 SPECs register and
  `specByTag` resolves them, `entity.encode` dispatch test minting a
  `tessera.bottle` end-to-end (incl. >768 B escalation), greenfield
  gate, `generate --check`. Same verification shape as P1/P2.

### 8.5 Phasing

- **P3a** — `substrate_entity` switch→registry (additive) +
  `register`/`SpecRegistry` + tests. Behaviour-identical for oddjobz;
  independently reviewable; no cartridge changes.
- **P3b** — `cartridge_boot` `registerCells` pass + serve.zig thread +
  tessera contributes its 10 SPECs (chess/oddjobz optional later).
- **P3c** — tessera walkers mint real cells via `entity.encode`
  (per-verb, rides V0.5/V1).

Net: P3 is **feasible now, no kernel work, same risk profile as the
merged P1/P2** — a registry generalization + a boot-pass row, reviewed
the same way. The "kernel spike" worry is retired.
