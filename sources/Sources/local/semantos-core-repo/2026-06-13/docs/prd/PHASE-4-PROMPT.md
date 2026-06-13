---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-4-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.658907+00:00
---

# Phase 4 Prompt

**STATUS: IMPLEMENTED** — 2026-03-27. All deliverables complete. See `PHASE-4-PLEXUS-OPCODES.md` Post-Implementation Errata for notes.

Copy everything below the line into a fresh Claude Code session.

---

## Prompt Start

Read these documents in full before producing any output:

1. `/Users/toddprice/projects/semantos-core/docs/prd/README.md`
2. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-4-PLEXUS-OPCODES.md`
3. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-3-2PDA-CORE.md` — read the **Post-Implementation Errata** section at the bottom for context on what Phase 3 delivered and what was fixed.

Then read these source files — they are the authoritative references for the Plexus SDK type system. The SDK is TypeScript and is not fully shipped yet, but the types are stable enough to implement the Zig cell-level enforcement:

4. `/Users/toddprice/projects/semantos-core/src/cell-engine/opcodes.ts` — Plexus opcode definitions (0xC0-0xCF). **Note the opcode mapping differs from Phase 4 plan** — reconcile using the rules below.
5. `/Users/toddprice/projects/semantos-core/src/types/semantic-objects.ts` — SemanticType enum, LinearObject, AffineObject, RelevantObject, ConsumptionProof, RevocationProof, type guards.
6. `/Users/toddprice/projects/semantos-core/src/types/capability.ts` — CapabilityToken (LINEAR), CapabilityType enum, CapabilityConstraints.
7. `/Users/toddprice/projects/semantos-core/src/types/domain-flags.ts` — DomainFlag type, well-known flags (EDGE_CREATION through METERING), 3-tier ranges, classifyFlag(), toProtocolId().
8. `/Users/toddprice/projects/semantos-core/src/types/transfer.ts` — TransferRecord (AFFINE), TransferMetadata.
9. `/Users/toddprice/projects/semantos-core/src/types/metering.ts` — MeteringChannel, TickProof, SettlementRecord, ChannelState.
10. `/Users/toddprice/projects/semantos-core/src/compiler/validator.ts` — validateConsumption, validateAcknowledgement, validateDiscard, validateRevocation, validateCapabilitySpend, canConsume, isConsumed.
11. `/Users/toddprice/projects/semantos-core/src/cell-engine/wasm-interface.ts` — PlexusKernelWasm (the WASM export contract), PlexusKernelHostImports, TypeClassification enum.
12. `/Users/toddprice/semantos/semantos-gift-pack/forth/linearity-enforcement.fs` — The Forth reference implementation. S-DUP-ENFORCED, S-DROP-ENFORCED, S-SWAP-ENFORCED, S-OVER-ENFORCED. This is the authoritative behaviour specification.

### What already exists (Phase 0 + Phase 1 + Phase 2 + Phase 3 output)

Phases 0-3 are complete and verified. Everything lives at `/Users/toddprice/projects/semantos-core/`:

