---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-3-2PDA-CORE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.665897+00:00
---

# Phase 3: 2-PDA Core — Stack Operations and Standard Opcodes

**Duration**: 3 weeks (with 40% buffer: ~30 days)
**Prerequisites**: Phase 2 complete — BCA derivation works, host_sha256 functional, WASM binary exports working.
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` (in this directory: `semantos-core/docs/prd/`)

---

## Context

Bitcoin Script is a Two-Stack Pushdown Automaton (2-PDA). Every Bitcoin transaction is validated by executing a script on this dual-stack machine. The Semantos Cell Engine implements this 2-PDA in Zig with one critical extension: each stack slot holds a full 1KB semantic cell (not just raw bytes), enabling typed, linearity-enforced computation.

This is the largest single phase of the implementation. It covers: the dual-stack engine, an arena allocator for deterministic memory, all standard Bitcoin Script opcodes (relevant subset), the Craig macro opcodes (0xB0-0xBF), and bounded execution enforcement.

**Craig Wright's 2-PDA model**: A single script is a bounded DFA — no loops, no recursion, always terminates. Turing completeness is achieved through transaction chaining (the blockchain is the tape). The Zig implementation MUST enforce these bounds.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `FORTH:2PDA` | `semantos-gift-pack/forth/bitcoin-2pda.fs` | **Primary stack reference.** CELL-SIZE=1024, MAIN-STACK-CELLS=1024, AUX-STACK-CELLS=256. SPUSH/SPOP/APUSH/APOP operations. Stack overflow/underflow checking. LIFO ordering. |
| `CORE:EXECUTOR` | `bitcoin-script/core/script-executor.fs` | **Full opcode reference** (38KB). Every standard Bitcoin Script opcode with complete implementation. This is the authoritative behaviour reference for edge cases. |
| `FORTH:MACROS` | `semantos-gift-pack/forth/craig-macros.fs` | Craig macro table 0xB0-0xBF. XSWAP-2(0xB0), XSWAP-3(0xB1), XSWAP-4(0xB2), XDROP-2(0xB3), XDROP-3(0xB4), XDROP-4(0xB5), XROT-3(0xB6), XROT-4(0xB7), HASHCAT(0xB8). REPEAT-OP for loop unrolling. |
| `CORE:CONSTANTS` | `bitcoin-script/core/script-constants.fs` | BSV opcode values, SIGHASH_FORKID (0x41). |
| `CORE:WASM` | `semantos-core/src/cell-engine/wasm-interface.ts` | `PlexusKernelWasm` interface — the WASM export contract. `kernel_init`, `kernel_reset`, `kernel_load_script`, `kernel_load_unlock`, `kernel_execute`, `kernel_get_type_class`, `kernel_get_opcount`, `kernel_get_error`, `kernel_stack_depth`, `kernel_stack_peek`. |
| `CORE:OPCODES` | `semantos-core/src/cell-engine/opcodes.ts` | Plexus opcode definitions. |
| `CASHLANES:SETTLEMENT` | `cashlanes/src/settlement/CooperativeSettlementBuilder.ts` | Production SIGHASH usage: fee input 0x82 (ACP\|NONE), multisig input 0x41 (ALL\|FORKID). Dual-input pattern. |
| `CASHLANES:PREIMAGE` | `cashlanes/metanet-desktop/src/routing/ChannelTransactionBuilder.ts` | `TransactionSignature.format()` preimage computation. Double SHA256. Reference for BIP143 serialization. |
| `CASHLANES:SIGFSM` | `cashlanes/src/settlement/SignatureExchangeFSM.ts` | 3-round signature exchange protocol. nSequence monotonic enforcement. `0xFFFFFFFF` = finality. |
| `CASHLANES:MULTISIG` | `cashlanes/src/settlement/MultisigUnlockingScriptBuilder.ts` | `OP_0 <sig1> <sig2>` unlocking script construction. DER + SIGHASH flag byte format. |
| `CASHLANES:INCREMENTAL` | `cashlanes/src/channels/IncrementalChannelManager.ts` | nSequence as version counter. Locktime=0 for final, 24h for non-final. |

---

## Deliverables

### D3.1 — `pda.zig` (Dual-Stack Engine)

```zig
pub const CELL_SIZE = constants.CELL_SIZE;           // 1024
pub const MAIN_STACK_DEPTH = constants.MAIN_STACK_CELLS;  // 1024
pub const AUX_STACK_DEPTH = constants.AUX_STACK_CELLS;    // 256

pub const Cell = [CELL_SIZE]u8;

