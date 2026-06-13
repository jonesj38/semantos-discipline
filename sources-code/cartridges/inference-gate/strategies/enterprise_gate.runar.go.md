---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/strategies/enterprise_gate.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.420435+00:00
---

# cartridges/inference-gate/strategies/enterprise_gate.runar.go

```go
// Inference Gateway access-control predicate — enterprise_gate.
//
// Two unlock-provided integers (certTier, dataClass):
//   - certTier:  identity clearance level (0=none, 1=basic, 2=enterprise, 3=sovereign)
//   - dataClass: data classification    (0=public, 1=internal, 2=confidential, 3=restricted)
//
// Stack on entry (pushed by unlock builder before predicate runs):
//   [certTier]          ← pushed first, sits at bottom
//   [dataClass]         ← pushed second, sits on top
//
// Predicate accepts (truthy top-of-stack) iff BOTH:
//   certTier >= 2                  (must be enterprise tier; basic-tier (1) is insufficient)
//   certTier >= dataClass          (clearance meets or exceeds data classification)
//
// Rationale vs cert_gate: enterprise_gate blocks tier-1 (basic) identities from accessing
// *anything* — even internal (class 1) data.  Used for higher-sensitivity inference workloads
// where basic-registration is insufficient assurance.  The cost: some legitimate tier-1 users
// are blocked from internal data, which cert_gate would allow.  The tradeoff is explicit in
// the hex; the 1-byte difference (0x01 → 0x02) is the policy decision.
//
// Compiled hex: 7c760102a269a2  (7 bytes)
//
//   7c          OP_SWAP  → [dataClass, certTier]
//   76          OP_DUP   → [dataClass, certTier, certTier]
//   01 02       PUSH(2)  → [dataClass, certTier, certTier, 2]
//   a2          OP_GTE   → [dataClass, certTier, (certTier >= 2)]
//   69          OP_VERIFY→ [dataClass, certTier]   or FAIL (abort if certTier < 2)
//   a2          OP_GTE   → [(certTier >= dataClass)]
//
// Compiled via: runar-go -source enterprise_gate.runar.go -hex
// Upstream: github.com/icellan/runar @ d4c3b6e (2026-05-25)
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type EnterpriseGate struct {
	runar.SmartContract
}

func (c *EnterpriseGate) ShouldAllow(certTier runar.Int, dataClass runar.Int) {
	runar.Assert(certTier >= 2)        // must be enterprise-tier or above
	runar.Assert(certTier >= dataClass) // clearance must meet classification
}

```
