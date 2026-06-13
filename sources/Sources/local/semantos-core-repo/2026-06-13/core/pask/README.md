---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.797365+00:00
---

# `core/pask` — Paskian learning kernel

The constraint-graph learning layer that produced the chess result, ported
to Zig and compiled to two WASM targets so any host (Bun, Node, browser,
sovereign-node, ESP32) can drive it the same way.

This sits at the **kernel** layer of the semantos-core stack:

```
core/cell-engine     ← bitcoin-script-with-linearity VM (36 KB WASM)
core/pask            ← Paskian learning over a constraint graph (~7 KB WASM)
core/pask-and-cell   ← optional combined build, both kernels in one WASM (42 KB)
core/cell-ops, ...   ← TS libs over the kernels
extensions/          ← pask-using extensions live here
runtime/, apps/      ← consumers
```

Pask is a **lib**, not part of the cell-engine kernel. The two WASMs are
sibling modules. Hosts that want both instantiate both.

## What it does

Single-paragraph version: feed it interactions between named cells. It
maintains a graph where edges accumulate weight on co-occurrence, propagates
local constraint effects 1–3 hops per interaction, and surfaces the cells
whose ΔH has settled near zero as **stable threads** — the structures the
data has converged on.

Empirical claim: with no domain knowledge baked in, fed PGN games as
move-prefix transitions, it converges on the canonical chess opening
moves (e4, d4, Nf3, c4) ranked by traffic. The Zig port reproduces this:

```
chess: games=1500 nodes=4900 edges=4899 stable=1022
top first-ply moves by traffic:
  n=   705  p:e4
  n=   509  p:d4
  n=   148  p:Nf3
  n=   119  p:c4
```

That test (`zig build chess`) is the load-bearing conformance harness. If
you change the propagation math and it stops finding e4/d4 in the top
moves at 1500 GM games, the change is wrong.

## Build

```bash
cd core/pask
zig build              # produces zig-out/bin/pask.wasm (freestanding)
zig build wasm-wasi    # produces zig-out/bin/pask-wasi.wasm (server)
zig build test         # native unit conformance suite (~30 ms)
zig build chess        # 1500-game empirical conformance (~few s)
```

Both WASMs are import-free — `WebAssembly.instantiate(module, {})` is
enough. Memory grows on demand up to 64 MB; static state at default
caps (16k nodes, 32k edges, 64k delta-ring) takes ~18 MB.

## Exports

The wasm exports a flat C ABI (see [src/main.zig](src/main.zig)). All
clock arguments are caller-supplied — the kernel never calls a host
clock, so replays are bit-identical.

| Group | Exports |
| --- | --- |
| Lifecycle | `pask_init`, `pask_set_config`, `pask_reset`, `pask_last_error` |
| Mutate | `pask_upsert_node`, `pask_find_node`, `pask_interact_run`, `pask_finalize` |
| Read | `pask_node_count`, `pask_edge_count`, `pask_node_ptr`, `pask_edge_ptr`, `pask_node_h_state`, `pask_node_is_stable`, `pask_node_is_pruned`, `pask_stable_count`, `pask_stable_threads_into` |
| Snapshot | `pask_snapshot_state`, `pask_restore_state`, `pask_snapshot_buf_ptr`, `pask_snapshot_buf_len` |
| Scratch | `pask_scratch_ptr`, `pask_scratch_len` |

## Driving it from TypeScript

The bindings at [bindings/ts](bindings/ts) wrap the wasm in a class with the
same shape as the existing TS PaskianAdapter — drop-in for code that used
`@semantos/paskian`.

```ts
import { readFileSync } from 'node:fs';
import { loadPask, PaskAdapter } from '@semantos/pask';

const pask = await loadPask(readFileSync('core/pask/zig-out/bin/pask.wasm'));
const a = new PaskAdapter(pask);

await a.interact({ cellId: 'pos:e4', kind: 'chess', strength: 1.0,
                   relatedCells: ['pos:e4 c5'], nowMs: 1 });

a.finalize();
console.log(a.stableThreads().slice(0, 5));
```

