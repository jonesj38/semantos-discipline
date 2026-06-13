---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/OP-BRANCHONOUTPUT-SPEC.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.735240+00:00
---

# OP_BRANCHONOUTPUT — Specification

**Status:** Design — Phase 1 of OP_BRANCHONOUTPUT delivery
**Created:** 2026-05-26
**Owner:** Todd
**Tracker:** [docs/OP-BRANCHONOUTPUT-TRACKER.md](../OP-BRANCHONOUTPUT-TRACKER.md)

---

## 1. Purpose

`OP_BRANCHONOUTPUT` exposes the *current output index* of the execution
context to the script, allowing a single locking script to branch on which
output is being claimed or validated.

The motivating use case is **economically-weighted semantic segment
routing**: a multi-output cell carrying payment to N relays — one output
per hop in a [typed-segments][typed-segments] route. Without this opcode,
verifying "this output belongs to hop i" requires `N × OP_CHECKSIG` because
every spending path must run a signature check to decide which it is. With
this opcode, hop disambiguation becomes O(N) `memcmp` of the index, and
only the matching path runs `OP_CHECKSIG` — exactly one per spend.

This is the missing primitive that lets the TSP collapse described in the
architecture: semantic addressing pre-filters the relay set, payment turns
optimization into a market, and `OP_BRANCHONOUTPUT` makes the per-hop
payment verification O(1) per relay instead of N × CHECKSIG.

[typed-segments]: ../../core/protocol-types/src/mnca/typed-segments.ts

---

## 2. Opcode

| Field           | Value                                     |
| --------------- | ----------------------------------------- |
| Mnemonic        | `OP_BRANCHONOUTPUT`                       |
| Byte            | `0xE0`                                    |
| Range           | Routing opcodes `0xE0..0xEF` (new range)  |
| Stack delta     | `+1` (one push, no pop)                   |
| Tx-context read | `current_output_index: u32`               |
| Tx-context write| none                                      |

### 2.1 Range allocation

The existing opcode ranges are full or reserved:

| Range          | Owner          | Status              |
| -------------- | -------------- | ------------------- |
| `0x00..0xAF`   | Standard       | BSV-compatible      |
| `0xB0..0xBF`   | Craig macros   | 16/16 used          |
| `0xC0..0xCF`   | Plexus         | 16/16 used          |
| `0xD0..0xDF`   | Host call      | `0xD0` dispatch     |
| `0xE0..0xEF`   | **Routing**    | **NEW — this PR**   |
| `0xF0..0xFF`   | Reserved       | Future              |

Reserve `OPCODE_ROUTING_MIN = 0xE0` and `OPCODE_ROUTING_MAX = 0xEF` in
[constants.zig](../../core/cell-engine/src/constants.zig) alongside the
existing range constants.

---

## 3. Execution context extension

Add a single field to `TxContext` in [sighash.zig](../../core/cell-engine/src/sighash.zig):

```zig
pub const TxContext = struct {
    version: u32,
    locktime: u32,
    current_input_index: u32,
    current_output_index: u32,   // NEW — set by runtime per-output execution
    input_value: u64,
    // ... rest unchanged
};
```

**Read-only from script perspective.** No opcode in any range may write
`current_output_index`. The runtime sets it before invoking the script.

**Runtime contract.** When the cell engine validates a multi-output cell
spend, it calls `execute(script, tx_context)` once per output index of
interest, with `tx_context.current_output_index` set accordingly. The
specific output set is determined by the runtime caller (typically: every
output the script may need to verify, or only the one the script claims).
This spec does not constrain the caller's iteration policy — it only
defines what the script observes when invoked.

---

## 4. Small-step semantics

```
─── BRANCHONOUTPUT ───────────────────────────────────────────────────

  Pre:
    script[ctx.pc]               = 0xE0
    ctx.executing                = true
    ctx.tx_context.current_output_index = i ∈ [0, 2³²)
    ctx.pda.stack.depth          < MAX_STACK_DEPTH

  Step:
    let buf = u32_le(i)
    push buf onto stack
    ctx.pc += 1
    ctx.pda.opcount += 1

  Post:
    stack = u32_le(i) :: stack_before
    pc' = pc + 1
    tx_context unchanged
    pda.opcount = opcount + 1

  Errors:
    stack_overflow      if depth = MAX_STACK_DEPTH
    execution_limit     if opcount = max_ops at entry

─── In a non-executing branch (within failed OP_IF) ──────────────────

  Step:
    ctx.pc += 1
    no stack mutation, no opcount bump (matches existing opcode behavior)
```

The push is **always** the 4-byte little-endian encoding of `current_output_index`.
This matches the `OP_BIN2NUM` round-tripping convention used elsewhere in the
engine, so scripts may use `OP_EQUAL` directly against a 4-byte LE pushdata,
or convert via `OP_BIN2NUM` to use numeric comparisons.

---

## 5. Invariants (to prove)

### I1. Determinism

For any two execution contexts `c₁`, `c₂` that agree on
`(stack, pc, executing, tx_context.current_output_index, pda.opcount)`,
executing `OP_BRANCHONOUTPUT` from `c₁` and `c₂` produces results that
agree on the same fields.

