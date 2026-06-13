---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/34-cell-alignment.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.648996+00:00
---

# Chapter 34 — The 1024-Byte Cell: Alignment Across Layers

The cell is 1024 bytes. Not 512. Not 2048. Not a power-of-two chosen for taste. The exact size is **over-determined**: it satisfies four independent constraints simultaneously — one from the network, one from disk, one from the runtime, one from the bounded-termination proof. Any value that satisfies all four is a candidate; 1024 is the smallest. That is the load-bearing claim of this chapter.

The public framing tends to present the cell as a "shipping container with a manifest" — a metaphor that's evocative but understates why the dimensions are the dimensions. This chapter unpacks the alignment so future maintainers don't change the constant without understanding what breaks.

---

## 34.1 The Constants (Canonical)

The cell-size constants are generated from `core/constants/constants.json` into both TypeScript (`core/protocol-types/src/constants.ts`) and Zig (`packages/cell-engine/src/constants.zig`) by `bun run generate-constants`. The generator is idempotent and produces byte-identical output across runs.

| Constant | Value | Source |
|---|---|---|
| `CELL_SIZE` | `1024` | `core/protocol-types/src/constants.ts:5` |
| `HEADER_SIZE` | `256` | `core/protocol-types/src/constants.ts:8` |
| `PAYLOAD_SIZE` | `768` | `core/protocol-types/src/constants.ts:9` |
| `CONTINUATION_HEADER_SIZE` | `8` | `core/protocol-types/src/constants.ts:6` |
| `CONTINUATION_PAYLOAD_SIZE` | `1016` | `core/protocol-types/src/constants.ts:7` |
| `MAIN_STACK_CELLS` | `1024` | `core/protocol-types/src/constants.ts:16` |
| `MAIN_STACK_BYTES` | `1048576` (= 1024 × 1024) | `core/protocol-types/src/constants.ts:15` |
| `AUX_STACK_CELLS` | `256` | `core/protocol-types/src/constants.ts:14` |
| `AUX_STACK_BYTES` | `262144` (= 256 × 1024) | `core/protocol-types/src/constants.ts:13` |

A single cell is exactly 1024 bytes. A primary cell carries a 256-byte header and a 768-byte payload. A continuation cell (used when a logical payload exceeds 768 bytes) carries an 8-byte header and 1016 bytes of payload. Two stacks: a main stack of 1024 cells and an auxiliary stack of 256 cells.

These tests are pinned in `core/constants/__tests__/constants.test.ts:42-58` — any change to the constants without a corresponding change to that test (and a re-run of the generator) is a build break.

---

## 34.2 Layer 1 — Network: UDP Datagrams and Multicast Frames

### The constraint

UDP imposes a hard maximum payload size of 65,507 bytes per datagram (65,535 IPv4 packet limit minus 8 bytes UDP header minus 20 bytes IPv4 header; 65,527 for IPv6). The multicast transport substrate (chapter 17) places its own adapter header on top:

- Current `MulticastAdapter` (Phase-35A): 12-byte adapter header per datagram (`docs/textbook/17-mesh-and-session-skeleton.md` §17.2.2).
- BRC-124 reference (proposed alignment per `docs/prd/UNIFICATION-ROADMAP.md` §11.6): 92-byte header carrying tx-id, sender-id, sequence number, subtree-id, and payload length.

Useful payload per datagram is therefore bounded by `65507 - HEADER_SIZE`.

### The alignment

| Adapter header | Useful payload | Cells per datagram |
|---|---|---|
| 12 B (current) | 65,495 B | ⌊65,495 / 1024⌋ = **63 cells** with 7 B free |
| 92 B (BRC-124) | 65,415 B | ⌊65,415 / 1024⌋ = **63 cells** with 887 B free |

Either header sizing gives 63 cells per UDP datagram with room to spare for an envelope checksum or framing trailer. The mesh's `PayloadTooLargeError` (chapter 17 §17.2.3) is exactly this boundary — publishes larger than 65,507 minus the adapter header reject at the boundary rather than fragmenting silently.

### Why the alignment matters

