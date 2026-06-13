---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/policies-demo/mnca/tile_tick_advance.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.298302+00:00
---

# runtime/semantos-brain/src/policies-demo/mnca/tile_tick_advance.runar.go

```go
// MNCA tile-tick monotonicity invariant — Rúnar Go-DSL.
//
// Enforces the load-bearing MNCA progression rule:
//
//     newTick == prevTick + 1
//
// This is the strict-monotone constraint that keeps a tile snapshot
// chain unambiguous — every tile-step advances the tick by exactly one;
// you cannot skip a tick (would create an unmatched commitment), and
// you cannot go backwards (would orphan downstream snapshots).
//
// Compiled via: runar-go -source TileTickAdvance.runar.go -hex
// Upstream: github.com/icellan/runar @ d4c3b6e (2026-05-25)
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type TileTickAdvance struct {
    runar.SmartContract
}

// Two unlock-provided ints: prevTick (current snapshot's tick) and
// newTick (proposed next snapshot's tick).  Predicate accepts iff
// newTick is exactly prevTick + 1.
func (c *TileTickAdvance) Verify(prevTick runar.Int, newTick runar.Int) {
    runar.Assert(newTick == prevTick + 1)
}

```
