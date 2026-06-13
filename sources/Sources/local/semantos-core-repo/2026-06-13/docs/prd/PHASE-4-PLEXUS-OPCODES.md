---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-4-PLEXUS-OPCODES.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.698957+00:00
---

# Phase 4: Plexus Opcodes and Linearity Enforcement

**Status**: COMPLETE — implemented 2026-03-27. 240 Zig tests, 56 TS tests pass, 28KB WASM.
**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Prerequisites**: Phase 3 complete — 2-PDA core working, standard opcodes passing, WASM exports matching PlexusKernelWasm.
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` (in this directory: `semantos-core/docs/prd/`)

---

## Context

This is where Semantos diverges from standard Bitcoin Script. The Plexus opcodes (0xC0-0xCF) extend the 2-PDA with type enforcement — the ability to inspect a cell's header and reject operations that violate its linearity class.

Linearity is the mechanism that makes semantic objects behave like real-world resources:
- **LINEAR** (1): Must be used exactly once. Like money — you spend it or you don't, but you can't copy it or throw it away silently.
- **AFFINE** (2): Can be used at most once. Like a session token — use it or discard it, but don't copy it.
- **RELEVANT** (3): Must be used at least once. Like a public key — copy it freely, but you can't destroy it (it's part of the system state).
- **DEBUG** (4): Unrestricted. Development only.

The linearity enforcement happens at the stack operation level — when you try to DUP a LINEAR cell, the 2-PDA rejects it before the DUP executes. This is NOT a runtime check bolted on top. It's woven into the stack machine itself.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `FORTH:LINEARITY` | `semantos-gift-pack/forth/linearity-enforcement.fs` | **Primary reference.** S-DUP-ENFORCED, S-DROP-ENFORCED, S-SWAP-ENFORCED, S-OVER-ENFORCED. LINEAR: cannot duplicate (DUP/OVER/PICK fail), cannot discard (DROP fails). AFFINE: cannot duplicate, CAN discard. RELEVANT: CAN duplicate, cannot discard. State transitions are atomic. |
| `CORE:SEMOBJ` | `semantos-core/src/types/semantic-objects.ts` | SemanticType enum. LinearObject (has ConsumptionProof — single use). AffineObject (use or discard). RelevantObject (copy freely, can't destroy). Type guards: isLinear(), isAffine(), isRelevant(). |
| `CORE:OPCODES` | `semantos-core/src/cell-engine/opcodes.ts` | Plexus opcode definitions 0xC0-0xCF. |
| `CORE:VALIDATOR` | `semantos-core/src/compiler/validator.ts` | Consumption rule validation per semantic type. |
| `CORE:DOMAIN-FLAGS` | `semantos-core/src/types/domain-flags.ts` | DomainFlag type, well-known flags, 3-tier ranges, classifyFlag(), toProtocolId(). |
| `CORE:CAPABILITY` | `semantos-core/src/types/capability.ts` | CapabilityToken structure. CapabilityConstraints: expiresAt, geoBounds, maxInvocations, requiredDomainFlags. |

---

## Deliverables

### D4.1 — `linearity.zig`

```zig
pub const LinearityType = enum(u32) {
    linear = 1,
    affine = 2,
    relevant = 3,
    debug = 4,
};

pub const LinearityOperation = enum {
    duplicate,  // DUP, OVER, PICK, 2DUP, 3DUP
    discard,    // DROP, 2DROP, NIP
    consume,    // Normal read-and-use (CHECKSIG, etc.)
    swap,       // SWAP, ROT (reorder, no copy/destroy)
    inspect,    // SPEEK, SIZE (read-only, no mutation)
};

pub const LinearityError = error{
    CannotDuplicateLinear,
    CannotDiscardLinear,
    CannotDuplicateAffine,
    CannotDiscardRelevant,
    InvalidLinearityType,
};

