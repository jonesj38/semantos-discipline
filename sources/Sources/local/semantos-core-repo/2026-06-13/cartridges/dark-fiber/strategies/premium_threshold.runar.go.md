---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/dark-fiber/strategies/premium_threshold.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.422841+00:00
---

# cartridges/dark-fiber/strategies/premium_threshold.runar.go

```go
// EU Networks dark fiber — premium threshold commit predicate.
//
// Two unlock-provided integers (utilizationPct, bidCentsPerGbps):
//   - utilizationPct:    current link utilization, integer 0..100
//   - bidCentsPerGbps:   buyer's bid in €-cents per Gbps-hour
//                        (e.g., 500 = €5.00/Gbps-hr)
//
// Predicate accepts (truthy top-of-stack) iff BOTH:
//   utilizationPct  <= 50     (link below 50% — high-availability headroom)
//   bidCentsPerGbps >= 500    (premium tier: €5.00/Gbps-hr floor)
//
// Commitment decision: sell into the spot market at premium tier pricing
// when the predicate accepts.  This tier guarantees committed wavelengths
// have at least 50% residual link headroom — SLA-quality availability.
// Reserved for AI training runs and latency-critical HPC bursts.
//
// Why higher thresholds: premium-tier buyers pay 2× for the guarantee that
// their slot won't be crowded out.  The 50% utilization gate enforces that
// guarantee structurally — it's not a promise, it's a predicate.
//
// Compiled via: runar-go -source premium_threshold.runar.go -hex
// Upstream: github.com/icellan/runar @ d4c3b6e (2026-05-25)
//
// Compiled hex: 7c0132a16902f401a2  (9 bytes)
// Opcode trace:
//   Stack on entry: [utilizationPct, bidCentsPerGbps]
//   7c          OP_SWAP            → [bidCentsPerGbps, utilizationPct]
//   01 32       PUSH(50)           → [bidCentsPerGbps, utilizationPct, 50]
//   a1          OP_LESSTHANOREQUAL → [bidCentsPerGbps, (utilPct <= 50)]
//   69          OP_VERIFY          → [bidCentsPerGbps]  or FAIL
//   02 f4 01    PUSH(500)          → [bidCentsPerGbps, 500]
//   a2          OP_GTE             → [(bid >= 500)]
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type PremiumThreshold struct {
	runar.SmartContract
}

func (c *PremiumThreshold) ShouldCommit(utilizationPct runar.Int, bidCentsPerGbps runar.Int) {
	runar.Assert(utilizationPct <= 50)
	runar.Assert(bidCentsPerGbps >= 500)
}

```
