---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/SEMANTOS_ZIG_WASM_PRD.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.681671+00:00
---

# Semantos Zig/WASM Cell Engine — Production Requirements Document

**Version**: 1.0
**Date**: 26 March 2026
**Author**: Todd Price
**Status**: DRAFT — Pending partner review

---

## Claude Code Prompt: Semantos Zig/WASM Production Implementation

### CONTEXT HANDOFF

You are being engaged to produce a production implementation plan for the Semantos Zig/WASM execution layer. This is not R&D. This is a production implementation. Read every word of this prompt before producing any output.

### WHAT SEMANTOS IS

Semantos is a Semantic Name System (SNS) — infrastructure that maps cryptographically typed names to sovereign digital objects. It is NOT a blockchain application, NOT a wallet, NOT a credential system. It is a name system that operates at the level of meaning rather than addresses.

The system has three layers:

**Layer 1 — Plexus (identity substrate)**

- BRC-52 certificate DAG for sovereign identity
- BRC-42 deterministic key derivation (client-side only, server never touches private keys)
- Recovery-as-a-Service: ~3.4KB export payload, PBKDF2 reconstruction
- `@semantos/core` v0.2.0 — Todd's code, at `/Users/toddprice/projects/semantos-core/`. TypeScript package with: semantic object type system (LINEAR/AFFINE/RELEVANT), WASM kernel interface (`PlexusKernelWasm`, `PlexusKernelHostImports`), capability tokens (BRC-108), domain flags, recovery protocol, metering FSM. Peer dependency on `@bsv/sdk`.
- Todd authored the Plexus Technical Requirements (v1.3) and Client Requirements (v2.1) that guide Dusk's development of the Graph SDK (DAG operations, traversal) and RaaS SDK (Recovery-as-a-Service). Those SDKs are being built by Dusk — Todd has not seen the code.

**Layer 2 — Semantos Kernel (semantic object runtime)**

- Domain-agnostic runtime for typed, versioned, hash-chained semantic objects
- Production `cellPacker.ts` (650 lines) at `oddjobtodd/src/lib/semantos-kernel/cellPacker.ts` — structured multi-cell packing with BUMP (BRC-74), Atomic BEEF (BRC-95), State Envelope, and Data cells. LIFO alt-stack ordering. Imports from `typeHashRegistry.ts` for header construction. **This is the canonical TypeScript cell packer that the Zig implementation must produce bit-identical output to.**
- A second `cellPacker.ts` variant exists in `data/brem-agent/src/lib/brem-compiler/semantos/cellPacker.ts` (the brem-agent compiler integration)
- Existing schema: `linear_semantic_objects`, `bkds_semantic_keys`, `linear_object_audit` tables (SQLite)
- Existing CLI tooling: `semantic-cli`, `semantic-utxo-basket`, `semantic-indexer`, `broadcast-semantic-object`
- Tauri+Svelte desktop wallet with Rust backend for semantic object commands
- Existing Forth reference implementation of the 2-PDA, semantic objects, linearity enforcement, commerce headers, and Craig macros
- TypeScript semantic object services (`SEMOBJ:SERVICE`, `SEMOBJ:ADAPTER`) with UTXO binding, lifecycle management, and two-phase commit anchoring
- SemanticManager CLI bridge (`SEMOBJ:MANAGER`) mapping semantic objects to CLI commands
- SpendableOutput store (`SEMOBJ:OUTPUT-STORE`) with derived views for unspent outputs and balance tracking
- CashLanes payment channel implementation (`CASHLANES:FSM`, `CASHLANES:SETTLE`) — production BRC-100 compliant 7-state FSM with prepaid 1-sat fee pattern, dual-basket UTXO tracking, and universal metered flow adapters. **Reference for plexus-core metering FSM and settlement patterns.**

**Layer 3 — Zig/WASM Execution Layer (what you are planning)**

- Two-stack Pushdown Automaton (2-PDA): main stack 1024 cells, aux stack 256 cells
- Bounded, deterministic, loop-free Bitcoin Script execution
- Custom Plexus opcodes 0xC0–0xCF for type enforcement
- 1KB cell format serialisation/deserialisation
- BEEF/BUMP SPV verification
- BCA (Bitcoin-Certified Address) IPv6 address derivation and verification
- Linearity enforcement (LINEAR/AFFINE/RELEVANT)
- Capability token verification (BRC-108)
- Deployable as: Bun server module, browser WASM, embedded microcontroller (ESP32-class), SRv6 network node

---

## 1. Executive Summary

The Semantos Cell Engine (`@semantos/cell-engine`) is a Zig-implemented, WASM-compiled execution layer for 1KB semantic cells with cryptographic linearity enforcement. It provides deterministic script evaluation, cell packing/unpacking, BCA address derivation, and capability token verification — all in a sub-500KB WASM binary deployable across server, browser, and embedded targets.

This is the missing execution layer between the Plexus identity substrate (Layer 1, built by Dusk) and the Semantos kernel (Layer 2, existing TypeScript/Forth codebase). It replaces the Forth reference implementation with a production-grade engine that produces bit-identical cells, integrates with existing BSV SDKs via host function imports, and defines clean interface contracts with both plexus-core and the existing kernel.

**Commercial enablement**: A shipping cell engine means typed semantic objects can be created, verified, and anchored on BSV from any deployment target — Bun servers, browser tabs, or ESP32 edge devices — with the same cell format and the same verification guarantees. This is what turns the protocol spec into deployable infrastructure.

---

## 2. System Architecture

### 2.1 Package Boundaries

```
┌─────────────────────────────────────────────────────────────────────┐
│                        PLEXUS (Layer 1)                             │
│  Built by Dusk Inc — Todd authored requirements docs                │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │ plexus-core  │  │  plexus-     │  │  Vendor SDK  │              │
│  │ (TypeScript) │  │  contracts   │  │  (Graph DB)  │              │
│  │              │  │ (shared types│  │              │              │
│  │ BRC-52 certs │  │  zero deps)  │  │ DAG ops      │              │
│  │ BRC-42 deriv │  │              │  │ child index  │              │
│  │ Recovery     │  │ interfaces,  │  │              │              │
│  │ Cap tokens   │  │ enums, Zod   │  │              │              │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘              │
│         │                 │                                         │
│         │  subjectPublicKey (33 bytes)                              │
│         │  capabilityToken UTXO data                                │
│         │  domainFlag values                                        │
└─────────┼─────────────────┼─────────────────────────────────────────┘
          │                 │
          ▼                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  @semantos/protocol-types                           │
│           Shared types — zero runtime dependencies                  │
│                                                                     │
│  CertificateRef, CapabilityTokenRef, BCAInput, BCAOutput,          │
│  CellHeader, CellPayload, ScriptContext, ScriptResult,             │
│  LinearityOperation, LinearityResult, CellType enum,               │
│  CommercePhase enum, TaxonomyDimension enum                        │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
┌─────────────────┐ ┌───────────┐ ┌───────────────────────────────┐
│ @semantos/      │ │  Existing │ │  @semantos/cell-engine        │
│ cell-engine     │ │  Kernel   │ │  (Zig → WASM)                 │
│ (TS bindings)   │ │           │ │                               │
│                 │ │ SQLite    │ │  ┌─────────────────────────┐  │
│ Thin FFI wrapper│ │ schema    │ │  │  2-PDA Engine            │  │
│ over WASM       │ │ CLI tools │ │  │  main: 1024 × 1KB cells │  │
│ exports         │ │ Tauri app │ │  │  aux:  256 × 1KB cells  │  │
│                 │ │           │ │  └─────────────────────────┘  │
│ Matches existing│ │           │ │  ┌─────────────────────────┐  │
│ kernel interface│ │           │ │  │  Cell Pack/Unpack        │  │
│                 │ │           │ │  │  256-byte header          │  │
└────────┬────────┘ └─────┬─────┘ │  │  768-byte payload        │  │
         │               │       │  └─────────────────────────┘  │
         │               │       │  ┌─────────────────────────┐  │
         └───────────────┘       │  │  BCA Derivation          │  │
                                 │  │  IPv6 addr from pubkey   │  │
                                 │  └─────────────────────────┘  │
                                 │  ┌─────────────────────────┐  │
                                 │  │  Linearity Enforcement   │  │
                                 │  │  LINEAR/AFFINE/RELEVANT  │  │
                                 │  └─────────────────────────┘  │
                                 │  ┌─────────────────────────┐  │
                                 │  │  Plexus Opcodes          │  │
                                 │  │  0xC0–0xCF               │  │
                                 │  └─────────────────────────┘  │
                                 └───────────────────────────────┘
                                           │
                              Host function imports (WASM boundary)
                                           │
                                           ▼
                                 ┌─────────────────────┐
                                 │  @bsv/sdk (v1.6.12) │
                                 │  Local Bun package   │
                                 │                     │
                                 │  BEEF parse/build   │
                                 │  BUMP verification  │
                                 │  BRC-42 derivation  │
                                 │  ARC broadcast      │
                                 │  Transaction build   │
                                 └─────────────────────┘
                                 ┌─────────────────────┐
                                 │  @bsv/wallet-toolbox│
                                 │  (v1.5.9)           │
                                 │  Local Bun package   │
                                 │                     │
                                 │  Key derivation     │
                                 │  Signing helpers    │
                                 │  createAction       │
                                 │  internalizeAction  │
                                 └─────────────────────┘
```

### 2.2 Data Flow

```
Certificate issuance (Plexus)
  │
  ▼
subjectPublicKey (33 bytes, compressed secp256k1)
  │
  ├──→ cell-engine.deriveBCA(pubkey, prefix, modifier) → IPv6 addr (16 bytes)
  │
  ├──→ cell-engine.packCell(header, payload) → 1024 bytes
  │         │
  │         ▼
  │    @bsv/sdk.createAction() → anchored on BSV
  │         │
  │         ▼
  │    BEEF envelope with BUMP merkle proof
  │         │
  │         ▼
  │    cell-engine.executeScript(lockingScript, context) → ScriptResult
  │
  └──→ cell-engine.checkLinearity(header, operation) → LinearityResult
```

### 2.3 WASM Boundary — What Crosses It

**Zig → TypeScript (WASM exports):**
- `packCell`, `unpackCell`, `packMultiCell`, `unpackMultiCell`
- `deriveBCA`, `verifyBCA`
- `executeScript`, `checkLinearity`
- `initEngine`, `resetEngine`

**TypeScript → Zig (WASM host function imports):**
- `host_parseBEEF(rawBytesPtr, rawBytesLen) → structPtr`
- `host_verifyBUMP(proofPtr, proofLen, headerPtr, headerLen) → bool`
- `host_sha256(dataPtr, dataLen, outPtr)`
- `host_log(msgPtr, msgLen, level)`

The Zig layer does NOT parse BEEF/BUMP directly. It calls into @bsv/sdk TypeScript for all BSV transaction operations. This keeps @bsv/sdk as the single source of truth for BSV parsing.