```
semantos-core/
├── package.json                   # @semantos/core v0.3.0
├── docs/prd/
└── packages/
    ├── constants/
    │   └── constants.json         # Single source of truth (includes domain flags, header offsets, linearity values)
    ├── protocol-types/
    │   └── src/index.ts           # CellHeader, BCA types, enums
    └── cell-engine/
        ├── build.zig              # Multi-target build with test targets
        ├── zig-out/bin/
        │   └── cell-engine.wasm   # ~25KB — all Phase 0-3 functionality
        ├── src/
        │   ├── main.zig           # WASM exports (Phase 0-3)
        │   ├── constants.zig      # Generated — ALL header offsets, domain flags, linearity values
        │   ├── cell.zig           # packCell, unpackCell
        │   ├── commerce.zig       # CommerceExtension + OnChainBinding
        │   ├── multicell.zig      # Multi-cell pack/unpack
        │   ├── bca.zig            # BCA derivation
        │   ├── host.zig           # Comptime host dispatch (SHA256, HASH160, CHECKSIG)
        │   ├── errors.zig         # KernelError enum (codes 0-21, 255)
        │   ├── allocator.zig      # Bump arena allocator
        │   ├── pda.zig            # Dual-stack 2-PDA (1024×1KB main, 256×1KB aux) — FULLY WORKING
        │   ├── sighash.zig        # BIP143 preimage (streaming hash, all 6 SIGHASH modes)
        │   ├── executor.zig       # Script executor with unlock→lock sequencing, single-step debugger
        │   ├── linearity.zig      # STUB — you are implementing this
        │   └── opcodes/
        │       ├── standard.zig   # All standard Bitcoin Script opcodes — FULLY WORKING
        │       ├── macro.zig      # Craig macros 0xB0-0xB8 — FULLY WORKING
        │       └── plexus.zig     # STUB — you are implementing this
        ├── tests/
        │   ├── smoke_test.zig
        │   ├── cell_conformance.zig
        │   ├── multicell_conformance.zig
        │   ├── commerce_conformance.zig
        │   ├── bca_conformance.zig
        │   ├── allocator_conformance.zig
        │   ├── pda_conformance.zig        # 30+ stack operation tests
        │   ├── opcodes_conformance.zig    # Standard opcode tests
        │   ├── macro_conformance.zig      # Craig macro tests
        │   └── executor_conformance.zig   # Executor tests incl. branch skip regression tests
        └── tests-ts/
            └── kernel_compat.test.ts      # 20 cross-language WASM tests
```

### Cell Header Layout (from constants.zig — CANONICAL)

These are the byte offsets into the 256-byte cell header. You MUST use these exact offsets when reading linearity, domain flags, type hashes, etc. from cell bytes on the PDA stack:

```
Offset  Size  Field
──────  ────  ─────
0       16    magic (4 × u32: 0xDEADBEEF, 0xCAFEBABE, 0x13371337, 0x42424242)
16      4     linearity (u32 LE: 1=LINEAR, 2=AFFINE, 3=RELEVANT, 4=DEBUG)
20      4     version (u32 LE)
24      4     flags (u32 LE — this is the domain flag)
28      2     ref_count (u16 LE)
30      32    type_hash (SHA256 of type definition)
62      16    owner_id (truncated cert ID)
78      8     timestamp (u64 LE, Unix ms)
86      4     cell_count (u32 LE)
90      4     payload_total (u32 LE)
94      1     commerce_phase (u8)
95      1     commerce_dimension (u8)
96      32    commerce_parent_hash (SHA256)
128     32    commerce_prev_state (SHA256)
160     32    binding_txid (32 bytes BE)
192     4     binding_vout (u32 LE)
196     24    binding_bump_hash (truncated)
220     4     binding_derivation_index (u32 LE)
224-255 32    reserved/padding
```

### Opcode Mapping — Reconciliation

The Phase 4 plan (PHASE-4-PLEXUS-OPCODES.md) and the SDK (opcodes.ts) have different opcode assignments. Use this reconciled mapping:

| Byte | Name | Source | Behaviour |
|------|------|--------|-----------|
| 0xC0 | OP_CHECKLINEARTYPE | Both agree | Peek top cell, verify linearity == LINEAR, push TRUE |
| 0xC1 | OP_CHECKAFFINETYPE | Both agree | Peek top cell, verify linearity == AFFINE, push TRUE |
| 0xC2 | OP_CHECKRELEVANTTYPE | Both agree | Peek top cell, verify linearity == RELEVANT, push TRUE |
| 0xC3 | OP_CHECKCAPABILITY | SDK (opcodes.ts) | Pop expected capability type (u8). Peek top cell. Verify cell linearity is LINEAR AND cell has a valid capability type marker. See implementation notes below. |
| 0xC4 | OP_CHECKIDENTITY | SDK (opcodes.ts) | Pop expected owner_id (16 bytes). Peek top cell. Compare cell's owner_id (offset 62, 16 bytes). Push TRUE if match. |
| 0xC5 | OP_ASSERTLINEAR | SDK (opcodes.ts) | Peek top cell. If linearity != LINEAR, script fails (like VERIFY). Does NOT push TRUE — it's an assertion. |
| 0xC6 | OP_CHECKDOMAINFLAG | Phase 4 plan | Pop expected flag (u32). Peek top cell. Compare cell's domain flag (offset 24, 4 bytes LE). Push TRUE if match. |
| 0xC7 | OP_CHECKTYPEHASH | Phase 4 plan | Pop expected hash (32 bytes). Peek top cell. Compare type_hash (offset 30, 32 bytes). Push TRUE if match. |
| 0xC8-0xCF | Reserved | — | Return ReservedOpcode error. |