pub fn checkLinearity(linearity: LinearityType, operation: LinearityOperation) LinearityError!void {
    switch (linearity) {
        .linear => switch (operation) {
            .duplicate => return error.CannotDuplicateLinear,
            .discard => return error.CannotDiscardLinear,
            .consume, .swap, .inspect => {},
        },
        .affine => switch (operation) {
            .duplicate => return error.CannotDuplicateAffine,
            .discard, .consume, .swap, .inspect => {},
        },
        .relevant => switch (operation) {
            .discard => return error.CannotDiscardRelevant,
            .duplicate, .consume, .swap, .inspect => {},
        },
        .debug => {},  // All operations allowed
    }
}

/// Extract linearity type from a cell's header bytes
pub fn getLinearity(cell: *const [1024]u8) LinearityType {
    // Linearity is at offset 16, 4 bytes, little-endian
    const lin_bytes = cell[constants.HEADER_OFFSET_LINEARITY..][0..4];
    const lin_value = std.mem.readIntLittle(u32, lin_bytes);
    return @intToEnum(LinearityType, lin_value);
}
```

### D4.2 — Linearity-Aware Stack Operations

The PDA from Phase 3 must be extended. When linearity enforcement is active, stack operations check the cell's linearity before executing:

```zig
// In pda.zig — extend existing operations
pub fn sdup_enforced(self: *PDA) PDAError!void {
    const cell = try self.speek();
    const lin = linearity.getLinearity(cell);
    try linearity.checkLinearity(lin, .duplicate);
    try self.sdup();
}

pub fn sdrop_enforced(self: *PDA) PDAError!void {
    const cell = try self.speek();
    const lin = linearity.getLinearity(cell);
    try linearity.checkLinearity(lin, .discard);
    try self.sdrop();
}

// SWAP and ROT don't copy or destroy — they reorder
pub fn sswap_enforced(self: *PDA) PDAError!void {
    // No linearity check needed — reordering is always allowed
    try self.sswap();
}
```

**Critical**: The non-enforced operations from Phase 3 remain available for scripts that don't operate on typed cells (e.g., raw Bitcoin Script execution without semantic objects).

### D4.3 — `opcodes/plexus.zig` (Plexus Custom Opcodes 0xC0-0xCF)

```zig
pub fn executePlexus(pda: *PDA, opcode: u8) PDAError!void {
    switch (opcode) {
        0xC0 => try opCheckLinear(pda),
        0xC1 => try opCheckAffine(pda),
        0xC2 => try opCheckRelevant(pda),
        0xC3 => try opCheckDomainFlag(pda),
        0xC4 => try opCheckTypeHash(pda),
        0xC5...0xCF => return error.ReservedOpcode,
        else => unreachable,
    }
}

/// 0xC0 OP_CHECKLINEAR
/// Pop top cell. If its linearity != LINEAR, fail. Otherwise push TRUE.
fn opCheckLinear(pda: *PDA) PDAError!void {
    const cell = try pda.speek();
    const lin = linearity.getLinearity(cell);
    if (lin != .linear) return error.LinearityCheckFailed;
    // Leave cell on stack, push TRUE
    try pushTrue(pda);
}

/// 0xC3 OP_CHECKDOMAINFLAG
/// Pop expected flag value (u32). Pop cell. Check cell's domain flag matches.
fn opCheckDomainFlag(pda: *PDA) PDAError!void {
    const expected_flag = try popU32(pda);
    const cell = try pda.speek();
    const actual_flag = extractDomainFlag(cell);
    if (actual_flag != expected_flag) return error.DomainFlagMismatch;
    try pushTrue(pda);
}

/// 0xC4 OP_CHECKTYPEHASH
/// Pop expected hash (32 bytes). Pop cell. Compare type_hash field.
fn opCheckTypeHash(pda: *PDA) PDAError!void {
    const expected = try popBytes(pda, 32);
    const cell = try pda.speek();
    const actual = cell[constants.HEADER_OFFSET_TYPE_HASH..][0..32];
    if (!std.mem.eql(u8, actual, expected)) return error.TypeHashMismatch;
    try pushTrue(pda);
}
```

### D4.4 — Executor integration

Update `executor.zig` from Phase 3 to dispatch Plexus opcodes:

```zig
// Replace the Phase 3 stub:
} else if (opcode >= 0xC0 and opcode <= 0xCF) {
    try plexus.executePlexus(pda, opcode);
}
```

---

## TDD Gate — Tests That Must Pass

### Test 1: Linearity enforcement (Zig)
```zig
// linearity_conformance.zig