---

## 3. Existing Assets — Source Registry

Every source path referenced in this PRD is listed here by alias. All paths are relative to `/Users/toddprice/projects/semantos/`.

### 3.1 Forth Reference Implementation (semantos-gift-pack)

| Alias | Path | Description |
|-------|------|-------------|
| `FORTH:2PDA` | `semantos-gift-pack/forth/bitcoin-2pda.fs` | 1KB-cell dual-stack engine. SPUSH/SPOP/APUSH/APOP. Main: 1024 cells, Aux: 256 cells. **This is the reference for the Zig 2-PDA.** |
| `FORTH:SEMOBJ` | `semantos-gift-pack/forth/semantic-objects.fs` | 256-byte headers with linearity. Magic numbers, type hash, owner ID, timestamp, cell count. Object factories for LINEAR/AFFINE/RELEVANT. **This is the reference for cell header layout.** |
| `FORTH:SEMOBJ-ENH` | `semantos-gift-pack/forth/semantic-objects-enhanced.fs` | On-chain binding extension — TXID (32 bytes), VOUT (4 bytes), BUMP hash (24 bytes), derivation index (4 bytes) packed into 64 bytes of reserved header space. |
| `FORTH:LINEARITY` | `semantos-gift-pack/forth/linearity-enforcement.fs` | Enforcement logic for DUP/DROP/SWAP/OVER with linearity checks. LINEAR cannot duplicate or discard. AFFINE cannot duplicate. RELEVANT cannot discard. **This is the reference for Zig linearity.** |
| `FORTH:COMMERCE` | `semantos-gift-pack/forth/commerce-header.fs` | Commerce extension — Phase (1 byte, offset 94), Dimension (1 byte, offset 95), Parent Hash (32 bytes, offset 96), Prev State (32 bytes, offset 128). Type hash = SHA256(WHAT + ":" + HOW + ":" + INST). |
| `FORTH:MACROS` | `semantos-gift-pack/forth/craig-macros.fs` | Craig Wright macro system. XSWAP-n, XDROP-n, XROT-n, HASHCAT. Macro table at 0xB0-0xBF. REPEAT-OP for loop unrolling. |
| `FORTH:STORAGE` | `semantos-gift-pack/forth/semantic-storage-patterns.fs` | Payload usage patterns for the 768-byte data area. |
| `FORTH:SCRIPT-EXEC` | `semantos-gift-pack/forth/bitcoin-script-executor.fs` | Hex-based script execution through the 2-PDA. |
| `FORTH:S2S` | `semantos-gift-pack/forth/semantic-to-script.fs` | Bridge: semantic objects → Bitcoin Script hex. |
| `FORTH:COORDS` | `semantos-gift-pack/forth/coordinators-proven.fs` | Object coordination — how cells find and reference each other. |

### 3.2 Forth Core (bitcoin-script directory)

| Alias | Path | Description |
|-------|------|-------------|
| `CORE:2PDA` | `bitcoin-script/core/bitcoin-2pda.fs` | Core 2-PDA implementation (5.7KB). |
| `CORE:EXECUTOR` | `bitcoin-script/core/script-executor.fs` | Full script executor (38KB) — comprehensive opcode handling. |
| `CORE:SEMOBJ` | `bitcoin-script/core/semantic-objects.fs` | Core semantic objects (10.6KB). |
| `CORE:CONSTANTS` | `bitcoin-script/core/script-constants.fs` | BSV constants — SIGHASH_FORKID, opcodes. |
| `CORE:MACROS` | `bitcoin-script/core/craig-macros.fs` | Craig macros (4.8KB). |
| `FMT:BEEF` | `bitcoin-script/formats/beef.fs` | BEEF parser (BRC-95). |
| `FMT:BUMP` | `bitcoin-script/formats/bump.fs` | BUMP merkle proofs (BRC-74). |
| `FMT:EXTENDED` | `bitcoin-script/formats/extended-format.fs` | Extended format (BIP-239). |
| `FMT:SPV` | `bitcoin-script/formats/spv.fs` | SPV implementation. |

### 3.3 Semantos-Core (Todd's code, `@semantos/core` — formerly `@semantos/core`)

**Location**: `/Users/toddprice/projects/semantos-core/` (top-level project peer, NOT nested inside oddjobtodd)
**Origin**: Originally built as `@semantos/core` v0.2.0 inside `oddjobtodd/plexus-core/`. Must be moved to its own project directory and renamed. The package name in `package.json` should be `@semantos/core`.

| Alias | Path (relative to `/Users/toddprice/projects/semantos-core/`) | Description |
|-------|------|-------------|
| `CORE:ROOT` | `/` | Package root. `@semantos/core` (renamed from `@semantos/core`). Peer dep: `@bsv/sdk ^2.0.0`. |
| `CORE:INDEX` | `src/index.ts` | Barrel export: types, Compiler, Kernel, Recovery, Metering. |
| `CORE:SEMOBJ` | `src/types/semantic-objects.ts` | SemanticType enum (LINEAR/AFFINE/RELEVANT), LinearObject, AffineObject, RelevantObject interfaces, ConsumptionProof, RevocationProof, type guards. **This is the TypeScript type system the Zig layer must match.** |
| `CORE:CAPABILITY` | `src/types/capability.ts` | CapabilityToken (extends LinearObject), CapabilityType enum (RECOVERY, PERMISSION, DATA_ACCESS, COMPUTE_DELEGATION, METERED_ACCESS, TRANSFER), CapabilityConstraints, factory functions. **BRC-108 implementation.** |
| `CORE:DOMAIN-FLAGS` | `src/types/domain-flags.ts` | DomainFlag type (uint32). Well-known: EDGE_CREATION(0x01), SIGNING(0x02), ENCRYPTION(0x03), MESSAGING(0x04), ATTESTATION(0x05), CHILD_CREATION(0x06), PERMISSION_GRANT(0x07), DATA_SOVEREIGNTY(0x08), SCHEMA_SIGNING(0x09), METERING(0x0A). Ranges: well-known [1,255], extended [256,65535], sovereign [65536,0xFFFFFFFF]. `toProtocolId()` for BRC-43 conversion. |
| `CORE:WASM` | `src/cell-engine/wasm-interface.ts` | **PlexusKernelWasm** interface (the WASM export contract): `kernel_init`, `kernel_reset`, `kernel_load_script`, `kernel_load_unlock`, `kernel_execute`, `kernel_get_type_class`, `kernel_get_opcount`, `kernel_get_error`, `kernel_stack_depth`, `kernel_stack_peek`, `memory`. **PlexusKernelHostImports** interface: `host_sha256`, `host_hash160`, `host_hash256`, `host_checksig`, `host_checkmultisig`, `host_get_blocktime`, `host_get_sequence`, `host_log`. `loadKernel()` function. **The Zig WASM module must satisfy this interface exactly.** |
| `CORE:OPCODES` | `src/cell-engine/opcodes.ts` | Plexus opcode definitions for the 2-PDA. |
| `CORE:VALIDATOR` | `src/compiler/validator.ts` | Consumption rule validation per semantic type. |
| `CORE:RECOVERY` | `src/recovery/export-payload.ts` | Export payload assembly for recovery protocol. |
| `CORE:CHALLENGE` | `src/recovery/challenge.ts` | Challenge-response protocol. |
| `CORE:FSM` | `src/metering/channel-fsm.ts` | 8-state payment channel FSM. |
| `CORE:SETTLEMENT` | `src/metering/settlement.ts` | Settlement logic for metered channels. |
| `CORE:METERING-TYPES` | `src/types/metering.ts` | Metering type definitions. |
| `CORE:TRANSFER` | `src/types/transfer.ts` | Transfer record types. |
| `CORE:RECOVERY-TYPES` | `src/types/recovery.ts` | Recovery payload types. |

### 3.4 Semantos-Kernel (Production TypeScript Runtime)

The semantos-kernel (`oddjobtodd/src/lib/semantos-kernel/`) is the 220KB Layer 2 runtime — domain-agnostic infrastructure for typed, versioned, hash-chained semantic objects. The Zig cell engine integrates with this runtime: Zig handles cell packing/verification, the kernel handles persistence, state management, and domain logic. Phase 6 integration tests must validate against this runtime.

| Alias | Path | Description |
|-------|------|-------------|
| `KERNEL:INDEX` | `oddjobtodd/src/lib/semantos-kernel/index.ts` | Barrel export. Re-exports cellPacker, typeHashRegistry, adapter, schema, channel service, policy evaluator, merkle envelope, and both extensions. **Canonical import path for all kernel modules.** |
| `KERNEL:SCHEMA` | `oddjobtodd/src/lib/semantos-kernel/schema.core.ts` | **39KB Drizzle schema.** 15+ tables: `semanticObjects`, `objectStates`, `objectPatches`, `objectScores`, `evidenceItems`, `semInstruments`, `anchorRequests`, `participants`, `channels`, `channelPolicies`, `accessPolicies`, `objectEdges`, `objectBindings`, `pendingWrites`, `outcomes`. **Production persistence target — Phase 6 integration tests validate against this, NOT WALLET:SCHEMA (legacy SQLite).** |
| `KERNEL:ADAPTER` | `oddjobtodd/src/lib/semantos-kernel/adapter.base.ts` | **18KB SemanticAdapter base class.** `ensureObject()`, `recordState()`, `recordScore()`, `recordEvidence()`, `recordInstrument()`, `recordTransition()`, `requestAnchor()` (two-phase commit), `retryPendingWrites()` (dead-letter queue with exponential backoff). `_safeWrite()` DLQ pattern. **Base class extended by domain extensions (trades, risk).** |
| `KERNEL:MERKLE` | `oddjobtodd/src/lib/semantos-kernel/merkleEnvelope.ts` | **7.3KB merkle envelope.** `buildMerkleTree()` (double-SHA256), `computeMerkleRoot()`, `generateMerkleProof()`, `verifyMerkleProof()`, `serializeMerkleEnvelope()` → `[version(1B)][leafCount(4B)][root(32B)][proofCount(4B)][proofs...]`. **Phase 5 reference for ENVELOPE cell content generation.** |
| `KERNEL:CHANNEL` | `oddjobtodd/src/lib/semantos-kernel/channelService.ts` | **9.1KB channel service.** Participant/channel/policy CRUD. `AI_IDENTITY_REF = "ai:assistant"`. Channel lifecycle management with policy evaluation. |
| `KERNEL:POLICY` | `oddjobtodd/src/lib/semantos-kernel/policyEvaluator.ts` | **7.8KB RBAC policy evaluator.** `filterState()`, `filterStateForAi()`, `evaluateChannelPolicy()`, `checkContributionRight()`, `checkSelectionGateAccess()`. Role-based access control for semantic objects within channels. |
| `KERNEL:TRADES-SCHEMA` | `oddjobtodd/src/lib/semantos-kernel/trades/schema.trades.ts` | Trades extension Drizzle schema. |
| `KERNEL:TRADES-ADAPTER` | `oddjobtodd/src/lib/semantos-kernel/trades/adapter.trades.ts` | Trades extension adapter (extends SemanticAdapter). |
| `KERNEL:TRADES-POLICY` | `oddjobtodd/src/lib/semantos-kernel/trades/policies.trades.ts` | 4 policy templates: homeowner, short-term tenant, long-term tenant, landlord. |
| `KERNEL:RISK-SCHEMA` | `oddjobtodd/src/lib/semantos-kernel/risk/schema.risk.ts` | **9-cell BREM schema.** Risk assessment extension. |
| `KERNEL:RISK-ADAPTER` | `oddjobtodd/src/lib/semantos-kernel/risk/adapter.risk.ts` | **37KB risk adapter** (largest file). Scoring, gates, challenges, discretion cluster. Extends SemanticAdapter. |
| `KERNEL:RISK-POLICY` | `oddjobtodd/src/lib/semantos-kernel/risk/policies.risk.ts` | 5 risk policy templates. |
| `KERNEL:RISK-BREM` | `oddjobtodd/src/lib/semantos-kernel/risk/integration.brem.ts` | Bridge to brem-agent. BREM integration layer. |

