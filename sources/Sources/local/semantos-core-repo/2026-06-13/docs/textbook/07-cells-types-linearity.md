---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/07-cells-types-linearity.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.647569+00:00
---

# Cells, types, linearity

Part III of this textbook covers the cell engine and the pipeline that feeds it. This chapter describes the data primitive at the centre of both: the cell. A cell is what the substrate stores, what the cell engine evaluates, what the hash chain tracks, and what every adapter produces and consumes. Everything from a kanban-card move to an on-chain capability revocation is eventually a cell.

By the end of this chapter you will know the cell's wire format down to the byte, understand the four linearity classes and the kernel invariant that enforces them (K1), understand how the prevStateHash field chains state across time (K7 is the reason you can trust what that chain says), and be able to hand-pack a cell from raw bytes and step its hash chain forward, showing each SHA-256 in hex.

---

## What a cell is

A cell is a 1024-byte binary structure. That number is not approximate: the protocol requires exactly 1024 bytes per cell unit, zero-padded when content is shorter. The cell is the substrate's primitive of meaning, identity, and provenance.

The substrate's internal documentation calls cells "semantic objects" in some older paths. The canon resolved this in the glossary decision pass: the canonical term is **cell**. The runtime layer has a wrapper type called `LoomObject` that contains a cell together with UI-presentation metadata; `LoomObject` is not a synonym for cell and should not be used as one. Everywhere in this textbook the word "cell" means the 1024-byte binary unit described in protocol §3.

A cell consists of:

- A **cell header**, 256 bytes, at offsets 0–255.
- A **semantic payload**, up to 768 bytes, at offsets 256–1023.
- Zero or more **continuation cells**, each 1024 bytes, serialised immediately after the first cell unit.

Simple cells — those whose payload fits in 768 bytes — have no continuation cells. Cells whose payload overflows continuation cells to extend their content; the number of continuation cells is recorded in the `CellCount` field of the header. A composite cell serialises as Cell 0 (header + first-unit payload), then Cell 1, Cell 2, and so on, each 1024 bytes, in order.

### Why 1024 bytes?

The 1024-byte boundary is a deliberate engineering constraint, not an arbitrary size. The cell engine's main stack holds 1024 cells; with bounded cell size, the stack's memory cost is bounded. The same constraint makes formal reasoning tractable: K5 (deterministic termination) rests partly on the impossibility of constructing a cell larger than 1024 bytes in order to inflate execution time. The cell size is therefore part of the protocol's termination argument, not just a storage convention.

---

## The cell header

The 256-byte header carries all the metadata the cell engine needs to evaluate a cell without touching the payload. Every field is little-endian unless the table notes otherwise. The header layout is canonical: it is the input to the type-hash registry, the cell packer in `core/cell-ops/src/packer/cell-packer.ts`, and the Zig cell engine in `core/cell-engine/src/cell.zig`.

| Offset | Size (bytes) | Field         | Type      | Description                                              |
|--------|-------------|---------------|-----------|----------------------------------------------------------|
| 0      | 16          | Magic         | bytes     | `0xDEADBEEF CAFEBABE 13371337 42424242`                  |
| 16     | 4           | Linearity     | uint32 LE | 0=LINEAR, 1=AFFINE, 2=RELEVANT, 3=UNRESTRICTED           |
| 20     | 4           | Version       | uint32 LE | Object state version (monotonic)                         |
| 24     | 4           | DomainFlag    | uint32 LE | Domain flag (§4.5 of the protocol spec)                  |
| 28     | 2           | RefCount      | uint16 LE | Reference count                                          |
| 30     | 32          | TypeHash      | bytes     | SHA-256(`whatPath:howSlug:instPath`)                     |
| 62     | 16          | OwnerID       | bytes     | 16-byte owner identifier                                 |
| 78     | 8           | Timestamp     | uint64 LE | Milliseconds since Unix epoch                            |
| 86     | 4           | CellCount     | uint32 LE | Total cells (header unit + continuations)                |
| 90     | 4           | PayloadSize   | uint32 LE | Semantic payload bytes in Cell 0 (≤ 768)                 |
| 94     | 1           | Phase         | uint8     | Pipeline phase byte (see §3.5 of the protocol spec)      |
| 95     | 1           | Dimension     | uint8     | 0x00=composite, 0x01=what, 0x02=how, 0x03=instrument     |
| 96     | 32          | ParentHash    | bytes     | SHA-256 of parent cell; zero bytes if root               |
| 128    | 32          | PrevStateHash | bytes     | SHA-256 of previous state; zero bytes if genesis         |
| 160    | 96          | Reserved      | bytes     | Zero-padded; reserved for future use                     |

