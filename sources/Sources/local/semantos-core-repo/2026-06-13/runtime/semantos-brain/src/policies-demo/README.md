---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/policies-demo/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.292327+00:00
---

# Rúnar-policies worked example (brain-local)

Worked example demonstrating the Rúnar cartridge-precondition workflow documented at [`docs/cartridge-author-guide-runar.md`](../../../../docs/cartridge-author-guide-runar.md).

## Why this lives in the brain tree

Per Zig 0.15's `@embedFile` semantics: `runtime/semantos-brain/src/policy_runtime.zig` loads `range_check.expected.hex` via `@embedFile`, and the path must stay inside the package boundary the standalone test target declares as its root source. Cross-package paths (`../../../docs/...`) get rejected at compile time.

**Real cartridges author their `.runar.go` + `.expected.hex` pairs inside their own cartridge tree** — e.g., `cartridges/oddjobz/brain/zig/policies/`. This `policies-demo/` directory is the canonical worked example the author guide cites; it has no production consumer.

## Files

| File | Role |
|---|---|
| `range_check.runar.go` | Source. Self-documenting header carries provenance, invocation, output hex, and an opcode-by-opcode decode. |
| `range_check.expected.hex` | Compiled golden. Single line: `7600a0690164a1`. Load-bearing — this is what the brain executes. |

## Recompiling

Per Todd 2026-05-25 directive: the brain build does NOT depend on Rúnar / Go. Authors recompile on their own dev machine and commit the new hex.

```bash
# One-time setup:
git clone --depth 1 https://github.com/icellan/runar.git ~/runar
cd ~/runar/compilers/go && go build -o ~/.local/bin/runar-go .

# Per-source recompile:
runar-go -source range_check.runar.go -hex > range_check.expected.hex
```

Diff review catches drift. A PR that modifies `range_check.runar.go` without an updated `range_check.expected.hex` should be rejected.

## Test coverage

`policy_runtime.zig` inline tests (search for "§11.10 order 4b-2") cover:

- `range_check hex round-trip via @embedFile` — sanity that the embedded golden decodes to the documented 7-byte sequence
- `accepts amount in (0, 100]` — three accepts at 1, 50, 100 (lower bound, middle, upper bound)
- `rejects amount=0` with `verify_failed` (OP_VERIFY mid-script abort)
- `rejects amount=200` with `verify_failed` (trailing-false reject)

Run via:

```bash
cd runtime/semantos-brain && zig build test -j1
```