### 3.5 CellPacker & TypeHashRegistry (now in semantos-core)

These files have been cloned from `oddjobtodd` into `semantos-core/src/cell-engine/` so the package is self-contained. The semantos-core versions are canonical. Original locations in oddjobtodd are retained as downstream consumers but are not the source of truth for the Zig implementation.

| Alias | Path | Description |
|-------|------|-------------|
| `PACKER:MAIN` | `semantos-core/src/cell-engine/cellPacker.ts` | **650-line production cell packer.** Multi-cell structured packing. Constants: CELL_SIZE=1024, HEADER_SIZE=256, PAYLOAD_SIZE=768. Continuation types: BUMP(0x01), ATOMIC_BEEF(0x02), ENVELOPE(0x03), DATA(0x04), STATE(0x05). Continuation header: 8 bytes (cellType:1, cellIndex:2, totalCells:2, payloadSize:2, reserved:1). Functions: `packMultiCell`, `unpackMultiCell`, `assembleSemanticObject`, `disassembleSemanticObject`, `createBumpCells`, `createAtomicBeefCells`, `createEnvelopeCells`, `createDataCells`. Imports `buildCellHeader`/`packCell`/`unpackCell`/`CellHeader` from `typeHashRegistry`. **This is the canonical reference for bit-identical Zig output.** |
| `PACKER:TYPE-REGISTRY` | `semantos-core/src/cell-engine/typeHashRegistry.ts` | **Canonical wire-format header builder.** `buildCellHeader`, `packCell`, `unpackCell`, `computeTypeHash`, `computeWhatHash`, `computeHowHash`, `computeInstHash`, `computePhaseHash`, `contentHash`, `isValidCell`. Defines `CellHeader` interface, `LINEARITY` constants (1-4), `PHASE_BYTES` (0x00-0xFF), `DIMENSION_BYTES` (0x00-0x03), `PHASE_LINEARITY` mapping (which pipeline phase produces which linearity class). **This file resolves Q6: packed offsets are magic(0,16B), linearity(16,4B), version(20,4B), flags(24,4B), refCount(28,2B), typeHash(30,32B), ownerId(62,16B), timestamp(78,8B), cellCount(86,4B), totalSize(90,4B). The Zig implementation MUST match these offsets.** |
| `PACKER:MERKLE` | `semantos-core/src/cell-engine/merkleEnvelope.ts` | **7.3KB merkle envelope.** `buildMerkleTree()` (double-SHA256), `computeMerkleRoot()`, `generateMerkleProof()`, `verifyMerkleProof()`, `serializeMerkleEnvelope()`. Dependency of cellPacker.ts. |
| `PACKER:BREM` | `data/brem-agent/src/lib/brem-compiler/semantos/cellPacker.ts` | Brem-agent variant (7.9KB). Compiler integration version (downstream consumer, not source of truth). |

### 3.6 BSV SDKs (Bun-converted, local)

| Alias | Path | Description |
|-------|------|-------------|
| `SDK:TS` | `ts-sdk/` | `@bsv/sdk` v1.6.12. 211 TypeScript files. Primitives (ECDSA, Hash, PublicKey, PrivateKey), Transaction (Beef, BeefTx, MerklePath), Wallet, Script, Auth. Build: `bun run build`. |
| `SDK:TOOLBOX` | `wallet-toolbox/` | `@bsv/wallet-toolbox` v1.5.9. 197 TypeScript files. Wallet class, Signer (createAction, signAction, internalizeAction), Storage, Monitor, Services. Build: `tsc --build`. |

### 3.7 Documentation

| Alias | Path | Description |
|-------|------|-------------|
| `DOC:BRIDGE` | `semantos-gift-pack/docs/compiler-to-semantos-bridge.md` | TypeScript compiler → Forth cell mapping. Type hash computation, linearity transitions, cell fit analysis (JSON vs binary TLV). |
| `DOC:PIPELINE` | `semantos-gift-pack/docs/semantic-compiler-pipeline.md` | Full compiler: SOURCE → LEXER → PARSER → AST → TYPE CHECK → OPTIMISE → CODEGEN → RUNTIME. |
| `DOC:TAXONOMY` | `semantos-gift-pack/docs/universal-commerce-taxonomy-spec.md` | Type system: WHAT × HOW × INSTRUMENT. |
| `DOC:LISP` | `semantos-gift-pack/docs/lisp-forth-script.md` | LISP axiom pipeline: symbolic composition → concatenative assembly → stack operations. |
| `DOC:LINEAR-COMPILER` | `semantos-gift-pack/docs/linear-script-macro-compiler.md` | Linearity-aware macro compilation. Resource signatures on macros. |
| `DOC:WASM-SPEC` | `semantos-gift-pack/docs/plexus-wasm-runtime-spec.docx` | WASM runtime spec. |
| `DOC:TRADES` | `semantos-gift-pack/docs/real-world-example-trades-extension.md` | Real-world example: handyman intake bot with LINEAR state transitions. |
| `DOC:PLEXUS-TECH` | `semantos-gift-pack/docs/Plexus Technical Requirements Draft v1.3.pdf` | Plexus technical requirements (authored by Todd, used to guide Dusk development). Components: Plexus API, Core Library, Contracts Library, Network SDK, Vendor SDK, Plexus CLI, Capability Domain, Verifier Sidecar, Identity Domain. |
| `DOC:PLEXUS-CLIENT` | `semantos-gift-pack/docs/Plexus Client Requirements Draft v2.1.pdf` | Plexus client requirements (authored by Todd). Recovery Substrate, OTP/Challenge auth, Metadata Assembly/Export, Zero-Knowledge Key Facilitation, Canonical Derivation Registry, Functional Domain Scoping. |
| `DOC:BCA-PAPER` | `(uploaded) 2311.15842v1.pdf` | "IPv6 Bitcoin-Certified Addresses" by Mathieu Ducroux (nChain). BCA generation from public key + block header + modifier. Verification: 2 hash evaluations. BCA Parameters: modifier (16 bytes), public key, transaction, block header, subnet prefix (8 bytes), collision count (1 byte). |
| `DOC:SEMANTOS-V3` | `semantos/docs/semantosV3-implementation-plan.md` | Bitcoin Script Semantic OS implementation plan. Core architecture vision. Semantic opcodes. Earlier 194-byte header spec (superseded by 256-byte layout). |
| `DOC:THING-MAKER` | `semantos/docs/thing-maker-mvp-specification.md` | Thing object MVP spec. Pool-based memory: THING pool (4096), MAKER pool (256), String pool (8192B). |
| `DOC:FORTH-GUIDE` | `semantos/docs/semantos-forth-guide.md` | Forth kernel guide. Thing structure defs (Container, Patch, Certificate, Capsule). Registry system. |
| `DOC:HYBRID-ARCH` | `semantos/HYBRID-LINEAR-AFFINE-MEMORY-MODEL.md` | Resource classification: LINEAR/AFFINE/RELEVANT/DEBUG. Linearity-aware 28-byte enhanced object. |
| `DOC:HYBRID-ARCH2` | `semantos/hybrid-architecture.md` | Resource-aware symbolic reduction. Phase-aware stack discipline (Phases 1-12). |
| `DOC:MFP-SPEC` | `cashlanes/MFP-SPECIFICATION.md` | Universal Metered Flow Protocol specification. Defines flow measurement, settlement, and channel lifecycle for micropayment-metered infrastructure. |

### 3.8 Semantic Wallet & CLI

| Alias | Path | Description |
|-------|------|-------------|
| `WALLET:CLI` | `semantic-wallet/cli/semantic-cli.cjs` | CLI tool. Uses BSV SDK (Script, Transaction, OP, PrivateKey, Hash). Creates semantic objects with UTXO binding. |
| `WALLET:BASKET` | `semantic-wallet/cli/semantic-utxo-basket.cjs` | UTXO basket operations. |
| `WALLET:INDEXER` | `semantic-wallet/cli/semantic-indexer.cjs` | Semantic object indexer. |
| `WALLET:BROADCAST` | `semantic-wallet/cli/broadcast-semantic-object.cjs` | Broadcasting semantic objects. |
| `WALLET:SCHEMA` | `semantic-wallet/migrations/004_linear_semantic_objects.sql` | Linear semantic objects schema — `linear_semantic_objects`, `bkds_semantic_keys`, `linear_object_audit` tables. |
| `WALLET:RUST-TYPES` | `semantic-wallet/src-tauri/src/types/linear_semantic.rs` | Rust semantic types. |
| `WALLET:RUST-CMD` | `semantic-wallet/src-tauri/src/commands/semantic_objects.rs` | Rust semantic object commands. |

### 3.9 CashLanes (Universal Metered Flow Protocol)