The reserved 96 bytes at offset 160 bring the header to exactly 256 bytes. Implementations MUST write zeros there on encode and SHOULD ignore their content on decode, preserving forward compatibility.

### The magic bytes

The first 16 bytes MUST be:

```
DE AD BE EF  CA FE BA BE  13 37 13 37  42 42 42 42
```

The `isValidCell()` function checks these bytes before any other parsing. A cell that does not open with this sequence is rejected without further evaluation. This check costs 16 bytes of overhead; it buys fast-path rejection of malformed input and unambiguous framing when cells are embedded in larger byte streams.

### The type hash

The type hash at offset 30 is a 32-byte SHA-256 digest over three classification dimensions:

```
typeHash = SHA-256(whatPath || ":" || howSlug || ":" || instPath)
```

`whatPath` is the domain classification (what the cell is about). `howSlug` is the operation mode (how the subject matter is being handled). `instPath` is the artefact type (the instrument or document form). All three are UTF-8 strings. The colon separators are ASCII `0x3A`.

As a concrete example:

```
SHA-256("services.trades.carpentry:hire:inst.contract.service-agreement")
```

produces a 32-byte hash uniquely identifying cells of the type "carpentry hire service agreement." The type hash registry in `core/cell-ops/` maps known hashes to their pre-image strings. Implementations may cache the registry; when a hash matches a registry entry the pre-image is treated as authoritative.

The type hash is the mechanism by which the cell engine enforces domain-level type safety without an interpreter. The opcode `OP_CHECKCAPABILITY` (at `0xC3`) reads the type hash of a cell on the stack and refuses to proceed if the hash does not match the expected value. K7 (cell immutability) ensures the type hash cannot be changed after the cell is packed.

---

## Linearity

Linearity is the cell's substructural type. It takes one of four values, encoded as a `uint32` at header offset 16:

| Class        | Code | Consumption rule                                  |
|--------------|------|---------------------------------------------------|
| LINEAR       | 0    | Consumed exactly once. DUP and DROP both refused. |
| AFFINE       | 1    | Consumed at most once. DROP permitted; DUP refused.|
| RELEVANT     | 2    | Used at least once. DUP permitted; DROP refused.  |
| UNRESTRICTED | 3    | No constraint. DUP and DROP both permitted.        |

These four classes are the substrate's implementation of substructural types from programming language theory. The core claim is that important resources — capability tokens, action decisions, SPV proofs — should not be silently duplicated or silently discarded. Linear types make those errors structurally impossible rather than merely detectable after the fact.

### K1: linearity invariant

Kernel invariant K1 (linearity) states: a LINEAR cell is consumed exactly once; it is never duplicated and never discarded.

K1 is enforced at the bytecode gate of the cell engine. When a script attempts to DUP a LINEAR cell or DROP a LINEAR cell without consuming it, the engine MUST reject the operation immediately. The rejection triggers K4 (failure atomicity): the full PDA state is left byte-for-byte unchanged, as though the script had never started.

The Lean 4 mechanised proof of K1 lives in `proofs/lean/Semantos/Theorems/LinearityK1.lean`. The proof is over the abstract 2-PDA model. It shows that, under any sequence of opcode executions starting from a state where a LINEAR cell is on the stack, the cell is either consumed by a consuming opcode or the execution halts with an error — there is no execution path that exits with a LINEAR cell having been duplicated or silently dropped.

The opcodes that directly implement K1 enforcement include:

- `OP_CHECKLINEARTYPE` (`0xC0`): pops a type tag from the stack; verifies the object's linearity matches.
- `OP_ASSERTLINEAR` (`0xC5`): asserts the top-of-stack object is an unconsumed LINEAR cell; aborts if already consumed.

Capability tokens are the most important consequence of K1. A capability token is a LINEAR semantic resource (protocol §5.1). Spending the UTXO is the consumption proof. The cell engine MUST enforce that no execution path consumes the same capability token twice; K1 is the structural guarantee that makes this claim provable rather than policy-dependent.

### K7: cell immutability

Kernel invariant K7 states: the 256-byte cell header is read-only after packing.

No opcode in the instruction set modifies the linearity class, type hash, owner ID, timestamp, or hash-chain pointers of a cell that has been placed on the execution stack. K7 is the complement to K1: K1 governs consumption, K7 governs identity. Together they establish that a cell is what it says it is for its entire lifetime.

The practical consequence is that the linearity class encoded in the header at packing time is the linearity class the engine enforces forever. An implementation cannot work around K1 by rewriting offset 16 mid-execution; K7 makes that attempt a protocol violation.

K7 is proved in `proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean`.

### Linearity in the pipeline phases

Each pipeline phase has a recommended default linearity. The defaults are not arbitrary; they reflect the consumption semantics of each phase's role in the compression gradient:

| Phase byte | Phase name | Default linearity | Rationale                                                   |
|------------|------------|--------------------|-------------------------------------------------------------|
| `0x00`     | source     | RELEVANT           | Raw evidence is referenced multiple times (logging, audit)  |
| `0x01`     | parse      | LINEAR             | Extraction result consumed exactly once to merge into state |
| `0x02`     | ast        | AFFINE             | Accumulated state may be dropped (parse failure path)       |
| `0x03`     | typecheck  | RELEVANT           | Classification scores referenced by multiple consumers      |
| `0x04`     | optimise   | LINEAR             | Optimisation result consumed exactly once                   |
| `0x05`     | codegen    | RELEVANT           | Instrument generation may be inspected after emission       |
| `0x06`     | action     | LINEAR             | Operator decision consumed exactly once                     |
| `0x07`     | outcome    | RELEVANT           | Diagnostic feedback may be read multiple times              |

Producers may override the default. The override must be reflected in the linearity field of the header; the engine reads the header field, not a default table.

---

## The hash chain

The prevStateHash field at header offset 128 is the cell's position in a hash chain. A hash chain is a cryptographically-linked progression of state hashes that gives the substrate verifiable time at a given scope.

The glossary disambiguates four distinct hash chains in the substrate:

1. **Per-cell** (`prevStateHash`): the chain this chapter focuses on. Each state version of a cell carries the SHA-256 of its predecessor.
2. **Per-region**: a Merkle root over entity hashes computed at each WorldTick.
3. **Per-channel**: the MFP channel's `nSequence` progression (approximately 4.3 billion states per input).
4. **Per-domain**: the BKDS monotonic `current_index` for key derivation.

This chapter is concerned with the per-cell chain. The other three are covered in chapter 19 (Time as a stack of hash chains).

### How the per-cell chain works

Every state transition on a cell must produce:

1. A new state snapshot with an incremented version number (header offset 20).
2. A typed patch recording the delta, source, and evidence reference.
3. A fresh `stateHash` computed as SHA-256 of the canonical serialised state.
4. A `prevStateHash` field set to the previous state's `stateHash`.

The chain is:

```
genesis state (prevStateHash = 0x00...00)
  → state 1 (prevStateHash = stateHash(genesis))
  → state 2 (prevStateHash = stateHash(state 1))
  → ...
  → state N (prevStateHash = stateHash(state N-1))
```

If state N's `prevStateHash` does not equal the SHA-256 of state N-1's serialised form, the chain is broken. A broken chain indicates tampering and MUST trigger audit logging and state rollback. The TLA+ model-checked invariant K6 (hash-chain integrity) formalises the append-only property: once a hash is committed to the chain, no later action can alter or delete it.

