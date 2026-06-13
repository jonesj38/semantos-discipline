---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/policies-demo/mnca/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.298015+00:00
---

# MNCA tile-rule Rúnar policies

Worked examples that demonstrate the **MNCA + Rúnar + PolicyRuntime + anchor** convergence Todd asked about 2026-05-26. Each policy is an MNCA-shaped invariant authored in Rúnar's Go DSL, compiled offline to Bitcoin Script bytes, and committed alongside its hex golden so the brain can execute it without a Rúnar toolchain dep.

## What this directory closes

> "What can we do with Rúnar now and our MNCA?"

The full loop in something a third party can verify:

```
[author writes]      tile_tick_advance.runar.go      (high-level invariant)
        ↓
[Rúnar Go tier]      runar-go -source X -hex
        ↓
[author commits]     tile_tick_advance.expected.hex  (Bitcoin Script bytes)
        ↓
[brain @embedFile]   policy_runtime.zig inline test
        ↓
[PolicyRuntime]      .real_executor mode (PR-2b)
        ↓
[2-PDA executor]     Real Bitcoin Script semantics on the bytes
        ↓
[result]             accept iff invariant holds for the input
        ↓
[and downstream]     accepted cell → AnchorEmitter → BSV mainnet anchor
                     committing cell_hash + type_hash on chain (PR-3a-bridge-*)
```

A reviewer reading PR diffs sees BOTH the human-readable Rúnar source AND the byte-perfect script the brain executes. Cross-impl conformance + Lean verification of the Rúnar pipeline guarantees the bytes are correct.

## Policies

### `tile_tick_advance` — strict-monotone tile-step invariant

| Field | Value |
|---|---|
| Invariant | `newTick == prevTick + 1` |
| Source | [`tile_tick_advance.runar.go`](tile_tick_advance.runar.go) |
| Compiled hex | `7c8b9c` (3 bytes) |
| Opcodes | `OP_SWAP OP_1ADD OP_NUMEQUAL` |

Trace with stack `[prevTick, newTick]` (newTick on top from the unlock push):

```
OP_SWAP     → [newTick, prevTick]
OP_1ADD     → [newTick, prevTick + 1]
OP_NUMEQUAL → [(newTick == prevTick + 1) ? 1 : 0]
```

Why this invariant is load-bearing for MNCA: every tile-step advances the tick by exactly one. Skipping ticks creates unmatched commitments downstream; going backwards orphans downstream snapshots. PolicyRuntime enforcement keeps the tile snapshot chain unambiguous at the brain's write boundary.

## Recompiling

Per Todd 2026-05-26 directive ("let's go c, no need for go"): the brain build does NOT depend on Rúnar / Go. Authors recompile on their own dev machine and commit the new hex.

```bash
git clone --depth 1 https://github.com/icellan/runar.git ~/runar
cd ~/runar/compilers/go && go build -o ~/.local/bin/runar-go .

runar-go -source tile_tick_advance.runar.go -hex
# → 7c8b9c
```

Diff review catches drift. A PR that modifies the source without an updated hex should be rejected.

## Test coverage

`runtime/semantos-brain/src/policy_runtime.zig` inline tests (search "MNCA tile-tick"):

- `accepts 5 → 6` (canonical happy path: tick advances by exactly one)
- `accepts 0 → 1` (boundary: zero is a valid prevTick)
- `rejects 5 → 5` (no-op rejected — tick must advance)
- `rejects 5 → 7` (skip rejected — must be exactly +1)
- `rejects 5 → 4` (backward rejected)
- `embedded hex round-trip` (sanity that the golden matches what the test runs)

Run via `cd runtime/semantos-brain && zig build test -j1`.

## Strategic note

This is the smallest possible demo proving the full integration. Real cartridges author bigger invariants (energy conservation, halo-radius bounds, type-coherence, multi-field range checks) the same way. Each one stays in source-controlled, diff-reviewable bytes that PolicyRuntime executes deterministically and the anchor pipeline commits to BSV mainnet.

See also: [`../range_check.runar.go`](../range_check.runar.go) — the generic worked example the [`docs/cartridge-author-guide-runar.md`](../../../../../docs/cartridge-author-guide-runar.md) cites.
