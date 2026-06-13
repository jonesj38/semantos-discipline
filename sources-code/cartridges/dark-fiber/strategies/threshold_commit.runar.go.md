---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/dark-fiber/strategies/threshold_commit.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.423120+00:00
---

# cartridges/dark-fiber/strategies/threshold_commit.runar.go

```go
// EU Networks dark fiber — threshold commit predicate.
//
// Two unlock-provided integers (utilizationPct, bidCentsPerGbps):
//   - utilizationPct:    current link utilization, integer 0..100
//   - bidCentsPerGbps:   buyer's bid in €-cents per Gbps-hour
//                        (e.g., 250 = €2.50/Gbps-hr)
//
// Predicate accepts (truthy top-of-stack) iff BOTH:
//   utilizationPct  <= 70     (link below 70% full — capacity available)
//   bidCentsPerGbps >= 250    (bid meets minimum floor of €2.50/Gbps-hr)
//
// Commitment decision: sell the wavelength slot into the spot market when
// the predicate accepts.  Otherwise reserve capacity for contracted customers.
//
// Why this shape: dark fiber wavelengths are sold by the Gbps-hour in the
// spot market.  If link utilization is already high, committing more capacity
// risks impacting contracted customers.  If the bid is too low, spot revenue
// doesn't justify the switching cost.  Two thresholds, nine bytes.
//
// Compiled via: runar-go -source threshold_commit.runar.go -hex
// Upstream: github.com/icellan/runar @ d4c3b6e (2026-05-25)
//
// Compiled hex: 7c0146a16902fa00a2  (9 bytes)
// Opcode trace:
//   Stack on entry: [utilizationPct, bidCentsPerGbps]
//   7c          OP_SWAP            → [bidCentsPerGbps, utilizationPct]
//   01 46       PUSH(70)           → [bidCentsPerGbps, utilizationPct, 70]
//   a1          OP_LESSTHANOREQUAL → [bidCentsPerGbps, (utilPct <= 70)]
//   69          OP_VERIFY          → [bidCentsPerGbps]  or FAIL
//   02 fa 00    PUSH(250)          → [bidCentsPerGbps, 250]
//   a2          OP_GTE             → [(bid >= 250)]
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type ThresholdCommit struct {
	runar.SmartContract
}

func (c *ThresholdCommit) ShouldCommit(utilizationPct runar.Int, bidCentsPerGbps runar.Int) {
	runar.Assert(utilizationPct <= 70)
	runar.Assert(bidCentsPerGbps >= 250)
}

```
