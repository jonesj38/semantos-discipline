---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-3-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.680778+00:00
---

# Phase 3 Prompt

Copy everything below the line into a fresh Claude Code session.

---

## Prompt Start

Read these two documents in full before producing any output:

1. `/Users/toddprice/projects/semantos-core/docs/prd/README.md`
2. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-3-2PDA-CORE.md`

This is the largest single phase. Take time to read the source files before writing code.

### What already exists (Phase 0 + Phase 1 + Phase 2 output)

Phases 0-2 are complete and verified. Everything lives at `/Users/toddprice/projects/semantos-core/`:

```
semantos-core/
├── package.json                   # @semantos/core v0.3.0, depends on @bsv/sdk ^2.0.0
├── src/cell-engine/
│   ├── typeHashRegistry.ts        # Canonical wire-format header builder
│   ├── cellPacker.ts              # Multi-cell packer (TS reference)
│   ├── merkleEnvelope.ts          # Merkle envelope serialization
│   ├── wasm-interface.ts          # PlexusKernelWasm + PlexusKernelHostImports
│   └── index.ts
├── docs/prd/
└── packages/
    ├── constants/
    │   ├── constants.json         # Single source of truth (includes BCA constants)
    │   └── generate.ts
    ├── protocol-types/
    │   └── src/index.ts           # CellHeader, BCA types, enums
    ├── __tests__/
    │   └── phase0-gate.test.ts
    └── cell-engine/
        ├── build.zig              # Multi-target: freestanding, wasi, native tests
        ├── zig-out/bin/
        │   ├── cell-engine.wasm   # 4.6KB — cell packing + BCA derivation
        │   └── cell-engine-wasi.wasm
        ├── src/
        │   ├── main.zig           # 305 lines — WASM exports (cell_pack/unpack, multicell, bca_derive/verify)
        │   ├── constants.zig      # Generated — offsets, ranges, BCA constants
        │   ├── cell.zig           # 201 lines — packCell, unpackCell, magic, commerce/binding
        │   ├── commerce.zig       # 76 lines — CommerceExtension + OnChainBinding
        │   ├── multicell.zig      # 180 lines — multi-cell pack/unpack, continuation headers
        │   ├── bca.zig            # 99 lines — deriveBCA, verifyBCA (simplified algorithm)
        │   ├── host.zig           # 35 lines — comptime SHA256 switch (WASM: extern, native: std lib)
        │   ├── errors.zig         # KernelError enum (codes 0-15, 255)
        │   ├── pda.zig            # STUB — you are implementing this
        │   ├── linearity.zig      # STUB (Phase 4)
        │   └── opcodes/
        │       ├── standard.zig   # STUB — you are implementing this
        │       ├── macro.zig      # STUB — you are implementing this
        │       └── plexus.zig     # STUB (Phase 4)
        ├── tests/
        │   ├── smoke_test.zig             # Phase 0 constants
        │   ├── cell_conformance.zig       # Phase 1 pack/unpack
        │   ├── commerce_conformance.zig   # Phase 1 commerce/binding
        │   ├── multicell_conformance.zig  # Phase 1 multi-cell
        │   ├── bca_conformance.zig        # Phase 2 BCA derivation
        │   ├── generate-vectors.ts        # Cell test vector generator
        │   ├── generate-bca-vectors.ts    # BCA test vector generator
        │   └── vectors/                   # .bin + .json test vectors
        ├── tests-ts/
        │   ├── compat.test.ts             # Phase 1 cross-language cell tests
        │   └── bca_compat.test.ts         # Phase 2 cross-language BCA tests
        ├── __tests__/
        │   └── wasm-build.test.ts
        └── bindings/
            ├── host-functions.ts  # Real host_sha256 via @bsv/sdk Hash, other stubs
            └── index.ts
