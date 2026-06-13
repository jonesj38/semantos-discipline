---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/strategies/soc_quadratic.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.575657+00:00
---

# cartridges/aemo-dispatch/strategies/soc_quadratic.runar.go

```go
// Quadratic SoC-weighting — much steeper than soc_adaptive's
// linear scaling.  At 100% SoC discharges at $500/MWh; halves to
// $2k at 50% SoC; explodes to $50k at 10% SoC (effectively never
// fires near-empty).  Strategy thesis: preserve battery depth for
// absolute peaks; let small peaks pass by.
//
// Threshold = priceCents * socPct² >= 500_000_000.
//
// Discharge thresholds:
//   100% SoC → priceCents × 10000 >= 5e8 → $500/MWh
//    75% SoC → priceCents ×  5625 >= 5e8 → $889/MWh
//    50% SoC → priceCents ×  2500 >= 5e8 → $2000/MWh
//    25% SoC → priceCents ×   625 >= 5e8 → $8000/MWh
//    10% SoC → priceCents ×   100 >= 5e8 → $50000/MWh
//     5% SoC → priceCents ×    25 >= 5e8 → $200000/MWh (basically never)
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type SocQuadratic struct {
    runar.SmartContract
}

func (c *SocQuadratic) ShouldDispatch(priceCents runar.Int, socPct runar.Int) {
    runar.Assert(priceCents * socPct * socPct >= 500000000)
}

```