| Alias | Path | Description |
|-------|------|-------------|
| `CASHLANES:FSM` | `cashlanes/src/fsm/ChannelFSM.ts` | **636-line payment channel FSM.** 7 states: UNFUNDED → FUNDING_PENDING → FUNDED → FLOW_READY → FLOW_ACTIVE → SETTLING → CLOSED. SPV validation before flow init. Frozen canonical artifacts. **Direct reference for plexus-core metering FSM.** |
| `CASHLANES:FLOW` | `cashlanes/src/fsm/FlowAdapter.ts` | **324-line universal flow adapter.** Abstract interface for domain-specific flow measurement (network MB, energy kWh, compute CPU-sec, storage GB, transport km). Tick-based metering with settlement callbacks. **Pattern for Semantos metered channels.** |
| `CASHLANES:WALLET` | `cashlanes/src/wallet/MultiRoleWalletManager.ts` | Role isolation: provider/consumer via distinct org IDs, session cookies, CookieJars. BRC-42 key derivation per role. |
| `CASHLANES:UTXO` | `cashlanes/src/wallet/ChannelUTXOTracker.ts` | Dual-protocol basket-based UTXO tracking. Same UTXO in both customer/provider baskets. Minimal payload internalization (BRC-100). |
| `CASHLANES:BRC100` | `cashlanes/src/wallet/BRC100PayloadBuilder.ts` | BRC-100 action payload generation. Role-scoped keyIDs with entropy. Protocol separation: identity [0], wallet payment [1], basket insertion [1]. |
| `CASHLANES:SETTLE` | `cashlanes/src/settlement/BasketSettlementManager.ts` | **297-line prepaid fee settlement.** 1-sat ANYONECANPAY|NONE fee pattern. Multisig UTXO discovery via dual baskets. Standard 2-of-2 signatures. |
| `CASHLANES:BRC100-SETTLE` | `cashlanes/src/settlement/BRC100SettlementManager.ts` | BRC-100 compliant settlement orchestration with SPV verification before broadcast. |
| `CASHLANES:KEY-DERIV` | `cashlanes/src/settlement/SettlementKeyDerivation.ts` | BRC-42 key derivation for settlement channels. |
| `CASHLANES:IDENTITY` | `cashlanes/src/identity/BRC42ChannelKeyManager.ts` | Channel key derivation via BRC-42. Identity-aware channel management. |
| `CASHLANES:SPV` | `cashlanes/src/spv/TransactionAncestryResolver.ts` | BEEF proof handling for SPV verification. |
| `CASHLANES:BEEF` | `cashlanes/src/spv/BEEFPackageBuilder.ts` | SPV proof construction via BEEF packages. |
| `CASHLANES:1SAT` | `cashlanes/src/utils/OneSatUTXOManager.ts` | 1-sat fee UTXO pool management. |
| `CASHLANES:SPEC` | `cashlanes/MFP-SPECIFICATION.md` | Complete Universal Metered Flow Protocol specification. |
| `CASHLANES:GUARDRAILS` | `cashlanes/CLAUDE.md` | Implementation guardrails: role separation, basket naming, FSM rules, BRC-100 compliance. |

### 3.10 Semantos Implementation Documents

| Alias | Path | Description |
|-------|------|-------------|
| `DOC:SEMANTOS-V3` | `semantos/docs/semantosV3-implementation-plan.md` | Bitcoin Script Semantic OS implementation plan. Core architecture vision. Phase 0 (crypto foundation) → Phase 1 (Bitcoin Script semantic model). Defines semantic opcodes (OP_CREATE_CONTAINER, OP_APPLY_PATCH, OP_SEAL_CONTAINER). 194-byte object header spec (earlier iteration — superseded by 256-byte layout). |
| `DOC:THING-MAKER` | `semantos/docs/thing-maker-mvp-specification.md` | MVP specification for Thing object implementation. Pool-based memory allocation: THING pool (4096 slots), MAKER pool (256 slots), String pool (8192 bytes). |
| `DOC:FORTH-GUIDE` | `semantos/docs/semantos-forth-guide.md` | Forth implementation guide for Semantic OS kernel. Thing structure definitions (Container, Patch, Certificate, Capsule). Registry system and semantic stack specs. Working Forth code examples. |
| `DOC:HYBRID-ARCH` | `semantos/HYBRID-LINEAR-AFFINE-MEMORY-MODEL.md` | Resource classification system (LINEAR, AFFINE, RELEVANT, DEBUG). Linearity-aware 28-byte object structure. Phase-specific implementations. Dev mode vs production mode. |
| `DOC:HYBRID-ARCH2` | `semantos/hybrid-architecture.md` | Enhanced core principles with resource-aware symbolic reduction. Phase-aware stack discipline (Phases 1-12 progression). Linearity-enforcing stack machine details. |

### 3.11 TypeScript Semantic Objects & UTXO Mapping

| Alias | Path | Description |
|-------|------|-------------|
| `SEMOBJ:SERVICE` | `semantos/semantic-wallet/src/lib/services/semanticObjects.ts` | SemanticObjectsService with header serialization and linearity verification. |
| `SEMOBJ:ADAPTER` | `oddjobtodd/src/lib/semantos-kernel/adapter.base.ts` | SemanticAdapter base class — `ensureObject()`, `recordState()`, `recordScore()`, `recordEvidence()`, `recordInstrument()`, `requestAnchor()` (two-phase commit), `retryPendingWrites()` (dead-letter queue with exponential backoff). |
| `SEMOBJ:MANAGER` | `semantos/semantic-object-tool/src/semantic-manager.js` | SemanticManager class with CLI command bridge methods: `generateCliCommand(semanticObject, action, amount, recipient)`. |
| `SEMOBJ:OUTPUT-STORE` | `semantos/semantic-wallet/src/lib/stores/outputs.ts` | Svelte store managing SpendableOutput array — `addOutput()`, `updateOutput()`, `removeOutput()`, `markAsSpent()`. Derived stores: `unspentOutputs`, `totalBalance`, `outputsByAddress`. |
| `SEMOBJ:WALLET-SVC` | `semantos/semantic-wallet/src/lib/services/walletService.ts` | Wallet service using wallet-toolbox. Lists outputs, manages spendable state. |
| `SEMOBJ:BTC-TYPES` | `semantos/semantic-wallet/src/lib/types/bitcoin.ts` | SpendableOutput interface: `{ txid, index, satoshis, spent, address?, lockScript?, privateKey?, keyIndex?, bumpProof? }`. Bitcoin transaction types. |
| `SEMOBJ:UTXO-TEST` | `semantos/semantic-wallet/test/migration/phase2a/test_utxo_binding.js` | Test demonstrating UTXO binding with semantic objects — validates the cell-to-output mapping. |
| `SEMOBJ:LIFECYCLE` | `semantos/semantic-wallet/test/migration/phase2a/test_object_lifecycle.js` | Complete object lifecycle testing (create → bind → spend → verify). |

### 3.12 Infrastructure

| Alias | Path | Description |
|-------|------|-------------|
| `INFRA:WAB` | `bsv-wab/` | Wallet Authentication Backend. |
| `INFRA:AUTH` | `bsv-auth-service/` | BSV auth service with schema. |
| `INFRA:METANET` | `metanet-desktop/` | Metanet Desktop. |
| `INFRA:HEADERS` | `block-headers-service/` | Block headers service. |

---

## 4. Hard Constraints — Non-Negotiable

### 4.1 No Mocks in Production Code Paths

- Test fixtures are real serialised data, not fabricated structs
- Integration tests use a real PostgreSQL/SQLite instance, real BSV testnet transactions, real WASM binary
- Unit tests operate on real inputs derived from the Forth reference implementation (`FORTH:2PDA`, `FORTH:SEMOBJ`)
- If you cannot test something without a mock, the architecture is wrong — redesign the interface

### 4.2 No Hardcoded Values

- All constants (stack sizes, cell sizes, opcode ranges, threshold values, magic numbers) defined in a single `constants.zig` and a matching `constants.ts`
- Both files are generated from a single source of truth (`constants.json`) via a build step
- The magic numbers (`0xDEADBEEF`, `0xCAFEBABE`, `0x13371337`, `0x42424242`) come from `FORTH:SEMOBJ` lines 78-81
- Header field sizes come from `FORTH:SEMOBJ` lines 40-50
- Linearity type constants (1=LINEAR, 2=AFFINE, 3=RELEVANT, 4=DEBUG) come from `FORTH:SEMOBJ` lines 23-26
- Commerce phase constants come from `FORTH:COMMERCE` lines 38-46
- Taxonomy dimension constants come from `FORTH:COMMERCE` lines 51-54
- Protocol version, schema version, IR version — all from constants, never literals in logic

### 4.3 No General R&D Artefacts

- No `TODO: implement later` in production code paths
- No placeholder functions that return hardcoded success
- No feature flags that disable production behaviour
- If a component is not ready, it is not merged — it lives in a feature branch with a failing test that documents what is missing

### 4.4 Leverage Existing Code

- The Forth `FORTH:SEMOBJ` is the reference for header layout. Port it to Zig. Do not redesign the cell format.
- The existing `SDK:TS` handles all BSV transaction operations. The Zig layer calls into it via the WASM boundary — it does not reimplement transaction parsing.
- Plexus-core (being built by Dusk per `DOC:PLEXUS-TECH`) owns BRC-52 certificate issuance and BRC-42 derivation. The Zig layer consumes public key bytes — it does not re-derive keys.
- The Forth linearity enforcement (`FORTH:LINEARITY`) is the semantic reference. The Zig implementation must reject the same operations the Forth rejects.
- CashLanes (`CASHLANES:FSM`, `CASHLANES:SETTLE`) is the production reference for payment channel FSM states, BRC-100 settlement, and metered flow adapters. The plexus-core metering module must align with these battle-tested patterns.
- The TypeScript semantic object adapter (`SEMOBJ:ADAPTER`) demonstrates the two-phase commit anchoring pattern and dead-letter queue recovery. The Zig layer's cell lifecycle must support the same anchor/retry semantics.
- `PACKER:TYPE-REGISTRY` (`typeHashRegistry.ts`) defines the canonical packed wire-format header offsets (Q6 resolved). The Zig header layout must match these offsets byte-for-byte.

### 4.5 Production Engineering Standards

- Every public function has a doc comment
- Every error case is handled explicitly — no `catch unreachable` in production paths
- Memory: no leaks, no use-after-free, verified by Zig's safety checks in debug builds
- The build must be reproducible: same inputs always produce the same WASM binary

---

## 5. Package Specification

### 5.1 `@semantos/protocol-types` (or extend `@semantos/core`)

**Purpose**: Single source of truth for cross-package TypeScript types. **Note**: Much of what this package would contain already exists in `CORE:SEMOBJ`, `CORE:CAPABILITY`, `CORE:DOMAIN-FLAGS`, and `CORE:WASM`. The decision (see Q5, Q6) is whether to create a new package or extend plexus-core's types module. Either way, these are the canonical types.

**Public API**:

```typescript
// Cell format types
// Packed wire format (from typeHashRegistry.ts — Q6 RESOLVED)
export interface CellHeader {
  magic: Uint8Array;        // 16 bytes at offset 0  (0xDEADBEEF CAFEBABE 13371337 42424242)
  linearity: LinearityType; //  4 bytes at offset 16
  version: number;          //  4 bytes at offset 20
  flags: number;            //  4 bytes at offset 24
  refCount: number;         //  2 bytes at offset 28
  typeHash: Uint8Array;     // 32 bytes at offset 30
  ownerId: Uint8Array;      // 16 bytes at offset 62
  timestamp: bigint;        //  8 bytes at offset 78
  cellCount: number;        //  4 bytes at offset 86
  totalSize: number;        //  4 bytes at offset 90
  // reserved block starts at offset 94 (162 bytes)
}

export interface CommerceExtension {
  phase: CommercePhase;       // 1 byte at offset 94
  dimension: TaxonomyDimension; // 1 byte at offset 95
  parentHash: Uint8Array;     // 32 bytes at offset 96
  prevState: Uint8Array;      // 32 bytes at offset 128
}

export interface OnChainBinding {
  txid: Uint8Array;           // 32 bytes
  vout: number;               // 4 bytes
  bumpHash: Uint8Array;       // 24 bytes
  derivationIndex: number;    // 4 bytes
}

export enum LinearityType {
  LINEAR = 1,     // Must be used exactly once (money, signatures)
  AFFINE = 2,     // Can be discarded (certificates, permissions)
  RELEVANT = 3,   // Can be copied (public keys, hashes)
  DEBUG = 4,      // Unrestricted during development
}

export enum CommercePhase {
  SOURCE = 0x00, PARSE = 0x01, AST = 0x02,
  TYPECHECK = 0x03, OPTIMISE = 0x04, CODEGEN = 0x05,
  ACTION = 0x06, OUTCOME = 0x07, UNKNOWN = 0xFF,
}

export enum TaxonomyDimension {
  COMPOSITE = 0x00, WHAT = 0x01, HOW = 0x02, INSTRUMENT = 0x03,
}

export enum CellType {
  BUMP = 0x01, ATOMIC_BEEF = 0x02, ENVELOPE = 0x03, DATA = 0x04,
}

// Plexus integration types
export interface CertificateRef {
  certId: Uint8Array;         // 32 bytes
  subjectPublicKey: Uint8Array; // 33 bytes, compressed secp256k1
  issuerCertId: Uint8Array;   // 32 bytes
  childIndex: number;
}

export interface CapabilityTokenRef {
  txid: Uint8Array;           // 32 bytes
  vout: number;
  lockingScript: Uint8Array;
  ownerCertId: Uint8Array;    // 32 bytes
}

// BCA types (per BCA paper DOC:BCA-PAPER)
export interface BCAInput {
  subjectPublicKey: Uint8Array; // 33 bytes, compressed secp256k1
  subnetPrefix: Uint8Array;    // 8 bytes (64-bit IPv6 subnet prefix)
  modifier: Uint8Array;        // 16 bytes (128-bit)
}

export interface BCAOutput {
  ipv6Address: Uint8Array;     // 16 bytes
}

export interface BCAVerifyInput extends BCAInput {
  ipv6Address: Uint8Array;     // 16 bytes to verify
}

// Script execution types
export interface ScriptContext {
  lockingScript: Uint8Array;
  unlockingScript: Uint8Array;
  transaction?: Uint8Array;    // raw tx bytes for CHECKSIG
  inputIndex?: number;
  hostFunctions: HostFunctionSet;
}

export interface ScriptResult {
  success: boolean;
  error?: ScriptError;
  stackDepth: number;
  topValue?: Uint8Array;
}

export enum ScriptError {
  STACK_OVERFLOW = 1,
  STACK_UNDERFLOW = 2,
  INVALID_OPCODE = 3,
  VERIFY_FAILED = 4,
  INSTRUCTION_LIMIT = 5,
  LINEARITY_VIOLATION = 6,
  DOMAIN_FLAG_MISMATCH = 7,
}

// Linearity operation types
export interface LinearityOperation {
  operation: 'consume' | 'duplicate' | 'discard' | 'inspect';
  cellHeader: Uint8Array;     // 256 bytes
}

export interface LinearityResult {
  allowed: boolean;
  error?: LinearityError;
}

export enum LinearityError {
  ALREADY_CONSUMED = 1,
  CONTRADICTORY_TRANSITION = 2,
  REVOKED_OBJECT = 3,
  CANNOT_DUPLICATE_LINEAR = 4,
  CANNOT_DUPLICATE_AFFINE = 5,
  CANNOT_DISCARD_RELEVANT = 6,
}

// Host function interface (what Zig imports from TS)
export interface HostFunctionSet {
  parseBEEF: (rawBytes: Uint8Array) => { transaction: Uint8Array; merkleProof: Uint8Array };
  verifyBUMP: (merkleProof: Uint8Array, blockHeader: Uint8Array) => boolean;
  sha256: (data: Uint8Array) => Uint8Array;
}
```

**Dependencies**: None (zero runtime dependencies).

**Build targets**: TypeScript → ESM + CJS via `tsc`.

### 5.2 `@semantos/cell-engine` (Zig → WASM)

**Purpose**: The execution engine. Implements the 2-PDA, cell packing, BCA derivation, linearity enforcement, and Plexus opcodes in Zig, compiled to WASM.

**Source Structure**:

```
packages/cell-engine/
  src/
    main.zig              # WASM entry point, exports
    cell.zig              # Cell pack/unpack (reference: FORTH:SEMOBJ)
    pda.zig               # 2-PDA engine (reference: FORTH:2PDA)
    opcodes.zig           # Standard Bitcoin Script opcodes (reference: CORE:EXECUTOR)
    opcodes_plexus.zig    # Plexus opcodes 0xC0-0xCF
    opcodes_macro.zig     # Craig macro opcodes 0xB0-0xBF (reference: FORTH:MACROS)
    bca.zig               # BCA derivation (reference: DOC:BCA-PAPER)
    linearity.zig         # Linearity enforcement (reference: FORTH:LINEARITY)
    commerce.zig          # Commerce header (reference: FORTH:COMMERCE)
    constants.zig         # Generated from constants.json
    host.zig              # Host function imports (WASM imports)
    errors.zig            # Error types (Zig error unions)
    allocator.zig         # Arena allocator for script execution
  tests/
    cell_conformance.zig      # Layer 1
    pda_conformance.zig       # Layer 1
    bca_conformance.zig       # Layer 1
    linearity_conformance.zig # Layer 1
    opcodes_conformance.zig   # Layer 1
    commerce_conformance.zig  # Layer 1
  bindings/
    index.ts                  # TypeScript WASM wrapper
    types.ts                  # Re-exports from @semantos/protocol-types
    loader.ts                 # WASM binary loader (Bun + browser)
    host-functions.ts         # Host function implementations using @bsv/sdk
  tests-ts/
    compat.test.ts            # Layer 2 — cross-language compatibility
    integration.test.ts       # Layer 3 — real infrastructure
    bench.ts                  # Layer 4 — benchmarks
  build.zig
  build.zig.zon
  constants.json              # Single source of truth
  package.json
```

**WASM Exports** — must satisfy `PlexusKernelWasm` interface from `CORE:WASM`:

```zig
// Kernel operations (matching PlexusKernelWasm interface exactly)
export fn kernel_init() callconv(.C) i32;
export fn kernel_reset() callconv(.C) void;
export fn kernel_load_script(script_ptr: [*]const u8, script_len: u32) callconv(.C) i32;
export fn kernel_load_unlock(unlock_ptr: [*]const u8, unlock_len: u32) callconv(.C) i32;
export fn kernel_execute() callconv(.C) i32;
export fn kernel_get_type_class() callconv(.C) i32;  // 0=LINEAR, 1=AFFINE, 2=RELEVANT, -1=unclassified
export fn kernel_get_opcount() callconv(.C) i32;
export fn kernel_get_error() callconv(.C) [*]const u8;  // null-terminated error string
export fn kernel_stack_depth() callconv(.C) i32;
export fn kernel_stack_peek(index: u32) callconv(.C) [*]const u8;

// Cell operations (extensions beyond PlexusKernelWasm)
export fn packCell(header_ptr: [*]const u8, payload_ptr: [*]const u8, out_ptr: [*]u8) callconv(.C) i32;
export fn unpackCell(cell_ptr: [*]const u8, header_out: [*]u8, payload_out: [*]u8) callconv(.C) i32;
export fn packMultiCell(input_ptr: [*]const u8, input_len: u32, out_ptr: [*]u8) callconv(.C) i32;
export fn unpackMultiCell(buffer_ptr: [*]const u8, buffer_len: u32, out_ptr: [*]u8) callconv(.C) i32;

// BCA operations
export fn deriveBCA(pubkey_ptr: [*]const u8, prefix_ptr: [*]const u8, modifier_ptr: [*]const u8, out_ptr: [*]u8) callconv(.C) i32;
export fn verifyBCA(addr_ptr: [*]const u8, pubkey_ptr: [*]const u8, prefix_ptr: [*]const u8, modifier_ptr: [*]const u8) callconv(.C) i32;

// Linearity
export fn checkLinearity(header_ptr: [*]const u8, operation: u8) callconv(.C) i32;

// Memory management
export fn allocBuffer(size: u32) callconv(.C) [*]u8;
export fn freeBuffer(ptr: [*]u8, size: u32) callconv(.C) void;
```

**WASM Imports** — must implement `PlexusKernelHostImports` from `CORE:WASM`:

```zig
// Crypto (matching PlexusKernelHostImports exactly)
extern "host" fn host_sha256(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
extern "host" fn host_hash160(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
extern "host" fn host_hash256(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
extern "host" fn host_checksig(pubkey_ptr: [*]const u8, pubkey_len: u32, msg_ptr: [*]const u8, msg_len: u32, sig_ptr: [*]const u8, sig_len: u32) i32;
extern "host" fn host_checkmultisig(pubkeys_ptr: [*]const u8, pubkeys_count: u32, sigs_ptr: [*]const u8, sigs_count: u32, msg_ptr: [*]const u8, msg_len: u32, threshold: u32) i32;
extern "host" fn host_get_blocktime() i32;
extern "host" fn host_get_sequence() i32;
extern "host" fn host_log(msg_ptr: [*]const u8, msg_len: u32) void;
```

**Build targets**:
- `zig build` → native tests
- `zig build -Dtarget=wasm32-freestanding` → embedded WASM
- `zig build -Dtarget=wasm32-wasi` → server WASM

**Dependencies**:
- Zig: zero external dependencies (std lib only)
- TypeScript bindings: `@semantos/protocol-types`, `@bsv/sdk` (local at `SDK:TS`)

**WASM binary size target**: < 500KB

---

## 6. Implementation Phases

### Phase 0: Scaffolding and Constants Unification
**Duration**: 1 week (with 40% buffer: ~10 days)
**Completion criterion**: `constants.json` exists, `constants.zig` and `constants.ts` are generated from it, `@semantos/protocol-types` compiles with zero errors, Zig build scaffold compiles to an empty WASM binary.

**Tasks**:
1. Create `constants.json` from `FORTH:SEMOBJ` (lines 16-18, 23-26, 40-68, 78-81) and `FORTH:COMMERCE` (lines 29-54)
2. Write build script: `constants.json` → `constants.zig` + `constants.ts`
3. Create `@semantos/protocol-types` package with all types from Section 5.1
4. Scaffold `packages/cell-engine/` with `build.zig`, empty source files, `package.json`
5. Verify: `zig build` produces an empty WASM binary, `bun run build` compiles protocol-types

