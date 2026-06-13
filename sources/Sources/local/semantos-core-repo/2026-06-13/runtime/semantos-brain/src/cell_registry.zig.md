---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cell_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.230826+00:00
---

# runtime/semantos-brain/src/cell_registry.zig

```zig
// M4.6 — CellRegistry: in-memory CAS+location dual addressing (D6.6).
//
// Maps type_hash ([32]u8) ↔ OctaveAddress bidirectionally.
// Both directions must return consistent results (same cell).
//
// Thread-safety: single-threaded (brain is single-threaded per Zig async model).
// No heap allocation on lookup paths — only register/unregister touch the maps.
//
// by_location key packs octave (u8) and slot (u16) into a u32:
//   (@as(u32, @intFromEnum(addr.octave)) << 16) | addr.slot
// The offset field is NOT part of the location key.

const std = @import("std");
const octave = @import("octave");
const OctaveAddress = octave.OctaveAddress;

pub const RegistryError = error{
    /// Same type_hash registered at a different OctaveAddress.
    HashCollision,
    /// Same OctaveAddress slot already occupied by a different type_hash.
    SlotConflict,
};

pub const CellRegistry = struct {
    allocator: std.mem.Allocator,

    /// Primary index: type_hash → OctaveAddress
    by_hash: std.AutoHashMap([32]u8, OctaveAddress),

    /// Reverse index: packed (octave u8 << 16 | slot u16) → type_hash
    by_location: std.AutoHashMap(u32, [32]u8),

    pub fn init(allocator: std.mem.Allocator) CellRegistry {
        return .{
            .allocator = allocator,
            .by_hash = std.AutoHashMap([32]u8, OctaveAddress).init(allocator),
            .by_location = std.AutoHashMap(u32, [32]u8).init(allocator),
        };
    }

    pub fn deinit(self: *CellRegistry) void {
        self.by_hash.deinit();
        self.by_location.deinit();
    }

    /// Pack octave and slot into a u32 location key (offset excluded).
    fn locationKey(addr: OctaveAddress) u32 {
        return (@as(u32, @intFromEnum(addr.octave)) << 16) | addr.slot;
    }

    /// Register a cell at the given location with the given type_hash.
    ///
    /// - If type_hash already registered at a different location → error.HashCollision
    /// - If location already occupied by a different hash → error.SlotConflict
    /// - Idempotent if the same (hash, location) pair is registered twice.
    pub fn register(self: *CellRegistry, type_hash: *const [32]u8, addr: OctaveAddress) !void {
        const loc_key = locationKey(addr);

        // Check existing hash entry.
        if (self.by_hash.get(type_hash.*)) |existing_addr| {
            if (existing_addr.octave == addr.octave and existing_addr.slot == addr.slot) {
                // Idempotent: same (hash, location) — no-op.
                return;
            }
            // Same hash, different location.
            return RegistryError.HashCollision;
        }

        // Check existing location entry.
        if (self.by_location.get(loc_key)) |existing_hash| {
            if (std.mem.eql(u8, &existing_hash, type_hash)) {
                // Idempotent: same (hash, location) — no-op (defensive, shouldn't reach here
                // since by_hash check above would have caught it).
                return;
            }
            // Same location, different hash.
            return RegistryError.SlotConflict;
        }

        // Insert into both indexes.
        try self.by_hash.put(type_hash.*, addr);
        try self.by_location.put(loc_key, type_hash.*);
    }

    /// Look up an OctaveAddress by typeHash. Returns null if not registered.
    pub fn lookupByHash(self: *const CellRegistry, type_hash: *const [32]u8) ?OctaveAddress {
        return self.by_hash.get(type_hash.*);
    }

    /// Look up a typeHash by OctaveAddress. Returns null if not registered.
    pub fn lookupByLocation(self: *const CellRegistry, addr: OctaveAddress) ?[32]u8 {
        return self.by_location.get(locationKey(addr));
    }

    /// Unregister a cell (removes both index entries). Returns true if found.
    pub fn unregister(self: *CellRegistry, type_hash: *const [32]u8) bool {
        const addr = self.by_hash.get(type_hash.*) orelse return false;
        _ = self.by_hash.remove(type_hash.*);
        _ = self.by_location.remove(locationKey(addr));
        return true;
    }

    /// Number of registered cells.
    pub fn count(self: *const CellRegistry) usize {
        return self.by_hash.count();
    }
};

```
