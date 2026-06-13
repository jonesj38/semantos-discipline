---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Cell.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.357519+00:00
---

# proofs/lean/Semantos/Cell.lean

```lean
-- Semantos Plane — Cell Structure Model
--
-- Models the 1024-byte semantic cell with its 256-byte header.
-- Header layout matches packages/cell-engine/src/cell.zig and
-- packages/cell-engine/src/constants.zig exactly.
--
-- We model the semantic structure (typed fields), not raw bytes.
-- Byte offsets are documented in comments for fidelity tracking.

namespace Semantos

-- Forward declaration of Linearity (defined in Linearity.lean)
inductive Linearity where
  | linear    -- 1: Must be consumed exactly once (no DUP, no DROP)
  | affine    -- 2: Can be consumed at most once (no DUP, DROP allowed)
  | relevant  -- 3: Must be consumed at least once (DUP allowed, no DROP)
  | debug     -- 4: Unrestricted — development only
  deriving Repr, DecidableEq, BEq

-- Magic bytes: 0xDEADBEEF 0xCAFEBABE 0x13371337 0x42424242
-- Offset 0, size 16 bytes (constants.zig: HEADER_OFFSET_MAGIC=0, HEADER_SIZE_MAGIC=16)

/-- 256-byte cell header. Field offsets match constants.zig exactly.
    See packages/cell-engine/src/cell.zig:19 (CellHeader struct). -/
structure CellHeader where
  -- Offset 0, 16 bytes: magic bytes (HEADER_OFFSET_MAGIC=0)
  -- Not modeled as a field — always DEADBEEF CAFEBABE 13371337 42424242
  -- Offset 16, 4 bytes LE: linearity class (HEADER_OFFSET_LINEARITY=16)
  linearity : Linearity
  -- Offset 20, 4 bytes LE: protocol version (HEADER_OFFSET_VERSION=20)
  version : UInt32
  -- Offset 24, 4 bytes LE: domain flag (HEADER_OFFSET_FLAGS=24)
  domainFlag : UInt32
  -- Offset 28, 2 bytes LE: reference count (HEADER_OFFSET_REF_COUNT=28)
  refCount : UInt16
  -- Offset 30, 32 bytes: type hash (HEADER_OFFSET_TYPE_HASH=30)
  typeHash : Fin (2^256)
  -- Offset 62, 16 bytes: owner ID (HEADER_OFFSET_OWNER_ID=62)
  ownerId : Fin (2^128)
  -- Offset 78, 8 bytes LE: timestamp (HEADER_OFFSET_TIMESTAMP=78)
  timestamp : UInt64
  -- Offset 86, 4 bytes LE: cell count (HEADER_OFFSET_CELL_COUNT=86)
  cellCount : UInt32
  -- Offset 90, 4 bytes LE: payload total (HEADER_OFFSET_PAYLOAD_TOTAL=90)
  payloadTotal : UInt32
  -- Offset 94: commerce phase (1 byte)
  -- Offset 95: dimension (1 byte)
  -- Offset 96-127: parent hash (32 bytes)
  -- Offset 128-159: prev state hash (32 bytes)
  -- Offset 160-255: binding + padding (96 bytes)
  -- These are in the reserved block and not relevant to K1-K5/K7 proofs
  deriving Repr, DecidableEq, BEq

/-- Capability type — first byte of payload (offset 256).
    See linearity.zig:98 (getCapabilityType). -/
inductive CapabilityType where
  | recovery          -- 0
  | permission        -- 1
  | dataAccess        -- 2
  | computeDelegation -- 3
  | meteredAccess     -- 4
  | transfer          -- 5
  deriving Repr, DecidableEq, BEq

/-- A semantic cell: header + payload abstraction.
    Total size: 1024 bytes (CELL_SIZE from constants.zig:5).
    Header: 256 bytes (HEADER_SIZE from constants.zig:8).
    Payload: 768 bytes (PAYLOAD_SIZE from constants.zig:9). -/
structure Cell where
  header : CellHeader
  -- Payload is abstracted — we model only the capability type
  -- (first byte of payload) when needed for K2 proofs.
  capabilityType : Option CapabilityType
  deriving Repr, DecidableEq, BEq

-- Protocol constants matching constants.zig
def cellSize : Nat := 1024
def headerSize : Nat := 256
def payloadSize : Nat := 768

-- Header offset constants matching constants.zig
def headerOffsetMagic : Nat := 0
def headerOffsetLinearity : Nat := 16
def headerOffsetVersion : Nat := 20
def headerOffsetFlags : Nat := 24
def headerOffsetRefCount : Nat := 28
def headerOffsetTypeHash : Nat := 30
def headerOffsetOwnerId : Nat := 62
def headerOffsetTimestamp : Nat := 78
def headerOffsetCellCount : Nat := 86
def headerOffsetPayloadTotal : Nat := 90

end Semantos

```
