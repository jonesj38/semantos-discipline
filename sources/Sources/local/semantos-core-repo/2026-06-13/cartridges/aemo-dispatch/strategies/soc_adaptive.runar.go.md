---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/strategies/soc_adaptive.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.575325+00:00
---

# cartridges/aemo-dispatch/strategies/soc_adaptive.runar.go

```go
// SoC-adaptive battery dispatch predicate.
//
// More interesting than the constant-threshold peak_discharge because
// it scales the dispatch decision with how much energy the battery
// currently holds.  Real operators reason this way:
//
//   - Full battery: take any decent peak — opportunity cost is low
//   - Half battery: hold for stronger peaks — preserve depth
//   - Near empty:    only discharge in scarcity — protect what's left
//
// Encoded as a single combined-value test: priceCents * socPct >=
// 2_500_000.  Discharge thresholds at sample SoCs:
//
//   100% SoC → discharge if price >= $250/MWh    (catch any decent peak)
//    75% SoC → discharge if price >= $333/MWh
//    50% SoC → discharge if price >= $500/MWh
//    25% SoC → discharge if price >= $1000/MWh
//    10% SoC → discharge if price >= $2500/MWh   (scarcity only)
//     5% SoC → discharge if price >= $5000/MWh   (severe scarcity)
//
// One predicate, dynamic threshold — operator gets bias for free.
// Wear cost is bounded by the natural reluctance to discharge low SoC.
//
// Compiled via: runar-go -source SocAdaptive.runar.go -hex
// Upstream: github.com/icellan/runar @ d4c3b6e
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type SocAdaptive struct {
    runar.SmartContract
}

func (c *SocAdaptive) ShouldDispatch(priceCents runar.Int, socPct runar.Int) {
    runar.Assert(priceCents * socPct >= 2500000)
}

```