### I2. Stack delta is exactly +1

If `OP_BRANCHONOUTPUT` succeeds from context `c`, then
`stack_depth(c') = stack_depth(c) + 1` and the new top is `u32_le(c.tx_context.current_output_index)`.

### I3. Non-malleability of `current_output_index`

No sequence of opcodes — including arbitrary use of `OP_BRANCHONOUTPUT` —
can modify `tx_context.current_output_index`. Formally, for any script `s`
and any starting context `c`, running `s` from `c` produces a context `c'`
where `c'.tx_context.current_output_index = c.tx_context.current_output_index`.

This is the load-bearing safety property. It ensures the runtime — and only
the runtime — controls which output the script believes it is checking.

### I4. Linear type preservation

If a cell has `linearity = LINEAR`, then for any script `s` extracted from
its locking program and any two contexts `c₁ ≠ c₂` differing only in
`current_output_index`, at most one of `runScript(s, c₁)` and
`runScript(s, c₂)` can return `done_true`.

This prevents a single LINEAR cell from being successfully claimed at two
distinct output indices — the source of single-spend safety in the routing
payment model.

I4 is conditional on the locking script having been structured to branch
on `OP_BRANCHONOUTPUT` (i.e., having distinct paths per output). The spec
proves the *meta*-property: that `OP_BRANCHONOUTPUT` is the *only* way for
the script to observe `current_output_index`, so I4 reduces to "every
truth-producing path must take a unique branch."

---

## 6. Example: economically-weighted route

A 3-hop route from `typed-segments.ts` produces a SRH containing
`[(BCA_A, type), (BCA_B, type), (BCA_C, type)]`. The source crafts a
single locking script that pays each relay from a 3-output cell:

```
OP_BRANCHONOUTPUT          ; push current output index
OP_DUP OP_0 OP_EQUAL OP_IF
  OP_DROP                  ; drop the duplicated index
  <BCA_A> OP_CHECKSIG      ; only relay A reaches this path
OP_ELSE OP_DUP OP_1 OP_EQUAL OP_IF
  OP_DROP
  <BCA_B> OP_CHECKSIG
OP_ELSE OP_DUP OP_2 OP_EQUAL OP_IF
  OP_DROP
  <BCA_C> OP_CHECKSIG
OP_ELSE
  OP_DROP OP_FALSE         ; out-of-range index → spend fails
OP_ENDIF OP_ENDIF OP_ENDIF
```

**Per-relay cost:** 1 push + 1 `OP_BRANCHONOUTPUT` + ≤ 3 `OP_EQUAL` (memcmp) +
1 `OP_CHECKSIG`. The signature check happens once per relay, not N times.

**Baseline (without `OP_BRANCHONOUTPUT`):** every spending path must run
`OP_CHECKSIG` to discriminate between candidate relays, giving N CHECKSIG
operations per spend attempt. On the C6 (~270 ms per ECDSA verify per
[c6_ecdsa_verify_cost][c6-cost]), the difference for an 8-hop route is
~2 seconds vs ~270 ms per claim.

[c6-cost]: ../../docs/perf/c6-ecdsa-verify-cost.md

---

## 7. Out of scope

- Iteration policy: the spec does not define how the runtime chooses
  `current_output_index` values to invoke the script with. That is the
  caller's responsibility and is documented per-callsite.
- Multi-input attestation: `OP_BRANCHONINPUT` (analogous opcode reading
  `current_input_index`) is a separate, future opcode (`0xE1` reserved).
- Cross-output value flow: a separate opcode (`OP_OUTPUTVALUE`, `0xE2`
  reserved) for asserting per-output satoshi values is left for a future
  spec when needed by a payment use case.

---

## 8. Verification scope

| Phase | Artifact                                  | Proves                  |
| ----- | ----------------------------------------- | ----------------------- |
| 2     | `core/cell-engine/lean4/*.lean`           | I1, I2, I3, I4          |
| 3     | `core/cell-engine/tla/RoutingPayment.tla` | Concurrent I4, liveness |
| 4     | `core/cell-engine/src/routing.zig` + tests| Implementation parity   |
| 5     | TS parity tests + integration             | Cross-language parity   |

The Lean4 proofs prove the opcode is safe in isolation (single-script
execution). The TLA+ model proves the system is safe under concurrent
execution by N relays racing to claim outputs.

---

## 9. Decision points

The following design decisions are locked by this spec:

| ID  | Decision                                                  | Rationale                     |
| --- | --------------------------------------------------------- | ----------------------------- |
| D1  | Opcode byte `0xE0`                                        | New `0xE0..0xEF` routing range|
| D2  | Push 4-byte LE                                            | Matches `OP_BIN2NUM` convention|
| D3  | Read from `TxContext.current_output_index`                | Reuse existing tx_context     |
| D4  | Non-malleable (no write opcode in any range)              | Single source of truth = runtime|
| D5  | Stack delta = +1 (push only, no pop)                      | Idempotent context read       |
| D6  | Range 0xE0..0xEF named "Routing", reserves 16 future slots| Symmetry with other ranges    |

If any of these change later, this spec must be updated first.