**Why this mapping**: The SDK defines 0xC3-0xC5. The Phase 4 plan defines CHECKDOMAINFLAG and CHECKTYPEHASH. Both are needed. We assign the SDK's opcodes first (they're the shipping product), then append the plan's opcodes at 0xC6-0xC7.

### OP_CHECKCAPABILITY Implementation Notes

The Plexus SDK defines 6 capability types (from `capability.ts`):

```
RECOVERY = 0        (key rotation, backup restoration)
PERMISSION = 1      (delegation on behalf of another identity)
DATA_ACCESS = 2     (read-only proofs, document sharing)
COMPUTE_DELEGATION = 3  (offloaded signing, proof generation)
METERED_ACCESS = 4  (usage quota on metered resources)
TRANSFER = 5        (capability to transfer assets to new parent)
```

In the cell encoding, the capability type is stored as a u8 at **payload offset 0** (byte 256 of the cell — first byte of the 768-byte payload). This is a convention for Phase 4; it does not need to match a finalized wire format since the SDK is still evolving.

OP_CHECKCAPABILITY logic:
1. Pop top of stack → interpret first byte as expected capability type (u8, 0-5)
2. Peek second item on stack (the cell to check)
3. Verify: cell linearity (offset 16) == LINEAR (1)
4. Verify: cell payload byte 0 (offset 256) == expected capability type
5. If both checks pass, push TRUE. Otherwise, script fails.

**Partial implementation is acceptable** — if the full capability constraint checking (expiry, geo bounds, max invocations) is too complex for Phase 4, implement the type check only and add a `// TODO Phase 5: constraint validation` comment. The important thing is the cell layout convention and the opcode dispatch.

### OP_CHECKIDENTITY Implementation Notes

BRC-52 identity certificates bind to cells via the `owner_id` field (offset 62, 16 bytes). This is a truncated hash of the identity certificate. OP_CHECKIDENTITY compares this field against an expected value popped from the stack.

Logic:
1. Pop top of stack → take first 16 bytes as expected owner_id
2. Peek second item on stack (the cell to check)
3. Compare cell bytes [62..78] with expected owner_id
4. If match, push TRUE. Otherwise, script fails.

### Linearity Enforcement — The Core of Phase 4

This is where the Zig 2-PDA diverges from a standard Bitcoin Script engine. The Forth reference (`linearity-enforcement.fs`) is authoritative.

**Enforcement is opt-in per script execution.** The executor has an `enforcement_enabled` flag. When enabled, every stack operation checks the linearity of affected cells before executing. When disabled (default for raw Bitcoin Script), operations work exactly as Phase 3.

**Rules (from Forth reference + SDK validator.ts):**

| Operation | LINEAR | AFFINE | RELEVANT | DEBUG |
|-----------|--------|--------|----------|-------|
| DUP/OVER/PICK/2DUP/3DUP | REJECT | REJECT | ALLOW | ALLOW |
| DROP/2DROP/NIP | REJECT* | ALLOW | REJECT | ALLOW |
| SWAP/ROT/2SWAP/2ROT/ROLL | ALLOW | ALLOW | ALLOW | ALLOW |
| Consume (CHECKSIG, etc.) | ALLOW | ALLOW | ALLOW | ALLOW |
| Inspect (SPEEK, SIZE, DEPTH) | ALLOW | ALLOW | ALLOW | ALLOW |