### Phase 1: Cell Packing in Zig
**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Completion criterion**: Layer 1 cell conformance tests pass. Layer 2 cross-language compatibility tests pass — Zig-packed cells are byte-identical to cells packed by the Forth reference (`FORTH:SEMOBJ`).

**Tasks**:
1. Implement `cell.zig`: `packCell`, `unpackCell` matching `FORTH:SEMOBJ` header layout exactly
2. Implement `commerce.zig`: commerce header extension matching `FORTH:COMMERCE`
3. Implement `packMultiCell`/`unpackMultiCell` for continuation cells (8-byte header + 1016-byte payload)
4. Write `cell_conformance.zig` — test vectors derived from running `FORTH:SEMOBJ` in GForth and capturing raw bytes
5. Write `commerce_conformance.zig` — test vectors from `FORTH:COMMERCE`
6. Write `compat.test.ts` — pack in Zig, verify bytes match; pack in TS, verify Zig unpacks correctly
7. Verify: `zig build test` passes, `bun test tests-ts/compat.test.ts` passes

### Phase 2: BCA Derivation and Verification
**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Completion criterion**: BCA conformance tests pass. `deriveBCA` produces correct IPv6 addresses per the BCA paper (DOC:BCA-PAPER). `verifyBCA` validates in 2 hash evaluations.

**Tasks**:
1. Implement `bca.zig` following Section IV of DOC:BCA-PAPER
   - BCA generation: hash(modifier || subnetPrefix || collisionCount || pubkey) → Hash1 → interfaceIdentifier
   - Concatenate subnetPrefix + interfaceIdentifier → 128-bit IPv6 address
   - Mask u, g bits; encode sec parameter
2. Implement `host.zig` with `host_sha256` import (BCA needs SHA-256)
3. Write `bca_conformance.zig` with test vectors computed independently
4. Write `host-functions.ts` — implement `host_sha256` using `SDK:TS` Hash module
5. Verify: `zig build test` passes, BCA derivation < 1ms

### Phase 3: 2-PDA Core — Stack Operations and Standard Opcodes
**Duration**: 3 weeks (with 40% buffer: ~30 days)
**Completion criterion**: Layer 1 PDA conformance tests pass. All standard Bitcoin Script opcodes (relevant subset) execute correctly on the 2-PDA.

**Tasks**:
1. Implement `pda.zig` — dual-stack engine matching `FORTH:2PDA`:
   - Main stack: 1024 × 1KB cells
   - Aux stack: 256 × 1KB cells
   - SPUSH/SPOP/APUSH/APOP
   - S-DEPTH/A-DEPTH/S-EMPTY/A-EMPTY
   - LIFO ordering
2. Implement `allocator.zig` — arena allocator for script execution (no dynamic allocation in hot paths)
3. Implement `opcodes.zig` — standard Bitcoin Script opcodes (reference: `CORE:EXECUTOR`):
   - Stack manipulation: OP_DUP, OP_DROP, OP_SWAP, OP_ROT, OP_OVER, OP_PICK, OP_ROLL, OP_TOALTSTACK, OP_FROMALTSTACK
   - Arithmetic: OP_ADD, OP_SUB, OP_MUL, OP_1ADD, OP_1SUB, OP_NEGATE, OP_ABS
   - Logic: OP_EQUAL, OP_EQUALVERIFY, OP_IF/OP_ELSE/OP_ENDIF, OP_VERIFY, OP_RETURN
   - Crypto: OP_SHA256, OP_HASH160, OP_HASH256, OP_CHECKSIG (via host function), OP_CHECKMULTISIG
   - Data: OP_PUSHDATA1/2/4, OP_0 through OP_16
4. Implement `opcodes_macro.zig` — Craig macro opcodes 0xB0-0xBF matching `FORTH:MACROS`
5. Implement bounded execution: hard instruction limit, no loops, no backward jumps
6. Write `pda_conformance.zig` — test vectors from running `FORTH:2PDA` operations in GForth
7. Write `opcodes_conformance.zig` — test every opcode against `CORE:EXECUTOR` reference behaviour
8. Implement `errors.zig` — all errors as Zig error unions, never panics in production
9. Verify: `zig build test` passes

### Phase 4: Plexus Opcodes and Linearity Enforcement
**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Completion criterion**: Plexus opcodes 0xC0–0xC4 execute correctly. Linearity enforcement rejects the same operations the Forth reference rejects.

**Tasks**:
1. Implement `linearity.zig` matching `FORTH:LINEARITY`:
   - `checkLinearity(header, operation)` → allowed/error
   - LINEAR: CANNOT_DUPLICATE_LINEAR on DUP, proper consumption tracking
   - AFFINE: CANNOT_DUPLICATE_AFFINE on DUP, can discard
   - RELEVANT: CANNOT_DISCARD_RELEVANT on DROP, can duplicate
   - State transitions are atomic — partial application is a hard error
2. Implement `opcodes_plexus.zig` — Plexus custom opcodes:
   - 0xC0 OP_CHECKLINEAR: verify top-of-stack is LINEAR
   - 0xC1 OP_CHECKAFFINE: verify top-of-stack is AFFINE
   - 0xC2 OP_CHECKRELEVANT: verify top-of-stack is RELEVANT
   - 0xC3 OP_CHECKDOMAINFLAG: verify domain flag matches expected value
   - 0xC4 OP_CHECKTYPEHASH: verify type hash matches expected value
3. Write `linearity_conformance.zig` — test vectors from running `FORTH:LINEARITY` enforcement scenarios
4. Verify: `zig build test` passes

### Phase 5: BEEF/BUMP Host Function Integration and Capability Token Verification
**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Completion criterion**: BEEF parsing works via host functions. BUMP verification works via host functions. Capability token locking scripts evaluate correctly through the 2-PDA.

**Tasks**:
1. Implement full `host-functions.ts`:
   - `host_parseBEEF` using `SDK:TS` Beef class (`ts-sdk/src/transaction/Beef.ts`)
   - `host_verifyBUMP` using `SDK:TS` MerklePath class (`ts-sdk/src/transaction/MerklePath.ts`)
2. Implement `host.zig` host function dispatch
3. Implement capability token verification flow:
   - Parse BRC-108 token UTXO data (from plexus-core CapabilityTokenRef)
   - Evaluate locking script through the 2-PDA
   - Apply Plexus opcode evaluation inline
4. Write integration tests with real BSV testnet transactions (not mocked)
5. Verify: `bun test tests-ts/compat.test.ts` passes with host functions active

### Phase 6: TypeScript Bindings and Bun Integration
**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Completion criterion**: TypeScript bindings load the WASM binary in Bun. All WASM exports are callable from TypeScript. Layer 3 integration tests pass.

**Tasks**:
1. Implement `loader.ts`:
   - Bun: `WebAssembly.instantiate` with WASI
   - Browser: standard WASM instantiation
   - Host function injection at instantiation time
2. Implement `index.ts` — typed wrapper over WASM exports:
   - `packCell(header: CellHeader, payload: Uint8Array): Uint8Array`
   - `unpackCell(cell: Uint8Array): { header: CellHeader; payload: Uint8Array }`
   - `deriveBCA(input: BCAInput): BCAOutput`
   - `verifyBCA(input: BCAVerifyInput): boolean`
   - `executeScript(context: ScriptContext): ScriptResult`
   - `checkLinearity(operation: LinearityOperation): LinearityResult`
3. Implement `integration.test.ts`:
   - Real SQLite database (use existing schema from `WALLET:SCHEMA`)
   - Real BSV testnet connection (use `SDK:TS` ARC broadcaster)
   - Create semantic object → pack to cells → anchor on testnet → verify via WASM SPV
4. Verify: `bun test:integration` passes

### Phase 7: CI/CD Pipeline and Performance Benchmarks
**Duration**: 1 week (with 40% buffer: ~10 days)
**Completion criterion**: All CI stages pass. Performance benchmarks have a committed baseline.

**Tasks**:
1. Create GitHub Actions workflow (see Section 8)
2. Implement `bench.ts`:
   - BCA derivation: target < 1ms
   - Cell pack/unpack: target < 100μs per cell
   - 2-PDA script execution: target < 10ms for 100-opcode script
   - WASM binary load time: target < 50ms cold start in Bun
3. Commit baseline to `benchmarks/baseline.json`
4. WASM binary audit: validate exports/imports, check size < 500KB
5. Verify: all 5 CI stages pass

### Phase 8: Embedded Target Validation
**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Completion criterion**: `wasm32-freestanding` binary compiles. Cell packing and BCA derivation execute on ESP32-class hardware (or WASM runtime simulating the constraints).

**Tasks**:
1. Build `wasm32-freestanding` target (no WASI, no host filesystem)
2. Verify all host function dependencies are properly abstracted
3. Create minimal embedded test harness
4. Profile memory usage: must fit in ESP32 constraints (520KB SRAM)
5. Document embedded deployment guide

**Total estimated duration**: 17 weeks (~4.25 months) including 40% buffers.

---

## 7. Test Plan

### 7.1 Layer 1 — Protocol Conformance Tests (Zig)

| Test File | Tests | Source of Test Vectors |
|-----------|-------|----------------------|
| `cell_conformance.zig` | Pack/unpack round-trip; header field extraction at correct offsets; magic number validation; zero-padding to 1024 bytes; multi-cell continuation headers | `FORTH:SEMOBJ` run in GForth, bytes captured |
| `pda_conformance.zig` | SPUSH/SPOP round-trip; stack overflow/underflow; S-DEPTH accuracy; APUSH/APOP; 1KB cell boundary; LIFO ordering | `FORTH:2PDA` run in GForth |
| `bca_conformance.zig` | deriveBCA with known pubkey/prefix/modifier → known IPv6; verifyBCA true positive; verifyBCA false (wrong pubkey); collision count handling | Independently computed from DOC:BCA-PAPER algorithm |
| `linearity_conformance.zig` | LINEAR: consume succeeds, duplicate fails, discard fails; AFFINE: consume succeeds, duplicate fails, discard succeeds; RELEVANT: duplicate succeeds, discard fails; DEBUG: all succeed | `FORTH:LINEARITY` enforcement scenarios |
| `opcodes_conformance.zig` | Every standard opcode; every Craig macro 0xB0-0xBF; every Plexus opcode 0xC0-0xC4; instruction limit enforcement; bounded execution (no loops) | `CORE:EXECUTOR` and `FORTH:MACROS` |
| `commerce_conformance.zig` | Commerce header read/write at correct offsets; phase/dimension constants match `FORTH:COMMERCE`; type hash computation | `FORTH:COMMERCE` run in GForth |

**Run**: `zig build test` — zero external dependencies.

### 7.2 Layer 2 — Cross-Language Compatibility Tests

