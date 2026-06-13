---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/OPCODE-HARDENING-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.804111+00:00
---

# Opcode Hardening Plan — Failure Atomicity and Safety

**Scope**: `macro.zig` (0xB0-0xB8) and `plexus.zig` (0xC0-0xC7)
**Approach**: TDD — write failing tests first, then fix implementations, then verify zero regressions.

---

## Bug 1: hashcat is not failure-atomic

**File**: `src/opcodes/macro.zig` lines 92-114
**Problem**: `hashcat` calls `spop()` for `b`, then `spop()` for `a`. If the stack has only one element, the first pop succeeds (mutating the stack), the second fails. The machine state has been partially mutated on error.

**Fix**: Precheck `sdepth() < 2` before any pops. Then use `catch unreachable` since depth is already validated.

**Test to write** (must fail before fix):
```
test "HASHCAT with 1 element: stack unchanged on underflow" {
    push [0x01]
    depth == 1
    hashcat → expect error.stack_underflow
    depth == 1  // THIS CURRENTLY FAILS — depth is 0 after partial pop
    top == [0x01]  // original element intact
}
```

---

## Bug 2: hashcat concat_buf may overflow

**File**: `src/opcodes/macro.zig` line 105
**Problem**: `concat_buf: [2048]u8` — no bounds check on `a_len + b_len`. Cell size is currently 1024 so max is 2048, but there's no guard. If cell size assumptions change, this is a silent buffer overwrite.

**Fix**: Add `if (a_len + b_len > concat_buf.len) return error.stack_overflow;` after both pops. Better: size the buffer from `2 * pda_mod.CELL_SIZE` and add the bounds check.

**Test to write**:
```
test "HASHCAT bounds: two max-length cells concatenated fit in buffer" {
    push 1024 bytes of 0xAA
    push 1024 bytes of 0xBB
    hashcat → should succeed (2048 == buffer size)
    result len == 32 (SHA256)
}
```

---

## Bug 3: Plexus check ops not failure-atomic

**File**: `src/opcodes/plexus.zig` — `opCheckCapability`, `opCheckIdentity`, `opCheckDomainFlag`, `opCheckTypeHash`
**Problem**: All four ops call `spop()` to consume the expected argument before verifying the cell. If the check fails (wrong linearity, wrong capability type, etc.), the expected argument has already been removed from the stack. The stack is partially mutated on error.

**Fix**: Precheck `sdepth() < 2`, then `speekAt(0)` to read the expected value without consuming, `speekAt(1)` to read the cell. Only after all checks pass, do a single `sdrop()` to remove the expected argument and `pushTrue()`.

**Tests to write** (must fail before fix):
```
test "OP_CHECKCAPABILITY with wrong cap type: stack unchanged on failure" {
    push LINEAR cell with cap=4
    push expected cap=2 (mismatch)
    depth == 2
    executePlexus(0xC3) → expect error.capability_type_mismatch
    depth == 2  // CURRENTLY FAILS — depth is 1, expected cap consumed
}

test "OP_CHECKIDENTITY with wrong owner: stack unchanged on failure" {
    push LINEAR cell with owner=0xBB*16
    push expected owner=0x11*16
    depth == 2
    executePlexus(0xC4) → expect error.owner_id_mismatch
    depth == 2  // CURRENTLY FAILS
}

test "OP_CHECKDOMAINFLAG with wrong flag: stack unchanged on failure" {
    push LINEAR cell with flag=1
    push expected flag=5
    depth == 2
    executePlexus(0xC6) → expect error.domain_flag_mismatch
    depth == 2  // CURRENTLY FAILS
}

test "OP_CHECKTYPEHASH with wrong hash: stack unchanged on failure" {
    push LINEAR cell with hash=0xAA*32
    push expected hash=0x00*32
    depth == 2
    executePlexus(0xC7) → expect error.type_hash_mismatch
    depth == 2  // CURRENTLY FAILS
}
```

---

## Bug 4: Stack contract not standardised

**Problem**: The peek-only ops (0xC0-0xC2, 0xC5) and the consuming ops (0xC3, 0xC4, 0xC6, 0xC7) have different stack contracts, but this is not documented. The consuming ops should have explicit pre/post stack comments.

**Fix**: Add stack contract comments to every opcode:
```
/// Stack: [cell, expected_cap] → [cell, TRUE]  (on success)
/// Stack: [cell, expected_cap] → [cell, expected_cap]  (on failure — unchanged)
```

This is documentation, not a code change, but it needs to be done alongside the atomicity fix.

---

## Hygiene 1: xdrop leaves stale lengths

**File**: `src/opcodes/macro.zig` lines 60-64
**Problem**: `xdrop` only decrements `main_sp` without zeroing `main_lengths` for dropped slots. Functionally correct since dead slots are ignored, but stale data makes debugging harder and could cause aliasing bugs in future.

**Fix**: Zero the lengths of dropped slots.

**Test to write**:
```
test "XDROP-2 zeroes lengths of dropped slots" {
    push [0x01]
    push [0x02, 0x03]  // len=2
    push [0x04, 0x05, 0x06]  // len=3
    xdrop-2
    depth == 1
    // The slots at sp and sp+1 should have length 0
    // (verify via direct access to main_lengths)
}
```

---

## Hygiene 2: cellToU32 comment misleading

**File**: `src/opcodes/plexus.zig` line 145
**Problem**: Comment says "u32 LE (Bitcoin Script number encoding)" but Script numbers are sign-magnitude, not plain LE. The implementation correctly uses `cellToI64` then clamps.

**Fix**: Update comment to: "Interpret stack item as Bitcoin Script number (sign-magnitude LE), clamp to u32 range. Empty → 0, negative → 0."

---

## Hygiene 3: unused execution_limit error

**File**: `src/opcodes/macro.zig` line 20
**Problem**: `MacroError` includes `execution_limit` but no macro op ever returns it. It's either premature or orphaned.

**Fix**: Remove from `MacroError`. If metering is added later, it gets added back.

---

## Implementation Order

1. **Write all failing tests** — add to `tests/macro_conformance.zig` and `tests/plexus_conformance.zig`
2. **Run tests, confirm they fail** — this validates the bugs are real and the tests catch them
3. **Fix hashcat** — precheck + bounds check + `catch unreachable`
4. **Fix plexus check ops** — refactor to peek-inspect-then-mutate pattern
5. **Fix xdrop** — zero stale lengths
6. **Update comments** — stack contracts, cellToU32
7. **Remove execution_limit** from MacroError
8. **Run full suite** — `zig build test`, all phases 0-5 pass, zero regressions

---

## Files Modified

| File | Change |
|------|--------|
| `tests/macro_conformance.zig` | Add 3 new tests (atomicity, bounds, xdrop hygiene) |
| `tests/plexus_conformance.zig` | Add 4 new tests (atomicity for each check op) |
| `src/opcodes/macro.zig` | Fix hashcat, fix xdrop, remove execution_limit |
| `src/opcodes/plexus.zig` | Fix 4 check ops, update comments, fix cellToU32 doc |

Total: 7 new failing tests → 7 fixes → 0 regressions.