*LINEAR DROP: The Forth reference marks the object as consumed before dropping. In the Zig implementation, LINEAR cells cannot be silently discarded — they must be consumed through a cryptographic operation (CHECKSIG/CHECKMULTISIG) or explicitly consumed via OP_ASSERTLINEAR. If you need to remove a LINEAR cell from the stack, the script must first prove it was properly consumed.

**However**: For Phase 4, implement the simpler Forth model where LINEAR DROP fails with `CannotDiscardLinear`. The "consumed via CHECKSIG" refinement is Phase 5 when we have full transaction context integration.

### Domain Flag Tier System

From `domain-flags.ts`, domain flags have three tiers:

```
Well-Known:  [0x00000001, 0x000000FF]  — Plexus protocol-level
Extended:    [0x00000100, 0x0000FFFF]  — Dusk-reserved extensions
Sovereign:   [0x00010000, 0xFFFFFFFF]  — Client application use
```

Well-known flags already in `constants.zig`:
```
EDGE_CREATION      = 1   (0x01)
SIGNING            = 2   (0x02)
ENCRYPTION         = 3   (0x03)
MESSAGING          = 4   (0x04)
ATTESTATION        = 5   (0x05)
CHILD_CREATION     = 6   (0x06)
PERMISSION_GRANT   = 7   (0x07)
DATA_SOVEREIGNTY   = 8   (0x08)
SCHEMA_SIGNING     = 9   (0x09)
METERING           = 10  (0x0A)
```

OP_CHECKDOMAINFLAG just compares the cell's flag value — it doesn't need tier classification. But add a `classifyFlag()` helper to `linearity.zig` for future use:

```zig
pub fn classifyFlag(flag: u32) enum { well_known, extended, sovereign, reserved } {
    if (flag == 0) return .reserved;
    if (flag >= 1 and flag <= 0xFF) return .well_known;
    if (flag >= 0x100 and flag <= 0xFFFF) return .extended;
    return .sovereign;
}
```

### PDA Integration — Enforcement Mode

The PDA struct needs a boolean flag and enforced wrappers:

```zig
// In pda.zig — add to PDA struct:
enforcement_enabled: bool = false,

pub fn enableEnforcement(self: *PDA) void { self.enforcement_enabled = true; }
pub fn disableEnforcement(self: *PDA) void { self.enforcement_enabled = false; }

// Enforced operations — check linearity before executing
pub fn sdup_enforced(self: *PDA) !void {
    if (self.enforcement_enabled) {
        const top = try self.speek();
        const lin = linearity.getLinearity(top.data);
        try linearity.checkLinearity(lin, .duplicate);
    }
    try self.sdup();
}
```

**Critical**: Do NOT modify the existing non-enforced operations from Phase 3. They must continue to work for raw Bitcoin Script. The enforced operations are NEW methods that check linearity first.

### Executor Integration

The executor needs:
1. An `enforcement_enabled` field on `ExecutionContext`
2. When enforcement is enabled, dispatch stack-modifying opcodes to enforced versions
3. A new WASM export `kernel_set_enforcement(enabled: u32)` to toggle enforcement
4. Update `kernel_get_type_class()` to read the linearity from the top-of-stack cell after execution

The standard opcode handler (`standard.zig`) needs a branching path:
```zig
// In the stack manipulation switch:
OP_DUP => {
    if (ctx.enforcement_enabled) return p.sdup_enforced()
    else return p.sdup();
},
```

### WASM Export Additions

Add these exports to `main.zig`:

```zig
export fn kernel_set_enforcement(enabled: u32) callconv(.C) void;
export fn kernel_get_type_class() callconv(.C) i32;  // Already declared in Phase 3 but returns -1; now implement properly
```

`kernel_get_type_class` should:
1. Check if the main stack is non-empty
2. Read the linearity field from the top-of-stack cell (offset 16, 4 bytes LE)
3. Return: 0=LINEAR, 1=AFFINE, 2=RELEVANT, -1=unclassified (matches `TypeClassification` enum in wasm-interface.ts)