pub const PDA = struct {
    main_stack: [MAIN_STACK_DEPTH]Cell,
    main_sp: u32,           // Stack pointer (top of stack index)
    aux_stack: [AUX_STACK_DEPTH]Cell,
    aux_sp: u32,
    opcount: u32,           // Instructions executed
    max_ops: u32,           // Hard limit (bounded execution)
    error_code: i32,        // 0 = OK, negative = error
    error_msg: [256]u8,     // Human-readable error

    pub fn init(max_ops: u32) PDA;
    pub fn reset(self: *PDA) void;

    // Main stack operations
    pub fn spush(self: *PDA, cell: *const Cell) PDAError!void;
    pub fn spop(self: *PDA) PDAError!Cell;
    pub fn speek(self: *PDA) PDAError!*const Cell;
    pub fn sdepth(self: *const PDA) u32;
    pub fn sempty(self: *const PDA) bool;

    // Aux stack operations
    pub fn apush(self: *PDA, cell: *const Cell) PDAError!void;
    pub fn apop(self: *PDA) PDAError!Cell;
    pub fn adepth(self: *const PDA) u32;
    pub fn aempty(self: *const PDA) bool;

    // Stack manipulation helpers
    pub fn sdup(self: *PDA) PDAError!void;     // OP_DUP
    pub fn sdrop(self: *PDA) PDAError!void;    // OP_DROP
    pub fn sswap(self: *PDA) PDAError!void;    // OP_SWAP
    pub fn srot(self: *PDA) PDAError!void;     // OP_ROT
    pub fn sover(self: *PDA) PDAError!void;    // OP_OVER
    pub fn spick(self: *PDA, n: u32) PDAError!void;  // OP_PICK
    pub fn sroll(self: *PDA, n: u32) PDAError!void;  // OP_ROLL
    pub fn toalt(self: *PDA) PDAError!void;    // OP_TOALTSTACK
    pub fn fromalt(self: *PDA) PDAError!void;  // OP_FROMALTSTACK
};
```

**Critical constraints**:
- Stack overflow: spush when main_sp == MAIN_STACK_DEPTH → StackOverflow error
- Stack underflow: spop when main_sp == 0 → StackUnderflow error
- Same for aux stack with AUX_STACK_DEPTH
- LIFO ordering: last pushed = first popped
- All operations increment opcount. If opcount exceeds max_ops → ExecutionLimitExceeded error
- No dynamic memory allocation in stack operations — the stacks are statically allocated

**Memory footprint**: Main stack = 1024 * 1024 = 1MB. Aux stack = 256 * 1024 = 256KB. Total static: ~1.25MB. This is fine for server/browser but too large for ESP32 (see Phase 8).

### D3.2 — `allocator.zig` (Arena Allocator)

Arena allocator for script execution — allocate during execution, free all at once when script completes. No individual frees in hot paths.

```zig
pub const ScriptArena = struct {
    buffer: []u8,
    offset: usize,

    pub fn init(buffer: []u8) ScriptArena;
    pub fn alloc(self: *ScriptArena, size: usize) ?[]u8;
    pub fn reset(self: *ScriptArena) void;  // Free all at once
};
```

### D3.3 — `opcodes/standard.zig` (Standard Bitcoin Script Opcodes)

Implement the following opcodes. Reference: `CORE:EXECUTOR`.

**Stack manipulation**:
- OP_DUP (0x76), OP_DROP (0x75), OP_SWAP (0x7C), OP_ROT (0x7B)
- OP_OVER (0x78), OP_PICK (0x79), OP_ROLL (0x7A)
- OP_2DUP (0x6E), OP_3DUP (0x6F), OP_2DROP (0x6D), OP_2SWAP (0x72)
- OP_NIP (0x77), OP_TUCK (0x7D)
- OP_TOALTSTACK (0x6B), OP_FROMALTSTACK (0x6C)
- OP_DEPTH (0x74), OP_SIZE (0x82)

**Arithmetic**:
- OP_ADD (0x93), OP_SUB (0x94), OP_MUL (0x95)
- OP_1ADD (0x8B), OP_1SUB (0x8C), OP_NEGATE (0x8F), OP_ABS (0x90)
- OP_NOT (0x91), OP_0NOTEQUAL (0x92)
- OP_NUMEQUAL (0x9C), OP_NUMEQUALVERIFY (0x9D)
- OP_LESSTHAN (0x9F), OP_GREATERTHAN (0xA0), OP_MIN (0xA3), OP_MAX (0xA4)
- OP_WITHIN (0xA5)

**Logic/comparison**:
- OP_EQUAL (0x87), OP_EQUALVERIFY (0x88)
- OP_BOOLAND (0x9A), OP_BOOLOR (0x9B)

**Flow control**:
- OP_IF (0x63), OP_NOTIF (0x64), OP_ELSE (0x67), OP_ENDIF (0x68)
- OP_VERIFY (0x69), OP_RETURN (0x6A)
- OP_NOP (0x61), OP_NOP1-10

**Data push**:
- OP_0 (0x00), OP_1 through OP_16 (0x51-0x60), OP_1NEGATE (0x4F)
- OP_PUSHDATA1 (0x4C), OP_PUSHDATA2 (0x4D), OP_PUSHDATA4 (0x4E)
- Direct push: 0x01-0x4B (push next N bytes)

**Crypto** (via host functions):
- OP_SHA256 (0xA8) → host_sha256
- OP_HASH160 (0xA9) → host_hash160
- OP_HASH256 (0xAA) → host_hash256
- OP_CHECKSIG (0xAC) → host_checksig (with SIGHASH dispatch — see D3.7)
- OP_CHECKMULTISIG (0xAE) → host_checkmultisig (with SIGHASH dispatch — see D3.7)

**String/splice** (BSV-restored):
- OP_CAT (0x7E), OP_SPLIT (0x7F), OP_NUM2BIN (0x80), OP_BIN2NUM (0x81)

### D3.4 — `opcodes/macro.zig` (Craig Macros 0xB0-0xBF)

```zig
// Craig Wright macro system — loop unrolling in a loop-free language
pub fn executeMacro(pda: *PDA, opcode: u8) PDAError!void {
    switch (opcode) {
        0xB0 => xswap(pda, 2),   // XSWAP-2: swap top with 2nd (= OP_SWAP)
        0xB1 => xswap(pda, 3),   // XSWAP-3: swap top with 3rd
        0xB2 => xswap(pda, 4),   // XSWAP-4: swap top with 4th
        0xB3 => xdrop(pda, 2),   // XDROP-2: drop 2 items
        0xB4 => xdrop(pda, 3),   // XDROP-3: drop 3 items
        0xB5 => xdrop(pda, 4),   // XDROP-4: drop 4 items
        0xB6 => xrot(pda, 3),    // XROT-3: rotate top 3 (= OP_ROT)
        0xB7 => xrot(pda, 4),    // XROT-4: rotate top 4
        0xB8 => hashcat(pda),    // HASHCAT: pop 2, SHA256(a||b), push
        else => return error.UnknownMacro,
    }
}
```

### D3.5 — `executor.zig` (Script Executor)

```zig
pub fn execute(pda: *PDA, script: []const u8) ExecuteError!bool {
    var pc: usize = 0;
    while (pc < script.len) {
        if (pda.opcount >= pda.max_ops) return error.ExecutionLimitExceeded;
        const opcode = script[pc];
        pc += 1;

        // Dispatch to appropriate handler
        if (opcode <= 0x4B) { ... }           // Direct push
        else if (opcode <= 0x4E) { ... }      // PUSHDATA1/2/4
        else if (opcode <= 0xAF) {
            try standard.execute(pda, opcode, script, &pc);
        } else if (opcode >= 0xB0 and opcode <= 0xBF) {
            try macro.executeMacro(pda, opcode);
        } else if (opcode >= 0xC0 and opcode <= 0xCF) {
            // Plexus opcodes — stub for Phase 4
            return error.UnimplementedOpcode;
        }

        pda.opcount += 1;
    }

    // Script succeeds if top of stack is truthy
    return pda.sdepth() > 0 and isTruthy(try pda.speek());
}
```

**Bounded execution rules**:
- No backward jumps (pc must always advance)
- No OP_JUMP or OP_GOTO — these don't exist in Bitcoin Script
- IF/ELSE/ENDIF nesting tracked by a counter, never exceeds configured max depth
- Total opcount hard-capped by `pda.max_ops`
- Script length hard-capped at configurable maximum

### D3.6 — WASM Exports (matching PlexusKernelWasm)

The executor must be exposed via the WASM exports defined in `CORE:WASM`:

```zig
export fn kernel_init() callconv(.C) i32;
export fn kernel_reset() callconv(.C) void;
export fn kernel_load_script(script_ptr: [*]const u8, script_len: u32) callconv(.C) i32;
export fn kernel_load_unlock(unlock_ptr: [*]const u8, unlock_len: u32) callconv(.C) i32;
export fn kernel_execute() callconv(.C) i32;
export fn kernel_get_type_class() callconv(.C) i32;
export fn kernel_get_opcount() callconv(.C) i32;
export fn kernel_get_error() callconv(.C) [*]const u8;
export fn kernel_stack_depth() callconv(.C) i32;
export fn kernel_stack_peek(index: u32) callconv(.C) [*]const u8;

