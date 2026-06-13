---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/ixp-routing/strategies/route_accept.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.560415+00:00
---

# cartridges/ixp-routing/strategies/route_accept.runar.go

```go
// IXP BGP route-acceptance predicate — route_accept rule.
//
// Two unlock-provided integers (asnTier, prefixLen):
//   - asnTier:   peer trust level pushed first (sits lower on stack)
//                0 = unknown / unregistered
//                1 = registered ASN (RIPE / ARIN / APNIC record)
//                2 = verified peering partner (SLA + NOC contact)
//                3 = trusted partner (bilateral agreement, traffic-engineered)
//   - prefixLen: route prefix length pushed second (sits higher on stack)
//                8..32 where 8=/8 broad super-aggregate, 32=/32 host-specific
//                More specific (larger number) = safer, less hijack surface
//
// Predicate accepts iff BOTH:
//   prefixLen >= 16   (reject super-aggregates: /8-/15 block entire regions)
//   asnTier   >= 1    (reject unknown / unregistered ASNs)
//
// Policy rationale: any /8-/15 route advertisement is a red flag — only
// RIRs and tier-1 backbones legitimately advertise at that breadth, and
// they don't peer at IXPs in small-specific routes.  Combined with a
// minimum tier-1 (registered ASN) requirement, this policy blocks the
// two most common BGP hijack patterns: prefix super-aggregation and
// ghost-ASN injection.
//
// Compiled via: runar-go -source route_accept.runar.go -hex
// Upstream: github.com/icellan/runar @ d4c3b6e (2026-05-25)
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type RouteAccept struct {
    runar.SmartContract
}

func (c *RouteAccept) ShouldAcceptRoute(asnTier runar.Int, prefixLen runar.Int) {
    // Stack at entry: [asnTier, prefixLen]
    //
    // Compiled hex: 760110a269750101a2  (9 bytes)
    //
    // 76          OP_DUP             → [asnTier, prefixLen, prefixLen]
    // 01 10       PUSH(16)           → [asnTier, prefixLen, prefixLen, 16]
    // a2          OP_GTE             → [asnTier, prefixLen, (prefixLen >= 16)]
    // 69          OP_VERIFY          → [asnTier, prefixLen]  or FAIL (too broad)
    // 75          OP_DROP            → [asnTier]              (drop prefixLen off top)
    // 01 01       PUSH(1)            → [asnTier, 1]
    // a2          OP_GTE             → [(asnTier >= 1)]
    runar.Assert(prefixLen >= 16)
    runar.Assert(asnTier >= 1)
}

```
