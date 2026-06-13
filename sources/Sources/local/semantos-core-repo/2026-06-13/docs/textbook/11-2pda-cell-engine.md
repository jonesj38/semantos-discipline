---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/11-2pda-cell-engine.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.653288+00:00
---

# The 2-PDA cell engine

Part III has built up the pipeline in layers: surface grammar produces an abstract syntax tree; the AST lowers into the Semantic IR (SIR), a jural-typed intermediate representation; SIR lowers into the Opcode IR (OIR) in administrative normal form (ANF); OIR emits opcode bytes. This chapter covers what happens to those bytes next. The cell engine receives them, evaluates them against the two stacks of the pushdown automaton, and either commits the resulting state transitions or rolls every byte back.

Boot-sequence step 7 — `kernel_set_enforcement(1)` — is the moment the cell engine stops accepting raw execution without invariant enforcement and begins operating as the protocol requires. This chapter works through the machine model, the opcode set, the three-phase verification pipeline, and the five kernel invariants the cell engine enforces (K1, K3, K4, K5, K7). It ends with the Lean 4 proof that grounds K1, and the declaration that step 7 is now unlocked.

---

## The machine model

### Two stacks, no loops

The cell engine is a deterministic, bounded two-stack pushdown automaton (2-PDA). Every term in that description carries protocol weight.

**Deterministic.** Given the same opcode bytes and the same initial stack contents, the cell engine produces the same result on every execution, on every conformant implementation, in every profile. The reference implementation is approximately 4,900 lines of Zig compiled to WebAssembly. The embedded profile strips approximately 156 KB of debug code paths and ships at ~29 KB; the full profile ships at ~185 KB. Both profiles execute byte-identical opcode programs against byte-identical inputs and produce byte-identical outputs (§8.5 of the protocol spec). A conformant implementation MUST enforce this property; any execution that produces a profile-dependent result is a non-conformance.

**Bounded.** The cell engine has no heap allocation and no garbage collector. The main stack holds at most 1,024 cells. The auxiliary stack holds at most 256 cells. Execution terminates within `opcountLimit` steps — a configurable bound defaulting to 1,000,000 opcodes per script. K5 states this formally: every execution terminates within `opcountLimit` steps, and the proof `TerminationK5.lean` is mechanised in Lean 4 over the abstract 2-PDA model. There is no way for opcode execution to run indefinitely. K10 (see chapter 12) situates this in a wider Turing-completeness argument: the 2-PDA plus the bounded opcount gives a decidable execution model.

**Two-stack pushdown automaton.** A single-stack PDA is the standard model for context-free recognition. The cell engine uses two stacks: a main stack for cell evaluation, and an auxiliary stack for continuation cells. The auxiliary stack is the mechanism that makes three-phase verification work — continuation cells are pushed onto it in reverse order so that LIFO popping yields the BUMP cell first, then the atomic-BEEF cell, then the state envelope. This ordering is not an implementation convenience; it is a protocol invariant that enables fail-fast verification (§8.4 of the protocol spec). A cell that cannot establish its on-chain anchor in phase 1 stops there, consuming no further computation.

### The cell as the unit of evaluation

The primary value type in the cell engine is the cell (see the `cell` glossary entry). A cell is a 1,024-byte binary structure: a 256-byte typed header, up to 768 bytes of semantic payload in cell 0, and zero or more 1,024-byte continuation cells. The cell header is packed once and is read-only after packing — this is K7, the object-integrity invariant, with proof `CellImmutabilityK7.lean`. No opcode in the instruction set modifies the linearity class, type hash, owner identifier, or hash-chain pointers of a cell on the stack.

The header carries, among other fields: a 32-byte type hash (SHA-256 of `whatPath:howSlug:instPath`), the linearity class (one of LINEAR, AFFINE, RELEVANT, UNRESTRICTED encoded as a uint32 at offset 16), the pipeline phase byte (offset 94), the domain flag (offset 24–27), the owner identifier (offset 62), and the `prevStateHash` linking this cell to its predecessor in the hash chain (offset 128).