### Deliverables

#### D4.1 — `linearity.zig` (replace stub)

Full linearity module:
- `LinearityType` enum matching constants.zig values (1=LINEAR, 2=AFFINE, 3=RELEVANT, 4=DEBUG)
- `LinearityOperation` enum (duplicate, discard, consume, swap, inspect)
- `checkLinearity(type, op)` — returns error or void
- `getLinearity(cell_data: []const u8)` — reads offset 16, 4 bytes LE
- `getDomainFlag(cell_data: []const u8)` — reads offset 24, 4 bytes LE
- `getTypeHash(cell_data: []const u8)` — reads offset 30, 32 bytes
- `getOwnerId(cell_data: []const u8)` — reads offset 62, 16 bytes
- `getCapabilityType(cell_data: []const u8)` — reads offset 256, 1 byte (payload byte 0)
- `classifyFlag(flag: u32)` — tier classification
- Error types: CannotDuplicateLinear, CannotDiscardLinear, CannotDuplicateAffine, CannotDiscardRelevant, InvalidLinearityType, LinearityCheckFailed, DomainFlagMismatch, TypeHashMismatch, OwnerIdMismatch, CapabilityTypeMismatch

#### D4.2 — PDA enforcement methods in `pda.zig`

Add to PDA struct:
- `enforcement_enabled: bool`
- `enableEnforcement()`, `disableEnforcement()`
- `sdup_enforced()`, `sdrop_enforced()`, `sswap_enforced()`, `sover_enforced()`, `srot_enforced()`
- `spick_enforced(n)`, `sroll_enforced(n)`, `snip_enforced()`, `stuck_enforced()`
- `s2dup_enforced()`, `s3dup_enforced()`, `s2drop_enforced()`, `s2swap_enforced()`
- `s2over_enforced()`, `s2rot_enforced()`

Each enforced method: if `enforcement_enabled`, read linearity from top/affected cell, call `checkLinearity()`, then delegate to the non-enforced version.

#### D4.3 — `opcodes/plexus.zig` (replace stub)

Implement 0xC0-0xC7, reserve 0xC8-0xCF. Follow the reconciled opcode mapping above.

#### D4.4 — Executor integration in `executor.zig`

- Add `enforcement_enabled` to ExecutionContext
- When enabled, use enforced PDA methods for stack-modifying opcodes
- Dispatch 0xC0-0xCF to `plexus.executePlexus()` (replace the Phase 3 `not_implemented` stub)

#### D4.5 — WASM exports in `main.zig`

- `kernel_set_enforcement(enabled: u32)`
- Implement `kernel_get_type_class()` properly (read linearity from top-of-stack cell)

#### D4.6 — Error codes in `errors.zig`

Add Phase 4 error codes:
```zig
cannot_duplicate_linear = 22,
cannot_discard_linear = 23,
cannot_duplicate_affine = 24,
cannot_discard_relevant = 25,
invalid_linearity_type = 26,
linearity_check_failed = 27,
domain_flag_mismatch = 28,
type_hash_mismatch = 29,
owner_id_mismatch = 30,
capability_type_mismatch = 31,
reserved_opcode = 32,
```

### TDD Gate — Tests That Must Pass

#### Test target: `zig build test-linearity`

Create `tests/linearity_conformance.zig`:

```zig
// Linearity rule enforcement
test "LINEAR: DUP fails with CannotDuplicateLinear" { ... }
test "LINEAR: DROP fails with CannotDiscardLinear" { ... }
test "LINEAR: OVER fails with CannotDuplicateLinear" { ... }
test "LINEAR: PICK fails with CannotDuplicateLinear" { ... }
test "LINEAR: 2DUP fails with CannotDuplicateLinear" { ... }
test "LINEAR: 3DUP fails with CannotDuplicateLinear" { ... }
test "LINEAR: SWAP succeeds (reorder, no copy)" { ... }
test "LINEAR: ROT succeeds" { ... }
test "LINEAR: consume (speek/inspect) succeeds" { ... }

test "AFFINE: DUP fails with CannotDuplicateAffine" { ... }
test "AFFINE: DROP succeeds" { ... }
test "AFFINE: SWAP succeeds" { ... }
test "AFFINE: inspect succeeds" { ... }

test "RELEVANT: DUP succeeds" { ... }
test "RELEVANT: DROP fails with CannotDiscardRelevant" { ... }
test "RELEVANT: OVER succeeds" { ... }
test "RELEVANT: consume succeeds" { ... }

test "DEBUG: all operations succeed" { ... }
test "invalid linearity value returns InvalidLinearityType" { ... }

// Header field extraction
test "getLinearity reads offset 16, 4 bytes LE" { ... }
test "getDomainFlag reads offset 24, 4 bytes LE" { ... }
test "getTypeHash reads offset 30, 32 bytes" { ... }
test "getOwnerId reads offset 62, 16 bytes" { ... }
test "getCapabilityType reads offset 256, 1 byte" { ... }
test "classifyFlag: well-known, extended, sovereign, reserved" { ... }

// Enforcement toggle
test "enforcement disabled: DUP LINEAR cell succeeds" { ... }
test "enforcement enabled: DUP LINEAR cell fails" { ... }
test "enforcement can be toggled mid-session" { ... }
```

**How to build test cells**: Create a helper function that builds a 1024-byte cell with specific header values:
```zig
fn makeTestCell(linearity: u32, domain_flag: u32, type_hash: [32]u8, owner_id: [16]u8) [1024]u8 {
    var cell: [1024]u8 = [_]u8{0} ** 1024;
    // Write magic
    std.mem.writeInt(u32, cell[0..4], 0xDEADBEEF, .little);
    std.mem.writeInt(u32, cell[4..8], 0xCAFEBABE, .little);
    std.mem.writeInt(u32, cell[8..12], 0x13371337, .little);
    std.mem.writeInt(u32, cell[12..16], 0x42424242, .little);
    // Write linearity
    std.mem.writeInt(u32, cell[16..20], linearity, .little);
    // Write version
    std.mem.writeInt(u32, cell[20..24], 1, .little);
    // Write domain flag
    std.mem.writeInt(u32, cell[24..28], domain_flag, .little);
    // Write type hash
    @memcpy(cell[30..62], &type_hash);
    // Write owner_id
    @memcpy(cell[62..78], &owner_id);
    return cell;
}
```

#### Test target: `zig build test-plexus`

Create `tests/plexus_conformance.zig`:

```zig
test "OP_CHECKLINEARTYPE (0xC0): passes on LINEAR cell" { ... }
test "OP_CHECKLINEARTYPE (0xC0): fails on AFFINE cell" { ... }
test "OP_CHECKAFFINETYPE (0xC1): passes on AFFINE cell" { ... }
test "OP_CHECKRELEVANTTYPE (0xC2): passes on RELEVANT cell" { ... }

test "OP_CHECKCAPABILITY (0xC3): passes on LINEAR cell with matching capability type" { ... }
test "OP_CHECKCAPABILITY (0xC3): fails on non-LINEAR cell" { ... }
test "OP_CHECKCAPABILITY (0xC3): fails on mismatched capability type" { ... }

test "OP_CHECKIDENTITY (0xC4): passes on matching owner_id" { ... }
test "OP_CHECKIDENTITY (0xC4): fails on mismatched owner_id" { ... }

test "OP_ASSERTLINEAR (0xC5): passes on LINEAR cell (no stack push)" { ... }
test "OP_ASSERTLINEAR (0xC5): fails on AFFINE cell (script fails)" { ... }

test "OP_CHECKDOMAINFLAG (0xC6): passes on matching flag" { ... }
test "OP_CHECKDOMAINFLAG (0xC6): fails on mismatched flag" { ... }
test "OP_CHECKDOMAINFLAG (0xC6): works with METERING flag (0x0A)" { ... }

test "OP_CHECKTYPEHASH (0xC7): passes on matching 32-byte hash" { ... }
test "OP_CHECKTYPEHASH (0xC7): fails on mismatched hash" { ... }

test "reserved opcodes 0xC8-0xCF return ReservedOpcode" { ... }
```

