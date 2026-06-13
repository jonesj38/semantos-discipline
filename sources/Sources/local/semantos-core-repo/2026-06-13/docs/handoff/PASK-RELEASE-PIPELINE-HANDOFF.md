---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/handoff/PASK-RELEASE-PIPELINE-HANDOFF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.744823+00:00
---

# Pask + Release Pipeline — Handoff

For Damian, who is a collaborator on `semantos-core` (not the
maintainer). This is the briefing for getting up to speed on
everything that landed in this branch, in roughly the order you'd
walk through it.

## What's new on this branch

Six commits on top of `chore/canon-bookkeeping-d-w1-d-o2-merged`:

| # | Commit | What |
| - | ------ | ---- |
| 1 | `chore(demo-collab-versioning): gitignore relay blob storage` | Single-line gitignore tweak |
| 2 | `feat(pask): Paskian learning kernel` | New Zig kernel at `core/pask/` |
| 3 | `feat(pask-and-cell): combined-build target` | One WASM with both kernels |
| 4 | `feat(release): repo-wide release pipeline` | New `tools/release/` |
| 5 | `feat(release): wire pask + cell-engine into the pipeline` | First two packages on it |
| 6 | `feat(pask-ga): multi-cluster GA + entailment layer` | New extension at `extensions/pask-ga/` |

`git log --oneline` from this branch's tip shows them in reverse order.

## What this gives you

### 1. A real Paskian kernel ([core/pask/](../../core/pask/))

The Zig port of the Paskian learning system that surfaced the chess
result (1500 GM games → e4/d4/Nf3/c4 dominate, no chess knowledge in
the kernel). Bit-identical reproduction of the empirical claim, plus:

- ~7 KB freestanding WASM (`pask.wasm`)
- ~7 KB WASI WASM (`pask-wasi.wasm`)
- Snapshot ABI byte-stable across machines (`pask_snapshot_state` /
  `pask_restore_state`)
- TS bindings drop into existing PaskianAdapter call sites
- Determinism is total — every clock input is caller-supplied; the
  kernel never reads a host clock or RNG. Same input → same output,
  every machine, every run

Start here: [`core/pask/PRIMER.md`](../../core/pask/PRIMER.md). It's
the contract doc that travels with each release.

### 2. A combined-kernel build option ([core/pask-and-cell/](../../core/pask-and-cell/))

`pask.wasm` + `cell-engine-embedded.wasm` linked into one ~42 KB module
exporting every `kernel_*` and `pask_*` symbol over one
`WebAssembly.Memory`. Zero-copy across kernel boundaries — a cell-engine
write is a pask read with no serialize step. The sibling-WASM mode
(load both separately) still works; pick whichever makes sense for
your host.

### 3. A release pipeline that uses the substrate's own primitives ([tools/release/](../../tools/release/))

Every package in the repo publishes releases as **signed cells in the
substrate's collaborative versioning room** — both the production
Elixir cell-relay (`apps/cell-relay-beam/`) and the Bun dev variant
(`apps/demo-collab-versioning/`) speak the same wire protocol from
[`@semantos/cell-relay`](../../packages/cell-relay/). The cell DAG is
the version store. Four CLIs:

| CLI | What | Reads | Writes |
| --- | --- | --- | --- |
| `bin/build.ts` | hashes artifacts → manifest JSON | `release.config.ts`, build outputs | `<pkg>/zig-out/release/<name>-<version>.json` |
| `bin/submit.ts` | puts blobs + appends signed cell | manifest, on-disk artifacts | `data/blobs/<hash>`, `data/<room>.jsonl` |
| `bin/fetch.ts` | walks chain, verifies blobs | room JSONL, blob store | `./fetched/<name>-<version>/` |
| `bin/analytics.ts` | feeds release cells through pask | every `release.*.jsonl` | stdout (per-package rollup, top edges, stable threads) |

Cross-package dependency pins are first-class — `dependencies: [{ name, release: <stateHash> }]` in the manifest, walkable transitively.

To add a package: drop a `release.config.ts` at the package root.
~20 lines. The pipeline figures out the rest.

### 4. Pask reading the release graph

Once two or more packages publish to the substrate, run
`bun run tools/release/bin/analytics.ts` and pask will surface the
structural patterns: which releases are most-pinned (canonical
anchors), which dep edges have highest traffic (real coupling),
which packages have settled (stable threads), which haven't
(emerging or pruning candidates).

