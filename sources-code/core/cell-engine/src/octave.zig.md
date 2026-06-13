---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/octave.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.979821+00:00
---

# core/cell-engine/src/octave.zig

```zig
// Octave memory scaling — Phase 6
// Hierarchical cell addressing: 1KB → 1MB → 1GB → 1TB at factors of 1024.
// Reference: FORTH patterns (BYTES>CELLS, CHOOSE-STORAGE-STRATEGY, pool-per-linearity)
//
// Each octave has 1024 slots. A cell at octave N is 1024^(N+1) bytes.
//   Octave 0 (base):  1KB cells  × 1024 slots =   1MB address space
//   Octave 1 (kilo):  1MB cells  × 1024 slots =   1GB address space
//   Octave 2 (mega):  1GB cells  × 1024 slots =   1TB address space
//   Octave 3 (giga):  1TB cells  × 1024 slots =   1PB address space
//
// MFP cost scaling: 1000^octave sats per cell read.

const constants = @import("constants");

/// Octave levels in the hierarchical memory system.
pub const Octave = enum(u8) {
    base = 0, // 1KB cells (existing 2-PDA cells)
    kilo = 1, // 1MB cells (1024 × base cells)
    mega = 2, // 1GB cells (1024 × kilo cells)
    giga = 3, // 1TB cells (1024 × mega cells)
};

/// Maximum octave level supported.
pub const MAX_OCTAVE: u8 = 3;

/// Number of slots per octave level.
pub const SLOTS_PER_OCTAVE: u16 = 1024;

/// Hierarchical address for a cell in the octave memory system.
/// Primary addressing is by typeHash (CAS). This struct is the secondary
/// location-based addressing mode used by OP_DEREF_POINTER and host_fetch_cell.
pub const OctaveAddress = struct {
    octave: Octave,
    slot: u16, // 0..1023
    offset: u32, // byte offset within the cell (0 for full-cell access)

    /// Check if the address is valid (slot within bounds).
    pub fn isValid(self: OctaveAddress) bool {
        return self.slot < SLOTS_PER_OCTAVE;
    }
};

/// Slot lifecycle states, mirroring Forth POOL-FREE/ALLOCATED/CONSUMED.
/// Scaffolding for Phase 7 octave pool management — not used in Phase 6.
pub const SlotState = enum(u8) {
    free = 0,
    allocated = 1,
    consumed = 2,
};

/// Metadata for a single slot at any octave level.
/// Mirrors the Forth 8-byte block header concept, extended for octave use.
/// Scaffolding for Phase 7 octave pool management — not used in Phase 6.
pub const SlotMeta = struct {
    state: SlotState,
    linearity: u8, // 1=LINEAR, 2=AFFINE, 3=RELEVANT, 4=DEBUG
    content_hash: [32]u8, // SHA256 of cell content (for CAS lookup)
    type_hash: [32]u8, // semantic type hash
    actual_size: u32, // actual data bytes used (≤ cell size at this octave)
    ref_count: u16, // reference count for RELEVANT cells

    pub fn init() SlotMeta {
        return .{
            .state = .free,
            .linearity = 0,
            .content_hash = [_]u8{0} ** 32,
            .type_hash = [_]u8{0} ** 32,
            .actual_size = 0,
            .ref_count = 0,
        };
    }
};

/// Cell size in bytes at a given octave level.
/// Octave 0: 1024 (1KB), Octave 1: 1,048,576 (1MB), Octave 2: 1,073,741,824 (1GB).
/// Returns u64 to avoid overflow at higher octaves.
pub fn cellSizeForOctave(oct: Octave) u64 {
    const shift: u6 = @intCast(@as(u32, @intFromEnum(oct)) * 10);
    return @as(u64, constants.CELL_SIZE) << shift;
}

/// Total address space in bytes for an octave level (cell_size × 1024 slots).
pub fn addressSpaceForOctave(oct: Octave) u64 {
    return cellSizeForOctave(oct) * SLOTS_PER_OCTAVE;
}

/// Number of cells at a given octave needed to store `bytes` bytes.
/// Equivalent to Forth BYTES>CELLS: (bytes + cellSize - 1) / cellSize
pub fn bytesToCellsAtOctave(bytes: u64, oct: Octave) u64 {
    const cs = cellSizeForOctave(oct);
    return (bytes + cs - 1) / cs;
}

/// Determine the minimum octave level needed to store `bytes` in a single cell.
/// Returns null if the data exceeds even the largest octave.
/// Scaffolding for Phase 7 storeWithEscalation — not called in Phase 6.
pub fn minimumOctaveForSize(bytes: u64) ?Octave {
    if (bytes <= cellSizeForOctave(.base)) return .base;
    if (bytes <= cellSizeForOctave(.kilo)) return .kilo;
    if (bytes <= cellSizeForOctave(.mega)) return .mega;
    if (bytes <= cellSizeForOctave(.giga)) return .giga;
    return null;
}

/// MFP cost in satoshis for reading one cell at a given octave.
/// Cost = 1000^octave sats per cell read.
///   Octave 0: 1 sat
///   Octave 1: 1,000 sats
///   Octave 2: 1,000,000 sats
///   Octave 3: 1,000,000,000 sats
pub fn costSatsPerCell(oct: Octave) u64 {
    var cost: u64 = 1;
    var i: u8 = 0;
    while (i < @intFromEnum(oct)) : (i += 1) {
        cost *= 1000;
    }
    return cost;
}

```