// Debug/stepping exports — enables Script IDE integration (see COMMERCIAL-CONTEXT.md)
export fn kernel_step() callconv(.C) i32;              // execute one opcode, return status
export fn kernel_get_pc() callconv(.C) u32;             // current program counter
export fn kernel_get_current_op() callconv(.C) u8;      // next opcode about to execute
export fn kernel_alt_stack_depth() callconv(.C) i32;    // alt stack inspection
export fn kernel_alt_stack_peek(index: u32) callconv(.C) [*]const u8;

// Transaction context for OP_CHECKSIG preimage computation
export fn kernel_load_tx_context(tx_ptr: [*]const u8, tx_len: u32, input_index: u32, input_value: u64) callconv(.C) i32;
```

### D3.7 — SIGHASH Dispatch and Transaction Context

OP_CHECKSIG must handle all BSV SIGHASH modes. Each mode computes a different preimage hash over different parts of the transaction before passing it to the host for ECDSA verification. This is critical for payment channel support — different SIGHASH modes enable different channel topologies (unidirectional, bidirectional, multi-party streaming).

**Transaction context** — the executor needs access to the spending transaction to compute signature preimages. This is provided as an opaque blob loaded before execution:

```zig
pub const TxContext = struct {
    version: u32,
    inputs: []const TxInput,
    outputs: []const TxOutput,
    locktime: u32,
    current_input_index: u32,       // Which input is being validated

    pub const TxInput = struct {
        prev_txid: [32]u8,
        prev_vout: u32,
        script_len: u32,
        sequence: u32,              // nSequence — critical for payment channels
    };

    pub const TxOutput = struct {
        value: u64,                 // satoshis
        script: []const u8,         // locking script
    };
};
```

**SIGHASH modes** (BSV uses SIGHASH_FORKID 0x41 OR'd with the mode):

```zig
pub const SigHashType = struct {
    pub const ALL: u8 = 0x01;              // Sign all inputs and outputs
    pub const NONE: u8 = 0x02;             // Sign inputs only, outputs can change
    pub const SINGLE: u8 = 0x03;           // Sign only the output at same index
    pub const ANYONECANPAY: u8 = 0x80;     // Only sign the current input (combine with above)
    pub const FORKID: u8 = 0x40;           // BSV-specific (BIP143-like preimage)

    // Combined modes used in practice:
    // ALL|FORKID            (0x41) — standard BSV transaction
    // NONE|FORKID           (0x42) — sender signs inputs, receiver chooses outputs
    // SINGLE|FORKID         (0x43) — each party signs their own input-output pair
    // ALL|ANYONECANPAY|FORKID    (0xC1) — sign one input + all outputs
    // NONE|ANYONECANPAY|FORKID   (0xC2) — streaming micropayment (MFP model)
    // SINGLE|ANYONECANPAY|FORKID (0xC3) — multi-party atomic (Plexus mesh)
};
```

**Preimage computation** — OP_CHECKSIG extracts the SIGHASH type byte from the signature (last byte), then builds the appropriate preimage:

```zig
pub fn computeSigHash(
    tx: *const TxContext,
    input_index: u32,
    subscript: []const u8,     // The locking script being validated
    sighash_type: u8,
) [32]u8 {
    // BIP143 serialization (BSV uses this when FORKID is set):
    // 1. nVersion (4B LE)
    // 2. hashPrevouts — depends on ANYONECANPAY
    //    ALL: SHA256D of all input outpoints
    //    ANYONECANPAY: 0x00×32 (only sign current input)
    // 3. hashSequence — depends on mode
    //    ALL: SHA256D of all input nSequence values
    //    ANYONECANPAY or SINGLE or NONE: 0x00×32
    // 4. outpoint of current input (36B: txid + vout)
    // 5. subscript (length-prefixed)
    // 6. value of the output being spent (8B LE)
    // 7. nSequence of current input (4B LE)
    // 8. hashOutputs — depends on mode
    //    ALL: SHA256D of all outputs
    //    SINGLE: SHA256D of output at same index (or 0x00×32 if index out of range)
    //    NONE: 0x00×32
    // 9. nLockTime (4B LE)
    // 10. sighash_type (4B LE, includes FORKID)
    //
    // Final: SHA256D(preimage)
}
```

**nSequence access** — the nSequence field (u32 per input) is a **pure version counter** in BSV, not a relative timelock:
- **State counter** for payment channels — higher nSequence = later state update. Range: 0 to 4,294,967,295 (4.3B state transitions per channel input)
- **Finality marker**: `0xFFFFFFFF` means cooperative close (lockTime=0, irreversible)
- **Non-final states**: nSequence < 0xFFFFFFFF, lockTime set to future (e.g., 24 hours)
- The FSM must enforce monotonic progression — nSequence can only increase within a channel
- **BSV does NOT use OP_CHECKSEQUENCEVERIFY (BIP112)** — that was a BTC-specific soft fork. Opcode 0xB2 belongs to Craig macro XDROP-2, not CSV.

nSequence is exposed to scripts via `host_get_sequence()` (already declared in `host.zig`), not through an OP_CSV opcode.

Reference: CashLanes `IncrementalChannelManager.ts` and `SignatureExchangeFSM.ts` use nSequence as a monotonic version counter with `0xFFFFFFFF` as the finality signal.

**WASM export for transaction context loading:**

```zig
/// Load the spending transaction for signature verification.
/// tx_ptr: pointer to serialized transaction bytes
/// tx_len: length of transaction
/// input_index: which input is being validated
/// input_value: value of the UTXO being spent (needed for BIP143 preimage)
export fn kernel_load_tx_context(
    tx_ptr: [*]const u8,
    tx_len: u32,
    input_index: u32,
    input_value: u64,
) callconv(.c) i32;
```

**Payment channel implications** — with full SIGHASH dispatch, the cell engine can validate:
- Unidirectional channels (ALL|FORKID): consumer signs each state update
- Bidirectional channels (ALL|FORKID): both parties sign
- Streaming micropayments (NONE|ANYONECANPAY|FORKID): the MFP model from CashLanes
- Multi-party atomic (SINGLE|ANYONECANPAY|FORKID): Plexus mesh node settlements
- Each channel state update increments nSequence; the highest nSequence wins at settlement

---

## TDD Gate — Tests That Must Pass

### Test 1: Stack operations (Zig)
```zig
// pda_conformance.zig
test "spush/spop round-trip preserves 1KB cell" { ... }
test "stack overflow at MAIN_STACK_DEPTH" { ... }
test "stack underflow on empty stack" { ... }
test "aux stack overflow at AUX_STACK_DEPTH" { ... }
test "sdepth returns correct count" { ... }
test "LIFO ordering: last in first out" { ... }
test "toalt/fromalt transfers cell between stacks" { ... }
test "sdup creates independent copy" { ... }
test "sswap exchanges top two cells" { ... }
test "srot rotates top three cells" { ... }
test "spick(n) copies nth element to top" { ... }
test "sroll(n) moves nth element to top" { ... }
```

### Test 2: Standard opcodes (Zig)
```zig
// opcodes_conformance.zig