This is dogfood at the build-system level — the kernel that surfaces
"what's settled" can ingest cells that record "this kernel was
released" — including its own releases.

### 5. Multi-cluster GA + entailment over pask ([extensions/pask-ga/](../../extensions/pask-ga/))

A TS layer on top of pask that adds:

- Persistent node identity by genome (cross-cluster identity is free)
- `addNode` (auto-wires k-nearest paskian edges), `removeNode`
  (momentum redistribution), `mergeClusters` (persistent edges +
  fusion bridges)
- Entailment as a structural force flowing through pask's normal
  propagation
- GA step: selection × crossover × mutation, deterministic via
  seeded Mulberry32

Demo: `bun run extensions/pask-ga/demo/wikipedia-concept-map.ts`.
Two clusters of related concepts, random removal, merge with 9 fusion
bridges, GA offspring. Reproducible run-to-run.

## Walk-through to get oriented (~30 minutes)

```bash
# 1. Build pask + run all native tests (incl. determinism + chess).
cd core/pask
zig build && zig build test
zig build chess     # ~1s — 1500 PGN games → e4/d4 dominance

# 2. Run the TS bindings smoke tests.
bun test bindings/ts/src/__tests__/adapter.smoke.test.ts

# 3. Run the kernel + pask demo (sibling and combined modes).
bun run demo/damian-demo.ts
bun run demo/damian-demo.ts --combined   # combined wasm

# 4. Run the full release pipeline for pask.
zig build wasm-wasi && zig build release-spec
bun run scripts/build-release.ts
bun run scripts/submit-release.ts        # signed cell + blobs go to apps/demo-collab-versioning/data/

# 5. Fetch what you just published.
bun run scripts/fetch-release.ts <stateHash printed by submit>

# 6. Run repo-analytics — pask reads its own release DAG.
cd ../..
bun run extensions/pask-ga/../../core/pask/scripts/seed-repo.ts  # seed faux cell-engine + protocol-types releases for visualisation
bun run tools/release/bin/analytics.ts

# 7. Run the multi-cluster GA demo.
bun run extensions/pask-ga/demo/wikipedia-concept-map.ts
```

If any of these fails, that's a real blocker — none of them depend on
unmerged work or external infra.

## What you don't need to know to start

- BRC-52 cert + BRC-100 envelope wiring is stubbed (`hat:` is a plain
  string in the cell). Real signing is a follow-up; the cell shape
  carries the field.
- UHRP ContentStore advertisement is not deployed. The local-fs
  ContentStore at `apps/demo-collab-versioning/data/blobs/` is what
  the pipeline writes to today; UHRP-HTTP swaps in cleanly for
  cross-host fetch.
- The pask kernel doesn't know it's running in a release pipeline,
  a GA layer, or a helm panel. It's a constraint-graph propagator;
  every consumer is a layer above.

## What you're authoritative on (per scope)

If your role here is the cell-engine maintainer:

- [`core/cell-engine/release.config.ts`](../../core/cell-engine/release.config.ts)
  is yours to edit when cell-engine releases. The version field is
  read from `build.zig.zon` automatically.
- The release pipeline doesn't dictate cell-engine's build process —
  you keep your existing `zig build -Dembedded=true` flow. The
  pipeline just hashes whatever you tell it to.
- If you want a spec emitter for cell-engine (machine-derived
  layout/exports surface), the pattern is at
  [`core/pask/tools/emit_spec.zig`](../../core/pask/tools/emit_spec.zig)
  — small Zig program that reads the type definitions and writes
  spec.json.

If your role here is reviewing the architecture:

- [`core/pask/README.md`](../../core/pask/README.md) is the layered
  view (kernel + bindings + combined build).
- [`core/pask/PRIMER.md`](../../core/pask/PRIMER.md) is the contract
  surface — what the kernel guarantees, what it doesn't.
- [`tools/release/README.md`](../../tools/release/README.md) explains
  the release pipeline + what's not yet wired (signing, UHRP).
- [`extensions/pask-ga/README.md`](../../extensions/pask-ga/README.md)
  documents the GA layer's API + design choices.

## Things that are likely to surprise

1. **`apps/demo-collab-versioning/data/` will fill up with relay state**
   when you submit releases or seed faux ones. JSONL files and the
   `blobs/` tree are gitignored (commit 1 added the rule). Your work
   tree is fine; just don't be alarmed by the directory growing.