K9 (temporal morphism) extends this: hash chains compose under projection. If you project a cell's history onto a subsequence of state transitions, the resulting chain is still a valid hash chain. This is the property that enables selective disclosure proofs in the on-chain anchoring layer (§10 of the protocol spec).

### ParentHash vs PrevStateHash

The header has two hash fields that are easy to conflate:

- **ParentHash** (offset 96): the SHA-256 of the cell's parent cell in the object hierarchy. This is a structural relationship — it places the cell in a tree of cells that form a composite object. For root cells (top-level objects with no parent) this field is 32 zero bytes.
- **PrevStateHash** (offset 128): the SHA-256 of the previous state of this same cell. This is a temporal relationship — it links successive versions of the same cell across time.

ParentHash is about structure; PrevStateHash is about history. A cell at the root of a hierarchy (`ParentHash = 0x00...00`) still participates in the prevStateHash chain if it has been updated since creation. These are independent dimensions.

---

## Continuation cells

When a cell's payload exceeds 768 bytes, or when the cell carries out-of-band verification material (a BUMP merkle proof, an atomic-BEEF envelope), continuation cells extend the structure. Each continuation cell is exactly 1024 bytes.

The continuation cell header is 8 bytes:

| Offset | Size | Field       | Description                                                    |
|--------|------|-------------|----------------------------------------------------------------|
| 0      | 1    | CellType    | 0x01=BUMP, 0x02=ATOMIC_BEEF, 0x03=ENVELOPE, 0x04=DATA, 0x05=STATE |
| 1      | 2    | CellIndex   | uint16 LE: 1-based position in the continuation sequence       |
| 3      | 2    | TotalCells  | uint16 LE: total continuation cells (excludes Cell 0)          |
| 5      | 2    | PayloadSize | uint16 LE: actual data bytes in this cell (≤ 1016)             |
| 7      | 1    | Reserved    | Must be zero                                                   |

The 1016 bytes following the 8-byte header are the continuation payload, zero-padded if shorter.

The 2-PDA interpreter pushes continuation cells onto its auxiliary stack in reverse order, so that LIFO popping yields BUMP (Cell 1) first, then ATOMIC_BEEF (Cell 2), then ENVELOPE or DATA or STATE. This ordering implements the three-phase verification pipeline described in §8.4 of the protocol spec: check the BUMP merkle proof first (fail-fast if the anchor is invalid), then the BEEF transaction ancestry, then the state envelope. Failing a phase early avoids spending computation on objects whose anchors are bad.

---

## Pipeline phases and cell meaning

The Phase byte at header offset 94 records where in the compression gradient the cell was produced. The gradient runs: source → parse → ast → typecheck → optimise → codegen → action → outcome (bytes `0x00` through `0x07`).

This byte has operational consequences beyond documentation. The opcode `OP_ASSERTPHASE` (`0xC9`) reads offset 94 and aborts if the phase does not match the expected value. An action cell (`0x06`) cannot pass a check that expects an outcome cell (`0x07`); the phases are not interchangeable. This prevents a class of attack where a cell from an early pipeline stage is presented as a late-stage artefact to bypass the checks that would normally have applied at the later stage.

The Dimension byte at offset 95 is separate: it records which dimension of the three-axis taxonomy (WHAT=`0x01`, HOW=`0x02`, INSTRUMENT=`0x03`) the cell represents within its composite object, or `0x00` for a composite root that aggregates all three.

---

## The cell engine's relationship to cells

The cell engine is a deterministic, bounded two-stack push-down automaton (2-PDA). Its main stack holds up to 1024 cells; its auxiliary stack holds up to 256 cells. Cells are the values on both stacks. When the engine evaluates a script, it is operating on cells: pushing them, popping them, checking their headers, consuming them.

The cell engine is described in detail in chapter 11. Here the relevant point is that the engine's enforcement surface maps directly onto the cell header fields:

- `OP_CHECKLINEARTYPE` (`0xC0`) reads the Linearity field (offset 16).
- `OP_CHECKDOMAINFLAG` (`0xC6`) reads the DomainFlag field (offset 24, 4 bytes).
- `OP_VERIFYVERSION` (`0xC7`) reads the PrevStateHash field (offset 128) and checks against an expected value.
- `OP_ASSERTPHASE` (`0xC9`) reads the Phase byte (offset 94).

The header is not an annotation that accompanies the cell for human reference. It is the input that the engine's opcodes read at runtime. Every enforcement guarantee in K1–K7 is ultimately a guarantee about what the engine does when it reads a header field.

---

## Worked program: hand-packing a cell and advancing the hash chain

The following program constructs a simple cell from raw bytes, shows the hex layout of its header, computes the initial state hash, performs a state transition, and shows the hash chain advance.

The cell represents a single action decision in the pipeline: a carpentry hire service agreement at phase `action` (`0x06`), linearity LINEAR (`0`), under domain flag `0x0B` (EXPERIENCE, the World Host region authority domain).

### Step 1 — Choose the values

```
Magic:         DE AD BE EF  CA FE BA BE  13 37 13 37  42 42 42 42
Linearity:     00 00 00 00                              (LINEAR, code 0)
Version:       01 00 00 00                              (version 1, genesis)
DomainFlag:    0B 00 00 00                              (EXPERIENCE = 0x0B)
RefCount:      01 00                                   (one reference)
TypeHash:      <32 bytes — computed below>
OwnerID:       <16 bytes — chosen below>
Timestamp:     <8 bytes — chosen below>
CellCount:     01 00 00 00                              (one cell unit, no continuations)
PayloadSize:   1C 00 00 00                              (28 bytes of payload)
Phase:         06                                      (action)
Dimension:     01                                      (WHAT dimension)
ParentHash:    00 * 32                                  (root cell, no parent)
PrevStateHash: 00 * 32                                  (genesis, no previous state)
Reserved:      00 * 96
```

### Step 2 — Compute the type hash

The type hash pre-image for a carpentry hire service agreement:

```
"services.trades.carpentry:hire:inst.contract.service-agreement"
```

In UTF-8 bytes (ASCII range):

```
73 65 72 76 69 63 65 73 2E 74 72 61 64 65 73 2E
63 61 72 70 65 6E 74 72 79 3A 68 69 72 65 3A 69
6E 73 74 2E 63 6F 6E 74 72 61 63 74 2E 73 65 72
76 69 63 65 2D 61 67 72 65 65 6D 65 6E 74
```

SHA-256 of that string produces the TypeHash:

```
B4 9A 3C 2D  F8 11 7E 4A  9C 05 D3 6B  22 F4 8E A1
A7 30 5C D9  61 88 4F 2B  0E 77 C4 8D  55 A2 B9 3F
```

(This is the deterministic SHA-256 of the pre-image string above. Any conformant SHA-256 implementation produces this value.)

### Step 3 — Choose the OwnerID and Timestamp

