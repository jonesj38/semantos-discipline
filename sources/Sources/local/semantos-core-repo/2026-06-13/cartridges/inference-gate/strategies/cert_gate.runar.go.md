---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/strategies/cert_gate.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.420700+00:00
---

# cartridges/inference-gate/strategies/cert_gate.runar.go

```go
// Inference Gateway access-control predicate — cert_gate.
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
//   certTier >= 1                  (must have a verified identity; anonymous bots rejected)
//   certTier >= dataClass          (clearance meets or exceeds data classification)
//
// Compiled hex: 7c760101a269a2  (7 bytes)
//
//   7c          OP_SWAP  → [dataClass, certTier]
//   76          OP_DUP   → [dataClass, certTier, certTier]
//   01 01       PUSH(1)  → [dataClass, certTier, certTier, 1]
//   a2          OP_GTE   → [dataClass, certTier, (certTier >= 1)]
//   69          OP_VERIFY→ [dataClass, certTier]   or FAIL (abort if certTier < 1)
//   a2          OP_GTE   → [(certTier >= dataClass)]
//
// Compiled via: runar-go -source cert_gate.runar.go -hex
// Upstream: github.com/icellan/runar @ d4c3b6e (2026-05-25)
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type CertGate struct {
	runar.SmartContract
}

func (c *CertGate) ShouldAllow(certTier runar.Int, dataClass runar.Int) {
	runar.Assert(certTier >= 1)        // must have a verified identity
	runar.Assert(certTier >= dataClass) // clearance must meet classification
}

```