// LINEAR
test "LINEAR cell: DUP fails with CannotDuplicateLinear" { ... }
test "LINEAR cell: DROP fails with CannotDiscardLinear" { ... }
test "LINEAR cell: OVER fails with CannotDuplicateLinear" { ... }
test "LINEAR cell: PICK fails with CannotDuplicateLinear" { ... }
test "LINEAR cell: consume (CHECKSIG context) succeeds" { ... }
test "LINEAR cell: SWAP succeeds (reorder, no copy)" { ... }
test "LINEAR cell: inspect (SPEEK) succeeds" { ... }

// AFFINE
test "AFFINE cell: DUP fails with CannotDuplicateAffine" { ... }
test "AFFINE cell: DROP succeeds" { ... }
test "AFFINE cell: consume succeeds" { ... }
test "AFFINE cell: SWAP succeeds" { ... }

// RELEVANT
test "RELEVANT cell: DUP succeeds" { ... }
test "RELEVANT cell: DROP fails with CannotDiscardRelevant" { ... }
test "RELEVANT cell: OVER succeeds" { ... }
test "RELEVANT cell: consume succeeds" { ... }

// DEBUG
test "DEBUG cell: all operations succeed" { ... }

// Edge cases
test "invalid linearity value (0 or 5+) returns InvalidLinearityType" { ... }
test "getLinearity reads from correct header offset" { ... }
```

### Test 2: Plexus opcodes (Zig)
```zig
// plexus_conformance.zig
test "OP_CHECKLINEAR (0xC0): passes on LINEAR cell" { ... }
test "OP_CHECKLINEAR (0xC0): fails on AFFINE cell" { ... }
test "OP_CHECKAFFINE (0xC1): passes on AFFINE cell" { ... }
test "OP_CHECKRELEVANT (0xC2): passes on RELEVANT cell" { ... }
test "OP_CHECKDOMAINFLAG (0xC3): passes on matching flag" { ... }
test "OP_CHECKDOMAINFLAG (0xC3): fails on mismatched flag" { ... }
test "OP_CHECKTYPEHASH (0xC4): passes on matching hash" { ... }
test "OP_CHECKTYPEHASH (0xC4): fails on mismatched hash" { ... }
test "reserved opcodes 0xC5-0xCF return ReservedOpcode" { ... }
```

### Test 3: Integrated script with linearity (Zig)
```zig
test "script: push LINEAR cell, OP_CHECKLINEAR, OP_CHECKSIG" { ... }
test "script: push AFFINE cell, attempt OP_DUP, fails" { ... }
test "script: push RELEVANT cell, OP_DUP succeeds, OP_DROP fails" { ... }
test "script: push LINEAR cell, OP_CHECKDOMAINFLAG with EDGE_CREATION" { ... }
```

### Test 4: Cross-language linearity (TypeScript)
```typescript
// linearity_compat.test.ts
test("Zig rejects same operations as semantos-core validator", () => {
    // For each semantic type, verify Zig and semantos-core agree on what's allowed/rejected
});

