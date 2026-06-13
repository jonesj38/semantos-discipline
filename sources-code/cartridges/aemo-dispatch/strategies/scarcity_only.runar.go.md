---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/strategies/scarcity_only.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.576361+00:00
---

# cartridges/aemo-dispatch/strategies/scarcity_only.runar.go

```go
// Scarcity-only dispatch — fire only when wholesale price is in
// scarcity range ($1000/MWh+).  Strategy thesis: high margin per
// MWh dispatched offsets low volume; battery wear is minimal
// because we cycle 5-15× per year instead of 200×.  Suitable for
// operators with cycle-count warranty caps or high battery
// amortization cost.
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type ScarcityOnly struct {
    runar.SmartContract
}

func (c *ScarcityOnly) ShouldDispatch(priceCents runar.Int, socPct runar.Int) {
    runar.Assert(priceCents >= 100000)  // spot >= $1000/MWh
    runar.Assert(socPct >= 20)           // any meaningful charge
}

```