```

WASM binary is 4.6KB. All Phase 0/1/2 tests pass. host_sha256 works via @bsv/sdk.

### What you are building

Phase 3 implements the 2-PDA core engine — the dual-stack machine that executes Bitcoin Script. Seven deliverables:

- D3.1: `pda.zig` — Dual-stack engine (1024 main × 1KB cells, 256 aux × 1KB cells, LIFO)
- D3.2: `allocator.zig` — Arena allocator for script execution (alloc during, free-all at end)
- D3.3: `opcodes/standard.zig` — All standard Bitcoin Script opcodes (stack, arithmetic, logic, flow, data push, crypto, string/splice)
- D3.4: `opcodes/macro.zig` — Craig macros 0xB0-0xBF (XSWAP, XDROP, XROT, XPICK, HASHCAT)
- D3.5: `executor.zig` — Script executor with opcode dispatch, bounded execution
- D3.6: WASM exports matching PlexusKernelWasm + debug/stepping exports
- D3.7: SIGHASH dispatch and transaction context for OP_CHECKSIG

### Critical source files to read

Read ALL of these before writing any code:

1. `FORTH:2PDA` — The GForth 2-PDA reference. CELL-SIZE=1024, MAIN-STACK-CELLS=1024, AUX-STACK-CELLS=256.
2. `CORE:EXECUTOR` — The 38KB GForth script executor. Every standard opcode with edge cases.
3. `FORTH:MACROS` (`/Users/toddprice/projects/semantos/semantos-gift-pack/forth/craig-macros.fs`) — Craig macro table 0xB0-0xB8. **The INIT-MACROS registration table (lines 130-138) is the authoritative opcode mapping**: XSWAP-2(0xB0), XSWAP-3(0xB1), XSWAP-4(0xB2), XDROP-2(0xB3), XDROP-3(0xB4), XDROP-4(0xB5), XROT-3(0xB6), XROT-4(0xB7), HASHCAT(0xB8). Note: no XPICK macros exist. No XROT-2 exists (XROT-3 is the simplest rotation). XSWAP-2 is equivalent to OP_SWAP. XROT-3 is equivalent to OP_ROT.
4. `CORE:CONSTANTS` — BSV opcode values, SIGHASH_FORKID (0x41).
5. `CORE:WASM` (`/Users/toddprice/projects/semantos-core/src/cell-engine/wasm-interface.ts`) — The WASM export contract.
6. `CASHLANES:SETTLEMENT` (`/Users/toddprice/projects/cashlanes/src/settlement/CooperativeSettlementBuilder.ts`) — Production SIGHASH usage: fee input 0x82 (ACP|NONE), multisig input 0x41 (ALL|FORKID).
7. `CASHLANES:PREIMAGE` (`/Users/toddprice/projects/cashlanes/metanet-desktop/src/routing/ChannelTransactionBuilder.ts`) — `TransactionSignature.format()` preimage computation. This is the BIP143 reference.
8. `CASHLANES:SIGFSM` (`/Users/toddprice/projects/cashlanes/src/settlement/SignatureExchangeFSM.ts`) — nSequence monotonic enforcement. `0xFFFFFFFF` = finality.
9. `CASHLANES:MULTISIG` (`/Users/toddprice/projects/cashlanes/src/settlement/MultisigUnlockingScriptBuilder.ts`) — `OP_0 <sig1> <sig2>` format.

### The host function architecture

Crypto opcodes call through host functions — the Zig WASM binary does NOT contain crypto implementations:

- OP_SHA256 → `host.sha256()` (comptime switch: WASM → extern, native → std lib)
- OP_HASH160 → `host.hash160()` (needs implementing — SHA256 then RIPEMD160)
- OP_HASH256 → `host.hash256()` (double SHA256)
- OP_CHECKSIG → compute preimage in Zig, hash it, call `host_checksig(pubkey, msg_hash, sig)` for ECDSA verification
- OP_CHECKMULTISIG → same pattern with multiple pubkeys/sigs

For **native test builds**, host.zig already has the comptime SHA256 switch. You'll need to add equivalent switches for hash160 (using std lib), hash256 (double SHA256 via std lib), and checksig/checkmultisig (using a Zig ECDSA implementation from std lib or a test-only stub).

For the **SIGHASH preimage computation**: this happens entirely in Zig (no host call needed). The preimage is BIP143 serialization of the transaction context. Only the final ECDSA verification goes through `host_checksig`.

### SIGHASH dispatch — the most complex part

OP_CHECKSIG must:
1. Pop signature and pubkey from stack
2. Extract SIGHASH type from signature's last byte
3. Verify FORKID bit (0x40) is set — BSV requires it
4. Build the BIP143 preimage based on SIGHASH mode
5. Double-SHA256 the preimage
6. Call `host_checksig(pubkey, hash, signature_without_sighash_byte)` for ECDSA
7. Push 1 (true) or 0 (false)

The six SIGHASH combinations in practice:

| Mode | Value | hashPrevouts | hashSequence | hashOutputs |
|------|-------|-------------|-------------|------------|
| ALL\|FORKID | 0x41 | SHA256D(all outpoints) | SHA256D(all nSequences) | SHA256D(all outputs) |
| NONE\|FORKID | 0x42 | SHA256D(all outpoints) | 0x00×32 | 0x00×32 |
| SINGLE\|FORKID | 0x43 | SHA256D(all outpoints) | 0x00×32 | SHA256D(output[index]) or 0x00×32 |
| ALL\|ACP\|FORKID | 0xC1 | 0x00×32 | 0x00×32 | SHA256D(all outputs) |
| NONE\|ACP\|FORKID | 0xC2 | 0x00×32 | 0x00×32 | 0x00×32 |
| SINGLE\|ACP\|FORKID | 0xC3 | 0x00×32 | 0x00×32 | SHA256D(output[index]) or 0x00×32 |

(ACP = ANYONECANPAY = 0x80)

BIP143 preimage format (11 fields, serialized in order):
1. nVersion (4B LE)
2. hashPrevouts (32B)
3. hashSequence (32B)
4. outpoint (36B: prev_txid + prev_vout LE)
5. scriptCode (varint length + script bytes)
6. value (8B LE — satoshis of UTXO being spent)
7. nSequence (4B LE — of current input)
8. hashOutputs (32B)
9. nLockTime (4B LE)
10. nHashType (4B LE — sighash type including FORKID)

Final: `SHA256D(preimage)` = the message hash passed to ECDSA

Reference implementation: `TransactionSignature.format()` in `@bsv/sdk`. Read `CASHLANES:PREIMAGE` to see it used in production.

### CashLanes production pattern (must-know context)

CashLanes uses a **dual-input settlement transaction**:
- **Input 0**: 1-sat fee credit, signed with `0x82` (ANYONECANPAY|NONE). Pre-signed once, appendable.
- **Input 1**: 2-of-2 multisig funding UTXO, signed with `0x41` (ALL|FORKID). Re-signed per state update.

nSequence is a **pure version counter** (not a relative timelock):
- Increments from 0 upward per channel state update
- `0xFFFFFFFF` = cooperative close (final settlement, lockTime=0)
- Non-final states have lockTime set 24 hours in the future
- Monotonic enforcement: nSequence can only increase

**BSV does NOT use OP_CHECKSEQUENCEVERIFY (BIP112).** That was a BTC-specific soft fork. Opcode 0xB2 belongs to Craig macro XDROP-2. Do NOT implement OP_CSV.

Multisig unlocking script format: `OP_0 <sig1> <sig2>` (the OP_0 is the off-by-one CHECKMULTISIG bug workaround).

### Memory model

The PDA has ~1.25MB of static stack memory:
- Main stack: 1024 slots × 1024 bytes = 1MB
- Aux stack: 256 slots × 1024 bytes = 256KB

This is statically allocated — no heap allocation in stack operations. For script data (push data, intermediate results), use the arena allocator. For WASM, this memory comes from the linear memory.

**WASM memory considerations**: 1.25MB of stacks means the WASM module needs at least 20 pages (1.28MB) of initial memory. Set this in build.zig or let the host grow memory on demand.

### Opcode 0xB2 conflict resolution

In BTC, 0xB2 is OP_CHECKSEQUENCEVERIFY. In BSV (and in this implementation), **0xB2 is Craig macro XDROP-2**. Do NOT implement OP_CSV. The Craig macro range 0xB0-0xBF is authoritative.

### Bounded execution rules

Bitcoin Script is loop-free. The executor enforces:
- pc (program counter) must always advance — no backward jumps
- Total opcount hard-capped by `pda.max_ops` (configurable, default 500000)
- Script length hard-capped (configurable, default 10000 bytes)
- IF/ELSE/ENDIF nesting tracked by counter, capped (default depth 100)
- No OP_JUMP, no OP_GOTO — these don't exist in Bitcoin Script
- Turing completeness comes from transaction chaining, not from script loops

### Test vector generation for OP_CHECKSIG

Generate SIGHASH test vectors independently using `@bsv/sdk`:

```typescript
import { Transaction, TransactionSignature, PrivateKey, Hash } from '@bsv/sdk';