// Arithmetic
test "OP_ADD: 2 + 3 = 5" { ... }
test "OP_SUB: 5 - 3 = 2" { ... }
test "OP_MUL: 3 * 4 = 12" { ... }
test "OP_NEGATE: -(5) = -5" { ... }
test "OP_NUMEQUAL: 5 == 5 is true" { ... }
test "OP_LESSTHAN: 3 < 5 is true" { ... }

// Flow control
test "OP_IF true branch executes" { ... }
test "OP_IF false branch skips to ELSE" { ... }
test "nested IF/ELSE/ENDIF" { ... }
test "OP_VERIFY fails on false, succeeds on true" { ... }
test "OP_RETURN terminates immediately" { ... }

// Data push
test "OP_0 pushes empty/zero" { ... }
test "OP_1 through OP_16 push correct values" { ... }
test "PUSHDATA1 pushes N bytes" { ... }
test "PUSHDATA2 pushes N bytes (2-byte length)" { ... }
test "direct push 0x01-0x4B" { ... }

// Crypto (via host)
test "OP_SHA256 hashes top of stack" { ... }
test "OP_HASH160 applies SHA256+RIPEMD160" { ... }
test "OP_CHECKSIG validates signature" { ... }

// String (BSV-restored)
test "OP_CAT concatenates two items" { ... }
test "OP_SPLIT splits at index" { ... }
```

### Test 3: Craig macros (Zig)
```zig
// macro_conformance.zig
test "XSWAP-2 (0xB0) swaps top with 2nd — equivalent to OP_SWAP" { ... }
test "XSWAP-3 (0xB1) swaps top with 3rd" { ... }
test "XSWAP-4 (0xB2) swaps top with 4th" { ... }
test "XDROP-2 (0xB3) drops 2 items" { ... }
test "XDROP-3 (0xB4) drops 3 items" { ... }
test "XDROP-4 (0xB5) drops 4 items" { ... }
test "XROT-3 (0xB6) rotates top 3 — equivalent to OP_ROT" { ... }
test "XROT-4 (0xB7) rotates top 4" { ... }
test "HASHCAT (0xB8): SHA256(a||b)" { ... }
```

### Test 4: SIGHASH dispatch (Zig)
```zig
// sighash_conformance.zig

