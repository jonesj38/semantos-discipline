---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-5-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.681068+00:00
---

# Phase 5 Prompt

**STATUS: NOT STARTED**
**Architecture: Native Zig via BSVZ** — BEEF/BUMP parsing, ECDSA, and all crypto run natively in Zig. No TypeScript host delegation for crypto or SPV. Host functions remain only for runtime context (blocktime, sequence, logging).

Copy everything below the line into a fresh Claude Code session.

---

## Prompt Start

Read these documents in full before producing any output:

1. `/Users/toddprice/projects/semantos-core/docs/prd/README.md`
2. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-5-BEEF-BUMP-CAPABILITY.md`
3. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-4-PLEXUS-OPCODES.md` — read the **Post-Implementation Errata** section for context on Phase 4 output.
4. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-3-2PDA-CORE.md` — read the **Post-Implementation Errata** for the aliasing warning (E-P3.4) and host stub notes (E-P3.1, E-P3.2).

Then read these source files — existing cell engine code you'll modify:

5. `/Users/toddprice/projects/semantos-core/packages/cell-engine/src/host.zig` — Current host function module. SHA256/HASH256 have working Zig std lib implementations. HASH160 uses a test approximation (not real RIPEMD160). CHECKSIG/CHECKMULTISIG stubs return false for native builds, delegate to host externs for WASM. **Phase 5 replaces the native stubs with real BSVZ crypto and replaces the WASM host-delegation model for crypto/SPV.**
6. `/Users/toddprice/projects/semantos-core/packages/cell-engine/bindings/host-functions.ts` — Current TypeScript host function implementations. After Phase 5: for the **full profile**, crypto host functions become pass-through stubs (Zig/BSVZ does the real work) and only `host_get_blocktime`, `host_get_sequence`, and `host_log` remain meaningful. For the **embedded profile**, these TypeScript host functions remain the real crypto implementation — they MUST keep their `@bsv/sdk` Hash and ECDSA calls intact.
7. `/Users/toddprice/projects/semantos-core/src/cell-engine/wasm-interface.ts` — `PlexusKernelWasm` export interface and `PlexusKernelHostImports`. New WASM exports must be added to `PlexusKernelWasm`. Host imports shrink — crypto imports become optional/unused.
8. `/Users/toddprice/projects/semantos-core/packages/cell-engine/src/main.zig` — WASM entry point. All new kernel exports go here.
9. `/Users/toddprice/projects/semantos-core/packages/cell-engine/src/sighash.zig` — Transaction context and BIP143 preimage computation. The CHECKSIG opcode in standard.zig calls `computeSigHash()` from here, then passes the hash to `host.checksig()`. After Phase 5, `host.checksig()` calls BSVZ ECDSA natively instead of delegating to a host extern.
10. `/Users/toddprice/projects/semantos-core/packages/cell-engine/src/errors.zig` — Error codes. Phase 4 ends at code 32. Phase 5 errors start at 33.

Then read these reference implementations for BEEF/BUMP/SPV patterns:

11. `/Users/toddprice/projects/semantos-core/src/lib/semantos-kernel/cellPacker.ts` — Multi-cell packing with LIFO ordering. Cell 1 = BUMP, Cell 2 = Atomic BEEF. Shows `parseBumpHeader()`, `parseAtomicBeefHeader()`, `createBumpCells()`, `createAtomicBeefCells()`. **This is how BUMP and BEEF data arrives at the cell engine — packed into 1024-byte cells on the alt stack.**
12. `/Users/toddprice/projects/semantos-core/src/lib/semantos-kernel/merkleEnvelope.ts` — State chain merkle envelope. `buildMerkleTree()`, `computeMerkleRoot()`, `generateMerkleProof()`, `verifyMerkleProof()`. Cell 3 content.
13. `/Users/toddprice/cashlanes/src/spv/BEEFPackageBuilder.ts` — Production BRC-62 BEEF package construction. Reference for how BEEF packages are built in practice.
14. `/Users/toddprice/cashlanes/src/spv/SPVProofValidator.ts` — Production SPV proof validation. Merkle path verification, settlement record validation, block header chain verification with PoW.
15. `/Users/toddprice/projects/semantos-core/src/types/capability.ts` — CapabilityToken (LINEAR), CapabilityType enum, CapabilityConstraints (expiresAt, geoBounds, maxInvocations, requiredDomainFlags).

### BSVZ — The Native BSV Library for Zig

**CRITICAL: Phase 5 uses BSVZ as a native Zig dependency for all BSV cryptographic and transaction operations.**

BSVZ is a pure-Zig BSV foundation library with zero external dependencies. It provides:
- secp256k1 ECDSA (signing, verification, DER encoding, low-S normalization)
- SHA256, SHA512, RIPEMD160, HASH160, HASH256, HMAC
- BEEF V1/V2/Atomic parsing, serialization, and verification
- MerklePath/BUMP parsing and merkle root computation
- Transaction parsing, sighash computation, P2PKH verification
- Script interpreter with post-Genesis BSV execution

**Repository**: `https://github.com/b-open-io/bsvz`

