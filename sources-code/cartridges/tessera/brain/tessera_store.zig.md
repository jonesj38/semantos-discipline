---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tessera_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.635294+00:00
---

# cartridges/tessera/brain/tessera_store.zig

```zig
// tessera_store — the in-memory provenance state machine for the
// tessera care-chain cartridge's 13 action verbs.
//
// Reference:
//   docs/prd/TESSERA-CARTRIDGE.md §3 (verbs + cell graph)
//   docs/canon/commissions/wave-tessera.md §7 (V0.3 walker reg)
//   cartridges/tessera/brain/tessera_cells.zig (the kernel-validated
//     linearity classes this state machine respects at the domain layer)
//   cartridges/chess/brain/chess_game_store.zig (the pattern this
//     follows — StoreError vs ?Rejection, init/deinit/get + verb
//     methods, dup'd string keys, in-memory only / no anchoring)
//
// Status — V0.3 (pre-boot, no anchoring):
//
//   Models the grape→glass graph in memory: harvest → rack → blend →
//   bottle → assemble-case → transfer-custody → confirm-receipt, plus
//   care-events, tamper, scan, tasting-note. Mints/anchors NO cells
//   (the kernel linearity proof lives in tessera_cells.zig; on-chain
//   anchor/consume is Phase-2 / later V-rows). The store enforces the
//   domain-level shadow of each linearity class:
//     • LINEAR (barrel/bottle/case/pallet/shipment/tamper) — a record
//       is consumed exactly once; re-consume ⇒ Rejection.
//     • AFFINE (grape-lot/care-event) — draw at most the remaining
//       volume; a lot may be left partly unused.
//     • RELEVANT (scan-event) — created, never dropped (Care Score).
//     • DEBUG (tasting-note) — inert; never gates a transition.
//   Mutating verbs return `StoreError!?Rejection`: a StoreError is
//   OOM / malformed id; a non-null Rejection is a normal domain refusal
//   the walker renders as `{ok:false,reason:…}`. Greenfield §0.1: this
//   file lives under cartridges/tessera/, never brain-core.

const std = @import("std");

pub const StoreError = error{
    invalid_id,
    out_of_memory,
};

/// Why a verb was refused. Walkers turn these into `{ok:false,reason}`.
pub const Rejection = enum {
    lot_not_found,
    barrel_not_found,
    bottle_not_found,
    case_not_found,
    shipment_not_found,
    duplicate_id,
    already_consumed,
    insufficient_volume,
    empty_input,
    blend_not_conserved,
    already_tampered,
    bottle_tampered,
    no_pending_transfer,
    not_the_recipient,
    not_in_custody,
};

// ── Entity records ───────────────────────────────────────────────────

/// AFFINE origin. `remaining_ml` decreases as barrels are racked off;
/// may be left > 0 (affine drop allowed).
const GrapeLot = struct {
    id: []const u8,
    grower: []const u8,
    remaining_ml: u64,
};

/// LINEAR. `consumed` flips exactly once (into a blend or a bottling).
const Barrel = struct {
    id: []const u8,
    volume_ml: u64,
    consumed: bool = false,
};

/// LINEAR. `consumed` flips once (assembled into a case). `tampered`
/// is the one-shot intact→broken transition (tessera.tamper-event).
const Bottle = struct {
    id: []const u8,
    barrel_id: []const u8,
    consumed: bool = false,
    tampered: bool = false,
    scans: u32 = 0, // RELEVANT scan-event count (>=1 ⇒ Care Score renders)
    notes: u32 = 0, // DEBUG tasting-note count (inert)
};

/// LINEAR custody container (case/pallet/shipment share this shape).
/// `holder` is current custodian; `pending_to` is an open transfer
/// awaiting confirm-receipt (custody linearity: exactly one open
/// transfer, closed by exactly the named recipient).
const Container = struct {
    id: []const u8,
    kind: Kind,
    holder: []const u8,
    pending_to: ?[]const u8 = null,
    care_events: u32 = 0, // AFFINE care-event accumulation
    closed: bool = false, // shipment received

    const Kind = enum { case_, pallet, shipment };
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    lots: std.StringHashMap(GrapeLot),
    barrels: std.StringHashMap(Barrel),
    bottles: std.StringHashMap(Bottle),
    containers: std.StringHashMap(Container),
    /// P4b — per-cartridge domain-id → cell_id index, populated by
    /// walkers after a successful LINEAR mint via `recordCellId`. The
    /// in-memory FSM stays authoritative for domain invariants; this
    /// index is the cartridge-local map the consume helpers (P4c) will
    /// use to resolve a verb's predecessor domain id to the spent-set
    /// key the substrate expects. AFFINE event mints do not populate
    /// this map — only LINEAR successors get an entry.
    cell_id_by_domain_id: std.StringHashMap([32]u8),

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{
            .allocator = allocator,
            .lots = std.StringHashMap(GrapeLot).init(allocator),
            .barrels = std.StringHashMap(Barrel).init(allocator),
            .bottles = std.StringHashMap(Bottle).init(allocator),
            .containers = std.StringHashMap(Container).init(allocator),
            .cell_id_by_domain_id = std.StringHashMap([32]u8).init(allocator),
        };
    }

    pub fn deinit(self: *Store) void {
        freeMap(&self.lots, self.allocator, &.{ "id", "grower" });
        freeMap(&self.barrels, self.allocator, &.{"id"});
        freeMap(&self.bottles, self.allocator, &.{ "id", "barrel_id" });
        freeContainers(self);
        // P4b — keys are owned dupes; values are [32]u8 by-value (no free).
        var dit = self.cell_id_by_domain_id.iterator();
        while (dit.next()) |e| self.allocator.free(e.key_ptr.*);
        self.lots.deinit();
        self.barrels.deinit();
        self.bottles.deinit();
        self.containers.deinit();
        self.cell_id_by_domain_id.deinit();
    }

    /// P4b — record `(domain_id, cell_id)` for a successful LINEAR mint.
    /// Caller (walker) invokes this after `settleMinted{,Many}` succeeds.
    /// Idempotent for the same `(domain_id, cell_id)`; **overwrites** if
    /// the same `domain_id` was previously recorded with a different
    /// cell_id (caller's responsibility — FSM already prevents legitimate
    /// duplicate LINEAR creates via `duplicate_id` Rejection).
    pub fn recordCellId(self: *Store, domain_id: []const u8, cell_id: [32]u8) StoreError!void {
        if (domain_id.len == 0) return StoreError.invalid_id;
        // Reuse the existing key when present; only dup on first insert
        // (avoids leaking the previous key on overwrite).
        if (self.cell_id_by_domain_id.getEntry(domain_id)) |entry| {
            entry.value_ptr.* = cell_id;
            return;
        }
        const k = self.allocator.dupe(u8, domain_id) catch return StoreError.out_of_memory;
        errdefer self.allocator.free(k);
        self.cell_id_by_domain_id.put(k, cell_id) catch return StoreError.out_of_memory;
    }

    /// P4b — look up the cell_id minted for `domain_id`, if any.
    pub fn cellIdByDomainId(self: *Store, domain_id: []const u8) ?[32]u8 {
        return self.cell_id_by_domain_id.get(domain_id);
    }

    /// P4b — count entries in the domain-id → cell_id index (tests).
    pub fn domainIdIndexCount(self: *Store) usize {
        return self.cell_id_by_domain_id.count();
    }

    fn freeMap(map: anytype, a: std.mem.Allocator, comptime str_fields: []const []const u8) void {
        var it = map.iterator();
        while (it.next()) |e| {
            inline for (str_fields) |f| a.free(@field(e.value_ptr.*, f));
            a.free(e.key_ptr.*);
        }
    }

    fn freeContainers(self: *Store) void {
        var it = self.containers.iterator();
        while (it.next()) |e| {
            self.allocator.free(e.value_ptr.id);
            self.allocator.free(e.value_ptr.holder);
            if (e.value_ptr.pending_to) |p| self.allocator.free(p);
            self.allocator.free(e.key_ptr.*);
        }
    }

    fn dup(self: *Store, s: []const u8) StoreError![]const u8 {
        return self.allocator.dupe(u8, s) catch StoreError.out_of_memory;
    }

    pub fn lotCount(self: *Store) usize {
        return self.lots.count();
    }
    pub fn bottleCount(self: *Store) usize {
        return self.bottles.count();
    }
    pub fn getBottle(self: *Store, id: []const u8) ?Bottle {
        return self.bottles.get(id);
    }
    pub fn getContainer(self: *Store, id: []const u8) ?Container {
        return self.containers.get(id);
    }

    /// Return the substrate cell-name that matches this container's
    /// kind ("tessera.case" / "tessera.pallet" / "tessera.shipment"),
    /// or null if the container isn't known. Used by transfer-custody
    /// and confirm-receipt to re-mint the same container type at each
    /// custody transition (clean LINEAR chain — each new cell consumes
    /// the prior; the container's `id` is the constant domain_id, the
    /// `cell_id` advances per transition).
    pub fn getContainerCellName(self: *Store, id: []const u8) ?[]const u8 {
        const c = self.containers.get(id) orelse return null;
        return switch (c.kind) {
            .case_ => "tessera.case",
            .pallet => "tessera.pallet",
            .shipment => "tessera.shipment",
        };
    }

    // ── 1. harvest — create an AFFINE grape-lot ──────────────────────
    pub fn harvest(self: *Store, lot_id: []const u8, grower: []const u8, volume_ml: u64) StoreError!?Rejection {
        if (lot_id.len == 0 or grower.len == 0) return StoreError.invalid_id;
        if (self.lots.contains(lot_id)) return .duplicate_id;
        const k = try self.dup(lot_id);
        errdefer self.allocator.free(k);
        const idd = try self.dup(lot_id);
        errdefer self.allocator.free(idd);
        const gd = try self.dup(grower);
        self.lots.put(k, .{ .id = idd, .grower = gd, .remaining_ml = volume_ml }) catch return StoreError.out_of_memory;
        return null;
    }

    // ── 2. rack — draw an AFFINE volume off a lot into a LINEAR barrel ─
    pub fn rack(self: *Store, lot_id: []const u8, barrel_id: []const u8, volume_ml: u64) StoreError!?Rejection {
        if (lot_id.len == 0 or barrel_id.len == 0) return StoreError.invalid_id;
        const lot = self.lots.getPtr(lot_id) orelse return .lot_not_found;
        if (volume_ml == 0) return .insufficient_volume;
        if (volume_ml > lot.remaining_ml) return .insufficient_volume;
        if (self.barrels.contains(barrel_id)) return .duplicate_id;
        const k = try self.dup(barrel_id);
        errdefer self.allocator.free(k);
        const idd = try self.dup(barrel_id);
        self.barrels.put(k, .{ .id = idd, .volume_ml = volume_ml }) catch return StoreError.out_of_memory;
        lot.remaining_ml -= volume_ml; // AFFINE partial draw
        return null;
    }

    // ── 3. blend — consume N LINEAR barrels into 1, volume conserved ──
    //    (Lean: tessera.blend_conservation, V5.4 — sum(in) == out)
    pub fn blend(self: *Store, out_id: []const u8, in_ids: []const []const u8, declared_out_ml: u64) StoreError!?Rejection {
        if (out_id.len == 0) return StoreError.invalid_id;
        if (in_ids.len == 0) return .empty_input;
        if (self.barrels.contains(out_id)) return .duplicate_id;
        var sum: u64 = 0;
        for (in_ids) |bid| {
            const b = self.barrels.getPtr(bid) orelse return .barrel_not_found;
            if (b.consumed) return .already_consumed;
            sum += b.volume_ml;
        }
        if (sum != declared_out_ml) return .blend_not_conserved; // conservation
        for (in_ids) |bid| {
            self.barrels.getPtr(bid).?.consumed = true; // LINEAR consume
        }
        const k = try self.dup(out_id);
        errdefer self.allocator.free(k);
        const idd = try self.dup(out_id);
        self.barrels.put(k, .{ .id = idd, .volume_ml = declared_out_ml }) catch return StoreError.out_of_memory;
        return null;
    }

    // ── 4. bottle — consume 1 LINEAR barrel → N LINEAR bottles ────────
    pub fn bottle(self: *Store, barrel_id: []const u8, bottle_ids: []const []const u8) StoreError!?Rejection {
        if (bottle_ids.len == 0) return .empty_input;
        const b = self.barrels.getPtr(barrel_id) orelse return .barrel_not_found;
        if (b.consumed) return .already_consumed;
        for (bottle_ids) |bid| {
            if (bid.len == 0) return StoreError.invalid_id;
            if (self.bottles.contains(bid)) return .duplicate_id;
        }
        b.consumed = true; // LINEAR consume of the barrel
        for (bottle_ids) |bid| {
            const k = try self.dup(bid);
            const idd = try self.dup(bid);
            const brd = try self.dup(barrel_id);
            self.bottles.put(k, .{ .id = idd, .barrel_id = brd }) catch return StoreError.out_of_memory;
        }
        return null;
    }

    // ── 5. assemble-case — reference N LINEAR bottles into a case ─────
    pub fn assembleCase(self: *Store, case_id: []const u8, holder: []const u8, bottle_ids: []const []const u8) StoreError!?Rejection {
        if (case_id.len == 0 or holder.len == 0) return StoreError.invalid_id;
        if (bottle_ids.len == 0) return .empty_input;
        if (self.containers.contains(case_id)) return .duplicate_id;
        for (bottle_ids) |bid| {
            const bt = self.bottles.getPtr(bid) orelse return .bottle_not_found;
            if (bt.consumed) return .already_consumed; // LINEAR: a bottle is in one case only
            if (bt.tampered) return .bottle_tampered;
        }
        for (bottle_ids) |bid| self.bottles.getPtr(bid).?.consumed = true;
        return self.makeContainer(case_id, .case_, holder);
    }

    fn makeContainer(self: *Store, id: []const u8, kind: Container.Kind, holder: []const u8) StoreError!?Rejection {
        const k = try self.dup(id);
        errdefer self.allocator.free(k);
        const idd = try self.dup(id);
        errdefer self.allocator.free(idd);
        const hd = try self.dup(holder);
        self.containers.put(k, .{ .id = idd, .kind = kind, .holder = hd }) catch return StoreError.out_of_memory;
        return null;
    }

    /// Create a pallet/shipment custody container directly (the spine
    /// also lets a case act as the transfer unit).
    pub fn openContainer(self: *Store, id: []const u8, kind_s: []const u8, holder: []const u8) StoreError!?Rejection {
        if (id.len == 0 or holder.len == 0) return StoreError.invalid_id;
        if (self.containers.contains(id)) return .duplicate_id;
        const kind: Container.Kind = if (std.mem.eql(u8, kind_s, "pallet")) .pallet else if (std.mem.eql(u8, kind_s, "shipment")) .shipment else .case_;
        return self.makeContainer(id, kind, holder);
    }

    // ── 6. transfer-custody — open a LINEAR custody transfer ──────────
    pub fn transferCustody(self: *Store, id: []const u8, from: []const u8, to: []const u8) StoreError!?Rejection {
        if (to.len == 0) return StoreError.invalid_id;
        const c = self.containers.getPtr(id) orelse return .shipment_not_found;
        if (c.closed) return .already_consumed;
        if (!std.mem.eql(u8, c.holder, from)) return .not_in_custody;
        if (c.pending_to != null) return .already_consumed; // one open transfer
        c.pending_to = try self.dup(to);
        return null;
    }

    // ── 11. confirm-receipt — close the transfer (exactly recipient) ──
    pub fn confirmReceipt(self: *Store, id: []const u8, who: []const u8) StoreError!?Rejection {
        const c = self.containers.getPtr(id) orelse return .shipment_not_found;
        const pend = c.pending_to orelse return .no_pending_transfer;
        if (!std.mem.eql(u8, pend, who)) return .not_the_recipient;
        self.allocator.free(c.holder);
        c.holder = try self.dup(who);
        self.allocator.free(pend);
        c.pending_to = null;
        if (c.kind == .shipment) c.closed = true;
        return null;
    }

    // ── 7/12/13. care-event family — AFFINE accumulation ─────────────
    pub fn recordCareEvent(self: *Store, container_id: []const u8) StoreError!?Rejection {
        const c = self.containers.getPtr(container_id) orelse return .shipment_not_found;
        c.care_events += 1; // AFFINE: accumulate; drop allowed (may stay 0)
        return null;
    }

    // ── 8. tamper — one-shot LINEAR intact→broken ────────────────────
    //    (Lean: tessera.tamper_one_shot, V5.2)
    pub fn tamper(self: *Store, bottle_id: []const u8) StoreError!?Rejection {
        const bt = self.bottles.getPtr(bottle_id) orelse return .bottle_not_found;
        if (bt.tampered) return .already_tampered; // one-shot
        bt.tampered = true;
        return null;
    }

    // ── 9. consumer-scan — RELEVANT evidence (must exist for Score) ───
    pub fn consumerScan(self: *Store, bottle_id: []const u8) StoreError!?Rejection {
        const bt = self.bottles.getPtr(bottle_id) orelse return .bottle_not_found;
        bt.scans += 1;
        return null;
    }

    // ── 10. add-tasting-note — DEBUG, inert (never gates anything) ────
    pub fn addTastingNote(self: *Store, bottle_id: []const u8) StoreError!?Rejection {
        const bt = self.bottles.getPtr(bottle_id) orelse return .bottle_not_found;
        bt.notes += 1;
        return null;
    }
};

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

test "spine: harvest → rack → bottle → assemble-case → transfer → confirm" {
    var s = Store.init(testing.allocator);
    defer s.deinit();
    try testing.expectEqual(@as(?Rejection, null), try s.harvest("lot1", "alice", 1000));
    try testing.expectEqual(@as(?Rejection, null), try s.rack("lot1", "bar1", 600));
    const bids = [_][]const u8{ "b1", "b2", "b3" };
    try testing.expectEqual(@as(?Rejection, null), try s.bottle("bar1", &bids));
    try testing.expectEqual(@as(usize, 3), s.bottleCount());
    const cids = [_][]const u8{ "b1", "b2" };
    try testing.expectEqual(@as(?Rejection, null), try s.assembleCase("case1", "alice", &cids));
    try testing.expectEqual(@as(?Rejection, null), try s.transferCustody("case1", "alice", "bob"));
    try testing.expectEqual(@as(?Rejection, null), try s.confirmReceipt("case1", "bob"));
    try testing.expectEqualStrings("bob", s.getContainer("case1").?.holder);
}

test "AFFINE lot: partial draw ok, over-draw refused, remainder may be left" {
    var s = Store.init(testing.allocator);
    defer s.deinit();
    _ = try s.harvest("lot", "g", 1000);
    try testing.expectEqual(@as(?Rejection, null), try s.rack("lot", "x", 400));
    try testing.expectEqual(Rejection.insufficient_volume, (try s.rack("lot", "y", 700)).?);
    try testing.expectEqual(@as(?Rejection, null), try s.rack("lot", "z", 600));
    // 0 ml left, lot still present (affine: remainder-left is fine, here 0).
}

test "blend conservation (Lean V5.4): sum(in) must equal declared out" {
    var s = Store.init(testing.allocator);
    defer s.deinit();
    _ = try s.harvest("lot", "g", 1000);
    _ = try s.rack("lot", "a", 300);
    _ = try s.rack("lot", "b", 500);
    const in = [_][]const u8{ "a", "b" };
    try testing.expectEqual(Rejection.blend_not_conserved, (try s.blend("out", &in, 900)).?);
    try testing.expectEqual(@as(?Rejection, null), try s.blend("out", &in, 800));
    // inputs are LINEAR-consumed; re-blending them is refused.
    const in2 = [_][]const u8{"a"};
    try testing.expectEqual(Rejection.already_consumed, (try s.blend("out2", &in2, 300)).?);
}

test "LINEAR bottle: consumed into exactly one case (no double-spend)" {
    var s = Store.init(testing.allocator);
    defer s.deinit();
    _ = try s.harvest("lot", "g", 1000);
    _ = try s.rack("lot", "bar", 500);
    const bids = [_][]const u8{ "b1", "b2" };
    _ = try s.bottle("bar", &bids);
    const c1 = [_][]const u8{"b1"};
    try testing.expectEqual(@as(?Rejection, null), try s.assembleCase("c1", "a", &c1));
    // b1 already consumed into c1 — cannot go into a second case.
    const c2 = [_][]const u8{"b1"};
    try testing.expectEqual(Rejection.already_consumed, (try s.assembleCase("c2", "a", &c2)).?);
}

test "tamper one-shot (Lean V5.2): second tamper refused" {
    var s = Store.init(testing.allocator);
    defer s.deinit();
    _ = try s.harvest("lot", "g", 100);
    _ = try s.rack("lot", "bar", 100);
    const bids = [_][]const u8{"b1"};
    _ = try s.bottle("bar", &bids);
    try testing.expectEqual(@as(?Rejection, null), try s.tamper("b1"));
    try testing.expectEqual(Rejection.already_tampered, (try s.tamper("b1")).?);
    try testing.expect(s.getBottle("b1").?.tampered);
}

test "custody linearity: confirm requires a pending transfer to exactly the recipient" {
    var s = Store.init(testing.allocator);
    defer s.deinit();
    _ = try s.openContainer("ship1", "shipment", "alice");
    try testing.expectEqual(Rejection.no_pending_transfer, (try s.confirmReceipt("ship1", "bob")).?);
    try testing.expectEqual(@as(?Rejection, null), try s.transferCustody("ship1", "alice", "bob"));
    try testing.expectEqual(Rejection.not_the_recipient, (try s.confirmReceipt("ship1", "carol")).?);
    try testing.expectEqual(@as(?Rejection, null), try s.confirmReceipt("ship1", "bob"));
    try testing.expect(s.getContainer("ship1").?.closed);
}

test "care-event AFFINE accumulation; scan RELEVANT presence; note DEBUG inert" {
    var s = Store.init(testing.allocator);
    defer s.deinit();
    _ = try s.harvest("lot", "g", 100);
    _ = try s.rack("lot", "bar", 100);
    const bids = [_][]const u8{"b1"};
    _ = try s.bottle("bar", &bids);
    _ = try s.openContainer("sh", "shipment", "dock");
    _ = try s.recordCareEvent("sh");
    _ = try s.recordCareEvent("sh");
    try testing.expectEqual(@as(u32, 2), s.getContainer("sh").?.care_events);
    try testing.expectEqual(@as(?Rejection, null), try s.consumerScan("b1"));
    try testing.expect(s.getBottle("b1").?.scans >= 1); // Care Score can render
    _ = try s.addTastingNote("b1");
    // DEBUG note never gates: bottle still scannable/assemblable.
    try testing.expectEqual(@as(?Rejection, null), try s.consumerScan("b1"));
}

test "not-found rejections, not store errors" {
    var s = Store.init(testing.allocator);
    defer s.deinit();
    try testing.expectEqual(Rejection.lot_not_found, (try s.rack("nope", "b", 1)).?);
    try testing.expectEqual(Rejection.bottle_not_found, (try s.tamper("ghost")).?);
    try testing.expectEqual(Rejection.shipment_not_found, (try s.confirmReceipt("ghost", "x")).?);
}

```