// Preimage construction
test "SIGHASH_ALL|FORKID preimage includes all inputs and outputs" { ... }
test "SIGHASH_NONE|FORKID preimage excludes outputs (hashOutputs = 0x00×32)" { ... }
test "SIGHASH_SINGLE|FORKID preimage includes only matching output" { ... }
test "SIGHASH_SINGLE|FORKID with out-of-range index uses 0x00×32" { ... }
test "ANYONECANPAY excludes other inputs (hashPrevouts = 0x00×32)" { ... }
test "NONE|ANYONECANPAY|FORKID — streaming micropayment preimage" { ... }
test "SINGLE|ANYONECANPAY|FORKID — multi-party atomic preimage" { ... }

// OP_CHECKSIG integration
test "OP_CHECKSIG extracts sighash type from signature last byte" { ... }
test "OP_CHECKSIG with ALL|FORKID validates standard BSV transaction" { ... }
test "OP_CHECKSIG with wrong sighash type fails verification" { ... }
test "OP_CHECKSIG with no tx context returns error" { ... }

// nSequence
test "nSequence accessible via host_get_sequence" { ... }
test "kernel_load_tx_context sets transaction context for OP_CHECKSIG" { ... }
```

### Test 5: Bounded execution (Zig)
```zig
test "execution stops at max_ops limit" { ... }
test "no backward jumps possible" { ... }
test "IF/ELSE/ENDIF nesting limit enforced" { ... }
test "script length limit enforced" { ... }
```

### Test 6: WASM export contract (TypeScript)
```typescript
// kernel_compat.test.ts
test("kernel_init returns 0 on success", () => { ... });
test("kernel_load_script + kernel_execute runs simple script", () => {
    // Script: OP_1 OP_1 OP_ADD → stack has 2
});
test("kernel_get_opcount returns correct count", () => { ... });
test("kernel_stack_depth returns correct depth", () => { ... });
test("kernel_stack_peek returns cell bytes", () => { ... });
test("kernel_get_error returns empty string on success", () => { ... });
test("kernel_reset clears all state", () => { ... });
```

---

## Phase Completion Criteria

You are **done with Phase 3** when ALL of the following are true:

1. `zig build test` passes all pda_conformance, opcodes_conformance, macro_conformance tests
2. All standard Bitcoin Script opcodes listed above execute correctly
3. All Craig macros 0xB0-0xB8 execute correctly matching `FORTH:MACROS` (XSWAP-2/3/4, XDROP-2/3/4, XROT-3/4, HASHCAT)
4. Bounded execution: max_ops enforced, no backward jumps, nesting depth capped
5. WASM exports match `PlexusKernelWasm` interface from `CORE:WASM`
6. `bun test tests-ts/kernel_compat.test.ts` passes — TypeScript can load WASM, call exports
7. Crypto opcodes (SHA256, HASH160, CHECKSIG) work via host functions
8. OP_CHECKSIG handles all SIGHASH modes: ALL, NONE, SINGLE, ANYONECANPAY, and combinations, all with FORKID (0x40)
9. BIP143-style preimage computation produces correct hash for each SIGHASH mode
10. `kernel_load_tx_context` loads transaction data; nSequence accessible via `host_get_sequence`
11. Arena allocator: no memory leaks during script execution (verified by Zig safety checks in debug builds)
12. Plexus opcodes 0xC0-0xCF return `UnimplementedOpcode` — they are Phase 4
13. No panics in any error path — all errors return via error unions

## What NOT To Do

- Do not implement linearity enforcement — that's Phase 4
- Do not implement Plexus opcodes — that's Phase 4
- Do not implement BEEF/BUMP parsing — that's Phase 5
- Do not implement loops or backward jumps — Bitcoin Script is loop-free
- Do not use dynamic memory allocation in stack operations — use static arrays
- Do not skip edge cases (stack underflow on nested IF, PICK with n > depth, etc.)

---

## Next Phase

Phase 3 output feeds into **Phase 4: Plexus Opcodes and Linearity Enforcement**, which adds the custom 0xC0-0xCF opcodes and the linearity type system.

---

## Post-Implementation Errata

The following errata were identified during deep code review of the Phase 3 deliverables. Items marked **CRITICAL** are load-bearing bugs that would cause incorrect behaviour in production scripts. Items marked **NOTE** are design decisions that are correct but warrant documentation. Items marked **FRAGILE** are things that work now but will break under real-world conditions.

### E-P3.1 — `host.zig` native hash160 is a test approximation (NOTE)

**File**: `host.zig:40-53`
**Status**: Documented, acceptable for Phase 3.

The native (non-WASM) `hash160()` uses `SHA256(SHA256(data))[0..20]` instead of `RIPEMD160(SHA256(data))`. This is correct behaviour — Zig std does not have RIPEMD160, so the native test build uses a deterministic substitute. Real HASH160 runs through the TypeScript host in WASM mode. The code comments document this. No fix needed.

### E-P3.2 — `host.zig` native checksig/checkmultisig always return false (NOTE)

**File**: `host.zig:72-111`
**Status**: Documented, acceptable for Phase 3.

Native test stubs for `checksig` and `checkmultisig` return false (actually return true only for all-empty inputs, which is an unreachable tautology). This means native Zig tests cannot validate ECDSA signature correctness — only the WASM path with the TypeScript host can. The SIGHASH preimage computation is tested separately. No fix needed until Phase 5 (cross-language validation suite), when a Zig-native secp256k1 binding should be added.

### E-P3.3 — `host.zig` extern declarations are pub (NOTE)

**File**: `host.zig:16-23`
**Status**: Low risk, cosmetic.

The raw `extern "host"` function declarations (`host_sha256`, `host_hash160`, etc.) are `pub`. The comment says "Do NOT call these externs directly — always use the unified wrappers below." Making the externs `pub` means other modules *could* import and call them, bypassing the comptime dispatch. Changing to non-pub would enforce the wrapper-only contract at compile time. Low priority.

### E-P3.4 — `pda.zig` spop returns pointer into stack memory (FRAGILE)

**File**: `pda.zig` spop/speek return `StackEntry` containing `.data` pointer into stack array.
**Status**: Known aliasing hazard, partially mitigated.

When `spop()` returns a `StackEntry`, the `.data` field points into the PDA's `main_stack` memory. A subsequent `spush()` can overwrite that same memory slot. The opcode implementations for `OP_CAT` and `OP_SPLIT` already mitigate this by copying through temp buffers (see `standard.zig` opCat/opSplit). However, any **new** opcode that pops two values and uses both after pushing must also use temp copies. This is a class of bug, not a single instance. Document as a mandatory pattern for Phase 4 Plexus opcodes.

### E-P3.5 — WASM binary size is excellent (NOTE)

**File**: `zig-out/bin/cell-engine.wasm` — 17,941 bytes (18KB)
**Status**: Positive finding.

The WASM binary is remarkably small at 18KB. This was achieved by using `undefined` for global PDA state (avoiding 1.25MB data segment) and `initInPlace()` to avoid returning the 1.5MB PDA struct by value. This is well-engineered and should be preserved — any change that initializes global structs with known values will bloat the binary back to ~1.3MB.

### E-P3.6 — `pda.zig` initInPlace avoids 1.5MB stack allocation (NOTE)

**File**: `pda.zig` initInPlace, `main.zig:31-32`
**Status**: Correct, critical design decision.

`PDA.init()` would return a 1.5MB struct by value, exceeding the 256KB WASM stack. `initInPlace()` writes fields directly to `&g_pda` (a global `undefined` struct). This is the correct pattern for WASM targets and must be preserved. Any refactor that reverts to `const pda = PDA.init(...)` will cause immediate WASM stack overflow.

### E-P3.7 — NOP1-NOP10 overlap with Craig macro range (NOTE)

**File**: `standard.zig:115-116`
**Status**: Non-issue due to dispatch ordering.

`OP_NOP1` is declared as `0xB0` and `OP_NOP10` as `0xB9`, which overlaps exactly with the Craig macro range `0xB0-0xBF`. This is intentional — in standard Bitcoin, these are NOPs; in the Semantos engine, the executor dispatches `0xB0-0xBF` to `macro.zig` before the standard handler, so the NOP constants are never reached. The constants exist only for documentation. No fix needed, but add a comment to prevent confusion.

### E-P3.8 — `kernel_compat.test.ts` writes at fragile WASM offset (FRAGILE)

**File**: `tests-ts/kernel_compat.test.ts`
**Status**: Works but fragile.

The TypeScript tests write script bytes at offset 1024 in WASM linear memory. The WASM stack pointer starts at `__stack_pointer = 0x10000` (64KB) and grows downward. Offset 1024 is within the stack zone. This works now because the stack never grows that deep during simple tests, but will corrupt under any test that triggers deep call stacks. The Phase 1 compat tests were already moved from offset 4096 to 0x100000 (1MB) during Phase 3 development. The Phase 3 tests should use the same high offset.

### E-P3.9 — Direct push opcodes skip bug in false IF branches (CRITICAL)

**File**: `executor.zig:242-243`
**Impact**: Any script with data pushes inside conditional branches will execute incorrectly.

When `executing` is false (inside a false IF branch), direct push opcodes `0x01-0x4B` return immediately without advancing `pc` past the N data bytes:

```zig
if (opcode >= 0x01 and opcode <= 0x4B) {
    if (!ctx.executing) return;  // BUG: pc not advanced past N data bytes
    const n: u32 = opcode;
    // ... push logic, then ctx.pc += n;
```

The data bytes are then interpreted as opcodes on the next iteration. For example, in a script like:

```
OP_0 OP_IF OP_PUSHBYTES_3 0xAA 0xBB 0xCC OP_ELSE OP_1 OP_ENDIF
```

When the false branch is being skipped, after reading `0x03` (OP_PUSHBYTES_3), `pc` is not advanced past the 3 data bytes. The next iteration reads `0xAA` as an opcode (OP_HASH256), then `0xBB`, then `0xCC`, completely corrupting execution flow.

**Fix**: In the false branch, advance `pc += opcode` before returning:
```zig
if (opcode >= 0x01 and opcode <= 0x4B) {
    if (!ctx.executing) {
        ctx.pc += opcode; // skip past data bytes
        return;
    }
```

### E-P3.10 — PUSHDATA1/2/4 skip bug in false IF branches (CRITICAL)

**File**: `executor.zig:253-256, 266-268, 279-281`
**Impact**: Same class of bug as E-P3.9, but for PUSHDATA opcodes.

PUSHDATA1 in a false branch advances past the 1-byte length field but NOT past the data bytes:

```zig
if (opcode == standard.OP_PUSHDATA1) {
    if (!ctx.executing) {
        if (ctx.pc < ctx.currentScriptLen()) ctx.pc += 1; // skips length byte only
        return;  // BUG: doesn't skip past the N data bytes indicated by the length
    }
```

PUSHDATA2 skips 2 length bytes but not data. PUSHDATA4 skips 4 length bytes but not data. Same corruption scenario as E-P3.9 — data bytes become opcodes.

**Fix**: Read the length value and advance past both length bytes AND data bytes:
```zig
if (opcode == standard.OP_PUSHDATA1) {
    if (!ctx.executing) {
        if (ctx.pc < ctx.currentScriptLen()) {
            const n: u32 = script[ctx.pc];
            ctx.pc += 1 + n; // skip length byte + data bytes
        }
        return;
    }
```

Same pattern for PUSHDATA2 (read u16 length, skip 2 + n) and PUSHDATA4 (read u32 length, skip 4 + n).

**Test gap**: The existing tests only use `OP_1`-`OP_16` (small number constants) inside conditional branches, never direct push or PUSHDATA opcodes. This is why the bug was not caught. Add tests with `OP_PUSHBYTES_N` and `PUSHDATA1` inside false IF branches.

### E-P3.11 — hashOutputs stack allocation will crash WASM (CRITICAL)

**File**: `sighash.zig:154`
**Impact**: `computeSigHash` will stack-overflow for ANY transaction when called in WASM mode.

```zig
var out_buf: [MAX_OUTPUTS * 10008]u8 = undefined;  // 256 * 10008 = 2,562,048 bytes
```

This allocates 2.56MB on the function call stack. The WASM stack is 256KB (`build.zig` sets `stack_size = 256 * 1024`). Any call to `computeSigHash` with `SIGHASH_ALL` will immediately overflow the WASM stack.

The same pattern appears in `hashPrevouts` and `hashSequence` but those use `[MAX_INPUTS * 36]u8` (9,216 bytes) and `[MAX_INPUTS * 4]u8` (1,024 bytes) respectively — small enough to survive.

**Fix**: Use streaming hash. Instead of buffering all serialized outputs then hashing, hash them incrementally:

```zig
// Option A: Streaming SHA256 (preferred)
var hasher = host.Sha256Hasher.init();
var i: u32 = 0;
while (i < tx.output_count) : (i += 1) {
    var val_buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &val_buf, tx.outputs[i].value, .little);
    hasher.update(&val_buf);
    var vi_buf: [9]u8 = undefined;
    const vi_len = writeVarInt(&vi_buf, tx.outputs[i].script_len);
    hasher.update(vi_buf[0..vi_len]);
    hasher.update(tx.outputs[i].script[0..tx.outputs[i].script_len]);
}
var first_hash: [32]u8 = undefined;
hasher.final(&first_hash);
// Then hash again for double-SHA256
host.sha256(&first_hash, preimage[pos..][0..32]);
```

This requires adding incremental SHA256 support to `host.zig` — either via a new host extern (WASM) or using `std.crypto.hash.sha2.Sha256` directly (native). Alternative: use the existing `ScriptArena` allocator instead of the stack.

### E-P3.12 — computeSigHash completely untested in WASM mode (CRITICAL)

**File**: `tests-ts/kernel_compat.test.ts`
**Impact**: The entire SIGHASH/CHECKSIG pipeline is untested end-to-end through WASM.

No TypeScript test calls `kernel_load_tx_context` followed by a script containing `OP_CHECKSIG`. The Zig-native sighash tests verify preimage construction, but the native `checksig` stub always returns false (E-P3.2), so even those don't verify a complete signature flow.

This means:
1. The hashOutputs stack overflow (E-P3.11) was never triggered
2. The TxContext parsing in WASM has never been exercised
3. The preimage→host_checksig→result pipeline is untested

**Fix**: Add a WASM integration test that:
1. Calls `kernel_load_tx_context` with a known BSV transaction
2. Loads a script containing `OP_CHECKSIG`
3. Loads an unlock script with a valid DER signature + pubkey
4. Calls `kernel_execute` and verifies the result

This test will immediately expose E-P3.11 (stack overflow). Fix E-P3.11 first.

### E-P3.13 — OP_2OVER and OP_2ROT missing from dispatch (CRITICAL)

**File**: `standard.zig` — constants declared at lines 56-57, not in switch at lines 166-198.
**Impact**: Any script using OP_2OVER (0x70) or OP_2ROT (0x71) will get `invalid_opcode` error.

`OP_2OVER` and `OP_2ROT` are declared as constants but not handled in the stack manipulation switch statement. The switch falls through to `else => {}` which eventually reaches the final `return error.invalid_opcode`. These are standard Bitcoin Script opcodes used in multi-sig scripts and complex locking scripts.

**Fix**: Add dispatch entries. The PDA module likely needs `s2over` and `s2rot` methods:
```zig
// In the stack manipulation switch:
OP_2OVER => return p.s2over(),  // copy items 2 and 3 to top
OP_2ROT => return p.s2rot(),    // rotate 6th and 5th items to top
```

`s2over`: copies the 3rd and 4th items to the top (stack: `... x1 x2 x3 x4 → ... x1 x2 x3 x4 x1 x2`)
`s2rot`: moves the 5th and 6th items to the top (stack: `x1 x2 x3 x4 x5 x6 → x3 x4 x5 x6 x1 x2`)

### E-P3.14 — OP_CHECKSIGVERIFY and OP_CHECKMULTISIGVERIFY not verified (FRAGILE)

**File**: `standard.zig:109-112`
**Impact**: Low — these opcodes are declared but need to be confirmed they're in the dispatch.

`OP_CHECKSIGVERIFY` (0xAD) and `OP_CHECKMULTISIGVERIFY` (0xAF) are defined. Verify they call the corresponding CHECKSIG/CHECKMULTISIG then VERIFY, per the Bitcoin spec. If they're missing from dispatch, same issue as E-P3.13.

### Summary Table

| ID | Severity | File | Issue | Blocks |
|----|----------|------|-------|--------|
| E-P3.1 | NOTE | host.zig | Native hash160 is test approximation | — |
| E-P3.2 | NOTE | host.zig | Native checksig stub returns false | Phase 5 |
| E-P3.3 | NOTE | host.zig | Extern declarations are pub | — |
| E-P3.4 | FRAGILE | pda.zig | spop aliasing hazard | Phase 4 opcodes |
| E-P3.5 | NOTE | cell-engine.wasm | 18KB binary, excellent | — |
| E-P3.6 | NOTE | pda.zig/main.zig | initInPlace is load-bearing | — |
| E-P3.7 | NOTE | standard.zig | NOP1-10 overlap with macro range | — |
| E-P3.8 | FRAGILE | kernel_compat.test.ts | Script offset 1024 in WASM stack zone | — |
| **E-P3.9** | **CRITICAL** | executor.zig | Direct push skip bug in false branches | **All conditional scripts** |
| **E-P3.10** | **CRITICAL** | executor.zig | PUSHDATA skip bug in false branches | **All conditional scripts** |
| **E-P3.11** | **CRITICAL** | sighash.zig | 2.56MB stack alloc crashes WASM | **All CHECKSIG** |
| **E-P3.12** | **CRITICAL** | kernel_compat.test.ts | SIGHASH untested in WASM | **Verification gap** |
| **E-P3.13** | **CRITICAL** | standard.zig | OP_2OVER/OP_2ROT missing | **Multi-sig scripts** |
| E-P3.14 | FRAGILE | standard.zig | CHECKSIGVERIFY dispatch unverified | — |
