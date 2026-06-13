---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.547240+00:00
---

# `tools/release` — repo-wide release pipeline

Every package in semantos-core publishes its releases as **signed cells
in the substrate's own collaborative versioning room**. No npm, no
Cargo, no Go modules. The cell DAG is the version store. This directory
is the toolchain that drives that.

## What this is

```
tools/release/
├── lib/           ← shared primitives (manifest, content store, cells, JSONL)
└── bin/           ← four CLIs that compose them
    ├── build.ts        wraps `assembleManifest`: hashes artifacts → JSON
    ├── submit.ts       puts blobs into ContentStore, appends signed cell
    ├── fetch.ts        walks chain from a stateHash, verifies + writes
    └── analytics.ts    feeds every release.*.jsonl through pask
```

Every package in the repo declares **one file** to opt in:

```ts
// core/<package>/release.config.ts
import type { ReleaseConfig } from '../../tools/release/lib';

export default {
  name: 'cell-engine',
  room: 'release.kernel.cell-engine',
  hat: 'cell-engine-maintainer@semantos',
  version: '0.15.2',
  artifacts: [
    { name: 'cell-engine-embedded.wasm', target: 'wasm32-freestanding',
      path: 'zig-out/bin/cell-engine-embedded.wasm' },
    { name: 'cell-engine-wasi-embedded.wasm', target: 'wasm32-wasi',
      path: 'zig-out/bin/cell-engine-wasi-embedded.wasm' },
  ],
  spec:    { schema: '1', path: 'zig-out/release/spec.json' },
  primer:  { path: 'PRIMER.md' },
  dependencies: [],
} satisfies ReleaseConfig;
```

That's it. `name` is the package; `room` is its cell-DAG room
(convention: `release.<kind>.<name>`); `artifacts` lists the build
outputs; `spec` and `primer` are optional. Run the pipeline:

```bash
bun run tools/release/bin/build.ts  --config core/<pkg>/release.config.ts
bun run tools/release/bin/submit.ts --config core/<pkg>/release.config.ts
bun run tools/release/bin/fetch.ts  <stateHash>
bun run tools/release/bin/analytics.ts
```

## The four CLIs

### `build.ts` — produce the manifest

Reads `release.config.ts`, hashes every artifact + spec + primer,
writes `<package>/zig-out/release/<name>-<version>.json`. The manifest
follows the `release.kernel.v1` schema; every claim is a content hash.

### `submit.ts` — commit the release

Puts every artifact into the local-fs ContentStore (default
`apps/demo-collab-versioning/data/blobs/`) at its sha256-addressed
path. Cross-checks against the manifest's claimed hashes — drift
aborts. Walks the room's JSONL to find the prior release, builds a
SerializedCell with `parentHashes` linking to it, computes the
stateHash, appends to the JSONL.

The relay (`apps/cell-relay-beam/` Elixir or `apps/demo-collab-versioning/`
Bun — both implementations of the same cell-relay protocol from
[`@semantos/cell-relay`](../../packages/cell-relay/)) treats the JSONL
as authoritative — no relay process needs to be running.

### `fetch.ts` — consumer side

Given a release `stateHash`, scans every `release.*.jsonl` to find
the cell, walks parents to the root validating links, then for the
pinned cell:

- Looks each blob up in the ContentStore by sha256.
- Recomputes the hash. **Mismatch hard-fails — no bytes returned.**
- Writes verified bytes to `--out <dir>` (default `./fetched/<name>-<version>/`).

No path, no URL, no name is trusted. Only content hashes.

### `analytics.ts` — pask reading the repo's release DAG

Loads every release cell across every room, sorts chronologically by
`builtAt`, feeds them into a fresh pask kernel as interactions:

- `cellId` = release stateHash
- `kind` = the room name (e.g. `release.kernel.pask`)
- `relatedCells` = parent + cross-package deps

Then prints:

- **Per-package rollup**: total / stable / pruned releases per room.
- **Top dependency edges**: most-trafficked cross-package pins.
- **Stable threads**: releases the dep graph has settled around.
- **Top inbound traffic**: which release stateHashes are most pinned
  (the canonical anchors).

The cell-engine version most-pinned by the rest of the repo surfaces
to the top automatically. As release activity grows, the pask graph's
emerging-thread / pruning-candidate signals become more informative.

## Directory layout summary

```
core/pask/release.config.ts                ← pask's declaration
core/cell-engine/release.config.ts         ← cell-engine's declaration
core/<future-package>/release.config.ts    ← drop-in for new packages

apps/demo-collab-versioning/data/
├── release.kernel.pask.jsonl              ← pask's release chain
├── release.kernel.cell-engine.jsonl       ← cell-engine's release chain
├── release.lib.protocol-types.jsonl       ← (when added)
└── blobs/                                  ← content-addressed bytes
    ├── e2/e2fe62...                        ← pask.wasm
    ├── a9/a9988c...                        ← cell-engine-embedded.wasm
    └── ...
```

The `blobs/` directory is shared across packages — it's content-addressed,
so identical bytes from different packages collapse to one file.

## What's NOT in here yet

- **BRC-52 cert + BRC-100 envelope signing**. The `hat` field is
  currently a plain string. Real signing requires the wallet-client +
  verifier-sidecar wiring; the cell shape already carries the field,
  so signing drops in without changing the chain or the schema.
- **UHRP advertisement**. `submit.ts` puts blobs to the local-fs
  ContentStore. To make releases globally fetchable, run the same
  blobs directory through `@semantos/content-store-uhrp-http` so
  remote consumers can resolve hashes over the network. The
  ContentStore interface is the same.
- **Workspace package promotion**. The lib is currently directly
  imported by relative path. If/when helm or another runtime needs
  to consume releases live (not just at build time), promote
  `tools/release/lib` to `packages/release` so it's importable as
  `@semantos/release`.

## Why this shape

The cell DAG already has every property a package manager needs:
hash chains, signed authorship, branchable history, tamper detection,
collaborative real-time. Wiring releases through it instead of a
separate registry means:

1. Releases of every kernel/lib/app share one mechanism — adding a
   package is a 20-line config file, not a new pipeline.
2. Cross-package dep edges are first-class — `dependencies: [{ name, release: stateHash }]`
   pins by content hash, walkable transitively.
3. The substrate dogfoods its own primitives at the build-system
   level. semantos-core releases its own parts using the same hash-
   chained signed cell DAG it asks every other vertical to use.
4. **Pask reads the resulting graph** and surfaces structural signals
   (stable / emerging / pruning, edge weights, co-release patterns)
   without anyone implementing analytics-specific code. Self-referential,
   deterministic, fully replayable.