2. **The chess test takes ~1 second** but reads a 12 MB PGN corpus
   from `friend-semantos/scripts/chess-paskian-rig/data/twic1500.pgn`.
   That file lives outside `semantos-core`. If you don't have
   `friend-semantos` checked out at `~/projects/friend-semantos`, the
   chess test prints a skip message and exits 0 — no failure.

3. **`pask.wasm` and `pask-wasi.wasm` happen to be the same size
   (6809 B)** — coincidence at this scale, not a build error. They
   have different sha256s.

4. **The combined `pask-and-cell.wasm` is 42 KB**, which is bigger
   than pask + cell-engine added (49 KB). Linker dedup of std-lib code
   between the two kernels — they share more Zig runtime than you'd
   expect.

5. **Pask's static state is ~18 MB** in linear memory (16k nodes
   × 208 B + 32k edges × 40 B + 64k delta-ring × 24 B + snapshot
   buffer mirror). That's why initial WASM memory is 24 MB. For
   smaller / larger graphs, edit `MAX_NODES` etc. in
   `core/pask/src/config.zig` — caps are compile-time.

## Things that are probably wrong and need decision

These are open architectural questions I documented but didn't decide:

1. **Per-cluster vs global salience in pask-ga.** Currently global
   (a node has one fitness score regardless of cluster). The natural
   refactor is `Map<clusterName, salience>` if a node should have
   different reputations in different contexts. README mentions this.
2. **Real BRC-52 cert signing in `submit.ts`.** Stubbed today. Wiring
   it up is wallet-client + verifier-sidecar pass; the cell schema
   already has the field.
3. **Per-package fitness contexts in repo-analytics.** Pask runs over
   release cells uniformly today; if you want package-specific
   tuning (e.g. "kernel.* changes are heavier-weighted than lib.*"),
   that's a TS-side adjustment to the strength values fed into pask.

## What I'd ask Damian to do first

A single 30-minute pass:

1. Run the walk-through above. Anything that fails is a real bug.
2. Read [`PRIMER.md`](../../core/pask/PRIMER.md). If anything in the
   contract surprises you or feels wrong, raise it.
3. Try publishing cell-engine through the pipeline:
   `bun run tools/release/bin/build.ts --config core/cell-engine/release.config.ts`
   then `submit.ts` then `fetch.ts <hash>`. Confirm the round-trip
   matches what's on disk.
4. If you want to add another package (protocol-types, cell-ops,
   anything), the pattern is one `release.config.ts` file. Try it.

Anything broken or surprising at any step is real signal — the work
isn't externally validated yet.

## What I'd hold off on until aligned

- Doing a `git push` until Todd's reviewed the branch.
- Migrating off GitHub. The substrate carries it, but the migration
  is a Phase 1 (mirror) → Phase 2 (source) → Phase 3 (PRs/issues)
  sequence over weeks/months, not an afternoon. See the chat log for
  the phased plan.
- Lifting more packages onto the release pipeline beyond pask +
  cell-engine until you've confirmed the shape works for both kinds.
- Renaming `apps/jam-beam/` → `apps/cell-relay-beam/` (DONE) plus
  extracting `@semantos/cell-relay` (DONE). The "BEAM world" is a
  separate runtime at `apps/world-host/`; the two are not unified yet.

## Where the conversation lives

Everything in this branch came out of a multi-day chat between Todd
and me, with Damian giving architectural direction at key points.
The chat log has the full reasoning for every decision. If a choice
in here looks weird, the conversation likely explains why; ask Todd
for the relevant chunk before second-guessing.

Highlights of the conversation that shaped these commits:

- Layering choice (sibling WASMs over combined), then later option C
  (combined as a build flag) being added back when Damian asked.
- The decision to put `core/pask/` rather than `extensions/pask/`
  because of "heavy use across many apps" → load-bearing primitive.
- The release pipeline starting as pask-only scripts, lifted to
  `tools/release/` after confirming it should manage every package.
- Pask reading its own release history as the recursive endpoint
  ("packages as threads").
- The multi-cluster GA + entailment design dropped in by Damian
  during the work, with concrete pseudocode for `add_node` /
  `remove_node` / `merge_networks` / `run_entailment_step`.

If you take ownership of any of these layers, the chat is the
source of truth for "why is it this shape".