| Test File | Tests |
|-----------|-------|
| `compat.test.ts` | Zig packs cell → TS unpacks → fields match. TS constructs header bytes → Zig unpacks → fields match. Round-trip: TS → Zig → TS byte-identical. Commerce extension round-trip. Multi-cell round-trip. BCA derivation: Zig and TS produce identical IPv6 addresses for same inputs. |

**Run**: `bun test tests-ts/compat.test.ts` — requires compiled WASM binary.

### 7.3 Layer 3 — Integration Tests

| Test File | Tests | Infrastructure |
|-----------|-------|---------------|
| `integration.test.ts` | Create semantic object with real SQLite. Pack to cells via Zig WASM. Construct BSV transaction with `SDK:TS`. Anchor on BSV testnet (if `BSV_TESTNET_KEY` env var set). Verify BUMP via WASM host functions. Execute capability token locking script. Linearity enforcement on real cell headers. | Docker: SQLite. Optional: BSV testnet. |

**Run**: `bun test:integration` — skips BSV testnet tests if key not set, with clear message (not faked).

### 7.4 Layer 4 — Performance Benchmarks

| Test File | Benchmarks | Targets |
|-----------|-----------|---------|
| `bench.ts` | BCA derivation | < 1ms |
| | Cell pack/unpack | < 100μs per cell |
| | 2-PDA 100-opcode script | < 10ms |
| | WASM cold start in Bun | < 50ms |
| | Linearity check | < 10μs |

**Run**: `bun bench` — fails if any benchmark regresses > 20% from baseline.

---

## 8. CI/CD Specification

### 8.1 Pipeline Stages

**Stage 1 — Zig build and test**
```yaml
- zig fmt --check src/
- zig build
- zig build test
- zig build -Dtarget=wasm32-freestanding
- zig build -Dtarget=wasm32-wasi
```

**Stage 2 — WASM compatibility**
```yaml
- bun install
- bun run generate-constants   # constants.json → constants.zig + constants.ts
- bun test tests-ts/compat.test.ts
```

**Stage 3 — Integration tests**
```yaml
- bun test:integration
# BSV testnet tests run only on main branch push, not on every PR
# BSV_TESTNET_KEY must be set in CI secrets — never hardcoded
```

**Stage 4 — Performance regression**
```yaml
- bun bench
# Fail if any benchmark regresses > 20% from baseline
# Baseline stored in benchmarks/baseline.json — committed to repo
```

**Stage 5 — WASM binary audit**
```yaml
- wasm-validate dist/cell-engine.wasm
- wasm-objdump -x dist/cell-engine.wasm
# Fail if binary size > 500KB
# Fail if any unexpected imports (only host_sha256, host_parseBEEF, host_verifyBUMP, host_log permitted)
```

### 8.2 Branch Strategy

- `main` — production ready, all stages pass
- `develop` — integration branch, Stages 1-3 pass
- Feature branches — Stages 1-2 pass, Stage 3 optional
- No direct pushes to main — PR required, one approval minimum

### 8.3 Secrets Management

- `BSV_TESTNET_KEY`: CI secrets only, never in code
- No `.env` files committed — `.env.example` with placeholder values
- All configuration via environment variables with explicit validation on startup

---

## 9. Interface Contracts

### 9.1 plexus-core → cell-engine

**What plexus-core provides** (per `DOC:PLEXUS-TECH` components):
- BRC-52 certificate structure: certId, subject public key (33 bytes compressed), issuerCertId, childIndex
- BRC-108 capability token UTXO data: txid, vout, lockingScript, ownerCertId
- Domain flag values (uint32) for OP_CHECKDOMAINFLAG evaluation (per `DOC:PLEXUS-CLIENT` Section 2.2: 0x00000001–0x000000FF for Plexus well-known flags, 0x00000100–0x0000FFFF for extended standard, 0x00010000–0xFFFFFFFF for client-defined sovereignty)

**What cell-engine provides to plexus-core**:
- BCA address for a given certificate (`deriveBCA` export)
- Capability token validity check (`executeScript` on the locking script)
- Linearity enforcement result for token consumption

**Interface**: Both depend on `@semantos/protocol-types`. Neither depends on the other directly.

### 9.2 @bsv/sdk → cell-engine (via WASM boundary)

The Zig layer does NOT parse BEEF/BUMP directly. Host functions in TypeScript (`host-functions.ts`) call into the local `SDK:TS` package:

```typescript
// host-functions.ts
import { Beef } from '../../../ts-sdk/src/transaction/Beef';
import { MerklePath } from '../../../ts-sdk/src/transaction/MerklePath';
import { Hash } from '../../../ts-sdk/src/primitives/Hash';

export function createHostFunctions(): HostFunctionSet {
  return {
    parseBEEF: (rawBytes: Uint8Array) => {
      const beef = Beef.fromBinary(Array.from(rawBytes));
      // Extract transaction and merkle proof
      return { transaction: ..., merkleProof: ... };
    },
    verifyBUMP: (merkleProof: Uint8Array, blockHeader: Uint8Array) => {
      const path = MerklePath.fromBinary(Array.from(merkleProof));
      return path.verify(/* txid */, /* chainTracker */);
    },
    sha256: (data: Uint8Array) => {
      return new Uint8Array(Hash.sha256(Array.from(data)));
    },
  };
}
```

### 9.3 cell-engine → kernel

The TypeScript bindings (`bindings/index.ts`) expose functions matching the interface expected by the existing CLI tools (`WALLET:CLI`, `WALLET:BASKET`, `WALLET:INDEXER`) and schema (`WALLET:SCHEMA`).

---

## 10. Forth Handoff

### 10.1 Interface Boundary

The Zig 2-PDA is the near-term execution engine. The long-term vision includes a Forth-based on-chain execution model. The interface boundary is the **cell format**: a cell packed by the Zig engine must be consumable by a future Forth engine, and vice versa.

The cell format (256-byte header + 768-byte payload, 1024 bytes total) is the interchange format. It is defined by `FORTH:SEMOBJ` and `FORTH:COMMERCE`. The Zig implementation must produce byte-identical cells.

### 10.2 Opcode Semantics Ownership

The Zig opcode implementations (0xC0–0xCF) are the **reference semantics** that a future Forth implementation must match. The Forth implementations in `FORTH:LINEARITY` and `FORTH:MACROS` are the **design reference** — they document intent. The Zig implementations are the **specification** — they define precise behaviour for all edge cases.

### 10.3 Opcode Classification

| Range | Zig-Only (host function required) | Pure Stack (Forth can implement natively) |
|-------|-----------------------------------|------------------------------------------|
| 0x00-0x4F | OP_CHECKSIG, OP_CHECKMULTISIG (need host crypto) | All stack manipulation, arithmetic, logic |
| 0xB0-0xBF | — | All Craig macros (XSWAP-n, XDROP-n, XROT-n, HASHCAT) |
| 0xC0-0xC2 | — | OP_CHECKLINEAR, OP_CHECKAFFINE, OP_CHECKRELEVANT (header inspection) |
| 0xC3-0xC4 | OP_CHECKDOMAINFLAG (may need host context), OP_CHECKTYPEHASH (needs SHA-256) | — |
| 0xC5-0xCF | Reserved for future Plexus opcodes | — |

### 10.4 LISP → Forth → Script Pipeline Preservation

The three-layer compilation pipeline described in `DOC:LISP` (LISP macros → Forth words → Bitcoin Script) is preserved. The Zig engine executes the final Bitcoin Script output. The macro expansion (0xB0-0xBF) is implemented in Zig matching `FORTH:MACROS` exactly, so scripts produced by either pipeline execute identically.

---

## 11. Semantos-Core Handoff

### 11.1 Ownership and Relationship

`@semantos/core` v0.2.0 (`CORE:ROOT`) is **Todd's code**, located at `/Users/toddprice/projects/semantos-core/`. It was built on Todd's machine using the technical requirements docs (`DOC:PLEXUS-TECH`, `DOC:PLEXUS-CLIENT`) that Todd and Ryan (Dusk) iterated on together. The package was originally under `@dusk-inc/plexus-core` and has been renamed and moved to its own top-level project directory.

**What Todd has (plexus-core):**
- Semantic object type system: `CORE:SEMOBJ` — SemanticType enum, LinearObject, AffineObject, RelevantObject with consumption/revocation proofs
- WASM kernel interface: `CORE:WASM` — **PlexusKernelWasm** (the export contract the Zig module must satisfy) and **PlexusKernelHostImports** (host functions the WASM module calls back into)
- Capability tokens: `CORE:CAPABILITY` — CapabilityToken (LINEAR), 6 capability types, factory functions
- Domain flags: `CORE:DOMAIN-FLAGS` — 10 well-known flags, 3-tier range system, BRC-43 protocol ID conversion
- Compiler/validator: `CORE:VALIDATOR` — consumption rule enforcement
- Recovery protocol: `CORE:RECOVERY`, `CORE:CHALLENGE` — export payload, challenge-response
- Metering FSM: `CORE:FSM`, `CORE:SETTLEMENT` — 8-state payment channel

**What Dusk is building separately (Todd has not seen the code):**
- Graph SDK — DAG operations, traversal, child indexing
- RaaS SDK — Recovery-as-a-Service server implementation
- Plexus API (Go/Gin) — server-side control plane
- Vendor SDK — client-side graph DB management

### 11.2 The WASM Interface Contract Is Already Defined

The critical insight: **the Zig WASM module's export interface is already defined** in `CORE:WASM`. The `PlexusKernelWasm` interface specifies exactly what the Zig module must export:

- `kernel_init()`, `kernel_reset()`
- `kernel_load_script()`, `kernel_load_unlock()`
- `kernel_execute()` → returns 0 if script evaluates to true
- `kernel_get_type_class()` → 0=LINEAR, 1=AFFINE, 2=RELEVANT
- `kernel_get_opcount()`, `kernel_get_error()`
- `kernel_stack_depth()`, `kernel_stack_peek()`
- `memory` (WebAssembly.Memory)

And `PlexusKernelHostImports` specifies exactly what the host provides:

- `host_sha256`, `host_hash160`, `host_hash256`
- `host_checksig`, `host_checkmultisig`
- `host_get_blocktime`, `host_get_sequence`
- `host_log`

**The Zig implementation must match these interfaces. No redesign needed — the contract exists.**

### 11.3 What Cell-Engine Needs from plexus-core

The cell-engine can import plexus-core directly (it's Todd's local package). The integration points are:

1. **WASM interface**: `CORE:WASM` defines the contract. The Zig `main.zig` exports must satisfy `PlexusKernelWasm`. The TypeScript `host-functions.ts` must implement `PlexusKernelHostImports`.

2. **Type system**: `CORE:SEMOBJ` defines the LinearObject/AffineObject/RelevantObject types. The Zig linearity enforcement (`linearity.zig`) must enforce the same rules.

3. **Capability tokens**: `CORE:CAPABILITY` defines CapabilityToken with lockingScript. The Zig 2-PDA evaluates these scripts including Plexus opcodes.