**Integration**: Add to `build.zig.zon`:
```zig
// In build.zig.zon:
.dependencies = .{
    .bsvz = .{
        .url = "git+https://github.com/b-open-io/bsvz.git",
        .hash = "<fetch hash>",  // Run: zig fetch --save git+https://github.com/b-open-io/bsvz.git
    },
},
```

Or fetch directly:
```bash
zig fetch --save git+https://github.com/b-open-io/bsvz.git
```

Then in `build.zig`, add the BSVZ module to all targets that need crypto/SPV:
```zig
const bsvz = b.dependency("bsvz", .{ .target = target, .optimize = optimize });
// Add to each module/exe/test that needs it:
module.addImport("bsvz", bsvz.module("bsvz"));
```

**Key BSVZ APIs you'll use:**

```zig
const bsvz = @import("bsvz");

// Crypto
const hash = bsvz.crypto.sha256(data);
const hash160 = bsvz.crypto.hash160(data);
const hash256 = bsvz.crypto.hash256(data);  // double SHA256

// ECDSA verification
const verified = bsvz.crypto.verifyDigest256Sec1(pubkey_bytes, sig_der, msg_hash);

// BEEF parsing (V1/V2/Atomic handled transparently)
const beef = try bsvz.transaction.beef.newBeefFromBytes(allocator, beef_bytes);
defer beef.deinit(allocator);

// BUMP/MerklePath
const path = try bsvz.spv.MerklePath.parse(allocator, bump_bytes);
const root = path.computeRoot(txid);

// SPV verification
const valid = try bsvz.spv.verifyBeef(beef, chain_tracker);
```

**WASM compatibility note**: BSVZ targets Zig 0.15.2 with `b.standardTargetOptions`. The cell engine compiles to wasm32-freestanding. You MUST verify that BSVZ's crypto primitives (secp256k1 point multiplication, SHA256, RIPEMD160) compile and run correctly under wasm32-freestanding. If any BSVZ module relies on OS-level APIs (file I/O, networking, threads), those modules cannot be used in WASM builds. The crypto and transaction/SPV modules should be pure computation with no OS dependencies — verify this by building the WASM target first before writing tests.

### Build Profiles: Full vs. Embedded

The cell engine produces TWO build profiles controlled by a compile-time flag:

**Full profile** (default): BSVZ linked, self-contained crypto and BEEF/BUMP parsing. Target: browser extensions, desktop apps, server-side verification. WASM binary ~150-200KB.

**Embedded profile** (`-Dembedded=true`): No BSVZ. Crypto and BEEF/BUMP delegate to host function externs. Target: ESP32, RISC-V, constrained WASM runtimes with ≤500KB RAM. Binary stays under 50KB.

In `build.zig`:
```zig
const embedded = b.option(bool, "embedded", "Minimal binary — delegate crypto to host") orelse false;
```

In `host.zig`, the dispatch becomes:
```zig
const use_bsvz = !@import("builtin").target.cpu.arch.isWasm() or !embedded;
// If use_bsvz: call BSVZ natively
// Else: call host externs (provided by TypeScript or device runtime)
```

Actually, simpler: pass `embedded` as a build option to the host module:
```zig
pub fn sha256(data: []const u8, out: *[32]u8) void {
    if (embedded) {
        // Host extern path — same as current Phase 3/4 code
        if (is_wasm) {
            host_sha256(data.ptr, @intCast(data.len), out);
        } else {
            // Zig std lib (no RIPEMD160, CHECKSIG returns false)
            const Sha256 = std.crypto.hash.sha2.Sha256;
            Sha256.hash(data, out, .{});
        }
    } else {
        // BSVZ native — works for all targets
        const hash = bsvz.crypto.sha256(data);
        @memcpy(out, &hash);
    }
}
```

Both profiles share the same source files, same WASM exports, same TypeScript interface. The only difference is whether crypto runs natively or delegates to the host. Linearity enforcement, Plexus opcodes, cell packing, PDA — all of that is always native regardless of profile.

**The embedded profile preserves the Phase 8 target**: ESP32 and RISC-V devices with 500KB RAM can run the ~30-40KB embedded WASM binary with a lightweight crypto host. The full profile is for environments where binary size doesn't matter and self-containment does.

**Embedded host runtime options** — the cell-engine-embedded.wasm module calls `host_sha256`, `host_checksig`, etc. via extern imports. The host runtime that provides these functions is language-agnostic. Viable options by target:

- **TypeScript (Bun/Node)** — `@bsv/sdk` Hash and PublicKey modules. Already implemented in `bindings/host-functions.ts`. Use for browser extensions, server-side, desktop apps.
- **Python (MicroPython / CPython)** — `bsv-blockchain/py-sdk` wraps `coincurve` (libsecp256k1 C binding) and `pycryptodomex` (C extension). Suitable for Raspberry Pi, Linux SBCs, CI pipelines. Not pure Python — requires C compilation for the target platform.
- **C (bare metal / RTOS)** — Link `libsecp256k1` + `mbedTLS` (or hardware SHA256 peripheral) directly. Smallest host overhead. Best for ESP32-S3, RISC-V MCUs, FreeRTOS targets.
- **Rust** — `k256` crate (pure Rust secp256k1) + `sha2` crate. Good for `no_std` embedded Rust targets or when the host application is already Rust.

