---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/policies-demo/range_check.runar.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.292044+00:00
---

# runtime/semantos-brain/src/policies-demo/range_check.runar.go

```go
// Cartridge precondition demo — amount-in-range.
//
// Asserts the spend `amount` satisfies 0 < amount <= 100.  Shape a
// payment-bounded cartridge would author as its canonical write-time
// precondition.
//
// Provenance:
//   Upstream:   github.com/icellan/runar @ d4c3b6e (2026-05-25)
//   Compiler:   Rúnar Go tier
//   Invocation: runar-go -source range_check.runar.go -hex
//   Output:     7600a0690164a1
//
// Decode (Bitcoin Script per Genesis-restored BSV spec):
//   76    OP_DUP                duplicate amount on top
//   00    OP_0                  push 0 sentinel
//   a0    OP_GREATERTHAN        amount > 0 ? push 1 : push 0
//   69    OP_VERIFY             pop; abort if 0
//   0164  push 1 byte = 100     push the upper bound
//   a1    OP_LESSTHANOREQUAL    amount <= 100 ? push 1 : push 0
//
// End state: top-of-stack is 1 iff 0 < amount <= 100; else 0 (rejected
// via OP_VERIFY mid-script or trailing false).  See
// runtime/semantos-brain/src/policy_runtime.zig inline tests for the
// matching PolicyRuntime.evaluateReal accept + reject smokes.
//
// Workflow: see ../../cartridge-author-guide-runar.md.

package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type RangeCheck struct {
    runar.SmartContract
}

func (c *RangeCheck) Verify(amount runar.Int) {
    runar.Assert(amount > 0)
    runar.Assert(amount <= 100)
}

```