## Both kernels together — two modes

You can wire the kernel + pask in either of two shapes. Same TS API
either way; the difference is whether they share linear memory.

### Sibling mode — two WASMs, two memories

Default. `cell-engine-embedded.wasm` and `pask.wasm` instantiated
independently. JS owns the trampoline between them — anything one
kernel needs from the other has to be copied through a JS buffer.

```ts
import { readFileSync } from 'node:fs';
import { loadPask, PaskAdapter } from '@semantos/pask';

// The cell-engine wasm — same path as the esp32-hackkit copy.
const cellWasm = readFileSync('core/cell-engine/zig-out/bin/cell-engine-embedded.wasm');
const cellModule = await WebAssembly.compile(cellWasm);
const cell = await WebAssembly.instantiate(cellModule, {
  // Provide host imports — see esp32-hackkit/docs/HOST_IMPORTS.md.
  // For server use, mbedtls-style implementations live in
  // apps/wallet-browser; for a tiny demo the noop host works.
  host: { /* host_sha256, host_hash160, ... */ },
});
const c = cell.exports as any;
c.kernel_init();

// And pask alongside.
const pask = await loadPask(readFileSync('core/pask/zig-out/bin/pask.wasm'));
const p = new PaskAdapter(pask);
```

### Combined mode — one WASM, one memory (zero-copy)

Built in `core/pask-and-cell/`. One executable (~42 KB embedded profile)
exporting every `kernel_*` AND `pask_*` symbol. Single
`WebAssembly.Memory` shared between both kernels — anything one writes
into linear memory the other reads directly without a copy.

```bash
cd core/pask-and-cell
zig build                    # default: embedded cell-engine profile
zig build -Dembedded=false   # full profile (requires bsvz, larger wasm)
# → zig-out/bin/pask-and-cell.wasm
```

Use it from JS with no special API — both export sets are on the same
`instance.exports`:

```ts
const bytes = readFileSync('core/pask-and-cell/zig-out/bin/pask-and-cell.wasm');
const module = await WebAssembly.compile(bytes);
const instance = await WebAssembly.instantiate(module, { host: hostImports() });
const x = instance.exports;
x.kernel_init();
x.pask_init();
// PaskAdapter accepts any { exports, module, instance } shape.
const adapter = new PaskAdapter({ exports: x, module, instance });
```

### Demo

[demo/damian-demo.ts](demo/damian-demo.ts) drives 200 PGN games through
pask alongside a one-byte cell-engine script:

```bash
bun run core/pask/demo/damian-demo.ts             # sibling mode (default)
bun run core/pask/demo/damian-demo.ts --combined  # one-WASM mode
```

Both produce identical output — the kernel is fully deterministic given
the same input stream (see "Determinism" below).

## Zero-copy interface

The kernel arrays (nodes, edges, stable threads) are kept contiguous in
linear memory. The TS bindings expose direct `Uint8Array` views:

```ts
const nodes = adapter.nodesView();
// nodes.bytes is a Uint8Array view over the kernel's nodes array.
// Each record is `nodes.stride` bytes wide; there are `nodes.count` of them.
// Reading node i's h_state:
new DataView(nodes.bytes.buffer, nodes.bytes.byteOffset + i * nodes.stride + 168, 8)
  .getFloat64(0, true);
```

