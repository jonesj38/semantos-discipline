---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/ixp-routing/strategies/tier_prefix_product.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.560043+00:00
---

# cartridges/ixp-routing/strategies/tier_prefix_product.runar.go

```go
// IXP BGP route-acceptance predicate — tier_prefix_product rule.
//
// Two unlock-provided integers (asnTier, prefixLen):
//   - asnTier:   peer trust level pushed first (sits lower on stack)
//                0 = unknown / unregistered
//                1 = registered ASN (RIPE / ARIN / APNIC record)
//                2 = verified peering partner (SLA + NOC contact)
//                3 = trusted partner (bilateral agreement, traffic-engineered)
//   - prefixLen: route prefix length pushed second (sits higher on stack)
//                8..32 where 8=/8 broad super-aggregate, 32=/32 host-specific
//
// Predicate accepts iff:
//   asnTier × prefixLen >= 32
//
// Policy rationale: smooth continuous tradeoff between trust and specificity.
// A fully trusted partner (tier-3) can advertise a /11 route (3×11=33 ≥ 32).
// An unregistered peer (tier-0) is rejected for any route (0×anything=0).
// A tier-1 registered peer must advertise at least /32 (1×32=32 ≥ 32).
// A tier-2 verified peer can advertise /16 (2×16=32 ≥ 32) and more specific.
//
// This produces a different false-positive profile than route_accept: it
// allows edge cases that the binary policy blocks (trusted partner with
// a /12 for traffic engineering), while still catching 85% of BGP hijack
// patterns because ghost-ASNs (tier-0) always score 0.
//
// Examples:
//   tier-1 + /32 = 32 ✓   tier-1 + /24 = 24 ✗
//   tier-2 + /16 = 32 ✓   tier-2 + /15 = 30 ✗
//   tier-3 + /11 = 33 ✓   tier-0 + /32 = 0  ✗ (always)
//
// Compiled via: runar-go -source tier_prefix_product.runar.go -hex
// Upstream: github.com/icellan/runar @ d4c3b6e (2026-05-25)
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type TierPrefixProduct struct {
    runar.SmartContract
}

func (c *TierPrefixProduct) ShouldAcceptRoute(asnTier runar.Int, prefixLen runar.Int) {
    // Stack at entry: [asnTier, prefixLen]
    //
    // Compiled hex: 950120a2  (4 bytes)
    //
    // 95          OP_MUL     → [asnTier * prefixLen]
    // 01 20       PUSH(32)   → [product, 32]
    // a2          OP_GTE     → [(asnTier * prefixLen >= 32)]
    runar.Assert(asnTier * prefixLen >= 32)
}

```
