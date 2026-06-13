---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/strategies/peak_discharge.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.576638+00:00
---

# cartridges/aemo-dispatch/strategies/peak_discharge.runar.go

```go
// AEMO battery-dispatch predicate — peak-discharge rule.
//
// Two unlock-provided integers (priceCents, socPct):
//   - priceCents: current 5-min dispatch price in cents per MWh
//                 (e.g., 30000 = $300.00/MWh)
//   - socPct:     battery state-of-charge as integer percent (0..100)
//
// Predicate accepts (truthy top-of-stack) iff BOTH:
//   priceCents >= 30000   (i.e., spot price >= $300/MWh)
//   socPct     >= 50      (i.e., battery at least half full)
//
// Discharge decision: bid the battery into the dispatch interval when
// the predicate accepts.  Otherwise hold / charge.
//
// Why this shape: every cell in an Australian NEM bidirectional battery
// fleet is a tile.  At each 5-min interval, each tile evaluates this
// predicate with its own (priceCents, socPct) inputs.  Accepted →
// discharge.  The decision IS the predicate; the strategy IS the source.
//
// Compiled via: runar-go -source PeakDischarge.runar.go -hex
// Upstream: github.com/icellan/runar @ d4c3b6e (2026-05-25)
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type PeakDischarge struct {
    runar.SmartContract
}

func (c *PeakDischarge) ShouldDispatch(priceCents runar.Int, socPct runar.Int) {
    runar.Assert(priceCents >= 30000)
    runar.Assert(socPct >= 50)
}

```