For range queries on stable threads (Damian's `[n..nx]` ask):

```ts
// Materialise top 1024 stable threads into the kernel buffer once, then
// read records [10, 20) directly. One trampoline call regardless of slice.
const slice = adapter.stableThreadsRange(10, 20, 1024);
// slice.nodeIdx, slice.hState, slice.totalConstraintStrength, slice.interactionCount
// are parallel typed arrays.
```

The struct layouts are pinned at compile time — `core/pask/src/main.zig`
has a `comptime` block asserting every field offset and size, so the
TS readers can't silently drift from the Zig structs.

## Determinism

Every kernel function takes a `now_ms` parameter. **The kernel never
reads a host clock or any source of entropy.** Replays from the same
input stream are bit-identical:

```bash
zig build test  # includes determinism_conformance:
                # two independent runs over the same input produce
                # byte-identical Store images.
```

This is the offchain-execution guarantee: feed the kernel the same
sequence of `interact` calls (with the same `now_ms` values) on a
different machine and you'll arrive at the same `pask_snapshot_state`
blob. Useful for any consensus-style verification, audit replay, or
cross-node migration scenario.

There is no Rust port and no plans for one — Zig already gives us the
zero-copy + same-toolchain story Rust would, without adding a third
compiler to the build.

## Releases live in the cell DAG

Every release of pask is a signed cell on the substrate's collaborative
versioning room — same primitive `apps/cell-relay-beam` and
`apps/demo-collab-versioning` use (the cell-relay protocol, defined in
[`@semantos/cell-relay`](../../packages/cell-relay/)). No npm, no
crates, no Go modules. The substrate's own hash-chained, signed,
branchable, BRC-52-cert-backed cell DAG is the version store.

### Layers

```
Cell DAG       release manifest, signed + hash-chained
  ↳ JSONL persistence: apps/demo-collab-versioning/data/release.kernel.pask.jsonl
  ↳ relay broadcasts: ws://...?room=release.kernel.pask  (cell-relay protocol — see @semantos/cell-relay)

ContentStore   wasm bytes + spec bytes, content-addressed by sha256
  ↳ local-fs: {root}/<hex(hash)[0:2]>/<hex(hash)>
  ↳ UHRP HTTP, USB-CDN backends share the same layout

VFS            human-readable paths (/release/kernel/pask/0.1.0)
  ↳ resolves to a cell stateHash; bytes flow through the ContentStore
```

The release manifest **never** embeds a filesystem path — it embeds
content hashes. Paths are operator config (where the local-fs root is)
and build cache (`zig-out/bin/pask.wasm`). Everything cross-machine is
content-addressed.

### The release pipeline

```bash
# Build artifacts
cd core/pask
zig build              # zig-out/bin/pask.wasm
zig build wasm-wasi    # zig-out/bin/pask-wasi.wasm

# Generate machine-derived spec (struct offsets via @offsetOf, default
# config, capacity caps, snapshot ABI, exports table).
zig build release-spec # zig-out/release/pask-spec.json

# Wrap the spec + wasm hashes into a release manifest.
bun run scripts/build-release.ts
                       # zig-out/release/pask-0.1.0.json

# Put the bytes into the local content store and commit a signed
# release-cell to the substrate's versioning room.
bun run scripts/submit-release.ts
                       # → apps/demo-collab-versioning/data/blobs/...
                       # → apps/demo-collab-versioning/data/release.kernel.pask.jsonl
```

### What's in a release cell

The cell follows the SerializedCell shape used by the
demo-collab-versioning relay:

```json
{
  "id": "142f88a7...",
  "stateHashHex": "142f88a7c6cb7adf9a5dc875ba525bb2aa0f77b6cee0e9631d09d115e629bc4b",
  "parentHashes": [],
  "patch": {
    "op": "release.kernel.publish",
    "payload": {
      "name": "pask",
      "version": "0.1.0",
      "artifacts": {
        "pask.wasm":      { "sha256": "e2fe62...", "sizeBytes": 6809, "target": "wasm32-freestanding" },
        "pask-wasi.wasm": { "sha256": "caf36f...", "sizeBytes": 6809, "target": "wasm32-wasi" }
      },
      "spec":         { "sha256": "256e89...", "sizeBytes": 7780, "schema": "1" },
      "build":        { "zigVersion": "0.15.2", "sourceCommit": "8e975cc...", "builtAt": "2026-05-01T..." },
      "dependencies": [],
      "parentReleaseHash": ""
    }
  },
  "hat": "pask-maintainer@semantos",
  "depth": 0,
  "branch": "main",
  "cherryPickedFromHash": null,
  "tampered": false
}
```

Subsequent releases (0.1.1, 0.2.0, …) commit cells with `depth+=1` and
`parentHashes: ["<prior release stateHash>"]`. The chain is verifiable
on the consumer side: walk parents, check signatures, hash-check each
artifact you fetch from the ContentStore.

### Reproducibility, demonstrated

A clean rebuild from the same source commit produces bit-identical wasm:

```
clean checkout → zig build → sha256(pask.wasm) = e2fe62aedb986368...
clean checkout (different shell, deleted zig-out) → same sha256
```

A consumer pinned to a release stateHash can verify what they got
matches what was published, without trusting any name, path, or URL.

### What's NOT signed yet

The current `submit-release.ts` writes the cell with `hat:
"pask-maintainer@semantos"` as a plain string. Real BRC-52 cert
binding + BRC-100 envelope signing requires the wallet-client +
verifier-sidecar wiring; that's a follow-up. The cell shape already
carries the field; the signature layer drops in without changing the
chain.

### What about external library deps

`build.zig.zon` already pins external Zig deps by URL + sha
(e.g. `bsvz` at `b57fc31a...`). The release manifest's `dependencies`
array lifts that into the signed cell — empty for the embedded pask
build (no deps), populated for any future release that pulls in bsvz
or other Zig modules. Transitive resolution is "follow the chain":
each dep is itself a release cell on its own room.

### What about a consumer fetcher

Step 3 (not built yet): `pask-fetch <stateHash>` walks the cell chain
from a pinned hash, validates parent links, looks up wasm sha256s in
the configured ContentStore, fetches missing blobs over UHRP, and
hands you the bytes ready to instantiate. Short script, no kernel
changes. Lands in `core/pask/scripts/fetch-release.ts`.

## Layout fidelity

The TS bindings hand-roll struct offsets into linear memory — there's no
generated layout. To prevent silent corruption when struct fields move,
[src/main.zig](src/main.zig) has a comptime block that asserts every
field offset and size. A struct-layout change fails the build before
shipping a wasm whose binary layout disagrees with the TS reader.

## Persistence

The cell-engine and pask both expose the same snapshot ABI:

```
[u32 magic]   "CESN" (cell-engine) or "PASK" (pask)
[u32 version] 1
[u32 length]  sizeof(static state)
[length bytes ... ]
```

A host can hand a blob to either kernel and round-trip the world
state. Same migration story for both.

## Tuning

Default config matches `friend-semantos/packages/paskian` exactly:
prune_threshold=-0.3, stability_epsilon=0.01, propagation_depth=3,
learning_rate=0.1, stability_window_ms=60_000, min_interactions=5.

Override via `pask_set_config` (see `Config` in [src/config.zig](src/config.zig))
or `new PaskAdapter(pask, { ...overrides })`.

Trade-offs:
- **propagation_depth**: more = richer constraint reach, more work per
  interact. Default 3.
- **stability_window_ms**: shorter = stability decisions track recent
  activity only. The chess result depends on this windowing.
- **min_interactions**: rarely-touched nodes never qualify as stable.
  The chess rig overrides 5 → 10.

## What's NOT in here yet

- Anchor policy / BSV write-back (the TS adapter writes compliance events
  to a StorageAdapter on stabilise / prune; the kernel does not — that's
  a JS-side concern).
- ECS bridge (`apps/settlement/src/ecs/paskian-system.ts`). Migrate it to
  call the bindings.
- Conversation-context tagging (`Phase 2` fields in the TS edge type).
  Add when a caller needs them; the wire format already has the room.