```
[FIGURE — needs real graphic for layout pass]

Cell 0 (1024 bytes)
┌─────────────────────────────────────────────────────┐
│ Header (256 bytes)                                  │
│  [0]   Magic            16 bytes                    │
│  [16]  Linearity         4 bytes  ← K1 gate         │
│  [20]  Version           4 bytes                    │
│  [24]  DomainFlag        4 bytes  ← K3 gate         │
│  [30]  TypeHash         32 bytes  ← K7: read-only   │
│  [62]  OwnerID          16 bytes                    │
│  [78]  Timestamp         8 bytes                    │
│  [86]  CellCount         4 bytes                    │
│  [90]  PayloadSize       4 bytes                    │
│  [94]  Phase             1 byte                     │
│  [96]  ParentHash       32 bytes                    │
│  [128] PrevStateHash    32 bytes  ← hash chain      │
│  [160] Reserved         96 bytes                    │
├─────────────────────────────────────────────────────┤
│ Payload (≤ 768 bytes, zero-padded)                  │
└─────────────────────────────────────────────────────┘

Continuation cells (Cell 1, Cell 2, ...) pushed onto aux stack:
  Cell 1 (BUMP, type 0x01) ← phase 1 verification
  Cell 2 (ATOMIC_BEEF, type 0x02) ← phase 2 verification
  Cell 3+ (ENVELOPE/DATA/STATE, types 0x03–0x05)
```

The magic bytes at offset 0 are fixed: `0xDEADBEEF CAFEBABE 13371337 42424242`. The `isValidCell()` function checks these 16 bytes before any other parsing and refuses cells that do not match. This is the cheapest possible gate: 16 bytes of comparison before any cryptographic work begins.

### Execution time proportional to opcount

The cell engine provides an execution-time guarantee that the pipeline layers above it depend on. Execution time MUST be proportional to opcount — there are no operations that produce unbounded work. This property, combined with the `opcountLimit` bound, gives operators a predictable worst-case execution time per script. The Verifier Sidecar (see chapter 14) can enforce opcount limits at the adapter boundary before a script enters the engine.

---

## The opcode set

### Standard range and Plexus extension range

The cell engine extends standard Bitcoin Script (`0x00`–`0x4B`) with the Plexus extension range (`0x4C`–`0xD0`). The full opcode table is canonical in `core/cell-engine/src/opcodes.zig` and rendered to `docs/canon/opcodes.yml`; any discrepancy between those two files and this chapter resolves in favour of those two files.

The extension range is the protocol's primary enforcement surface. Standard Bitcoin Script provides the basic stack operations (push, pop, conditional, arithmetic, hashing, signature checking) that any script-evaluation system needs. The Plexus extension range adds the semantic predicates specific to the cell engine's role: linearity enforcement, capability token checking, domain flag comparison, identity binding verification, BUMP and atomic-BEEF delegation to the host.

### Key opcodes in the Plexus subrange

The subrange `0xC0`–`0xCF` is the dense cluster of semantic enforcement opcodes. The full table from the protocol spec:

| Opcode | Mnemonic | Behaviour |
|--------|----------|-----------|
| `0xC0` | `OP_CHECKLINEARTYPE` | Pop type tag from stack; verify object linearity matches. |
| `0xC1` | `OP_CHECKAFFINETYPE` | Assert top-of-stack object is AFFINE. |
| `0xC2` | `OP_CHECKRELEVANTTYPE` | Assert top-of-stack object is RELEVANT. |
| `0xC3` | `OP_CHECKCAPABILITY` | Verify capability token UTXO is unspent via BUMP proof in Cell 1. |
| `0xC4` | `OP_CHECKIDENTITY` | Verify BRC-52 cert binding against participant graph. |
| `0xC5` | `OP_ASSERTLINEAR` | Assert object is unconsumed LINEAR; abort if already consumed. |
| `0xC6` | `OP_CHECKDOMAINFLAG` | Read bytes 24–27 of cell header as uint32; compare against expected. |
| `0xC7` | `OP_VERIFYVERSION` | Assert object state version hash matches expected (`prevStateHash` chain). |
| `0xC8` | `OP_CHECKDOMAIN` | Verify domain flag is within authorised range for current context. |
| `0xC9` | `OP_ASSERTPHASE` | Assert pipeline phase matches expected. |
| `0xCA` | `OP_CHECKCELL` | Validate continuation cell header: type tag, index, payload size bounds. |
| `0xCB` | `OP_VERIFYBUMP` | Delegate BUMP verification to host: parse BRC-74, compute merkle root. |
| `0xCC` | `OP_VERIFYBEEF` | Delegate atomic-BEEF verification: validate `0x01010101` prefix and ancestry. |
| `0xCD`–`0xCF` | reserved | Reserved for future Plexus extensions. |

