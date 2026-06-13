---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/strategies/band_discharge.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.575930+00:00
---

# cartridges/aemo-dispatch/strategies/band_discharge.runar.go

```go
// Modest-band discharge — lower threshold than peak_discharge, more
// dispatch action, more cycling.  Strategy thesis: capture more of
// the daily evening peak even when prices don't blow out.  Suitable
// for batteries with very low cycle cost (e.g., depreciated grid-
// scale LFP) where churn is cheap.
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type BandDischarge struct {
    runar.SmartContract
}

func (c *BandDischarge) ShouldDispatch(priceCents runar.Int, socPct runar.Int) {
    runar.Assert(priceCents >= 20000)  // spot >= $200/MWh
    runar.Assert(socPct >= 40)          // reserve a small floor
}

```