4. **Domain flags**: `CORE:DOMAIN-FLAGS` defines the flag values. When OP_CHECKDOMAINFLAG (0xC3) executes in the Zig 2-PDA, it checks the flag against the value from the ScriptContext.

### 11.4 Cell Packer Compatibility

The production `cellPacker.ts` (`PACKER:MAIN`) imports from `typeHashRegistry.ts` (`PACKER:TYPE-REGISTRY`) for Cell 0 header construction. The Zig cell packer must produce byte-identical output to `packMultiCell()` for the same inputs. Test vectors will be generated by running `PACKER:MAIN` on known inputs and comparing the raw bytes against the Zig output.

### 11.5 Timeline Independence from Dusk

The cell-engine development does NOT depend on Dusk's Graph SDK or RaaS SDK timelines because:
- plexus-core is Todd's code (available now)
- The WASM interface is defined (available now)
- The cellPacker.ts is production code (available now)
- BCA derivation needs only raw public key bytes
- Integration testing uses real plexus-core types, not synthetic stubs

---

## 12. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| R1 | WASM binary size exceeds 500KB target | Medium | Medium | Profile with `wasm-opt -Oz`. Remove unused opcodes from freestanding target. Split into core + extended modules if needed. |
| R2 | @bsv/sdk WASM boundary overhead makes host functions too slow | Medium | High | Benchmark early in Phase 2. If overhead > 10μs per call, consider Zig-native SHA-256 (pure computation, no @bsv/sdk dependency). BEEF/BUMP parsing can tolerate higher latency. |
| R3 | Zig/TypeScript type marshalling at WASM boundary is error-prone | High | Medium | Use fixed-size byte arrays at the boundary (no complex structs). All marshalling happens in `bindings/index.ts` and `host.zig`. Fuzz test the boundary. |
| R4 | plexus-core Graph SDK timeline slips (Dusk dependency) | Medium | Low | Cell-engine has zero runtime dependency on plexus-core. Integration tests use synthetic certificates. Production integration is a configuration change, not a code change. |
| R5 | BSV testnet availability for CI | High | Low | Testnet tests are optional (main branch only). Core conformance tests are pure Zig with no network dependency. |
| R6 | Cell format incompatibility with existing Forth `FORTH:SEMOBJ` | Medium | Critical | Phase 1 cross-language tests are the gate. Generate test vectors by running GForth on `FORTH:SEMOBJ` and capturing raw bytes. Byte-for-byte comparison, not semantic comparison. |
| R7 | ESP32 memory constraints (520KB SRAM) | Medium | Medium | Main stack 1024 × 1KB = 1MB exceeds ESP32 SRAM. Embedded target must use reduced stack size (configurable via constants). Document minimum viable stack size. |
| R8 | BCA paper algorithm has implementation ambiguities | Low | Medium | The BCA paper (DOC:BCA-PAPER) is clear on the algorithm. Compute independent test vectors. If ambiguity found, surface in Open Questions. |

---

## 13. Open Questions

| # | Question | Assigned To | Decision Needed By |
|---|----------|-------------|-------------------|
| Q1 | The Forth reference (`FORTH:SEMOBJ`) uses GForth cell size (8 bytes on 64-bit). The magic numbers are stored as 4 × CELL (32 bytes on 64-bit). On 32-bit Zig WASM, CELL is 4 bytes. Should magic numbers be stored as 4 × 8 bytes (matching 64-bit GForth) or 4 × 4 bytes (matching the actual values)? **Recommendation**: 4 × 4 bytes in the wire format (the values fit in 32 bits), but clarify with Forth reference. | Todd | Phase 0 |
| Q2 | The existing `WALLET:CLI` uses simulated BUMP proofs (line 29-45 of `semantic-cli.cjs`). When should we cut over to real BUMP proofs from `SDK:TS`? Phase 5 assumes real proofs. | Todd | Phase 5 |
| Q3 | `DOC:BCA-PAPER` Table II shows BCA Parameters include "Merkle proof of transaction" and "Merkle proof of modifier". In our usage, do we store these in the cell's continuation cells, or do we rely on BEEF envelopes for merkle proofs? | Todd | Phase 2 |
| Q4 | The embedded target (Phase 8) cannot use host functions (no TypeScript runtime). Should the freestanding WASM include a Zig-native SHA-256 implementation, or should embedded targets use a different host function provider? | Todd | Phase 7 |
| Q5 | `CORE:SEMOBJ`, `CORE:CAPABILITY`, `CORE:DOMAIN-FLAGS` already define the semantic object types. Should `@semantos/protocol-types` be a new package, or should cell-engine simply import directly from `@semantos/core`? Creating a new package adds a dependency boundary but duplicates types. Importing directly is simpler but couples cell-engine to plexus-core's evolution. | Todd | Phase 0 |
| Q6 | **RESOLVED.** `PACKER:TYPE-REGISTRY` (`typeHashRegistry.ts`) has been read. The wire-format header uses packed byte sizes (not GForth 8-byte cell-width). The canonical offsets are: magic(0,16B), linearity(16,4B), version(20,4B), flags(24,4B), refCount(28,2B), typeHash(30,32B), ownerId(62,16B), timestamp(78,8B), cellCount(86,4B), totalSize(90,4B), phase(94,1B), dimension(95,1B), parentHash(96,32B), prevStateHash(128,32B). **The Zig implementation MUST use these packed offsets (matching typeHashRegistry.ts), NOT the Forth GForth-cell-width offsets.** See updated Appendix A and B. | Resolved | — |
| Q7 | Reduced stack size for ESP32: what is the minimum viable main stack depth for the target use cases? 64 cells? 128? This determines the freestanding binary's static memory requirement. | Todd | Phase 7 |
| Q8 | The existing `WALLET:SCHEMA` uses SQLite with `unixepoch()`. Should the cell-engine integration tests use SQLite (matching existing code) or PostgreSQL (matching kernel's future direction)? | Todd | Phase 6 |

---

## Appendix A: Constants Reference

Extracted from Forth reference implementations. These values populate `constants.json`.

```json
{
  "protocol": {
    "version": 1,
    "cellSize": 1024,
    "headerSize": 256,
    "payloadSize": 768,
    "continuationHeaderSize": 8,
    "continuationPayloadSize": 1016
  },
  "stacks": {
    "mainStackCells": 1024,
    "auxStackCells": 256,
    "mainStackBytes": 1048576,
    "auxStackBytes": 262144
  },
  "magic": {
    "magic1": "0xDEADBEEF",
    "magic2": "0xCAFEBABE",
    "magic3": "0x13371337",
    "magic4": "0x42424242"
  },
  "linearity": {
    "LINEAR": 1,
    "AFFINE": 2,
    "RELEVANT": 3,
    "DEBUG": 4
  },
  "commercePhase": {
    "SOURCE": 0, "PARSE": 1, "AST": 2, "TYPECHECK": 3,
    "OPTIMISE": 4, "CODEGEN": 5, "ACTION": 6, "OUTCOME": 7, "UNKNOWN": 255
  },
  "taxonomyDimension": {
    "COMPOSITE": 0, "WHAT": 1, "HOW": 2, "INSTRUMENT": 3
  },
  "cellType": {
    "BUMP": 1, "ATOMIC_BEEF": 2, "ENVELOPE": 3, "DATA": 4, "STATE": 5
  },
  "headerOffsets": {
    "_note": "Packed byte offsets (from typeHashRegistry.ts, NOT GForth cell-width offsets)",
    "magic": 0,
    "magicSize": 16,
    "linearity": 16,
    "linearitySize": 4,
    "version": 20,
    "versionSize": 4,
    "flags": 24,
    "flagsSize": 4,
    "refCount": 28,
    "refCountSize": 2,
    "typeHash": 30,
    "typeHashSize": 32,
    "ownerId": 62,
    "ownerIdSize": 16,
    "timestamp": 78,
    "timestampSize": 8,
    "cellCount": 86,
    "cellCountSize": 4,
    "totalSize": 90,
    "totalSizeSize": 4,
    "reservedStart": 94,
    "commercePhase": 94,
    "commerceDimension": 95,
    "commerceParentHash": 96,
    "commerceParentHashSize": 32,
    "commercePrevState": 128,
    "commercePrevStateSize": 32,
    "reserved2Start": 160,
    "reserved2End": 255
  },
  "opcodeRanges": {
    "standardMin": 0, "standardMax": 175,
    "craigMacroMin": 176, "craigMacroMax": 191,
    "plexusMin": 192, "plexusMax": 207
  },
  "domainFlags": {
    "EDGE_CREATION": 1,
    "MESSAGING": 4,
    "CHILD_CREATION": 6,
    "PERMISSION_GRANT": 7,
    "plexusReservedMin": 1,
    "plexusReservedMax": 255,
    "extendedMin": 256,
    "extendedMax": 65535,
    "clientDefinedMin": 65536,
    "clientDefinedMax": 4294967295
  },
  "binding": {
    "txidSize": 32,
    "voutSize": 4,
    "bumpHashSize": 24,
    "derivationIndexSize": 4,
    "totalBindingSize": 64
  },
  "bca": {
    "modifierSize": 16,
    "subnetPrefixSize": 8,
    "ipv6AddressSize": 16,
    "publicKeySize": 33,
    "collisionCountMax": 2
  }
}
```

---

## Appendix B: Header Layout Diagram (Packed Wire Format)

**Source of truth**: `typeHashRegistry.ts` (`PACKER:TYPE-REGISTRY`). All offsets are packed byte offsets, NOT GForth cell-width offsets.

```
Byte offset (decimal):
  0              16  20  24  28 30                62       78  86  90  94
  ├─ MAGIC (16B) ┤LIN┤VER┤FLG┤RC┤── TYPE-HASH (32B) ──┤OWN(16B)┤TS(8B)┤CC┤TS┤
                  4B  4B  4B 2B                                     4B 4B

RESERVED block (offset 94-255, 162 bytes):
  94: PHASE (1B)          — commerce pipeline phase
  95: DIMENSION (1B)      — taxonomy dimension
  96-127: PARENT-HASH (32B) — parent object chaining
  128-159: PREV-STATE (32B) — previous state hash chaining
  160-255: RESERVED2 (96B)  — available for on-chain binding or future use

On-chain binding (in RESERVED2, offset 160-223, 64B total):
  160-191: TXID (32B)
  192-195: VOUT (4B)
  196-219: BUMP-HASH (24B)
  220-223: DERIVATION-INDEX (4B)
  224-255: UNUSED (32B)
```

Note: With Q6 resolved, commerce extension and on-chain binding now occupy NON-OVERLAPPING regions. Commerce uses offsets 94-159 (66 bytes). On-chain binding uses offsets 160-223 (64 bytes). The remaining 32 bytes (224-255) are available for future use. The Zig implementation must enforce this layout exactly to produce bit-identical output with `typeHashRegistry.ts`.