The opcodes cluster by concern. `0xC0`–`0xC2` and `0xC5` are the K1 gate: they check whether a proposed stack operation is permitted under the cell's linearity class. `0xC6` and `0xC8` are the K3 gate: they enforce domain flag isolation. `0xC4` is the K2 surface (identity verification gating state-changing transitions). `0xC7` is the hash-chain integrity check. `0xCB` and `0xCC` are the SPV delegation pair that drives phases 1 and 2 of the three-phase verification pipeline.

### OIR bindings and opcode emission

The OIR (Opcode IR) lowering pass emits these opcodes from named bindings. Each binding has a kind — `comparison`, `logical`, `capability`, `domainCheck`, `timeConstraint`, `hostCall`, `typeHashCheck`, `deref` — and each kind maps to a small canonical opcode sequence. A `capability` binding emits `OP_CHECKCAPABILITY` (`0xC3`). A `domainCheck` binding emits `OP_CHECKDOMAINFLAG` (`0xC6`) or `OP_CHECKDOMAIN` (`0xC8`) depending on whether the check is against a specific value or a range. A `comparison` binding emits the appropriate standard comparison opcode followed by `OP_CHECKLINEARTYPE` if the operand is a LINEAR cell.

The α-equivalence requirement (§7.4 of the protocol spec) guarantees that two SIR programs expressing the same semantic intent produce byte-identical opcode output. The cell engine MUST NOT depend on which surface grammar produced the bytes — the engine sees only the byte sequence and the initial stack, not the SIR program that emitted it.

---

## The WASM interface contract

### Module exports and host imports

The cell engine runs inside a sandboxed WASM environment. It has no direct access to the filesystem, the network, or private keys. All I/O crosses the WASM FFI boundary via explicitly typed host imports. This containment is the basis of the kernel-isolation security property (§13.5 of the protocol spec): even a compromised kernel module cannot exfiltrate data because it has no channel to do so.

The WASM module MUST export at least the following functions:

| Function | Purpose |
|----------|---------|
| `validateCell(cellPtr, cellLen)` | Pre-validate a cell against header invariants |
| `executeScript(scriptPtr, scriptLen, stackPtr)` | Execute opcode bytes against the stack |
| `verifyStateChain(chainPtr, chainLen)` | Validate `prevStateHash` chain integrity |
| `checkLinearity(objectPtr, operation)` | Enforce K1 at the gate |
| `kernel_init()` | Initialise kernel state |
| `kernel_load_script(scriptPtr, scriptLen)` | Load a script for execution |
| `kernel_execute()` | Execute the loaded script |
| `kernel_set_enforcement(enabled)` | Enable or disable invariant enforcement |

`kernel_set_enforcement` is the call that closes boot-sequence step 7. Until it is called with `enabled = 1`, the cell engine operates without invariant enforcement — useful during initialisation, when the bootstrap cells being loaded do not yet have a live capability domain to validate against. After the call, enforcement is permanent for the lifetime of the kernel instance.

The host MUST provide at least the following imports:

| Import | Purpose |
|--------|---------|
| `hostSha256(dataPtr, dataLen, outPtr)` | SHA-256 hash |
| `hostHmacSha256(keyPtr, keyLen, dataPtr, dataLen, outPtr)` | HMAC-SHA-256 |
| `hostVerifySignature(pubkeyPtr, msgPtr, sigPtr)` | ECDSA verify |
| `hostCheckBump(bumpPtr, bumpLen, txidPtr)` | BUMP merkle proof verification |

The cryptographic operations live in the host, which uses `@bsv/sdk` internally in the reference implementation. The kernel never touches private keys, never computes a signature, and never makes a network request. All comparisons involving secret material MUST use constant-time comparison — this is a host responsibility, not a kernel responsibility, which is why the honest assumption register (§13.6 of the protocol spec) explicitly flags the host imports as not formally verified.

### Production binary integrity

The production WASM binary's SHA-256 hash MUST be anchored on BSV at release time. Devices MUST verify `SHA-256(loaded_wasm) == anchored_hash` at boot, before the engine initialises. A hash mismatch MUST refuse to load. This is the trusted-boot assumption in the honest assumption register: the binary-integrity claim depends on the loader correctly verifying the anchored hash. This check happens before step 7; step 7 presupposes a verified binary.