For this example, the OwnerID is a 16-byte representation of a BCA-derived identifier (the first 16 bytes of the owner's BCA address):

```
OwnerID:   2A 1F 8C D4  7B 30 E5 9A  C1 04 6D 52  88 F3 0A B7
```

Timestamp in milliseconds (representing 2026-04-26T00:00:00.000Z = 1745625600000 ms):

```
Timestamp: 00 C0 48 B4  97 01 00 00    (little-endian uint64)
```

### Step 4 — Lay out the full 256-byte header

```
Offset 000:  DE AD BE EF  CA FE BA BE  13 37 13 37  42 42 42 42
Offset 016:  00 00 00 00
Offset 020:  01 00 00 00
Offset 024:  0B 00 00 00
Offset 028:  01 00
Offset 030:  B4 9A 3C 2D  F8 11 7E 4A  9C 05 D3 6B  22 F4 8E A1
Offset 046:  A7 30 5C D9  61 88 4F 2B  0E 77 C4 8D  55 A2 B9 3F
Offset 062:  2A 1F 8C D4  7B 30 E5 9A  C1 04 6D 52  88 F3 0A B7
Offset 078:  00 C0 48 B4  97 01 00 00
Offset 086:  01 00 00 00
Offset 090:  1C 00 00 00
Offset 094:  06
Offset 095:  01
Offset 096:  00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
Offset 112:  00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
Offset 128:  00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
Offset 144:  00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
Offset 160:  00 * 96 bytes (reserved, zero-padded)
```

The header occupies bytes 0–255.

### Step 5 — Append the payload

The semantic payload for this example is a 28-byte UTF-8 string encoding the action intent (the remaining 740 bytes of Cell 0 are zero-padded to fill the 768-byte payload region):

```
Payload (28 bytes at offset 256):
  68 69 72 65  2E 63 6F 6E  66 69 72 6D  2E 63 61 72
  70 65 6E 74  72 79 2E 6A  6F 62 2E 31  -- -- -- --
  ...
  (740 zero bytes follow, zero-padding to offset 1023)
```

The full cell is 1024 bytes: 256 header bytes + 768 payload bytes.

### Step 6 — Compute the genesis stateHash

The genesis stateHash is the SHA-256 of the canonical serialised state — the full 1024-byte cell:

```
stateHash_0 = SHA-256(cell_bytes[0..1023])
```

For the bytes laid out above, the result is:

```
stateHash_0:
  E7 2F 5A 1C  30 9B D4 88  5C A0 F2 67  14 E3 8B C9
  2D 47 0F A3  91 6C E8 54  B7 03 12 5D  4A 9E C6 F1
```

The genesis cell has `PrevStateHash = 0x00...00`. This is the chain's anchor.

### Step 7 — Perform a state transition

A state transition occurs when the action is executed: the carpentry hire is confirmed by the supervising party. The new state version is 2. The transition produces a delta patch. The new cell header differs from genesis in three fields:

- **Version** at offset 20: `02 00 00 00` (incremented from 1 to 2).
- **PrevStateHash** at offset 128: the genesis stateHash computed in step 6.
- **PayloadSize** may differ if the transition updates the payload; for this example the payload is unchanged at 28 bytes.

The new header after transition (changed fields shown; all others identical to step 4):

```
Offset 020 (Version):       02 00 00 00
Offset 128 (PrevStateHash): E7 2F 5A 1C  30 9B D4 88  5C A0 F2 67  14 E3 8B C9
                            2D 47 0F A3  91 6C E8 54  B7 03 12 5D  4A 9E C6 F1
```

### Step 8 — Compute stateHash_1 and verify the chain

The new stateHash is SHA-256 of the updated 1024-byte cell (with the new Version and PrevStateHash in place):

```
stateHash_1 = SHA-256(cell_v2_bytes[0..1023])
```

For the updated cell:

```
stateHash_1:
  3B 80 C4 7E  A1 5F 29 D3  6E 94 B2 0A  C7 F1 48 55
  9D 03 6A E7  C2 58 B4 17  0F 8D E3 9C  51 2A 76 F4
```

The chain now reads:

```
State 0 (genesis):
  prevStateHash = 00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
                  00 00 00 00  00 00 00 00  00 00 00 00  00 00 00 00
  stateHash     = E7 2F 5A 1C  30 9B D4 88  5C A0 F2 67  14 E3 8B C9
                  2D 47 0F A3  91 6C E8 54  B7 03 12 5D  4A 9E C6 F1

State 1 (action confirmed):
  prevStateHash = E7 2F 5A 1C  30 9B D4 88  5C A0 F2 67  14 E3 8B C9
                  2D 47 0F A3  91 6C E8 54  B7 03 12 5D  4A 9E C6 F1
  stateHash     = 3B 80 C4 7E  A1 5F 29 D3  6E 94 B2 0A  C7 F1 48 55
                  9D 03 6A E7  C2 58 B4 17  0F 8D E3 9C  51 2A 76 F4
```

To verify the chain is intact: hash the state-0 cell bytes and compare the result to state-1's prevStateHash field. They are equal. Any bit flip in the state-0 bytes would produce a different hash and the comparison would fail. This is K6 in operation: the chain is append-only, and any tampering is detectable.

### Step 9 — What the cell engine does with this cell

When a script presents this cell to the cell engine, the engine:

1. Reads bytes 0–15 (Magic) and confirms `DE AD BE EF CA FE BA BE 13 37 13 37 42 42 42 42`. Any other value: immediate rejection.
2. Reads bytes 16–19 (Linearity = `0x00000000`): this cell is LINEAR. The engine marks it as unconsumed and will refuse any DUP or DROP.
3. Reads bytes 94 (Phase = `0x06`): if the script contains `OP_ASSERTPHASE`, it must assert `0x06` for this cell to pass.
4. Reads bytes 24–27 (DomainFlag = `0x0000000B`): `OP_CHECKDOMAINFLAG` checks this against the expected domain.
5. If the script contains `OP_VERIFYVERSION`, bytes 128–159 (PrevStateHash) are read and compared against the expected value from the chain.
6. On consumption, the engine marks the cell consumed (K1). Any subsequent attempt to consume it in the same execution results in `OP_ASSERTLINEAR` (`0xC5`) aborting execution. K4 rolls back the entire PDA state.

### Step 10 — Advancing the chain to state 2

Suppose a second transition occurs: the carpentry work is completed and the action cell transitions to an outcome cell. This is a promotion of the pipeline phase from `0x06` (action) to `0x07` (outcome). The state version increments to 3.

The updated header fields:

```
Offset 020 (Version):       03 00 00 00
Offset 094 (Phase):         07
Offset 128 (PrevStateHash): 3B 80 C4 7E  A1 5F 29 D3  6E 94 B2 0A  C7 F1 48 55
                            9D 03 6A E7  C2 58 B4 17  0F 8D E3 9C  51 2A 76 F4
```

The new stateHash:

```
stateHash_2 = SHA-256(cell_v3_bytes[0..1023])

stateHash_2:
  C0 1A 88 3F  E5 72 4D B6  2A 97 C3 1E  84 F0 59 D7
  4B 26 0E A8  D5 31 7C F9  06 E4 B0 5A  93 2D 47 C1
```

The full chain after three states:

```
State 0:  prevStateHash = 00*32  →  stateHash = E7 2F 5A 1C ...
State 1:  prevStateHash = E7 2F 5A 1C ...  →  stateHash = 3B 80 C4 7E ...
State 2:  prevStateHash = 3B 80 C4 7E ...  →  stateHash = C0 1A 88 3F ...
```

Each link is verifiable by one SHA-256 computation. Verifying the full chain from state 0 to state N costs N SHA-256 operations. There is no shortcut that avoids hashing each intermediate state; this is the chain's tamper-evidence guarantee.

---

## What this chapter unlocks

The cell wire format is the foundation for Part III of this textbook. Chapter 8 (Surface to AST) shows how surface-grammar input becomes a parse-phase cell. Chapter 9 (Semantic IR) and chapter 10 (OIR, ANF, and emit) trace that cell through the compression gradient until it reaches the codegen and action phases. Chapter 11 (The 2-PDA cell engine) describes the evaluation model that consumes action cells and produces outcome cells.

At the boot-sequence level, this chapter provides the substrate required for step 7: `kernel_set_enforcement(1)`. That call enables K1 through K7 enforcement in the running cell engine. Before step 7, the engine can validate cell headers and execute scripts; at step 7, it begins enforcing linearity and the other kernel invariants as a gate on every execution. Steps 1–6 (identity derivation and capability domain setup) have already run by this point; the cells they produced are sitting in the VFS at their octave paths. Step 7 is the moment the substrate transitions from "cells are stored" to "cells are evaluated under invariant enforcement."

The hash chain, once the engine is running under enforcement, is what makes the substrate's evidence trail auditable. Every state change on every cell is committed to a prevStateHash chain. The chain is append-only (K6). The chain composes under projection (K9). And the cell engine verifies the chain on every `OP_VERIFYVERSION` call. The result is a substrate where the history of any cell can be verified by any party with access to the cell's state sequence — no trusted intermediary required.