The WASM module doesn't care which language provides the host functions — it calls `host_checksig(pk_ptr, pk_len, msg_ptr, msg_len, sig_ptr, sig_len) → u32` and gets back 1 or 0. Memory budget on ESP32: ~30KB WASM binary + ~64KB WASM3 runtime + ~50KB crypto library ≈ 150KB of 500KB available RAM.

If BSVZ does NOT compile cleanly for wasm32-freestanding in the full profile, the full profile still works for native builds (real crypto in Zig tests), and WASM builds automatically fall back to the embedded profile's host delegation.

### What already exists (Phases 0–4 output)

Phases 0–4 are complete and verified. Everything lives at `/Users/toddprice/projects/semantos-core/`:

```
semantos-core/
├── package.json                   # @semantos/core v0.3.0
├── docs/prd/
├── src/                           # TypeScript SDK source (types, kernel, compiler)
└── packages/
    ├── constants/
    │   └── constants.json         # Single source of truth
    ├── protocol-types/
    │   └── src/index.ts           # CellHeader, BCA types, enums
    └── cell-engine/
        ├── build.zig              # Multi-target build with test targets (MODIFY)
        ├── bindings/
        │   └── host-functions.ts  # TypeScript host function implementations (MODIFY — slim down)
        ├── zig-out/bin/
        │   └── cell-engine.wasm   # ~28KB — Phases 0-4
        ├── src/
        │   ├── main.zig           # WASM exports (MODIFY)
        │   ├── host.zig           # Host function bridge (MAJOR REWRITE — BSVZ native)
        │   ├── executor.zig       # Script executor
        │   ├── pda.zig            # 2-PDA with linearity enforcement
        │   ├── sighash.zig        # BIP143 preimage computation
        │   ├── linearity.zig      # Linearity type system
        │   ├── errors.zig         # Error codes (MODIFY)
        │   ├── constants.zig      # Header offsets, opcode ranges
        │   ├── cell.zig           # Cell packing
        │   ├── multicell.zig      # Multi-cell packing
        │   ├── bca.zig            # BCA derivation
        │   ├── allocator.zig      # ScriptArena allocator
        │   └── opcodes/
        │       ├── standard.zig   # Standard Bitcoin Script opcodes
        │       └── plexus.zig     # Plexus custom opcodes 0xC0-0xC7
        ├── tests/
        │   ├── cell_conformance.zig
        │   ├── bca_conformance.zig
        │   ├── executor_conformance.zig
        │   ├── sighash_conformance.zig
        │   ├── linearity_conformance.zig
        │   └── plexus_conformance.zig
        └── tests-ts/
            ├── kernel_compat.test.ts
            ├── bca_compat.test.ts
            └── linearity_compat.test.ts
```

---

## BRC Specifications (Authoritative)

You MUST follow these specifications exactly. They are the BSV Alliance standards.

### BRC-62: BEEF (Background Evaluation Extended Format)

Binary format for transmitting transactions with their ancestry proofs for SPV verification.

**Structure (sequential bytes):**

| Field | Size | Description |
|-------|------|-------------|
| version | 4 bytes | `0x0100BEEF` (Uint32LE = 4022206465) |
| nBUMPs | VarInt | Number of BUMP merkle paths following |
| BUMP data | variable | All BUMPs needed to prove input inclusion |
| nTransactions | VarInt | Number of transactions following |
| transactions | variable | Topologically sorted, each with format flag |

**Transaction entry format:**

| Field | Size | Description |
|-------|------|-------------|
| raw tx | variable | Full serialized transaction (BRC-12 format) |
| hasBUMP | 1 byte | `0x01` if merkle path index follows, `0x00` if not |
| BUMP index | VarInt | Index into the BUMPs array (only if hasBUMP=0x01) |