---

## Three-phase verification

### The auxiliary stack and continuation cells

When a cell object includes continuation cells — a BUMP proof, an atomic-BEEF envelope, a state merkle envelope — they are pushed onto the auxiliary stack in reverse order before evaluation begins. LIFO popping then yields them in the protocol-specified order: BUMP first (`0x01`), atomic-BEEF second (`0x02`), state envelope third (`0x03`). This is the structural guarantee of §3.3 of the protocol spec, and it is what makes fail-fast possible.

```
[FIGURE — needs real graphic for layout pass]

Auxiliary stack at start of evaluation (LIFO, top at left):
  ┌────────────────┬─────────────────────┬──────────────────┐
  │ Cell 1: BUMP   │ Cell 2: ATOMIC_BEEF │ Cell 3: ENVELOPE │
  │  (popped 1st)  │  (popped 2nd)       │  (popped 3rd)    │
  └────────────────┴─────────────────────┴──────────────────┘
         ↑
     Phase 1
   verification
```

### Phase 1: BUMP anchor check

The first operation on any multi-cell object is to establish that the anchor transaction is mined. The kernel calls `hostCheckBump` with the BRC-74 merkle path from Cell 1. The host parses the BUMP structure, recomputes the merkle root from the provided sibling hashes, and compares it to the block header the host has for that height.

If the merkle root does not match, execution halts immediately with phase 1 flagged as the failure site. No further computation occurs. The object is rejected. This is the fastest possible rejection of an invalid anchor — a single merkle-path recomputation — before any cryptographic signature work begins.

BUMP (BSV Unified Merkle Path, BRC-74) carries the merkle path as a sequence of sibling hashes and position bits sufficient to recompute the root from the leaf. The leaf is the anchor transaction's txid. Internal nodes use double-SHA-256 per Bitcoin convention. Odd leaf counts pad by duplicating the last leaf.

### Phase 2: atomic-BEEF ancestry check

The second phase establishes that the anchor transaction's full ancestry is valid. The kernel delegates BRC-95 atomic-BEEF validation to the host, which recursively verifies the full transaction graph using the `@bsv/sdk` BEEF parser.

The atomic-BEEF envelope (continuation cell type `0x02`) MUST start with the prefix `0x01010101` followed by the subject txid followed by the BRC-62 BEEF body for recursive ancestor validation. The `0x01010101` prefix is a distinguishing tag that lets the host immediately identify the envelope type before inspecting further.

Phase 2 failure halts execution with phase 2 as the failure site. A cell that passes phase 1 but fails phase 2 has a mined anchor transaction whose ancestors are invalid — this is a structural inconsistency that indicates either a malformed BEEF envelope or a transaction that was included in a block via an alternate chain. Either way the object cannot be accepted.

### Phase 3: state envelope deserialization

The third phase unpacks the semantic content. The kernel deserialises the state merkle envelope (continuation cell type `0x03`) and verifies selective disclosure proofs against the inscribed root. The envelope format is:

```
[1 byte: version]
[4 bytes: leafCount LE]
[32 bytes: merkle root]
[4 bytes: proofCount LE]
Per proof:
  [4 bytes: leafIndex LE]
  [32 bytes: leafHash]
  [4 bytes: siblingCount LE]
  Per sibling:
    [1 byte: position (0=left, 1=right)]
    [32 bytes: hash]
```

Only after the selective disclosure proofs pass does payload evaluation begin. The semantic payload in Cell 0 is then executed against the main stack.

This three-phase structure means that computation is front-loaded with the cheapest checks (BUMP recomputation) and defers the expensive work (payload evaluation) to objects that have already proven their on-chain existence and valid ancestry.

---

## Kernel invariants

### K1: linearity

K1 states: a LINEAR cell is consumed exactly once; never duplicated, never discarded. The linearity class at header offset 16 determines which stack operations are permitted on a cell. The four classes are:

| Class | Code | Rule |
|-------|------|------|
| LINEAR | 0 | Consumed exactly once. No DUP. No DROP. |
| AFFINE | 1 | Used at most once. No DUP. DROP permitted. |
| RELEVANT | 2 | Used at least once. DUP permitted. No DROP. |
| UNRESTRICTED | 3 | No constraint. DUP and DROP both permitted. |

