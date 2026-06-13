---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/lean4/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.991004+00:00
---

# Lean4 proofs — OP_BRANCHONOUTPUT

Formal verification of the invariants stated in
[../../../docs/design/OP-BRANCHONOUTPUT-SPEC.md](../../../docs/design/OP-BRANCHONOUTPUT-SPEC.md).

## Building

```bash
# Toolchain pinned to v4.29.1 via lean-toolchain
lake build
```

Expected output:

```
✔ Built BranchOnOutput
Build completed successfully
```

No `sorry` warnings — all four theorems are machine-checked.

## What's proved

| Theorem                                          | Status | What it says                                                                |
| ------------------------------------------------ | ------ | --------------------------------------------------------------------------- |
| `T1_determinism`                                 | proved | stepOp on equal inputs → equal outputs                                      |
| `T2_stack_delta_plus_one`                        | proved | OP_BRANCHONOUTPUT pushes exactly one item (executing branch)               |
| `T2_skip_when_not_executing`                     | proved | OP_BRANCHONOUTPUT is a no-op in a false IF branch                          |
| `T3_step_preserves_txc`                          | proved | No single opcode mutates `tx.txc`                                          |
| `T3_step_preserves_outputIdx`                    | proved | corollary: `tx.currentOutputIndex` specifically is preserved per-step      |
| `T3_runScript_preserves_txc`                     | proved | Full multi-step preservation by induction                                  |
| `T3_runScript_preserves_outputIdx`               | proved | spec-form: scripts cannot change `currentOutputIndex`                      |
| `step_non_branch_preserves_eqExceptTxc`          | proved | Single-step parallel-evaluation invariant for non-branch ops               |
| `runScript_non_branch_preserves_eqExceptTxc`     | proved | Multi-step parallel-evaluation invariant by induction                      |
| `T4_branchOnOutput_is_sole_observer`             | proved | Scripts without branchOnOutput are independent of currentOutputIndex       |

T3 is the load-bearing safety theorem.  It establishes that no opcode
can modify `currentOutputIndex` — so the runtime is the sole authority
on which output the script believes it is checking.

T4 is the stronger completeness statement: not only can no opcode
*write* the index, but no opcode other than `OP_BRANCHONOUTPUT` can
*observe* it either.  Proved by an `EqExceptTxc` parallel-evaluation
invariant preserved across single steps for every non-branch opcode,
lifted to `runScript` by induction.  No Mathlib used — just core
Lean 4.29.1 tactics.

## Linkage

- Top-level spec: [`docs/design/OP-BRANCHONOUTPUT-SPEC.md`](../../../docs/design/OP-BRANCHONOUTPUT-SPEC.md)
- Zig implementation: [`src/opcodes/routing.zig`](../src/opcodes/routing.zig)
- TLA+ system-level model: [`../tla/RoutingPayment.tla`](../tla/RoutingPayment.tla)
- Delivery tracker: [`docs/OP-BRANCHONOUTPUT-TRACKER.md`](../../../docs/OP-BRANCHONOUTPUT-TRACKER.md)