**Transaction ordering**: Topological sort (Khan's algorithm). Each transaction references only previously-listed inputs. The transaction being evaluated is LAST. This enables streaming validation — process from oldest ancestor to newest, reject early on invalid proofs.

### BRC-74: BUMP (BSV Unified Merkle Path)

Compact binary format for merkle proofs proving transaction inclusion in a block.

**Structure:**

| Field | Size | Description |
|-------|------|-------------|
| blockHeight | VarInt | Block number containing the transaction |
| treeHeight | 1 byte | Depth of merkle tree (max 64) |
| levels | variable | For each level (0 to treeHeight-1): nLeaves + leaf entries |

**Level format:**

| Field | Size | Description |
|-------|------|-------------|
| nLeaves | VarInt | Number of leaves at this level |
| leaves | variable | Leaf entries for this level |

**Leaf entry format:**

| Field | Size | Description |
|-------|------|-------------|
| offset | VarInt | Position from left within tree level |
| flags | 1 byte | See flag table below |
| hash | 32 bytes | Only present if flags bit 0 is NOT set |

**Flag byte:**

| Value | Meaning |
|-------|---------|
| `0x00` | Hash data follows; not a client txid |
| `0x01` | Duplicate working hash; NO hash data follows |
| `0x02` | Hash data follows; this IS the client txid |

**Verification algorithm:**
1. Locate your txid at level 0 (flag 0x02)
2. For each level, find sibling via offset
3. If sibling flag is 0x01 (duplicate), hash working value with itself
4. Otherwise, concatenate with sibling (order determined by offset parity: even=left, odd=right)
5. Hash concatenation with double-SHA256
6. Result at final level = merkle root
7. Compare against block header's merkle root

### BRC-95: Atomic BEEF

Wrapper around BRC-62 BEEF that restricts content to a single transaction's dependency graph.

**Structure:**

| Field | Size | Description |
|-------|------|-------------|
| prefix | 4 bytes | `0x01010101` (fixed constant) |
| subject TXID | 32 bytes | The primary transaction being validated |
| BEEF data | variable | Standard BRC-62 BEEF (starting with `0x0100BEEF`) |

**Constraint**: ALL transactions in the BEEF must be in the subject transaction's dependency graph. Unrelated transactions cause validation failure. The subject TXID must appear as the last transaction in the BEEF.

### BRC-96: BEEF V2 (Txid Only Extension)

Extension that allows known/validated transactions to be referenced by txid only.

**Changes from BRC-62:**

| Field | Change |
|-------|--------|
| version | `0x0200BEEF` (Uint32LE = 4022206466) |
| tx data format byte | New value `0x02` = txid-only |

**Tx data format byte values (replaces hasBUMP):**

| Value | Meaning |
|-------|---------|
| `0x00` | Raw transaction, no BUMP index |
| `0x01` | Raw transaction, BUMP index follows |
| `0x02` | Txid-only: 32 bytes (reverse byte order), implicitly valid |

**Txid-only entries**: No raw transaction data, no BUMP. The 32-byte txid is treated as already validated. Children consuming outputs from txid-only parents treat those inputs as fully verified. Useful when both parties have already validated shared transaction history.

**Ordering**: Parents (including txid-only) must still appear before children.

### VarInt Encoding (used by all BRC specs above)

| Range | Encoding |
|-------|----------|
| 0–0xFC | 1 byte: value directly |
| 0xFD–0xFFFF | 3 bytes: `0xFD` + Uint16LE |
| 0x10000–0xFFFFFFFF | 5 bytes: `0xFE` + Uint32LE |
| 0x100000000–0xFFFFFFFFFFFFFFFF | 9 bytes: `0xFF` + Uint64LE |

---

## Architecture Decision: Native Zig via BSVZ

**Phase 5 uses BSVZ for all crypto, BEEF/BUMP parsing, and SPV verification natively in Zig.**

This is a fundamental shift from the original Phase 5 plan which delegated everything to TypeScript host functions. The new architecture:

1. **Crypto (SHA256, HASH160, HASH256, ECDSA)** — BSVZ native, both WASM and native builds
2. **BEEF parsing (V1/V2/Atomic)** — BSVZ `transaction.beef` module
3. **BUMP/MerklePath verification** — BSVZ `spv.MerklePath` module
4. **SPV verification** — BSVZ `spv.verifyBeef()` / `spv.verify()`
5. **Runtime context (blocktime, sequence, logging)** — Still host functions (these are genuinely host-provided values)

**Why this is better**:
- The WASM binary becomes self-contained for verification — no TypeScript runtime needed
- A browser extension can verify transactions without a JS host
- Native builds get real crypto instead of stubs (CHECKSIG actually works in Zig tests)
- HASH160 gets real RIPEMD160 instead of the SHA256 truncation hack
- No WASM boundary crossing for crypto — significant performance gain for CHECKSIG-heavy workloads
- The engine can run on embedded targets (Phase 8) without any host dependency

**What the host function layer becomes**:
- `host_get_blocktime()` — still host-provided (current block timestamp)
- `host_get_sequence()` — still host-provided (nSequence of current input)
- `host_log()` — still host-provided (debug logging)
- `host_sha256/hash160/hash256/checksig/checkmultisig` — **kept as fallback externs for backward compatibility** but the default path uses BSVZ. The comptime dispatch in `host.zig` gains a third branch: BSVZ native (preferred) → host extern (WASM fallback if BSVZ doesn't compile for wasm32) → std lib stubs (test-only).

**Allocator strategy**: BSVZ functions that need an allocator (BEEF parsing, MerklePath) should use the cell engine's existing `ScriptArena` allocator from `allocator.zig`. This keeps memory usage bounded and predictable. For WASM builds, ensure the arena is large enough to hold a parsed BEEF structure — current arena is 64KB which should be sufficient for typical BEEF sizes (usually under 10KB serialized).

---

## Deliverables

### D5.1 — BSVZ dependency integration and build profiles (`build.zig` + `build.zig.zon`)

Create `build.zig.zon` (does not exist yet) with BSVZ dependency. Update `build.zig` to:
1. Add `-Dembedded` build option (default: false)
2. Import BSVZ dependency (conditional — only when `embedded=false`)
3. Add BSVZ module to `host` module, `main` module, and all test targets that need crypto/SPV
4. Add `test-spv`, `test-capability`, and `test-crypto` test targets
5. Produce two WASM outputs: `cell-engine.wasm` (full profile) and `cell-engine-embedded.wasm` (embedded profile)

**First verification gate**: After this step, both `zig build` (full) and `zig build -Dembedded=true` (embedded) must succeed for native and wasm32-freestanding targets. If BSVZ fails for wasm32, the full profile falls back to native-only and the embedded profile covers WASM.

### D5.2 — Rewrite `host.zig` with BSVZ native crypto

Replace the crypto stubs and host delegation with BSVZ native calls:

```zig
const bsvz = @import("bsvz");

pub fn sha256(data: []const u8, out: *[32]u8) void {
    const hash = bsvz.crypto.sha256(data);
    @memcpy(out, &hash);
}

pub fn hash160(data: []const u8, out: *[20]u8) void {
    const hash = bsvz.crypto.hash160(data);
    @memcpy(out, &hash);
}

pub fn hash256(data: []const u8, out: *[32]u8) void {
    const hash = bsvz.crypto.hash256(data);
    @memcpy(out, &hash);
}

pub fn checksig(pubkey: []const u8, msg_hash: []const u8, sig: []const u8) bool {
    // Use BSVZ ECDSA verification
    // sig includes SIGHASH type as last byte — strip it before DER decode
    const der_sig = sig[0 .. sig.len - 1]; // remove sighash byte
    return bsvz.crypto.verifyDigest256Sec1(pubkey, der_sig, msg_hash) catch false;
}
```

**Key changes from current code**:
- For the **full profile** (`embedded=false`): Remove the `is_wasm` comptime branching for crypto — BSVZ works for all targets. Crypto functions call BSVZ directly.
- For the **embedded profile** (`embedded=true`): Retain the host extern delegation for all crypto. The `host.zig` dispatch becomes a three-way comptime branch: `if (embedded) → host extern | else if (use_bsvz) → BSVZ native | else → std lib stub`.
- Keep the host extern declarations for `host_get_blocktime`, `host_get_sequence`, `host_log` — these are still host-provided in both profiles
- Keep the `is_wasm` dispatch for blocktime/sequence/log only
- The CHECKSIG signature bytes include the SIGHASH type as the last byte (BSV convention). Strip it before passing to BSVZ's DER decoder.
- CHECKMULTISIG: iterate pubkeys and signatures per BSV consensus rules (sequential matching, not exhaustive)

### D5.3 — Native BEEF/BUMP verification module (`src/beef.zig`)

Create a new `beef.zig` module that wraps BSVZ's BEEF and SPV APIs:

```zig
const bsvz = @import("bsvz");
const allocator_mod = @import("allocator");

pub const BeefVersion = enum(i32) {
    v1 = 1,       // BRC-62
    v2 = 2,       // BRC-96
    atomic = 3,   // BRC-95
    invalid = -1,
};

/// Detect BEEF version from first 4 bytes.
pub fn detectVersion(data: []const u8) BeefVersion {
    if (data.len < 4) return .invalid;
    const magic = std.mem.readInt(u32, data[0..4], .little);
    return switch (magic) {
        0x0100BEEF => .v1,
        0x0200BEEF => .v2,
        0x01010101 => .atomic,
        else => .invalid,
    };
}

/// Parse and verify a BEEF envelope. Returns true if all merkle proofs are valid
/// and the subject txid is found.
pub fn verifyBeef(arena: *allocator_mod.ScriptArena, beef_bytes: []const u8, txid: [32]u8) !bool {
    // Use BSVZ to parse and verify
    const beef = try bsvz.transaction.beef.newBeefFromBytes(arena.allocator(), beef_bytes);
    defer beef.deinit(arena.allocator());
    // Verify all transactions in the BEEF
    // Check that txid exists in the parsed structure
    // Return true if valid
}

/// Parse and verify a BUMP merkle path against an expected merkle root.
pub fn verifyBump(bump_bytes: []const u8, txid: [32]u8, expected_root: [32]u8) !bool {
    // Use BSVZ MerklePath
    const path = try bsvz.spv.MerklePath.parse(bump_bytes);
    const computed_root = path.computeRoot(txid);
    return std.mem.eql(u8, &computed_root, &expected_root);
}
```

**Important**: Study BSVZ's actual API signatures carefully before implementing. The pseudocode above shows the intent — the real BSVZ APIs may take allocators differently, return different types, or use different method names. Read `bsvz/src/transaction/beef.zig` and `bsvz/src/spv/lib.zig` source directly.

### D5.4 — WASM exports for SPV verification (`main.zig`)

```zig
/// Verify that a transaction is anchored via BEEF proof.
/// Returns: 0=valid, negative=error code
export fn kernel_verify_beef(beef_ptr: [*]const u8, beef_len: u32, txid_ptr: [*]const u8) callconv(.c) i32;

/// Verify a BUMP merkle proof against a known merkle root.
/// Returns: 0=valid, negative=error code
export fn kernel_verify_bump(bump_ptr: [*]const u8, bump_len: u32, txid_ptr: [*]const u8, merkle_root_ptr: [*]const u8) callconv(.c) i32;

/// Detect BEEF version from binary data.
/// Returns: 1=BRC-62 V1, 2=BRC-96 V2, 3=BRC-95 Atomic, negative=invalid
export fn kernel_beef_version(beef_ptr: [*]const u8, beef_len: u32) callconv(.c) i32;
```

These call the native `beef.zig` module directly — no host function delegation.

### D5.5 — Capability token script evaluation (`main.zig`)

```zig
/// Evaluate a capability token locking script.
/// Pushes context onto stack, enables enforcement, executes script.
/// Returns: 0=valid capability, negative=error code
export fn kernel_verify_capability(
    lock_script_ptr: [*]const u8, lock_script_len: u32,
    owner_pubkey_ptr: [*]const u8,  // 33 bytes compressed
    cap_type: u8,                    // CapabilityType enum value (0-5)
    domain_flag: u32,                // Domain flag value
    current_time: u32,               // Block timestamp for expiry checks
) callconv(.c) i32;
```

Implementation:
1. Reset the PDA
2. Push context values onto the stack in order: `current_time`, `domain_flag`, `cap_type`, `owner_pubkey` (top of stack)
3. Enable enforcement: `g_pda.enableEnforcement()`
4. Load and execute the locking script
5. Check result: top of stack must be truthy
6. Verify the top cell is LINEAR (via `kernel_get_type_class() == 0`)
7. Return 0 on success, error code on failure

### D5.6 — Error codes (`errors.zig`)

Add error codes 33–40:

| Code | Name | Description |
|------|------|-------------|
| 33 | `beef_parse_error` | BEEF binary could not be parsed |
| 34 | `beef_invalid_proof` | BEEF contains invalid merkle proof |
| 35 | `beef_txid_not_found` | Subject txid not found in BEEF |
| 36 | `bump_invalid_proof` | BUMP merkle path does not match expected root |
| 37 | `bump_parse_error` | BUMP binary could not be parsed |
| 38 | `capability_script_failed` | Capability locking script evaluated to false |
| 39 | `capability_not_linear` | Capability token is not LINEAR type |
| 40 | `checksig_failed` | ECDSA signature verification failed |

### D5.7 — Update `PlexusKernelWasm` interface (`wasm-interface.ts`)

Add the new exports to the interface:

```typescript
kernel_verify_beef(beefPtr: number, beefLen: number, txidPtr: number): number;
kernel_verify_bump(bumpPtr: number, bumpLen: number, txidPtr: number, merkleRootPtr: number): number;
kernel_beef_version(beefPtr: number, beefLen: number): number;
kernel_verify_capability(
    lockScriptPtr: number, lockScriptLen: number,
    ownerPubkeyPtr: number,
    capType: number, domainFlag: number, currentTime: number
): number;
```

Add the new exports to the `requiredExports` array in `loadKernel()`.

Update `KernelError` enum with codes 33–40.

**Host imports**: Keep existing crypto host imports in `PlexusKernelHostImports` for backward compatibility, but document that they are now no-ops when BSVZ is linked natively. The TypeScript side should still provide them (returning 0/failure) so the WASM module instantiates without errors.

### D5.8 — Slim down TypeScript host functions (`bindings/host-functions.ts`)

The crypto host functions (`host_sha256`, `host_hash160`, `host_hash256`, `host_checksig`, `host_checkmultisig`) are now handled natively by BSVZ in the Zig binary. The TypeScript implementations become no-op stubs that should never be called:

```typescript
host_sha256: (_dataPtr: number, _dataLen: number, _outPtr: number) => {
    // BSVZ handles this natively — this stub exists for WASM import compatibility
    console.warn('[kernel] host_sha256 called — should be handled by BSVZ natively');
},
```

Keep `host_get_blocktime`, `host_get_sequence`, and `host_log` as real implementations. Make blocktime and sequence configurable via `ScriptContext`:

```typescript
export interface ScriptContext {
    blockTime: number;
    inputSequence: number;
}
```

---

## Files to Modify

| File | Change |
|------|--------|
| `packages/cell-engine/build.zig` | Add BSVZ dependency, add it to module graph, add test-spv and test-capability targets |
| `packages/cell-engine/src/host.zig` | Major rewrite: replace stubs with BSVZ native crypto, keep host externs only for blocktime/sequence/log |
| `packages/cell-engine/src/main.zig` | Add kernel_verify_beef, kernel_verify_bump, kernel_beef_version, kernel_verify_capability exports |
| `packages/cell-engine/src/errors.zig` | Add error codes 33–40 |
| `packages/cell-engine/bindings/host-functions.ts` | Slim down: crypto stubs become no-ops, add ScriptContext for blocktime/sequence |
| `src/cell-engine/wasm-interface.ts` | Add new exports to PlexusKernelWasm, document host import changes, add error codes |

## Files to Create

| File | Purpose |
|------|---------|
| `packages/cell-engine/build.zig.zon` | Package manifest with BSVZ dependency |
| `packages/cell-engine/src/beef.zig` | BEEF/BUMP parsing and verification via BSVZ |
| `packages/cell-engine/tests/spv_conformance.zig` | ~20 tests for BEEF V1/V2/Atomic parsing, BUMP verification, version detection |
| `packages/cell-engine/tests/capability_conformance.zig` | ~12 tests for capability script evaluation with enforcement |
| `packages/cell-engine/tests/crypto_conformance.zig` | ~15 tests for BSVZ crypto: SHA256, HASH160, HASH256, ECDSA verify |
| `packages/cell-engine/tests-ts/spv_integration.test.ts` | ~10 tests for BEEF/BUMP verification through WASM boundary |
| `packages/cell-engine/tests-ts/capability_compat.test.ts` | ~8 tests for capability verification cross-language |
| `packages/cell-engine/tests-ts/checksig_integration.test.ts` | ~10 tests for real ECDSA CHECKSIG through WASM |
| `packages/cell-engine/tests-ts/fixtures/beef_v1_testnet.hex` | Real BRC-62 BEEF from BSV testnet |
| `packages/cell-engine/tests-ts/fixtures/beef_v2_testnet.hex` | Real BRC-96 BEEF V2 from BSV testnet |
| `packages/cell-engine/tests-ts/fixtures/atomic_beef_testnet.hex` | Real BRC-95 Atomic BEEF from BSV testnet |
| `packages/cell-engine/tests-ts/fixtures/bump_testnet.hex` | Real BRC-74 BUMP from BSV testnet |

---

## Implementation Steps

### Step 1: BSVZ integration (`build.zig.zon` + `build.zig`)

Create `build.zig.zon` and add BSVZ dependency. Update `build.zig` to import and wire BSVZ into the module graph. **Build both native and wasm32 targets immediately** to verify BSVZ compiles for both. If wasm32 fails, document the failure and use the hybrid approach (BSVZ for native, host externs for WASM).

### Step 2: Error codes (`errors.zig`)
Add codes 33–40 following the Phase 4 pattern.

### Step 3: Crypto conformance tests (`tests/crypto_conformance.zig`)
Write tests for BSVZ crypto BEFORE rewriting host.zig. Verify:
- SHA256 matches known test vectors
- HASH160 (SHA256 + RIPEMD160) matches known test vectors — this is the first time we'll have real HASH160 in native builds
- HASH256 (double SHA256) matches known test vectors
- ECDSA: verify a known good BSV signature (use a real P2PKH spend as test vector)
- ECDSA: reject a known bad signature

### Step 4: Rewrite `host.zig` with BSVZ native crypto
Replace the `is_wasm` comptime dispatch for crypto with direct BSVZ calls. Keep host extern dispatch only for `host_get_blocktime`, `host_get_sequence`, `host_log`. The CHECKSIG implementation must handle the sighash byte at the end of the signature — strip it before DER decoding.

### Step 5: Verify existing tests still pass
Run `zig build test` — all 240+ Phase 0–4 tests must still pass. The crypto change should be transparent to the executor and sighash modules since they call `host.checksig()` / `host.sha256()` etc. through the same function signatures. The only observable difference: CHECKSIG now returns real results instead of always-false.

### Step 6: BEEF/BUMP module (`src/beef.zig`)
Create the BEEF verification module using BSVZ. Implement `detectVersion`, `verifyBeef`, `verifyBump`. Wire it into the build module graph.

### Step 7: SPV conformance tests (`tests/spv_conformance.zig`)
Test BEEF version detection (V1, V2, Atomic, invalid magic), BEEF parsing with real test fixtures, BUMP verification against known merkle roots, tampered data rejection.

### Step 8: WASM exports (`main.zig`)
Add `kernel_verify_beef`, `kernel_verify_bump`, `kernel_beef_version`, `kernel_verify_capability`. Wire through to native modules.

### Step 9: Capability token evaluation (`main.zig`)
Implement `kernel_verify_capability` using the existing executor + PDA + enforcement infrastructure from Phase 4.

### Step 10: Capability conformance tests (`tests/capability_conformance.zig`)
Capability script evaluation with enforcement enabled, all 6 capability types, expiry checks, domain flag checks, non-LINEAR rejection.

### Step 11: Update interfaces and TS host functions
Update `wasm-interface.ts` with new exports and error codes. Slim down `host-functions.ts` — crypto stubs become no-ops, add ScriptContext.

### Step 12: TypeScript integration tests
- `checksig_integration.test.ts`: Real ECDSA CHECKSIG through WASM boundary with known BSV signatures
- `spv_integration.test.ts`: BEEF/BUMP verification through WASM with real testnet fixtures
- `capability_compat.test.ts`: Capability locking scripts through WASM

---

## Test Fixtures: Capturing Real BEEF/BUMP Data

The test fixtures MUST be real data from BSV testnet, not synthetic mocks. To capture them:

```typescript
import { Beef, Transaction, ARC } from '@bsv/sdk';

// 1. Create and broadcast a testnet transaction
const tx = new Transaction();
// ... build tx ...
const arc = new ARC('https://arc-test.taal.com/v1');
const response = await arc.submit(tx);

// 2. Get BEEF proof for the transaction
const beef = await Beef.fromTxid(response.txid);
const beefHex = beef.toBinaryHex();

// 3. Extract BUMP for a specific transaction
const bump = beef.bumps[0];
const bumpHex = bump.toHex();

// 4. Save as test fixtures
writeFileSync('fixtures/beef_v1_testnet.hex', beefHex);
writeFileSync('fixtures/bump_testnet.hex', bumpHex);
```

If BSV testnet is unavailable during implementation, create a fixture generation script (`tests-ts/generate_fixtures.ts`) that captures the data when run manually, and check the generated fixtures into the repo. Tests should load fixtures from disk, not generate them at test time.

For BEEF V2 fixtures: construct a BEEF with txid-only entries using the SDK's `Beef.addKnownTxid()` or equivalent.

For Atomic BEEF fixtures: wrap a standard BEEF with the `0x01010101` prefix + subject TXID.

---

## Verification

1. `zig build` — both native and wasm32-freestanding compile with BSVZ linked
2. `zig build test` — all Phase 0–4 tests still pass (no regressions), CHECKSIG now returns real results
3. `zig build test-crypto` — all crypto conformance tests pass with BSVZ
4. `zig build test-spv` — BEEF/BUMP conformance tests pass with real fixtures
5. `zig build test-capability` — capability conformance tests pass
6. `cd packages/cell-engine && bun test` — all TypeScript tests pass
7. Verify: `kernel_verify_beef` with real testnet fixture returns 0 (valid) — test against **both** full-profile WASM (BSVZ native) and embedded-profile WASM (host-delegated crypto via TS)
8. Verify: `kernel_verify_beef` with tampered fixture returns negative error code
9. Verify: `kernel_verify_capability` with valid LINEAR capability script returns 0
10. Verify: `kernel_verify_capability` with non-LINEAR cell returns error 39
11. Verify: `kernel_beef_version` correctly identifies all three BEEF variants (V1=1, V2=2, Atomic=3)
12. Verify: native `host.checksig()` validates a real BSV ECDSA signature (no longer returns false)
13. Verify: native `host.hash160()` produces correct RIPEMD160 output (no longer the SHA256 truncation hack)
14. **Full profile**: WASM binary with BSVZ — target under 200KB. If over 200KB, document the size breakdown.
15. **Embedded profile** (`-Dembedded=true`): WASM binary without BSVZ — must stay under 50KB (same as Phase 4 target). Verify both profiles build and pass their respective test suites.

---

## What NOT To Do

- Do not implement your own secp256k1, SHA256, RIPEMD160, or BEEF parser — use BSVZ
- Do not remove the host extern declarations from `host.zig` — keep them for backward compatibility even if unused
- Do not use mock BEEF envelopes in tests — use real testnet fixtures or a generation script
- Do not break Phase 3/4 tests — the crypto upgrade must be transparent to existing code
- Do not assume BSVZ compiles for wasm32 without testing — verify first, fall back to hybrid if needed
- Do not make testnet-dependent tests fail silently — print a clear skip message with instructions
- Do not use BSVZ's script interpreter for execution — the cell engine has its own 2-PDA executor, use BSVZ only for crypto, BEEF, and SPV primitives
- Do not allocate unbounded memory for BEEF parsing — use the ScriptArena allocator

---

## Phase 5 Completion Criteria

You are **done with Phase 5** when ALL of the following are true:

1. BSVZ is integrated as a Zig dependency and compiles for both native and wasm32 targets
2. `host.checksig()` validates a real BSV ECDSA signature natively via BSVZ (no host delegation)
3. `host.hash160()` produces correct SHA256+RIPEMD160 output via BSVZ (no truncation hack)
4. `host.checkmultisig()` handles m-of-n threshold verification natively via BSVZ
5. BEEF version detection correctly identifies BRC-62 V1, BRC-96 V2, and BRC-95 Atomic
6. `kernel_verify_beef` validates a real testnet BEEF fixture using BSVZ's BEEF parser
7. `kernel_verify_bump` validates a real testnet BUMP against a known merkle root via BSVZ MerklePath
8. `kernel_verify_capability` evaluates a capability locking script with Plexus opcodes and enforcement
9. All Phase 0–4 tests still pass (240+ Zig, 56+ TS) — no regressions
10. Full profile WASM binary compiles and runs with BSVZ linked (under 200KB)
10a. Embedded profile WASM binary compiles and runs without BSVZ (under 50KB)
11. Test fixtures are real BSV testnet data, not synthetic mocks
12. `PlexusKernelWasm` interface is updated with new exports
13. Crypto conformance tests prove BSVZ output matches known BSV test vectors

---

## Next Phase

Phase 5 output feeds into **Phase 6: TypeScript Bindings and Bun Integration**, which wraps the WASM binary in a typed TypeScript API with ergonomic methods for cell packing, script evaluation, and SPV verification. With BSVZ linked natively, the WASM binary is now self-contained — the TypeScript bindings become a convenience layer, not a dependency.