The enforcement point is the `checkLinearity` export and the linearity gate inside `executeScript`. When `linearityEnforced = true`, every opcode is classified by `classifyOp` into one of four stack operation categories: `consume`, `duplicate`, `discard`, `swap`, or `inspect`. Before executing the opcode, the gate calls `linearityPermits(cell.header.linearity, op)`. For a LINEAR cell, `linearityPermits(.linear, .duplicate)` returns `false` and `linearityPermits(.linear, .discard)` returns `false`. A `false` result causes the executor step function to return an error — execution halts, and K4 ensures the PDA state is rolled back byte-for-byte.

The direct Lean statement:

```lean
theorem k1a_linear_no_duplicate :
    linearityPermits .linear .duplicate = false := rfl

theorem k1b_linear_no_discard :
    linearityPermits .linear .discard = false := rfl
```

These are `rfl` proofs — the definitions of `linearityPermits` are explicit enough that the evaluator can check them without further argument. The stronger result, K1c, states that in any valid execution trace with linearity enforcement enabled, a LINEAR cell appears at most once across all stacks:

```lean
theorem k1c_linear_unique_on_stacks
    (cell : Cell)
    (_h_lin : cell.header.linearity = .linear)
    (state : ExecutorState)
    (_h_enf : state.linearityEnforced = true)
    (hostFetch : Cell → Option Cell)
    (state' : ExecutorState)
    (h_step : state.step hostFetch = .ok state')
    (h_count : countCell cell (allStackCells state.pda) ≤ 1) :
    countCell cell (allStackCells state'.pda) ≤ 1
```

The proof uses a structural lemma (`step_preserves_pda`) showing that the step function only modifies the `pc`, `opcount`, and `linearityEnforced` fields of the executor state, leaving the PDA — and therefore all stack cells — unchanged. Since K1a proves that no duplicate operation can succeed on a LINEAR cell, no new copy can be created, and the count-at-most-one property is preserved across every step.

Capability tokens (BRC-108 UTXOs) are modelled as LINEAR semantic resources. Spending the UTXO is the consumption proof; the cell engine enforces this with `OP_ASSERTLINEAR` (`0xC5`) and `OP_CHECKCAPABILITY` (`0xC3`). A capability token that has already been consumed cannot be presented as unconsumed — the on-chain spend is the record, and the cell engine's linearity gate is the local enforcement complement.

### K3: domain isolation

K3 states: `OP_CHECKDOMAINFLAG` is total and correct. The proof `DomainIsolationK3.lean` establishes this mechanically.

Domain flags are 4-byte uint32 namespace identifiers carried at cell header offset 24–27. The namespace is partitioned into three ranges: `0x00000001`–`0x000000FF` (Plexus reserved), `0x00000100`–`0x0000FFFF` (extended Plexus standards), and `0x00010000`–`0xFFFFFFFF` (operator sovereignty). `OP_CHECKDOMAINFLAG` reads the four bytes at offset 24 as a little-endian uint32 and compares it against an expected value on the stack. `OP_CHECKDOMAIN` checks whether the flag falls within an authorised range for the current context.

The totality claim means `OP_CHECKDOMAINFLAG` terminates on every input and either succeeds or fails cleanly — it cannot enter an undefined state, loop, or produce a domain-flag result that depends on memory outside the cell header. The correctness claim means the opcode's result is exactly the boolean of `cell.header.domainFlag == expected`.

Domain isolation at the cell engine level complements governance domain enforcement at the SIR layer. The SIR layer refuses, at compile time, to lower certain cross-domain claims — a node with `trustClass: authoritative` but `proofRequirement` other than `formal` is a static rejection. Domain flag enforcement at the cell engine is the runtime complement: even if an opcode program is constructed that bypasses the SIR compiler, the cell engine checks the domain flag in the header on every execution.

### K4: failure atomicity

K4 states: failed Plexus opcodes leave the PDA state byte-for-byte unchanged. The proof `FailureAtomicK4.lean` covers this property.

The consequence for deployment is that a script that fails partway through — a linearity violation, a BUMP mismatch, a capability token check that fails — leaves the cell engine in exactly the state it was in before the script began. There is no partial state advance, no partial consumption, no partial capability spend. The operator or adapter that submitted the script can retry with a corrected script or report the failure, knowing that no side effect has been applied.