// Build a real transaction, compute preimage with TransactionSignature.format()
// for each SIGHASH mode, record the preimage hash and expected ECDSA signature.
// Store as JSON vectors in tests/vectors/sighash_*.json
```

The Zig preimage computation must produce the same hash as `TransactionSignature.format()` + double SHA256 for the same transaction and SIGHASH mode.

### Sequence

1. Read ALL 9+ source files listed in the Phase 3 doc
2. Read `host.zig` — understand the comptime switch pattern. You'll extend it with hash160, hash256, checksig wrappers
3. Read `main.zig` — understand the WASM export pattern (callconv(.c), linear memory pointers)
4. Read `build.zig` — understand the module graph. You'll add pda, allocator, executor, standard, macro modules
5. Add new error codes to `errors.zig` (stack_overflow, stack_underflow, execution_limit, etc. — many already exist from Phase 0)
6. Write RED tests for PDA stack operations (`pda_conformance.zig`)
7. Implement `pda.zig` (GREEN) — dual stacks, push/pop/peek, overflow/underflow
8. Write RED tests for arena allocator
9. Implement `allocator.zig` (GREEN)
10. Write RED tests for standard opcodes (`opcodes_conformance.zig`) — start with arithmetic (OP_ADD, OP_SUB), then stack manip, then flow control
11. Implement `opcodes/standard.zig` (GREEN) — incrementally, one group at a time
12. Write RED tests for Craig macros (`macro_conformance.zig`)
13. Implement `opcodes/macro.zig` (GREEN)
14. Write RED tests for SIGHASH preimage (`sighash_conformance.zig`) using independently-generated vectors
15. Implement the TxContext struct and `computeSigHash` function
16. Implement `executor.zig` with full opcode dispatch
17. Generate SIGHASH test vectors (TypeScript script using `@bsv/sdk TransactionSignature.format()`)
18. Wire WASM exports in `main.zig` — replace Phase 0 stubs with real implementations
19. Wire debug/stepping exports (`kernel_step`, `kernel_get_pc`, `kernel_get_current_op`, `kernel_alt_stack_depth`, `kernel_alt_stack_peek`)
20. Add `kernel_load_tx_context` export
21. Update `host.zig` with hash160, hash256, checksig wrappers (comptime switch for each)
22. Update `host-functions.ts` — implement host_hash160 and host_hash256 using @bsv/sdk
23. Write cross-language tests (`kernel_compat.test.ts`) — load WASM, execute scripts, verify results
24. Run full test suite — all Phase 0 + 1 + 2 + 3 tests must pass
25. Verify WASM binary size is under 500KB (stacks are static, but code size will grow)

### What NOT to do

- Do NOT implement linearity enforcement — that's Phase 4
- Do NOT implement Plexus opcodes 0xC0-0xCF — that's Phase 4 (return UnimplementedOpcode)
- Do NOT implement BEEF/BUMP parsing — that's Phase 5
- Do NOT implement OP_CHECKSEQUENCEVERIFY (0xB2) — BSV doesn't use it; 0xB2 is Craig macro XDROP-2
- Do NOT implement OP_CHECKLOCKTIMEVERIFY unless it's in the BSV opcode table (verify first)
- Do NOT use dynamic memory allocation in stack operations — stacks are statically allocated
- Do NOT skip edge cases (stack underflow on nested IF, PICK with n > depth, SPLIT at boundary, etc.)
- Do NOT adjust tests to match wrong output — fix the code
- Do NOT break Phase 0/1/2 tests — cell packing and BCA must still work
- Do NOT implement a SHA256 in Zig for the WASM target — use host functions
- Do NOT hardcode opcode values — use constants from `CORE:CONSTANTS` / `constants.zig`

### Zig 0.15 notes

The project uses Zig 0.15. Key patterns from Phase 1/2:
- Module imports use named modules via build.zig: `@import("constants")`, `@import("host")`
- `builtin.target.cpu.arch == .wasm32` for comptime target detection
- `callconv(.c)` for WASM exports
- `std.mem.readInt` / `std.mem.writeInt` for endian-aware integer access
- `@embedFile` for test vectors in conformance tests

### Done criteria

All 13 Phase Completion Criteria from the Phase 3 doc must be true. The most critical:
- Criterion 8: OP_CHECKSIG handles ALL, NONE, SINGLE, ANYONECANPAY combinations with FORKID
- Criterion 9: BIP143 preimage produces correct hash for each SIGHASH mode (verified against @bsv/sdk vectors)
- Criterion 10: `kernel_load_tx_context` loads transaction data; nSequence accessible via `host_get_sequence`

This is the phase that turns the cell engine from a serialization tool into a script execution engine. Take it methodically — PDA first, then opcodes one group at a time, then SIGHASH last.