A wire format that packs cells must support batching for throughput. With 1024-byte cells, the multicast adapter can pack a full datagram with 63 cells in a single send. A 2048-byte cell would halve this density to 31 cells per datagram, doubling the bandwidth needed for the same throughput. A 512-byte cell would double density to 127 cells per datagram, but the per-cell overhead of 256 bytes of header (which doesn't scale down) becomes 50% of the cell instead of 25%.

1024 is the smallest size where the 256-byte header is 25% overhead while still packing ≥60 cells per UDP datagram. The next smaller candidate that keeps header overhead ≤25% is 1024 exactly.

---

## 34.3 Layer 2 — Disk: LMDB 4 KB Page Packing

### The constraint

LMDB is the local persistent store underneath the brain. References in `runtime/semantos-brain/src/visits_store_lmdb.zig`, `quotes_store_lmdb.zig`, and `intent_cell_lmdb_store.zig` show LMDB used for cell-shaped records under K4 (failure-atomicity) discipline: write to LMDB first, then mutate in-memory state only on success.

LMDB's default page size is 4 KB (4096 bytes), determined by the underlying OS page size on Linux/macOS x86_64 and arm64. Records that straddle pages incur an extra page read on retrieval; records that pack cleanly into a page boundary do not.

### The alignment

```
4096 bytes / 1024 bytes per cell = exactly 4 cells per LMDB page
```

Zero waste. No straddle. Four cells fit per page with the page boundary landing exactly on a cell boundary. The next-cell read after a four-cell page is guaranteed to be a new page read, not a partial-page read.

### Counter-examples

- **2048-byte cells**: 2 per page — still clean, but worse density.
- **512-byte cells**: 8 per page — fine for packing, but the cell becomes too small to carry a 256-byte header plus useful payload.
- **1500-byte cells**: 2 per page with 1096 bytes wasted, or 3 cells straddling (one cell split across two pages) — worst case.
- **1024-byte cells**: 4 per page exactly. Optimal among candidates that satisfy other constraints.

The Pask layer (`core/pask/`, kernel-layer Zig WASM per memory `semantos_pask_layering.md`) uses LMDB cursors over these pages for its constraint-graph storage. Page-aligned reads keep cursor scans deterministic.

---

## 34.4 Layer 3 — Runtime: WASM Pages and Stack Allocation

### The constraint

WebAssembly's memory model uses 64 KB (65,536-byte) pages. Memory is allocated in whole-page increments. The 2PDA cell engine ships as a WASM module (`packages/cell-engine/`). Stack allocation must therefore round to WASM page boundaries; any sub-page allocation wastes the remainder of the page.

The 2PDA architecture (per `docs/FORMAL-VERIFICATION-STRATEGY.md` line 26) specifies "1024 main slots, 256 aux slots, no JMP" — fixed-size stacks of cell-sized entries.

### The alignment

Main stack:

```
1024 cells × 1024 bytes/cell = 1,048,576 bytes = 1 MB = 16 WASM pages exactly
```

Auxiliary stack:

```
256 cells × 1024 bytes/cell = 262,144 bytes = 256 KB = 4 WASM pages exactly
```

Combined: 20 WASM pages for both stacks, fitting in a 1.25 MB initial allocation. No half-pages. No fragmentation. The WASM linear memory layout for the cell engine is:

| Region | Pages | Bytes | Cells |
|---|---|---|---|
| Main stack | 16 | 1,048,576 | 1024 |
| Aux stack | 4 | 262,144 | 256 |

A change to `CELL_SIZE` cascades: a 2048-byte cell would force `MAIN_STACK_BYTES = 2,097,152` = 32 WASM pages; a 512-byte cell would force `MAIN_STACK_BYTES = 524,288` = 8 pages. Either is allowed by WASM, but only the 1024-byte size yields the "1 MB main stack" convenience that maps cleanly to operator-readable memory accounting.

### Cell pool reuse

The cell engine maintains pools of recycled cell-sized buffers for transient operations (continuation reads, scratch state during opcode evaluation). A 1024-byte buffer pool with N entries occupies exactly `N × 1024` bytes — no padding, no header per pool entry. Pool growth is cell-quantised, which simplifies allocator accounting.

---

## 34.5 Layer 4 — Anchoring: SHA-256 and BSV Provenance

### The constraint

Cell identity is content-addressed. The cell ID is the SHA-256 of the canonical cell state — header plus payload, 1024 bytes total. This appears in the cell header at offset 30 (`HeaderOffsets.typeHash`, 32 bytes per `core/protocol-types/src/constants.ts:96`) as the `typeHash` field and is the lookup key in the VFS (`runtime/shell/src/vfs/`).

Anchoring to BSV happens via BRC-62 BEEF envelopes (`extensions/chain-broadcast/BeefStore`). A cell is committed by including its SHA-256 in the OP_RETURN output of an anchoring transaction. SPV proofs (BRC-9) and merkle proofs (BRC-74 BUMP) reference these anchors.

### The alignment

SHA-256 has no preferred block size from the protocol's perspective — it'll hash any byte sequence. The point of alignment here is **predictability**: a 1024-byte input produces a SHA-256 hash in exactly 16 SHA-256 compression rounds (each round consumes 64 bytes; 1024 / 64 = 16). The cost of hashing one cell is fixed and known.

For a verifier sidecar (`packages/verifier-sidecar/`) that must hash thousands of cells per second during a BEEF ancestry verification, fixed-cost hashing is a scheduling property worth preserving. A variable-size cell would force the verifier to perform a multiplication per cell to estimate hash cost; a fixed-size cell turns hash cost into a constant.

### BRC-26 Universal Hash Resolution

Per §11.6 of `docs/prd/UNIFICATION-ROADMAP.md`, the VFS lookup path (`runtime/shell/src/vfs/`) should expose a BRC-26 endpoint that resolves cell IDs to their content. Cell ID = SHA-256(canonical state) maps directly to BRC-26's `hash → content` semantics. The 1024-byte cell is the unit of resolution; clients requesting a cell receive exactly one 1024-byte object.

---

## 34.6 Layer 5 — K5 Bounded Termination

### The invariant

K5 is the formal-verification invariant that guarantees every 2PDA execution terminates in a bounded number of opcodes (`docs/FORMAL-VERIFICATION-STRATEGY.md:26, :153-155`):

> **K5 (Deterministic Termination)**: Every execution terminates in at most `opcountLimit` steps. The PDA has no jump or call instructions.

The Lean 4 proof of K5 (`proofs/lean/Semantos/TerminationK5.lean`) depends on three preconditions:

1. The instruction set has no backward jump.
2. The opcount increments per step.
3. Stack operations are bounded.

Preconditions 1 and 2 are properties of the opcode dispatch table (no `JMP`, no `CALL`). Precondition 3 is where cell alignment enters the proof.

### Why fixed-size cells matter to K5

A bounded-opcount theorem needs every opcode to consume bounded resources. The 2PDA opcodes that manipulate the stack — `PUSH`, `POP`, `DUP`, `SWAP`, and the Plexus opcodes in the 0xC0–0xCF range (`OP_CHECKCAPABILITY = 0xC3`, `OP_ASSERTLINEAR = 0xC5`, etc., per `core/cell-ops/dist/opcodes.d.ts`) — each handle exactly one cell per invocation.

If cells were variable-size, a single `PUSH` could consume an unbounded number of bytes (and an unbounded number of memory-copy cycles), and the opcount-to-wall-clock relationship would degrade from linear to "depends on the largest cell pushed". A 1024-byte fixed cell makes every cell-handling opcode cost O(1) in cells and O(1024) in bytes — both constants.

K5's strength as a guarantee — "you can compute the worst-case execution time before running the program" — depends on the cell being a fixed size. Variable-size cells would force the theorem to be stated as "terminates in at most `opcountLimit × maxCellSize` steps", which is much weaker.

### The aux stack's role

The auxiliary stack (256 cells, 256 KB total) carries continuation cells used during three-phase fail-fast verification. Per the structure of fact-checked claims in `docs/prd/UNIFICATION-ROADMAP.md` §11, the verification path pops continuation cells in reverse order: BUMP merkle proof (BRC-74) first, then Atomic BEEF ancestry (BRC-95) second, then the state envelope. Each verification phase is bounded because each continuation cell is bounded.

A 256-cell aux stack means: at most 256 layers of continuation. This is the "verification depth" budget. Three-phase verification fits comfortably within this budget; if a vertical ever proposes a verification scheme requiring deeper continuations, the aux stack size is the constraint to revisit.

---

## 34.7 The Full Alignment Table

| Layer | Unit | Cells per unit | Waste |
|---|---|---|---|
| Network (UDP, current 12 B adapter header) | 65,507 B datagram | 63 cells | 7 B free |
| Network (UDP, BRC-124 92 B header) | 65,507 B datagram | 63 cells | 887 B free |
| Disk (LMDB) | 4096 B page | 4 cells | 0 B |
| Runtime (WASM) | 65,536 B page | 64 cells | 0 B |
| Runtime (main stack) | 1,048,576 B | 1024 cells | 0 B |
| Runtime (aux stack) | 262,144 B | 256 cells | 0 B |
| Anchoring (SHA-256) | 1024 B input | 1 cell → 16 rounds | exact |

The 1024-byte cell is simultaneously a clean fragment of a UDP datagram, a clean quarter of an LMDB page, a clean 1/64th of a WASM page, a clean unit of stack allocation, and a clean input to SHA-256. No other power-of-two value between 512 and 4096 satisfies all five alignments without waste.

---

## 34.8 Why Not 512, Why Not 2048

### 512-byte cells

- **Header overhead**: 256 / 512 = **50%** — half the cell is metadata.
- **Disk**: 8 cells per 4 KB page (fine).
- **Network**: 127 cells per UDP datagram (denser but no real benefit; the bottleneck is the datagram count, not cells per datagram).
- **Runtime**: 1024 cells × 512 B = 512 KB main stack (smaller, fine).
- **K5**: still O(1) per opcode.
- **Verdict**: rejected — too much header overhead.

### 2048-byte cells

- **Header overhead**: 256 / 2048 = **12.5%** — better than 1024's 25%.
- **Disk**: 2 cells per 4 KB page (fine).
- **Network**: 31 cells per UDP datagram (worse density; halves throughput).
- **Runtime**: 1024 cells × 2048 B = 2 MB main stack (32 WASM pages — more memory per stack).
- **K5**: still O(1) per opcode, but the constant doubles.
- **Verdict**: rejected — network density too low for the memory cost.

### 1500-byte cells (Ethernet MTU)

- **Disk**: straddles LMDB pages (2.7 cells per 4 KB page) — bad.
- **Verdict**: rejected — disk alignment breaks.

### 1024-byte cells

- **Header overhead**: 25% — acceptable.
- **Disk**: 4 per page exactly.
- **Network**: 63 cells per UDP datagram.
- **Runtime**: 1 MB main stack = 16 WASM pages exactly.
- **K5**: O(1) per opcode with a small constant.
- **Verdict**: selected. Smallest size that satisfies all four alignments.

---

## 34.9 What This Means for Maintainers

The cell size is a load-bearing constant. Changing it would cascade through:

1. `core/constants/constants.json` and the generator output (`core/protocol-types/src/constants.ts`, `packages/cell-engine/src/constants.zig`).
2. The multicast adapter's `PayloadTooLargeError` boundary (chapter 17 §17.2.3).
3. The LMDB page-packing assumption in every `*_lmdb.zig` store.
4. WASM stack page accounting in `packages/cell-engine/`.
5. The K5 Lean proof, specifically `TerminationK5.lean`'s opcount-to-byte-cost translation.
6. Every conformance test pinned to `cellSize: 1024` (start with `core/constants/__tests__/constants.test.ts`).

The continuation-cell mechanism (`CONTINUATION_HEADER_SIZE = 8`, `CONTINUATION_PAYLOAD_SIZE = 1016`) exists precisely so that logical payloads larger than 768 bytes don't require enlarging `CELL_SIZE`. Continuations are the supported escape valve; resizing the cell is not.

If a future requirement seems to demand changing the cell size, examine whether continuations can solve the problem first. The over-determination of 1024 means any other size will degrade at least one of the five alignments above.

---

## 34.10 Sources Referenced

- `core/protocol-types/src/constants.ts` — canonical generated TypeScript constants
- `core/constants/__tests__/constants.test.ts` — pinning tests (D0.1)
- `core/constants/constants.json` — single source of truth (generator input)
- `packages/cell-engine/src/constants.zig` — generated Zig mirror
- `packages/cell-engine/src/pda.zig` — 2PDA stack implementation (K5 owner)
- `docs/FORMAL-VERIFICATION-STRATEGY.md` §K5 (line 26, lines 153-155)
- `proofs/lean/Semantos/TerminationK5.lean` — K5 Lean proof
- `docs/textbook/17-mesh-and-session-skeleton.md` §17.2 — multicast wire format
- `docs/prd/UNIFICATION-ROADMAP.md` §11.6 — BRC-124, BRC-26 binding recommendations
- `extensions/chain-broadcast/BeefStore` — BSV anchoring path
- `runtime/semantos-brain/src/*_lmdb.zig` — LMDB stores under K4 discipline

The constants are not arbitrary. They are simultaneously satisfying the protocol, the disk, the runtime, the proof, and the wire. Any change should explain which of those it's improving — and what it's giving up.