This property is what makes the cell engine safe to use in a retry loop. An adapter that submits a cell for evaluation and receives a failure can resubmit — possibly with a corrected cell, a refreshed capability token proof, or an updated BUMP path — without risking a double-spend or a half-applied state transition.

K4 interacts with K1 in the capability token case. A capability token that is submitted to `OP_CHECKCAPABILITY` is checked, not consumed. The consumption is the on-chain spend. If `OP_CHECKCAPABILITY` fails (the UTXO has already been spent, or the BUMP proof is stale), the PDA state is unchanged by K4. The capability token has not been double-consumed because the local cell engine never was the authority for consumption — the BSV UTXO set is.

### K5: termination

K5 states: every execution terminates within `opcountLimit` steps. The proof `TerminationK5.lean` is mechanised over the abstract 2-PDA model.

The bound is enforced by the executor's opcount counter. Every time the executor processes one opcode, it increments `opcount`. If `opcount >= opcountLimit`, execution halts with an opcount-exceeded error before processing the next opcode. Combined with the no-loops, no-jumps property of the instruction set, this gives a hard upper bound on execution time.

The default `opcountLimit` is 1,000,000 opcodes per script. This is configurable — an operator deploying a cell engine for a use case with short scripts can reduce it; an operator with complex scripts can increase it, understanding that the worst-case execution time scales linearly with the limit.

K5 is the invariant that makes the cell engine deployable in latency-sensitive contexts. An adapter handling a real-time request can set a per-request `opcountLimit` appropriate to its SLA, confident that the cell engine will respect it.

### K7: cell immutability

K7 states: the 256-byte cell header is read-only after packing. The proof `CellImmutabilityK7.lean` establishes this over the instruction set.

The practical meaning is: no sequence of Plexus opcodes can modify the linearity class, type hash, owner identifier, domain flag, or hash-chain pointers of a cell that is on the stack. The header is read by many opcodes — `OP_CHECKLINEARTYPE`, `OP_CHECKDOMAINFLAG`, `OP_ASSERTLINEAR`, `OP_VERIFYVERSION` all read specific header fields — but no opcode writes to the header.

This property underpins the hash-chain integrity: if a cell's `prevStateHash` could be modified after packing, the hash chain could be rewritten in place. K7 prevents this. The hash chain is append-only at the cell level (see the TLA+ model for K6, which covers append-only semantics at the distributed level).

K7 also enforces the type hash's role as a type discriminator. The type hash (SHA-256 of `whatPath:howSlug:instPath`) is computed at pack time and cannot be changed. An adapter can trust that a cell bearing a particular type hash has the semantics that type hash represents — the cell engine cannot be used to recast a cell to a different type.

---

## Profiles and deployment

### Full and embedded profiles

The cell engine ships in two profiles. The full profile (~185 KB) includes native SHA-256, RIPEMD-160, and secp256k1 implementations and is appropriate for standalone servers and CLI tools that own their cryptographic stack. The embedded profile (~29 KB) expects cryptographic primitives to be provided by the host via WASM imports and is appropriate for browser applications that already carry a crypto library.

Both profiles MUST execute byte-identical opcode programs against byte-identical inputs and produce byte-identical outputs. The only structural difference is the source of cryptographic primitives. Implementations MUST NOT produce profile-dependent results; any divergence is a bug against §8.5 of the protocol spec.

The production WASM MUST be built with `embedded = true` to strip debug code paths. The debug code paths are not a security concern in themselves, but they increase binary size and may introduce non-constant-time paths that the formal verification posture does not cover.

### Bytecode gate integration

The cell engine's role in the broader substrate is as a bytecode gate: the point at which OIR-emitted opcode bytes are evaluated against the protocol invariants K1, K3, K4, K5, and K7. The Verifier Sidecar (chapter 14) operates at the adapter boundary, checking BRC-100 signatures and BRC-52 cert authenticity before a message reaches the cell engine. The cell engine then checks the semantic predicates — linearity, domain isolation, capability token validity, hash-chain integrity, and pipeline phase.

This division of responsibility is explicit in the protocol spec's conformance table. A kernel-conformant implementation MUST implement the cell wire format (§3), the cell engine (§8), and K1–K5 and K7 enforcement. The Verifier Sidecar is a SHOULD at minimum, required for identity-conformant and above.

### The substrate's U1 component