test("kernel_get_type_class returns correct linearity after script execution", () => { ... });
```

---

## Phase Completion Criteria

You are **done with Phase 4** when ALL of the following are true:

1. `zig build test` passes all linearity_conformance and plexus_conformance tests
2. Linearity enforcement matches `FORTH:LINEARITY` — same inputs, same accept/reject decisions
3. All 5 Plexus opcodes (0xC0-0xC4) execute correctly
4. Reserved opcodes (0xC5-0xCF) return `ReservedOpcode` error
5. Linearity-aware stack operations integrate cleanly with Phase 3's 2-PDA
6. `kernel_get_type_class` WASM export returns correct linearity for the last-executed script
7. Cross-language tests confirm Zig and semantos-core agree on linearity rules
8. No panics — all linearity violations return explicit error codes

## What NOT To Do

- Do not implement capability token verification logic — that's Phase 5
- Do not implement BEEF/BUMP integration — that's Phase 5
- Do not break Phase 3's standard opcode tests — linearity enforcement is additive, not a replacement
- Do not hardcode domain flag values — they come from constants.zig

---

## Next Phase

Phase 4 output feeds into **Phase 5: BEEF/BUMP Host Function Integration and Capability Token Verification**.

---

## Post-Implementation Errata

**Implementation date**: 2026-03-27
**Test results**: 240/240 Zig tests pass, 56/56 relevant TS tests pass, WASM binary 28KB.

### E-P4.1 — Opcode mapping expanded from 5 to 8 (RECONCILIATION)

**Files**: `opcodes/plexus.zig`, `PHASE-4-PROMPT.md`
**Impact**: The original plan specified 5 opcodes (0xC0-0xC4) with 0xC5-0xCF reserved. During implementation planning, the SDK's `opcodes.ts` was found to define 0xC3=CHECKCAPABILITY and 0xC4=CHECKIDENTITY, which conflicted with this plan's 0xC3=CHECKDOMAINFLAG and 0xC4=CHECKTYPEHASH. Resolution: SDK assignments took priority. The plan's CHECKDOMAINFLAG and CHECKTYPEHASH were bumped to 0xC6 and 0xC7. An ASSERTLINEAR opcode was added at 0xC5 (matching the SDK). Final reconciled mapping:

| Opcode | Name | Original Plan |
|--------|------|---------------|
| 0xC0 | CHECKLINEARTYPE | same |
| 0xC1 | CHECKAFFINETYPE | same |
| 0xC2 | CHECKRELEVANTTYPE | same |
| 0xC3 | CHECKCAPABILITY | was CHECKDOMAINFLAG |
| 0xC4 | CHECKIDENTITY | was CHECKTYPEHASH |
| 0xC5 | ASSERTLINEAR | was reserved |
| 0xC6 | CHECKDOMAINFLAG | new slot |
| 0xC7 | CHECKTYPEHASH | new slot |
| 0xC8-0xCF | reserved | same (narrower range) |

This is not a bug — the reconciliation was deliberate and documented in PHASE-4-PROMPT.md before implementation began.

### E-P4.2 — Enforced wrappers read linearity from full Cell buffer, not length-bounded slice (NOTE)

**File**: `pda.zig`, lines 411-559
**Impact**: Low. The enforced wrappers call `linearity.getLinearity(&self.main_stack[idx])` which passes the full 1024-byte Cell array to `getLinearity`. This is correct — `getLinearity` only reads 4 bytes at offset 16 and performs its own bounds check. However, the cell's effective data length (stored in `main_lengths[idx]`) is not consulted. A cell with `main_lengths[idx] = 10` (only 10 bytes of real data) would still pass the getLinearity bounds check because the underlying Cell array is always 1024 bytes. In practice this is a non-issue: a 10-byte stack item is not a valid semantic object header and the linearity bytes at offset 16 would be zero (Cell arrays are zero-initialized), which fails with `invalid_linearity_type`. But if zero were ever assigned as a valid linearity value, this would silently accept garbage.

**Recommendation**: Consider checking `main_lengths[idx] >= HEADER_SIZE` (256) before reading linearity in a future hardening pass. Not blocking.

### E-P4.3 — sswap_enforced, srot_enforced, sroll_enforced, s2swap_enforced, s2rot_enforced skip enforcement check entirely (NOTE)

**File**: `pda.zig`, lines 431-433, 473-475, 489-491, 528-530, 544-546
**Impact**: None — this is correct behaviour. Swap/rotate operations reorder stack elements without copying or destroying them. The Forth reference (`linearity-enforcement.fs`) confirms: `S-SWAP-ENFORCED` allows all linearity types. These wrappers exist purely for call-site uniformity — `standard.zig` can unconditionally call the `_enforced` variant without branching on operation type.

### E-P4.4 — cellToU32 in plexus.zig uses @constCast on data parameter (FRAGILE)

**File**: `opcodes/plexus.zig`, line 149
**Impact**: Low. The `cellToU32` helper calls `pda_mod.cellToI64(@constCast(data))` — the `@constCast` is needed because `cellToI64` takes `[]const u8` but the local slice binding is `[]const u8`. This is a Zig API mismatch, not a mutation. `cellToI64` does not write to the data. However, `@constCast` is a code smell that could mask future bugs if `cellToI64` ever gains write behaviour.

**Recommendation**: Change `cellToI64` signature to take `[]const u8` in a future cleanup pass.

### E-P4.5 — OP_CHECKCAPABILITY pops cap type value before peeking cell (DESIGN CHOICE)

**File**: `opcodes/plexus.zig`, lines 61-78
**Impact**: None — but worth documenting. The opcode pops the expected capability type from the stack first, then peeks the cell (now at top). This means the cap type argument must be pushed after the cell in script. Script pattern: `<cell> <cap_type_byte> OP_CHECKCAPABILITY`. If the stack has only one element, the pop succeeds but the peek fails with stack_underflow. This is the correct Bitcoin Script convention (arguments on top, subject below).

### E-P4.6 — kernel_get_type_class returns -1 for DEBUG type (DESIGN CHOICE)

**File**: `main.zig`, lines 79-91
**Impact**: Intentional. The `PlexusKernelWasm` interface's `TypeClassification` enum defines LINEAR=0, AFFINE=1, RELEVANT=2, UNCLASSIFIED=-1. There is no classification for DEBUG because DEBUG is a development-only type not expected in production scripts. Returning -1 (UNCLASSIFIED) for DEBUG is correct per the SDK interface contract. If a future SDK version adds a DEBUG classification, this mapping will need updating.

### E-P4.7 — No aliasing protection in enforced PDA wrappers (FRAGILE)

**File**: `pda.zig`, enforced wrapper methods
**Impact**: The Phase 3 errata (E-P3.4) warned about aliasing hazards in `spop` — popping returns a slice into the Cell array, and a subsequent push could overwrite it. The enforced wrappers use `speek()` (not `spop()`) to inspect cells before calling the non-enforced operation, so the aliasing risk is lower: peek doesn't modify the stack pointer. However, the Plexus opcodes in `plexus.zig` do use `spop()` followed by `speek()` (e.g., OP_CHECKIDENTITY pops the expected ID then peeks the cell). These correctly copy the popped data to a local `[16]u8` buffer before the peek, which is the right pattern. No current bug, but any new plexus opcode that pops-then-reads without copying would hit the aliasing issue.

### E-P4.8 — Two pre-existing test failures in bca_compat.test.ts (PRE-EXISTING)

**File**: `tests-ts/bca_compat.test.ts`
**Impact**: None — these failures predate Phase 4. One test asserts WASM binary under 20KB (an early Phase 0 expectation; binary is now 28KB). Another asserts `kernel_init` returns NOT_IMPLEMENTED (a Phase 0 stub that was implemented in Phase 1). These should be updated to match current reality but are not Phase 4 regressions.

### Summary Table

| ID | Severity | File | Issue |
|----|----------|------|-------|
| E-P4.1 | RECONCILIATION | plexus.zig | Opcode mapping expanded 5→8, SDK took priority |
| E-P4.2 | NOTE | pda.zig | Enforced wrappers don't check main_lengths |
| E-P4.3 | NOTE | pda.zig | Swap/rotate wrappers skip enforcement (correct) |
| E-P4.4 | FRAGILE | plexus.zig | @constCast on cellToI64 input |
| E-P4.5 | DESIGN CHOICE | plexus.zig | Cap type popped before cell peek |
| E-P4.6 | DESIGN CHOICE | main.zig | DEBUG returns -1 (UNCLASSIFIED) |
| E-P4.7 | FRAGILE | pda.zig + plexus.zig | Aliasing OK now but fragile for new opcodes |
| E-P4.8 | PRE-EXISTING | bca_compat.test.ts | Two stale tests from Phase 0 |