#### Integrated script tests (add to executor_conformance.zig):

```zig
test "script: push LINEAR cell, OP_CHECKLINEARTYPE, succeeds" { ... }
test "script: push AFFINE cell, enforcement enabled, OP_DUP fails" { ... }
test "script: push RELEVANT cell, enforcement enabled, OP_DUP succeeds, OP_DROP fails" { ... }
test "script: push LINEAR cell, OP_ASSERTLINEAR, OP_CHECKDOMAINFLAG with METERING" { ... }
test "script: enforcement disabled, LINEAR cell DUP succeeds (raw Bitcoin mode)" { ... }
```

#### Cross-language tests (TypeScript):

Add to `tests-ts/kernel_compat.test.ts` or create `tests-ts/linearity_compat.test.ts`:

```typescript
test("kernel_set_enforcement export exists", () => { ... });
test("kernel_get_type_class returns LINEAR (0) for LINEAR cell", () => { ... });
test("kernel_get_type_class returns AFFINE (1) for AFFINE cell", () => { ... });
test("kernel_get_type_class returns RELEVANT (2) for RELEVANT cell", () => { ... });
test("kernel_get_type_class returns -1 for empty stack", () => { ... });
test("enforcement enabled: Plexus opcodes work through WASM", () => {
    // Write a LINEAR cell to WASM memory, load script with OP_CHECKLINEARTYPE, execute
});
```

### Build Integration

Add test targets to `build.zig`:
```zig
// Add to createModules and test targets:
"linearity"  → tests/linearity_conformance.zig
"plexus"     → tests/plexus_conformance.zig
```

### Phase Completion Criteria

You are **done with Phase 4** when ALL of the following are true:

1. `zig build test` passes all existing Phase 0-3 tests (no regressions) PLUS new linearity and plexus tests
2. Linearity enforcement matches the Forth reference: same inputs, same accept/reject decisions
3. All 8 Plexus opcodes (0xC0-0xC7) execute correctly
4. Reserved opcodes (0xC8-0xCF) return ReservedOpcode error
5. Enforcement toggle works: disabled = raw Bitcoin mode, enabled = linearity checking
6. `kernel_get_type_class()` returns correct values (0/1/2/-1) matching TypeClassification enum
7. `kernel_set_enforcement()` WASM export toggles enforcement from TypeScript
8. Cross-language tests confirm Zig enforcement decisions match validator.ts rules
9. Cell header field extraction uses EXACT offsets from constants.zig
10. No panics — all linearity violations return explicit error codes
11. WASM binary stays under 50KB
12. `bun test` passes all TypeScript tests

### What NOT To Do

- Do not modify Phase 3's non-enforced stack operations — they must remain as-is for raw Bitcoin Script
- Do not implement full capability constraint validation (expiry, geo bounds, max invocations) — that's Phase 5
- Do not implement BEEF/BUMP integration — that's Phase 5
- Do not hardcode domain flag values — read them from cells, compare against values from constants.zig
- Do not change WASM memory layout, stack sizes, or binary target settings
- Do not break any existing tests from Phase 0-3
- Do not implement the "consumed via CHECKSIG" refinement for LINEAR DROP — keep the simple Forth model where DROP always fails for LINEAR

### Aliasing Warning (from Phase 3 errata E-P3.4)

When implementing enforced operations, remember that `spop()` returns a `StackEntry` whose `.data` points into stack memory. A subsequent `spush()` can overwrite that memory. If your enforced operation needs to inspect a cell's header bytes AND ALSO push/pop, copy the relevant bytes to a local buffer first. This was already needed for OP_CAT and OP_SPLIT in Phase 3.

### Next Phase

Phase 4 output feeds into **Phase 5: BEEF/BUMP Host Function Integration and Capability Token Constraint Validation**, which adds SPV proof parsing, full capability constraint checking (expiry, geo, invocations), and the formats module.