In the unification roadmap's ten-component substrate model, the cell engine is U1. The other nine components depend on it: the Plexus identity layer passes BRC-52 cert verification through it; the capability domain mints and consumes BRC-108 UTXOs via cell engine scripts; the mesh passes `SignedBundle` frames through it for verification; the SIR and lexicons generate the opcode programs it evaluates; the Lean proof layer verifies the invariants it enforces.

U1 being the first component in the substrate is not alphabetical accident. The cell engine is the substrate's execution kernel — everything that moves through the system eventually reaches the bytecode gate.

---

## The Lean proof of K1

The mechanised proof of K1 in `proofs/lean/Semantos/Theorems/LinearityK1.lean` establishes three sub-theorems. K1a and K1b are the primitive cases — they are `rfl` proofs that follow directly from the definition of `linearityPermits`. K1c is the structural induction that carries those primitive cases forward across an execution trace.

The proof target is the `linearityPermits` function in `linearity.zig` and the linearity gate inside the executor. The Lean model abstracts both into the `ExecutorState` type with its `step` function, and the `linearityPermits` function mapping `(LinearityClass, StackOp) → Bool`.

The key theorem statement, in full:

```lean
theorem k1c_linear_unique_on_stacks
    (cell : Cell)
    (_h_lin : cell.header.linearity = .linear)
    (state : ExecutorState)
    (_h_enf : state.linearityEnforced = true)
    (hostFetch : Cell → Option Cell)
    (state' : ExecutorState)
    (h_step : state.step hostFetch = .ok state')
    (h_count : countCell cell (allStackCells state.pda) ≤ 1) :
    countCell cell (allStackCells state'.pda) ≤ 1 := by
  have h_pda := step_preserves_pda state state' hostFetch h_step
  rw [allStackCells, h_pda]
  exact h_count
```

The proof body is three lines. The first calls the `step_preserves_pda` lemma, which establishes that the step function, when it returns `.ok state'`, leaves `state'.pda = state.pda`. The second rewrites the goal using that equality. The third discharges the goal directly from the hypothesis `h_count`.

The load-bearing work is in `step_preserves_pda`, which pattern-matches all branches of the step function and shows by case analysis that in every branch that returns `.ok state'`, the `pda` field is propagated unchanged. The branches that would modify the PDA (which do not exist in this instruction set) would have to be handled separately — their absence is the structural enforcement that K1c relies on.

The proof is not a proof that the Zig implementation is correct. It is a proof that the abstract model of the executor, as formalised in Lean, satisfies the K1 property. The formal verification strategy (see chapter 12 for the full picture) uses this as one layer of a three-layer argument: the Lean proof covers the abstract model; a separate correspondence argument (outside the scope of this chapter) connects the abstract model to the Zig implementation; testing against the WASM output then validates the correspondence.

---

## Boot-sequence step 7 unlocked

The boot sequence is a 15-step procedure taking a sovereign node from cold start to federated, metered, fully K1-through-K10-compliant online state. Steps 1 through 6 cover identity derivation and capability domain initialisation (see chapters 4 and 5). Step 7 is:

> **Cell engine boots; `kernel_set_enforcement(1)` is called.**

This call is the crossing of the invariant enforcement threshold. Before it, the cell engine accepts opcode programs without checking K1 through K5 or K7. After it, every script submitted to the engine is checked against all five enforcement invariants before any state transition is committed. The call is irreversible for the lifetime of the kernel instance.

Step 7 can be reached without external network dependencies. The WASM binary is loaded from a locally verified artefact (the binary hash checked against the on-chain anchor from the prior release cycle); `kernel_init()` initialises the kernel state; bootstrap scripts load and execute the initial cells that establish the local capability domain; `kernel_set_enforcement(1)` is called. All of this can complete on a machine with no internet connection, provided the binary and the bootstrap cells are present on disk.

Steps 8 through 15 — the Verifier Sidecar, World Host, mesh adapter, Helm, adapter subscriptions, recovery backup, MFP cashlanes, and user federation — each require external services or network peers for their full function. Step 7 is the boundary between the locally-provable substrate boot and the network-dependent federation.

With step 7 complete, the cell engine is operational and enforcement is live. The remaining chapters of Part III are in the past; the chapters of Part IV begin with step 8 as their target.

**Boot-sequence step 7 is now unlocked: `kernel_set_enforcement(1)` has been called.**
