---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tessera_walkers.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.634602+00:00
---

# cartridges/tessera/brain/tessera_walkers.zig

```zig
// tessera_walkers — the brain-side write-seam handlers for the tessera
// care-chain cartridge's 13 action verbs.
//
// Reference:
//   docs/prd/TESSERA-CARTRIDGE.md §3 (the 13 verbs)
//   docs/canon/commissions/wave-tessera.md §7 (V0.3 walker reg)
//   runtime/semantos-brain/src/verb_dispatcher.zig (the WalkerFn contract)
//   cartridges/tessera/brain/tessera_store.zig (the typed provenance
//     state machine these drive)
//   cartridges/chess/brain/chess_walkers.zig (the pattern this follows
//     verbatim — parse JSON params, mutate the typed store, return a
//     typed JSON body; registerAll wires every verb at brain boot)
//
// Status — V0.3 (pre-boot, no anchoring):
//
//   The 13 verbs parse their JSON params and drive tessera_store — the
//   in-memory provenance state machine. NO cells are minted/anchored
//   (kernel linearity proof is tessera_cells.zig; on-chain is later).
//   Domain refusals (lot not found, blend not conserved, already
//   tampered, …) return a 200 body `{ok:false,reason:…}` — normal
//   care-chain flow, not an RPC fault. Only malformed params map to
//   DispatchError.invalid_params; OOM → out_of_memory.
//
//   Module wiring (build.zig root_source_file + inline test +
//   substrate_test_step) is done. Boot-time registerAll + Store
//   construction threaded into serve/cmdServe + wss_wallet.Backend is
//   the SHARED-BOOT-PATH step deferred for user review — exactly the
//   line chess stopped at (CHESS-DOUBLING-CUBE-TRACKING.md §1).
//   Greenfield §0.1: this file lives under cartridges/tessera/.

const std = @import("std");
const verb_dispatcher = @import("verb_dispatcher");
const store_mod = @import("tessera_store");
// P3c — real substrate cell minting (encode half; store-independent).
const tessera_mint = @import("tessera_mint");
// P3d — substrate entity CellStore interface (late-bound at boot;
// null in tests/dry-run, exactly like entity_encode_walker).
const cell_store = @import("cell_store");

pub const Store = store_mod.Store;

/// Shared walker state. serve/cmdServe constructs the store at boot and
/// passes &State here, exactly as chess passes its State (the deferred
/// shared-boot-path step).
pub const State = struct {
    store: *Store,
    /// P3d — entity CellStore, late-bound by cartridge_boot.bindCellStore
    /// from serve.zig's --enable-repl block. Null in tests / when the
    /// store isn't up: minting still returns a cell_id (persisted:false),
    /// exactly as entity_encode_walker behaves with a null store.
    cell_store: ?*const cell_store.CellStore = null,
};

// ─── JSON helpers (mirror chess_walkers.zig) ─────────────────────────

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    try out.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            else => try out.append(allocator, c),
        }
    }
    try out.append(allocator, '"');
}

fn reqStr(obj: std.json.ObjectMap, key: []const u8) verb_dispatcher.DispatchError![]const u8 {
    const v = obj.get(key) orelse return verb_dispatcher.DispatchError.invalid_params;
    if (v != .string or v.string.len == 0) return verb_dispatcher.DispatchError.invalid_params;
    return v.string;
}

fn reqU64(obj: std.json.ObjectMap, key: []const u8) verb_dispatcher.DispatchError!u64 {
    const v = obj.get(key) orelse return verb_dispatcher.DispatchError.invalid_params;
    if (v != .integer or v.integer < 0) return verb_dispatcher.DispatchError.invalid_params;
    return @intCast(v.integer);
}

/// Parse a JSON string array into a transient []const []const u8. The
/// element slices point into `parsed` (alive for the walker call); the
/// store dups whatever it retains, so transient lifetime is correct.
fn reqStrArray(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
    key: []const u8,
) verb_dispatcher.DispatchError![]const []const u8 {
    const v = obj.get(key) orelse return verb_dispatcher.DispatchError.invalid_params;
    if (v != .array or v.array.items.len == 0) return verb_dispatcher.DispatchError.invalid_params;
    var list = allocator.alloc([]const u8, v.array.items.len) catch return verb_dispatcher.DispatchError.out_of_memory;
    for (v.array.items, 0..) |item, i| {
        if (item != .string or item.string.len == 0) {
            allocator.free(list);
            return verb_dispatcher.DispatchError.invalid_params;
        }
        list[i] = item.string;
    }
    return list;
}

fn parseObj(allocator: std.mem.Allocator, params_json: []const u8) verb_dispatcher.DispatchError!std.json.Parsed(std.json.Value) {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch {
        return verb_dispatcher.DispatchError.invalid_params;
    };
    if (parsed.value != .object) {
        parsed.deinit();
        return verb_dispatcher.DispatchError.invalid_params;
    }
    return parsed;
}

fn rejectionBody(allocator: std.mem.Allocator, reason: []const u8) verb_dispatcher.DispatchError![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"ok\":false,\"reason\":\"{s}\"}}", .{reason}) catch
        verb_dispatcher.DispatchError.out_of_memory;
}

fn mapStoreErr(e: store_mod.StoreError) verb_dispatcher.DispatchError {
    return switch (e) {
        store_mod.StoreError.invalid_id => verb_dispatcher.DispatchError.invalid_params,
        store_mod.StoreError.out_of_memory => verb_dispatcher.DispatchError.out_of_memory,
    };
}

/// Resolve a `StoreError!?Rejection` into the verb's JSON body: a
/// non-null Rejection → {ok:false,reason}; null → {ok:true,...echo}.
fn settle(
    allocator: std.mem.Allocator,
    res: store_mod.StoreError!?store_mod.Rejection,
    ok_body: []const u8,
) verb_dispatcher.DispatchError![]u8 {
    const rej = res catch |e| return mapStoreErr(e);
    if (rej) |r| return rejectionBody(allocator, @tagName(r));
    return allocator.dupe(u8, ok_body) catch verb_dispatcher.DispatchError.out_of_memory;
}

fn okId(allocator: std.mem.Allocator, id: []const u8) verb_dispatcher.DispatchError![]u8 {
    var b: std.ArrayList(u8) = .{};
    errdefer b.deinit(allocator);
    b.appendSlice(allocator, "{\"ok\":true,\"id\":") catch return verb_dispatcher.DispatchError.out_of_memory;
    appendJsonString(allocator, &b, id) catch return verb_dispatcher.DispatchError.out_of_memory;
    b.append(allocator, '}') catch return verb_dispatcher.DispatchError.out_of_memory;
    return b.toOwnedSlice(allocator) catch verb_dispatcher.DispatchError.out_of_memory;
}

/// P3f — settle a store transition AND mint the cell it produces.
/// Generalises harvest's proven mint path so every single-cell-mint
/// verb shares ONE tested code path: store error/rejection → same as
/// `settle`; success → encode `cell_name` (owner from optional
/// ownerIdHex, P3e), persist when the CellStore is bound (P3d), return
/// {ok,id,cellId,persisted}. The in-memory store transition stays
/// authoritative; the mint is additive.
///
/// P4c — when `predecessors` is non-null, the helper also performs the
/// host-side K1 consume protocol against the substrate spent-set
/// (#474). Order is: settle → resolve predecessors via the cartridge
/// domain-id index (#476) → spent-check each (when CellStore is bound)
/// → mint successor(s) → persist → record successor → spend each
/// predecessor. Spend is last because the successor cell IS the proof
/// of consumption: if put fails we have not committed; if put succeeds
/// we must spend, because the successor now exists. Mid-flight
/// rejections (`unknown_predecessor` / `cell_already_consumed`) surface
/// as the usual `{ok:false,reason}` body — they are domain refusals,
/// not dispatch errors. CellStore-unbound (tests / dry-run) skips both
/// is_spent and spend: the helper degrades to "resolve-only", FSM stays
/// authoritative — same null-resilience the entity-encode walker has.
///
/// `settleMintedConsumes*` from the design doc collapse to one
/// optional parameter on each existing helper; the walker-side
/// retrofit is mechanical.
///
/// P-boot-rebuild — when `record_domain_id[s]` is non-null, the helper
/// wraps the cell payload to include a canonical `domainId` field as
/// the first key. This makes the cell self-describing at the substrate
/// layer: at fresh boot, cartridge_boot can scan CellStore for
/// tessera-tagged cells and replay (`domainId → cell_id`) into the
/// per-cartridge index — closing the "unknown_predecessor at fresh
/// boot" window the consume helpers (P4c) would otherwise hit.
/// AFFINE mints (record_domain_id = null) keep the raw verb-input
/// payload unchanged.

/// Wrap a JSON-object payload with a leading `"domainId":"<id>"` key,
/// and (P4d) — when `consumed_cell_ids.len > 0` — a
/// `"consumedCellIds":["hex",…]` array immediately after. Preserves all
/// existing keys; produces a single valid JSON object. Empty
/// `consumed_cell_ids` omits the audit field entirely so genesis verbs
/// (harvest / open-container) keep a clean payload.
fn payloadWithDomainId(
    a: std.mem.Allocator,
    pj: []const u8,
    domain_id: []const u8,
    consumed_cell_ids: []const [32]u8,
) verb_dispatcher.DispatchError![]u8 {
    var b: std.ArrayList(u8) = .{};
    errdefer b.deinit(a);
    b.append(a, '{') catch return verb_dispatcher.DispatchError.out_of_memory;
    appendJsonString(a, &b, "domainId") catch return verb_dispatcher.DispatchError.out_of_memory;
    b.append(a, ':') catch return verb_dispatcher.DispatchError.out_of_memory;
    appendJsonString(a, &b, domain_id) catch return verb_dispatcher.DispatchError.out_of_memory;
    if (consumed_cell_ids.len > 0) {
        b.append(a, ',') catch return verb_dispatcher.DispatchError.out_of_memory;
        appendJsonString(a, &b, "consumedCellIds") catch return verb_dispatcher.DispatchError.out_of_memory;
        b.appendSlice(a, ":[") catch return verb_dispatcher.DispatchError.out_of_memory;
        for (consumed_cell_ids, 0..) |cid, i| {
            if (i > 0) b.append(a, ',') catch return verb_dispatcher.DispatchError.out_of_memory;
            b.append(a, '"') catch return verb_dispatcher.DispatchError.out_of_memory;
            try appendHex(a, &b, &cid);
            b.append(a, '"') catch return verb_dispatcher.DispatchError.out_of_memory;
        }
        b.append(a, ']') catch return verb_dispatcher.DispatchError.out_of_memory;
    }
    // Advance past pj's opening '{' and any whitespace; if the inner
    // object is empty, close ours — otherwise append a comma + the
    // remainder (which carries the original keys and the closing '}').
    var i: usize = 0;
    while (i < pj.len and (pj[i] == ' ' or pj[i] == '\t' or pj[i] == '\n' or pj[i] == '\r')) : (i += 1) {}
    if (i < pj.len and pj[i] == '{') i += 1;
    var j: usize = i;
    while (j < pj.len and (pj[j] == ' ' or pj[j] == '\t' or pj[j] == '\n' or pj[j] == '\r')) : (j += 1) {}
    if (j < pj.len and pj[j] != '}') {
        b.append(a, ',') catch return verb_dispatcher.DispatchError.out_of_memory;
        b.appendSlice(a, pj[j..]) catch return verb_dispatcher.DispatchError.out_of_memory;
    } else {
        b.append(a, '}') catch return verb_dispatcher.DispatchError.out_of_memory;
    }
    return b.toOwnedSlice(a) catch verb_dispatcher.DispatchError.out_of_memory;
}

fn settleMintedMany(
    a: std.mem.Allocator,
    s: *State,
    res: store_mod.StoreError!?store_mod.Rejection,
    id_for_body: []const u8,
    cell_name: []const u8,
    payloads: []const []const u8,
    obj: std.json.ObjectMap,
    /// P4b — when non-null, record (record_domain_ids[i], cell_id[i]) in
    /// the per-cartridge domain-id → cell_id index. Length must match
    /// payloads.len. Null = no recording (AFFINE event mints, where the
    /// "id" is the parent container, not a new lookupable entity).
    record_domain_ids: ?[]const []const u8,
    /// P4c — when non-null, predecessor domain ids to resolve via the
    /// per-cartridge index (#476) and consume against the substrate
    /// spent-set (#474). Null = no consume (genesis verbs / AFFINE
    /// events). See the helper doc above for ordering + rejections.
    predecessors: ?[]const []const u8,
) verb_dispatcher.DispatchError![]u8 {
    const rej = res catch |e| return mapStoreErr(e);
    if (rej) |r| return rejectionBody(a, @tagName(r));
    if (record_domain_ids) |ids| std.debug.assert(ids.len == payloads.len);

    // P4c — predecessor resolve + spent-check (BEFORE mint).
    var pred_ids: ?[][32]u8 = null;
    defer if (pred_ids) |b| a.free(b);
    if (predecessors) |preds| {
        const buf = a.alloc([32]u8, preds.len) catch return verb_dispatcher.DispatchError.out_of_memory;
        errdefer a.free(buf);
        for (preds, 0..) |did, i| {
            const cid = s.store.cellIdByDomainId(did) orelse {
                a.free(buf);
                return rejectionBody(a, "unknown_predecessor");
            };
            buf[i] = cid;
        }
        if (s.cell_store) |cs| {
            for (buf) |cid| {
                if (cs.isSpent(&cid)) {
                    a.free(buf);
                    return rejectionBody(a, "cell_already_consumed");
                }
            }
        }
        pred_ids = buf;
    }

    const owner_id = try ownerIdFromParams(obj);

    // P4d — predecessor cell_ids for the on-cell audit trail. Shared
    // across all successors in this verb's batch (e.g. bottle's N
    // bottles all carry their source barrel's cell_id). Empty slice
    // when there are no predecessors (genesis verbs / AFFINE).
    const consumed_for_audit: []const [32]u8 = if (pred_ids) |b| b else &.{};

    var cell_ids = a.alloc([32]u8, payloads.len) catch return verb_dispatcher.DispatchError.out_of_memory;
    defer a.free(cell_ids);
    var persisted = false;
    for (payloads, 0..) |item_pj, i| {
        // P-boot-rebuild — wrap the per-item payload with `domainId`;
        // P4d — also include `consumedCellIds` when non-empty. Free at
        // end of iteration (each loop iteration is its own scope).
        var maybe_wrapped: ?[]u8 = null;
        defer if (maybe_wrapped) |w| a.free(w);
        const payload_to_encode: []const u8 = if (record_domain_ids) |ids| blk: {
            maybe_wrapped = try payloadWithDomainId(a, item_pj, ids[i], consumed_for_audit);
            break :blk maybe_wrapped.?;
        } else item_pj;
        const enc = tessera_mint.encodeCellByName(cell_name, owner_id, payload_to_encode, null) catch
            return verb_dispatcher.DispatchError.invalid_params;
        cell_ids[i] = enc.cell_id;
        if (s.cell_store) |store| {
            _ = store.put(&enc.cell) catch return verb_dispatcher.DispatchError.walker_failed;
            persisted = true;
        }
        if (record_domain_ids) |ids| {
            s.store.recordCellId(ids[i], enc.cell_id) catch return verb_dispatcher.DispatchError.out_of_memory;
        }
    }

    // P4c — spend predecessors AFTER successor(s) persisted: the
    // successor is the proof of consumption.
    if (pred_ids) |buf| {
        if (s.cell_store) |cs| {
            for (buf) |cid| {
                _ = cs.spend(&cid) catch return verb_dispatcher.DispatchError.walker_failed;
            }
        }
    }

    var b: std.ArrayList(u8) = .{};
    errdefer b.deinit(a);
    b.appendSlice(a, "{\"ok\":true,\"id\":") catch return verb_dispatcher.DispatchError.out_of_memory;
    appendJsonString(a, &b, id_for_body) catch return verb_dispatcher.DispatchError.out_of_memory;
    b.appendSlice(a, ",\"cellIds\":[") catch return verb_dispatcher.DispatchError.out_of_memory;
    for (cell_ids, 0..) |cid, i| {
        if (i > 0) b.append(a, ',') catch return verb_dispatcher.DispatchError.out_of_memory;
        b.append(a, '"') catch return verb_dispatcher.DispatchError.out_of_memory;
        try appendHex(a, &b, &cid);
        b.append(a, '"') catch return verb_dispatcher.DispatchError.out_of_memory;
    }
    b.appendSlice(a, "],\"persisted\":") catch return verb_dispatcher.DispatchError.out_of_memory;
    b.appendSlice(a, if (persisted) "true" else "false") catch return verb_dispatcher.DispatchError.out_of_memory;
    b.append(a, '}') catch return verb_dispatcher.DispatchError.out_of_memory;
    return b.toOwnedSlice(a) catch verb_dispatcher.DispatchError.out_of_memory;
}

fn settleMinted(
    a: std.mem.Allocator,
    s: *State,
    res: store_mod.StoreError!?store_mod.Rejection,
    id_for_body: []const u8,
    cell_name: []const u8,
    pj: []const u8,
    obj: std.json.ObjectMap,
    /// P4b — when non-null, record (record_domain_id, cell_id) in the
    /// per-cartridge domain-id → cell_id index. LINEAR successor mints
    /// pass the new entity's id; AFFINE event mints pass null (the
    /// "id" they reference is the parent, not a new entity).
    record_domain_id: ?[]const u8,
    /// P4c — when non-null, predecessor domain ids to consume against
    /// the substrate spent-set. See `settleMintedMany`'s docstring for
    /// the protocol; this 1-successor variant is identical except the
    /// body shape (cellId vs cellIds).
    predecessors: ?[]const []const u8,
) verb_dispatcher.DispatchError![]u8 {
    const rej = res catch |e| return mapStoreErr(e);
    if (rej) |r| return rejectionBody(a, @tagName(r));

    // P4c — predecessor resolve + spent-check (BEFORE mint).
    var pred_ids: ?[][32]u8 = null;
    defer if (pred_ids) |b| a.free(b);
    if (predecessors) |preds| {
        const buf = a.alloc([32]u8, preds.len) catch return verb_dispatcher.DispatchError.out_of_memory;
        errdefer a.free(buf);
        for (preds, 0..) |did, i| {
            const cid = s.store.cellIdByDomainId(did) orelse {
                a.free(buf);
                return rejectionBody(a, "unknown_predecessor");
            };
            buf[i] = cid;
        }
        if (s.cell_store) |cs| {
            for (buf) |cid| {
                if (cs.isSpent(&cid)) {
                    a.free(buf);
                    return rejectionBody(a, "cell_already_consumed");
                }
            }
        }
        pred_ids = buf;
    }

    const owner_id = try ownerIdFromParams(obj);
    // P-boot-rebuild — wrap with `domainId` when recording an index
    // entry; P4d — also include `consumedCellIds` when consuming.
    const consumed_for_audit: []const [32]u8 = if (pred_ids) |b| b else &.{};
    var maybe_wrapped: ?[]u8 = null;
    defer if (maybe_wrapped) |w| a.free(w);
    const payload_to_encode: []const u8 = if (record_domain_id) |did| blk: {
        maybe_wrapped = try payloadWithDomainId(a, pj, did, consumed_for_audit);
        break :blk maybe_wrapped.?;
    } else pj;
    const enc = tessera_mint.encodeCellByName(cell_name, owner_id, payload_to_encode, null) catch
        return verb_dispatcher.DispatchError.invalid_params;
    var persisted = false;
    if (s.cell_store) |store| {
        _ = store.put(&enc.cell) catch return verb_dispatcher.DispatchError.walker_failed;
        persisted = true;
    }
    if (record_domain_id) |did| {
        s.store.recordCellId(did, enc.cell_id) catch return verb_dispatcher.DispatchError.out_of_memory;
    }

    // P4c — spend predecessors AFTER successor persisted.
    if (pred_ids) |buf| {
        if (s.cell_store) |cs| {
            for (buf) |cid| {
                _ = cs.spend(&cid) catch return verb_dispatcher.DispatchError.walker_failed;
            }
        }
    }
    var b: std.ArrayList(u8) = .{};
    errdefer b.deinit(a);
    b.appendSlice(a, "{\"ok\":true,\"id\":") catch return verb_dispatcher.DispatchError.out_of_memory;
    appendJsonString(a, &b, id_for_body) catch return verb_dispatcher.DispatchError.out_of_memory;
    b.appendSlice(a, ",\"cellId\":\"") catch return verb_dispatcher.DispatchError.out_of_memory;
    try appendHex(a, &b, &enc.cell_id);
    b.appendSlice(a, "\",\"persisted\":") catch return verb_dispatcher.DispatchError.out_of_memory;
    b.appendSlice(a, if (persisted) "true" else "false") catch return verb_dispatcher.DispatchError.out_of_memory;
    b.append(a, '}') catch return verb_dispatcher.DispatchError.out_of_memory;
    return b.toOwnedSlice(a) catch verb_dispatcher.DispatchError.out_of_memory;
}

// ─── Walkers (13 verbs) ──────────────────────────────────────────────

fn st(ctx: *anyopaque) *State {
    return @ptrCast(@alignCast(ctx));
}

fn appendHex(a: std.mem.Allocator, b: *std.ArrayList(u8), bytes: []const u8) verb_dispatcher.DispatchError!void {
    const hex = "0123456789abcdef";
    for (bytes) |byte| {
        b.append(a, hex[byte >> 4]) catch return verb_dispatcher.DispatchError.out_of_memory;
        b.append(a, hex[byte & 0x0f]) catch return verb_dispatcher.DispatchError.out_of_memory;
    }
}

// P3e — owner/hat context. Mirrors entity_encode_walker's owner_id_hex
// (32-hex → first 16 bytes of the operator hat id), but OPTIONAL with a
// zero-fill fallback so existing harvest callers are unaffected (a
// zero owner surfaces as an unowned cell in audit, per EncodeInput).
fn nibble(c: u8) verb_dispatcher.DispatchError!u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => verb_dispatcher.DispatchError.invalid_params,
    };
}

/// Parse optional `ownerIdHex` (exactly 32 hex chars) → [16]u8.
/// Absent ⇒ zero-fill. Present-but-malformed ⇒ invalid_params.
fn ownerIdFromParams(obj: std.json.ObjectMap) verb_dispatcher.DispatchError![16]u8 {
    var owner = [_]u8{0} ** 16;
    const v = obj.get("ownerIdHex") orelse return owner;
    if (v != .string or v.string.len != 32) return verb_dispatcher.DispatchError.invalid_params;
    for (0..16) |i| {
        const hi = try nibble(v.string[i * 2]);
        const lo = try nibble(v.string[i * 2 + 1]);
        owner[i] = (hi << 4) | lo;
    }
    return owner;
}

/// harvest — the first verb wired to mint a REAL substrate cell
/// (tessera.grape-lot) alongside the in-memory provenance store. The
/// store transition stays authoritative for FSM/linearity tests; the
/// mint produces the canonical 1024-byte cell + cell_id via the generic
/// encode path (tag/linearity/domain-flag from the registered SPEC —
/// P3a/P3b), persists when the CellStore is bound (P3d), and stamps the
/// operator hat id from optional `ownerIdHex` (P3e). The other 12
/// verbs' mint/consume semantics are incremental follow-ups.
pub fn harvestWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const lot = try reqStr(o, "lotId");
    const grower = try reqStr(o, "grower");
    const vol = try reqU64(o, "volumeMl");
    // harvest is genesis (AFFINE) — no predecessor to consume.
    return settleMinted(a, s, s.store.harvest(lot, grower, vol), lot, "tessera.grape-lot", pj, o, lot, null);
}

pub fn rackWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const lot = try reqStr(o, "lotId");
    const bar = try reqStr(o, "barrelId");
    const vol = try reqU64(o, "volumeMl");
    // P4c — consumes the grape-lot (LINEAR predecessor).
    const preds = [_][]const u8{lot};
    return settleMinted(a, s, s.store.rack(lot, bar, vol), bar, "tessera.barrel", pj, o, bar, &preds);
}

pub fn blendWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const out = try reqStr(o, "outBarrelId");
    const ins = try reqStrArray(a, o, "inBarrelIds");
    defer a.free(ins);
    const vol = try reqU64(o, "declaredOutMl");
    // P4c — consumes each input barrel (LINEAR predecessors).
    return settleMinted(a, s, s.store.blend(out, ins, vol), out, "tessera.barrel", pj, o, out, ins);
}

pub fn bottleWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const bar = try reqStr(o, "barrelId");
    const bottles = try reqStrArray(a, o, "bottleIds");
    defer a.free(bottles);

    var payloads = a.alloc([]u8, bottles.len) catch return verb_dispatcher.DispatchError.out_of_memory;
    var built: usize = 0;
    defer {
        for (payloads[0..built]) |bp| a.free(bp);
        a.free(payloads);
    }
    for (bottles, 0..) |bid, i| {
        var b: std.ArrayList(u8) = .{};
        errdefer b.deinit(a);
        b.append(a, '{') catch return verb_dispatcher.DispatchError.out_of_memory;
        appendJsonString(a, &b, "barrelId") catch return verb_dispatcher.DispatchError.out_of_memory;
        b.append(a, ':') catch return verb_dispatcher.DispatchError.out_of_memory;
        appendJsonString(a, &b, bar) catch return verb_dispatcher.DispatchError.out_of_memory;
        b.append(a, ',') catch return verb_dispatcher.DispatchError.out_of_memory;
        appendJsonString(a, &b, "bottleId") catch return verb_dispatcher.DispatchError.out_of_memory;
        b.append(a, ':') catch return verb_dispatcher.DispatchError.out_of_memory;
        appendJsonString(a, &b, bid) catch return verb_dispatcher.DispatchError.out_of_memory;
        b.append(a, '}') catch return verb_dispatcher.DispatchError.out_of_memory;
        payloads[i] = b.toOwnedSlice(a) catch return verb_dispatcher.DispatchError.out_of_memory;
        built = i + 1;
    }

    var const_payloads = a.alloc([]const u8, payloads.len) catch return verb_dispatcher.DispatchError.out_of_memory;
    defer a.free(const_payloads);
    for (payloads, 0..) |bp, i| const_payloads[i] = bp;

    // P4c — consumes the barrel (LINEAR predecessor for every bottle).
    const preds = [_][]const u8{bar};
    return settleMintedMany(a, s, s.store.bottle(bar, bottles), bar, "tessera.bottle", const_payloads, o, bottles, &preds);
}

pub fn assembleCaseWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const case_id = try reqStr(o, "caseId");
    const holder = try reqStr(o, "holder");
    const bottles = try reqStrArray(a, o, "bottleIds");
    defer a.free(bottles);
    // P4c — consumes each bottle (LINEAR predecessors).
    return settleMinted(a, s, s.store.assembleCase(case_id, holder, bottles), case_id, "tessera.case", pj, o, case_id, bottles);
}

pub fn openContainerWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const id = try reqStr(o, "id");
    const kind = try reqStr(o, "kind");
    const holder = try reqStr(o, "holder");
    // Cell type follows the container kind (tessera_store maps unknown
    // kinds → case; mirror that so the minted cell type matches).
    const cell_name = if (std.mem.eql(u8, kind, "pallet"))
        "tessera.pallet"
    else if (std.mem.eql(u8, kind, "shipment"))
        "tessera.shipment"
    else
        "tessera.case";
    // open-container creates a new container; no predecessor to consume.
    return settleMinted(a, s, s.store.openContainer(id, kind, holder), id, cell_name, pj, o, id, null);
}

// P-custody-linear — transfer-custody and confirm-receipt now mint a
// NEW container cell at each custody transition, consuming the prior
// container cell (the same domain_id, the prior cell_id). Same cell
// TYPE as the container (case/pallet/shipment) — the "custody chain"
// is materialized by overwriting the index entry per transition and
// chaining cell_ids via consumedCellIds. No new cell types added —
// keeps the §3.3 ten-cell-type contract intact.

pub fn transferCustodyWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const id = try reqStr(o, "id");
    const from = try reqStr(o, "from");
    const to = try reqStr(o, "to");
    // Cell type follows the container's current kind. On rejection
    // (container not found) cell_name is irrelevant — the FSM result
    // surfaces as {ok:false,reason} without minting.
    const cell_name = s.store.getContainerCellName(id) orelse "tessera.case";
    // Consumes the prior container cell (resolved from the index by
    // the same domain_id; recordCellId on success overwrites the entry
    // so the index always points to the latest cell).
    const preds = [_][]const u8{id};
    return settleMinted(a, s, s.store.transferCustody(id, from, to), id, cell_name, pj, o, id, &preds);
}

pub fn confirmReceiptWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const id = try reqStr(o, "id");
    const who = try reqStr(o, "who");
    const cell_name = s.store.getContainerCellName(id) orelse "tessera.case";
    // Consumes the in-flight (post-transfer) container cell.
    const preds = [_][]const u8{id};
    return settleMinted(a, s, s.store.confirmReceipt(id, who), id, cell_name, pj, o, id, &preds);
}

pub fn recordCareEventWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const cid = try reqStr(o, "containerId");
    // AFFINE event: `cid` is the parent container, not a new entity ⇒ no index entry, no consume.
    return settleMinted(a, s, s.store.recordCareEvent(cid), cid, "tessera.care-event", pj, o, null, null);
}

/// report-quality-issue and thermo-flag are care-event-family verbs
/// (cartridge.json §3 — category "care-event"): both accumulate an
/// AFFINE care-event against the named container.
pub fn reportQualityIssueWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    return recordCareEventWalker(a, ctx, pj);
}

pub fn thermoFlagWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    return recordCareEventWalker(a, ctx, pj);
}

pub fn tamperWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const b = try reqStr(o, "bottleId");
    // AFFINE event on bottle (terminal one-shot): no new entity to index, no consume.
    return settleMinted(a, s, s.store.tamper(b), b, "tessera.tamper-event", pj, o, null, null);
}

pub fn consumerScanWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const b = try reqStr(o, "bottleId");
    // RELEVANT scan-event accumulates against the bottle (parent) — no index entry, no consume.
    return settleMinted(a, s, s.store.consumerScan(b), b, "tessera.scan-event", pj, o, null, null);
}

pub fn addTastingNoteWalker(a: std.mem.Allocator, ctx: *anyopaque, pj: []const u8) verb_dispatcher.DispatchError![]u8 {
    const s = st(ctx);
    var p = try parseObj(a, pj);
    defer p.deinit();
    const o = p.value.object;
    const b = try reqStr(o, "bottleId");
    // DEBUG tasting-note accumulates against the bottle (parent) — no index entry, no consume.
    return settleMinted(a, s, s.store.addTastingNote(b), b, "tessera.tasting-note", pj, o, null, null);
}

// ─── Registration ────────────────────────────────────────────────────

pub fn registerAll(registry: *verb_dispatcher.Registry, state: *State) !void {
    const V = struct { name: []const u8, f: verb_dispatcher.WalkerFn };
    const verbs = [_]V{
        .{ .name = "tessera.harvest", .f = harvestWalker },
        .{ .name = "tessera.rack", .f = rackWalker },
        .{ .name = "tessera.blend", .f = blendWalker },
        .{ .name = "tessera.bottle", .f = bottleWalker },
        .{ .name = "tessera.assemble-case", .f = assembleCaseWalker },
        .{ .name = "tessera.open-container", .f = openContainerWalker },
        .{ .name = "tessera.transfer-custody", .f = transferCustodyWalker },
        .{ .name = "tessera.confirm-receipt", .f = confirmReceiptWalker },
        .{ .name = "tessera.record-care-event", .f = recordCareEventWalker },
        .{ .name = "tessera.report-quality-issue", .f = reportQualityIssueWalker },
        .{ .name = "tessera.thermo-flag", .f = thermoFlagWalker },
        .{ .name = "tessera.tamper", .f = tamperWalker },
        .{ .name = "tessera.consumer-scan", .f = consumerScanWalker },
        .{ .name = "tessera.add-tasting-note", .f = addTastingNoteWalker },
    };
    for (verbs) |v| {
        try registry.register(.{
            .extension_id = "tessera",
            .verb = v.name,
            .walker_fn = v.f,
            .ctx = @ptrCast(state),
        });
    }
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

fn contains(h: []const u8, n: []const u8) bool {
    return std.mem.indexOf(u8, h, n) != null;
}

test "registerAll registers all 14 tessera verbs" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    // 13 cartridge.json verbs + tessera.open-container (the
    // pallet/shipment custody opener; case is opened via assemble-case).
    try testing.expectEqual(@as(usize, 14), reg.count());
    try testing.expect(reg.hasExtension("tessera"));
}

test "spine through the dispatcher: harvest → rack → bottle → assemble → transfer → confirm" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    const h = try reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"L1\",\"grower\":\"alice\",\"volumeMl\":1000}");
    defer testing.allocator.free(h);
    try testing.expect(contains(h, "\"ok\":true"));

    const r = try reg.dispatch(testing.allocator, "tessera", "tessera.rack", "{\"lotId\":\"L1\",\"barrelId\":\"B1\",\"volumeMl\":600}");
    testing.allocator.free(r);
    const bo = try reg.dispatch(testing.allocator, "tessera", "tessera.bottle", "{\"barrelId\":\"B1\",\"bottleIds\":[\"x\",\"y\"]}");
    testing.allocator.free(bo);
    const ac = try reg.dispatch(testing.allocator, "tessera", "tessera.assemble-case", "{\"caseId\":\"C1\",\"holder\":\"alice\",\"bottleIds\":[\"x\",\"y\"]}");
    testing.allocator.free(ac);
    const tc = try reg.dispatch(testing.allocator, "tessera", "tessera.transfer-custody", "{\"id\":\"C1\",\"from\":\"alice\",\"to\":\"bob\"}");
    testing.allocator.free(tc);
    const cr = try reg.dispatch(testing.allocator, "tessera", "tessera.confirm-receipt", "{\"id\":\"C1\",\"who\":\"bob\"}");
    defer testing.allocator.free(cr);
    try testing.expect(contains(cr, "\"ok\":true"));
}

test "domain refusal → ok:false reason body (blend not conserved), not a dispatch error" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    {
        const x = try reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"L\",\"grower\":\"g\",\"volumeMl\":1000}");
        testing.allocator.free(x);
    }
    {
        const x = try reg.dispatch(testing.allocator, "tessera", "tessera.rack", "{\"lotId\":\"L\",\"barrelId\":\"a\",\"volumeMl\":300}");
        testing.allocator.free(x);
    }
    {
        const x = try reg.dispatch(testing.allocator, "tessera", "tessera.rack", "{\"lotId\":\"L\",\"barrelId\":\"b\",\"volumeMl\":500}");
        testing.allocator.free(x);
    }
    const bad = try reg.dispatch(testing.allocator, "tessera", "tessera.blend", "{\"outBarrelId\":\"o\",\"inBarrelIds\":[\"a\",\"b\"],\"declaredOutMl\":999}");
    defer testing.allocator.free(bad);
    try testing.expect(contains(bad, "\"ok\":false"));
    try testing.expect(contains(bad, "\"reason\":\"blend_not_conserved\""));
}

test "tamper one-shot through the dispatcher" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    inline for (.{
        "{\"lotId\":\"L\",\"grower\":\"g\",\"volumeMl\":100}",
    }) |hp| {
        const x = try reg.dispatch(testing.allocator, "tessera", "tessera.harvest", hp);
        testing.allocator.free(x);
    }
    {
        const x = try reg.dispatch(testing.allocator, "tessera", "tessera.rack", "{\"lotId\":\"L\",\"barrelId\":\"B\",\"volumeMl\":100}");
        testing.allocator.free(x);
    }
    {
        const x = try reg.dispatch(testing.allocator, "tessera", "tessera.bottle", "{\"barrelId\":\"B\",\"bottleIds\":[\"b1\"]}");
        testing.allocator.free(x);
    }
    {
        const ok = try reg.dispatch(testing.allocator, "tessera", "tessera.tamper", "{\"bottleId\":\"b1\"}");
        defer testing.allocator.free(ok);
        try testing.expect(contains(ok, "\"ok\":true"));
    }
    const again = try reg.dispatch(testing.allocator, "tessera", "tessera.tamper", "{\"bottleId\":\"b1\"}");
    defer testing.allocator.free(again);
    try testing.expect(contains(again, "\"reason\":\"already_tampered\""));
}

test "malformed params → invalid_params dispatch error" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"L\"}"),
    );
}

test "P3c: harvest mints a real tessera.grape-lot cell (cellId, 64-hex, persisted:false)" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    const h = try reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"L1\",\"grower\":\"alice\",\"volumeMl\":1000}");
    defer testing.allocator.free(h);
    try testing.expect(contains(h, "\"ok\":true"));
    try testing.expect(contains(h, "\"cellId\":\""));
    try testing.expect(contains(h, "\"persisted\":false"));
    // cellId is sha256 hex = 64 chars. Find it and length-check.
    const key = "\"cellId\":\"";
    const at = std.mem.indexOf(u8, h, key).? + key.len;
    const end = std.mem.indexOfScalarPos(u8, h, at, '"').?;
    try testing.expectEqual(@as(usize, 64), end - at);
}

fn cellIdOf(h: []const u8) []const u8 {
    const key = "\"cellId\":\"";
    const at = std.mem.indexOf(u8, h, key).? + key.len;
    const end = std.mem.indexOfScalarPos(u8, h, at, '"').?;
    return h[at..end];
}

test "P3e: ownerIdHex stamps the operator hat id (changes the cell_id)" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    // Same payload+lot shape, different owner ⇒ different cell bytes ⇒
    // different cell_id (owner_id is in the 256-byte header).
    const no_owner = try reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"A\",\"grower\":\"g\",\"volumeMl\":1}");
    defer testing.allocator.free(no_owner);
    const with_owner = try reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"B\",\"grower\":\"g\",\"volumeMl\":1,\"ownerIdHex\":\"0123456789abcdef0123456789abcdef\"}");
    defer testing.allocator.free(with_owner);
    try testing.expect(contains(with_owner, "\"ok\":true"));
    try testing.expect(!std.mem.eql(u8, cellIdOf(no_owner), cellIdOf(with_owner)));
}

test "P3e: malformed ownerIdHex → invalid_params (bad length AND non-hex)" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"C\",\"grower\":\"g\",\"volumeMl\":1,\"ownerIdHex\":\"abcd\"}"),
    );
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"D\",\"grower\":\"g\",\"volumeMl\":1,\"ownerIdHex\":\"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\"}"),
    );
}

test "P3f: rack mints a tessera.barrel cell via the shared helper" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    {
        const h = try reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"L\",\"grower\":\"g\",\"volumeMl\":1000}");
        defer testing.allocator.free(h);
        try testing.expect(contains(h, "\"cellId\":\""));
    }
    const r = try reg.dispatch(testing.allocator, "tessera", "tessera.rack", "{\"lotId\":\"L\",\"barrelId\":\"B\",\"volumeMl\":600}");
    defer testing.allocator.free(r);
    try testing.expect(contains(r, "\"ok\":true"));
    try testing.expect(contains(r, "\"cellId\":\""));
    try testing.expect(contains(r, "\"persisted\":false"));
    try testing.expectEqual(@as(usize, 64), cellIdOf(r).len);
    // Different cell type ⇒ different cell_id vs the grape-lot above is
    // implicit; here just assert rack produced its own barrel cell.
}

test "P3g: bottle mints N distinct tessera.bottle cells (one per bottleId)" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    inline for (.{
        .{ "tessera.harvest", "{\"lotId\":\"L\",\"grower\":\"g\",\"volumeMl\":1000}" },
        .{ "tessera.rack", "{\"lotId\":\"L\",\"barrelId\":\"B\",\"volumeMl\":600}" },
    }) |step| {
        const x = try reg.dispatch(testing.allocator, "tessera", step[0], step[1]);
        testing.allocator.free(x);
    }
    const bo = try reg.dispatch(testing.allocator, "tessera", "tessera.bottle", "{\"barrelId\":\"B\",\"bottleIds\":[\"x\",\"y\",\"z\"]}");
    defer testing.allocator.free(bo);
    try testing.expect(contains(bo, "\"ok\":true"));
    try testing.expect(contains(bo, "\"cellIds\":["));
    try testing.expect(contains(bo, "\"persisted\":false"));

    // Parse out the cellIds array and assert: 3 entries, each 64-hex, all distinct.
    const key = "\"cellIds\":[";
    const at = std.mem.indexOf(u8, bo, key).? + key.len;
    const end = std.mem.indexOfScalarPos(u8, bo, at, ']').?;
    const arr = bo[at..end];
    var found = [_][]const u8{ "", "", "" };
    var n: usize = 0;
    var cursor: usize = 0;
    while (std.mem.indexOfScalarPos(u8, arr, cursor, '"')) |start_q| {
        const close_q = std.mem.indexOfScalarPos(u8, arr, start_q + 1, '"').?;
        const hex = arr[start_q + 1 .. close_q];
        try testing.expectEqual(@as(usize, 64), hex.len);
        try testing.expect(n < 3);
        found[n] = hex;
        n += 1;
        cursor = close_q + 1;
    }
    try testing.expectEqual(@as(usize, 3), n);
    try testing.expect(!std.mem.eql(u8, found[0], found[1]));
    try testing.expect(!std.mem.eql(u8, found[1], found[2]));
    try testing.expect(!std.mem.eql(u8, found[0], found[2]));
}

test "P3f: tamper mints tessera.tamper-event; one-shot still enforced through the shared helper" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    inline for (.{
        .{ "tessera.harvest", "{\"lotId\":\"L\",\"grower\":\"g\",\"volumeMl\":100}" },
        .{ "tessera.rack", "{\"lotId\":\"L\",\"barrelId\":\"B\",\"volumeMl\":100}" },
        .{ "tessera.bottle", "{\"barrelId\":\"B\",\"bottleIds\":[\"b1\"]}" },
    }) |step| {
        const x = try reg.dispatch(testing.allocator, "tessera", step[0], step[1]);
        testing.allocator.free(x);
    }
    const t1 = try reg.dispatch(testing.allocator, "tessera", "tessera.tamper", "{\"bottleId\":\"b1\"}");
    defer testing.allocator.free(t1);
    try testing.expect(contains(t1, "\"ok\":true") and contains(t1, "\"cellId\":\""));
    const t2 = try reg.dispatch(testing.allocator, "tessera", "tessera.tamper", "{\"bottleId\":\"b1\"}");
    defer testing.allocator.free(t2);
    try testing.expect(contains(t2, "\"reason\":\"already_tampered\"")); // store stays authoritative
}

// ─── P4b — domain-id → cell_id index tests ──────────────────────────

/// Hex-decode a 64-char string into [32]u8.
fn hexDecode32(hex: []const u8) [32]u8 {
    std.debug.assert(hex.len == 64);
    var out: [32]u8 = undefined;
    for (0..32) |i| {
        const hi: u8 = switch (hex[i * 2]) {
            '0'...'9' => hex[i * 2] - '0',
            'a'...'f' => hex[i * 2] - 'a' + 10,
            'A'...'F' => hex[i * 2] - 'A' + 10,
            else => unreachable,
        };
        const lo: u8 = switch (hex[i * 2 + 1]) {
            '0'...'9' => hex[i * 2 + 1] - '0',
            'a'...'f' => hex[i * 2 + 1] - 'a' + 10,
            'A'...'F' => hex[i * 2 + 1] - 'A' + 10,
            else => unreachable,
        };
        out[i] = (hi << 4) | lo;
    }
    return out;
}

test "P4b: LINEAR mints record domain_id → cell_id (harvest/rack/blend/assemble/open)" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    // harvest L1 → grape-lot
    const h = try reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"L1\",\"grower\":\"g\",\"volumeMl\":1000}");
    defer testing.allocator.free(h);
    const h_cell = hexDecode32(cellIdOf(h));
    const indexed_lot = store.cellIdByDomainId("L1") orelse return error.TestExpectedNotNull;
    try testing.expectEqualSlices(u8, &h_cell, &indexed_lot);

    // rack → barrel B1
    const r = try reg.dispatch(testing.allocator, "tessera", "tessera.rack", "{\"lotId\":\"L1\",\"barrelId\":\"B1\",\"volumeMl\":600}");
    defer testing.allocator.free(r);
    const r_cell = hexDecode32(cellIdOf(r));
    const indexed_bar = store.cellIdByDomainId("B1") orelse return error.TestExpectedNotNull;
    try testing.expectEqualSlices(u8, &r_cell, &indexed_bar);
    // L1 entry unchanged.
    try testing.expectEqualSlices(u8, &h_cell, &(store.cellIdByDomainId("L1").?));

    // open-container P1 (pallet) → container cell
    const oc = try reg.dispatch(testing.allocator, "tessera", "tessera.open-container", "{\"id\":\"P1\",\"kind\":\"pallet\",\"holder\":\"alice\"}");
    defer testing.allocator.free(oc);
    const oc_cell = hexDecode32(cellIdOf(oc));
    try testing.expectEqualSlices(u8, &oc_cell, &(store.cellIdByDomainId("P1").?));

    // Three LINEAR entries; AFFINE-only verbs have not run yet.
    try testing.expectEqual(@as(usize, 3), store.domainIdIndexCount());
}

test "P4b: AFFINE event mints do NOT pollute the domain-id index" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    // Set up: lot → barrel → one bottle. Three LINEAR entries land in the index.
    inline for (.{
        .{ "tessera.harvest", "{\"lotId\":\"L\",\"grower\":\"g\",\"volumeMl\":100}" },
        .{ "tessera.rack", "{\"lotId\":\"L\",\"barrelId\":\"B\",\"volumeMl\":100}" },
        .{ "tessera.bottle", "{\"barrelId\":\"B\",\"bottleIds\":[\"b1\"]}" },
    }) |step| {
        const x = try reg.dispatch(testing.allocator, "tessera", step[0], step[1]);
        testing.allocator.free(x);
    }
    try testing.expectEqual(@as(usize, 3), store.domainIdIndexCount());

    // Snapshot the bottle's recorded cell_id; any AFFINE event against
    // "b1" must NOT overwrite it.
    const b1_pre = store.cellIdByDomainId("b1") orelse return error.TestExpectedNotNull;

    // Fire AFFINE/RELEVANT/DEBUG event verbs against the same bottle id.
    inline for (.{
        .{ "tessera.consumer-scan", "{\"bottleId\":\"b1\"}" },
        .{ "tessera.add-tasting-note", "{\"bottleId\":\"b1\"}" },
    }) |step| {
        const x = try reg.dispatch(testing.allocator, "tessera", step[0], step[1]);
        defer testing.allocator.free(x);
        try testing.expect(contains(x, "\"ok\":true"));
    }

    // Count unchanged: scan/tasting-note did not add entries.
    try testing.expectEqual(@as(usize, 3), store.domainIdIndexCount());
    // b1's recorded cell_id unchanged: AFFINE events did not overwrite the
    // bottle's LINEAR successor cell_id.
    const b1_post = store.cellIdByDomainId("b1") orelse return error.TestExpectedNotNull;
    try testing.expectEqualSlices(u8, &b1_pre, &b1_post);

    // Tamper is terminal AFFINE; also no overwrite.
    {
        const x = try reg.dispatch(testing.allocator, "tessera", "tessera.tamper", "{\"bottleId\":\"b1\"}");
        defer testing.allocator.free(x);
    }
    try testing.expectEqual(@as(usize, 3), store.domainIdIndexCount());
    try testing.expectEqualSlices(u8, &b1_pre, &(store.cellIdByDomainId("b1").?));
}

test "P4b: bottle records each bottleId → its own distinct cell_id" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    inline for (.{
        .{ "tessera.harvest", "{\"lotId\":\"L\",\"grower\":\"g\",\"volumeMl\":1000}" },
        .{ "tessera.rack", "{\"lotId\":\"L\",\"barrelId\":\"B\",\"volumeMl\":600}" },
    }) |step| {
        const x = try reg.dispatch(testing.allocator, "tessera", step[0], step[1]);
        testing.allocator.free(x);
    }
    const bo = try reg.dispatch(testing.allocator, "tessera", "tessera.bottle", "{\"barrelId\":\"B\",\"bottleIds\":[\"x\",\"y\",\"z\"]}");
    defer testing.allocator.free(bo);

    // 2 LINEAR predecessors (L, B) + 3 bottle entries = 5 entries.
    try testing.expectEqual(@as(usize, 5), store.domainIdIndexCount());
    const cx = store.cellIdByDomainId("x") orelse return error.TestExpectedNotNull;
    const cy = store.cellIdByDomainId("y") orelse return error.TestExpectedNotNull;
    const cz = store.cellIdByDomainId("z") orelse return error.TestExpectedNotNull;
    try testing.expect(!std.mem.eql(u8, &cx, &cy));
    try testing.expect(!std.mem.eql(u8, &cy, &cz));
    try testing.expect(!std.mem.eql(u8, &cx, &cz));
}

test "P4b: rejection does NOT pollute the domain-id index" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    // Duplicate harvest on the same lotId: the second is rejected by the
    // FSM (`duplicate_id`); the recorded cell_id must be the FIRST mint's.
    const h1 = try reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"L\",\"grower\":\"g\",\"volumeMl\":1}");
    defer testing.allocator.free(h1);
    const recorded = (store.cellIdByDomainId("L").?);

    const h2 = try reg.dispatch(testing.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"L\",\"grower\":\"other\",\"volumeMl\":2}");
    defer testing.allocator.free(h2);
    try testing.expect(contains(h2, "\"reason\":\"duplicate_id\""));
    try testing.expectEqualSlices(u8, &recorded, &(store.cellIdByDomainId("L").?));
    try testing.expectEqual(@as(usize, 1), store.domainIdIndexCount());
}

// ─── P4c — consume protocol tests ───────────────────────────────────

test "P4c: full chain harvest→rack→blend→bottle→assemble still works through retrofitted helpers" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    // Harvest two lots, rack two barrels, blend them, bottle the blend,
    // assemble a case. Every retrofit hop returns ok:true because the
    // walker chain populates the index before each consume.
    inline for (.{
        .{ "tessera.harvest", "{\"lotId\":\"L1\",\"grower\":\"g\",\"volumeMl\":1000}" },
        .{ "tessera.harvest", "{\"lotId\":\"L2\",\"grower\":\"g\",\"volumeMl\":1000}" },
        .{ "tessera.rack", "{\"lotId\":\"L1\",\"barrelId\":\"B1\",\"volumeMl\":500}" },
        .{ "tessera.rack", "{\"lotId\":\"L2\",\"barrelId\":\"B2\",\"volumeMl\":500}" },
        .{ "tessera.blend", "{\"outBarrelId\":\"Bo\",\"inBarrelIds\":[\"B1\",\"B2\"],\"declaredOutMl\":1000}" },
        .{ "tessera.bottle", "{\"barrelId\":\"Bo\",\"bottleIds\":[\"x\",\"y\"]}" },
        .{ "tessera.assemble-case", "{\"caseId\":\"C1\",\"holder\":\"alice\",\"bottleIds\":[\"x\",\"y\"]}" },
    }) |step| {
        const r = try reg.dispatch(testing.allocator, "tessera", step[0], step[1]);
        defer testing.allocator.free(r);
        try testing.expect(contains(r, "\"ok\":true"));
    }
    // Index now holds: L1, L2, B1, B2, Bo, x, y, C1 = 8.
    try testing.expectEqual(@as(usize, 8), store.domainIdIndexCount());
}

test "P4c: rack surfaces unknown_predecessor when the index lacks the lot (FSM-only state)" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    // Populate the FSM via the store directly — this BYPASSES the
    // walker, so the index is NOT updated. This is the same shape the
    // index would have at fresh boot before rebuild.
    const harvest_rej = try store.harvest("L_orphan", "g", 1000);
    try testing.expect(harvest_rej == null); // FSM accepted.
    try testing.expectEqual(@as(usize, 0), store.domainIdIndexCount());

    // Dispatching rack via the walker: FSM accepts (the lot exists in
    // memory), but the consume helper can't resolve L_orphan to a
    // cell_id (no walker mint recorded it). Surfaces as a domain
    // refusal — not a dispatch error.
    const r = try reg.dispatch(testing.allocator, "tessera", "tessera.rack", "{\"lotId\":\"L_orphan\",\"barrelId\":\"B\",\"volumeMl\":500}");
    defer testing.allocator.free(r);
    try testing.expect(contains(r, "\"ok\":false"));
    try testing.expect(contains(r, "\"reason\":\"unknown_predecessor\""));
    // FSM state was authoritative; rejection means no successor was
    // minted and the index stays empty.
    try testing.expectEqual(@as(usize, 0), store.domainIdIndexCount());
}

test "P4c: blend surfaces unknown_predecessor when ANY one input barrel is unindexed" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    // Walker-mint L1 + B1 (indexed); store-only L2 + B2 (FSM-only).
    inline for (.{
        .{ "tessera.harvest", "{\"lotId\":\"L1\",\"grower\":\"g\",\"volumeMl\":500}" },
        .{ "tessera.rack", "{\"lotId\":\"L1\",\"barrelId\":\"B1\",\"volumeMl\":500}" },
    }) |step| {
        const x = try reg.dispatch(testing.allocator, "tessera", step[0], step[1]);
        testing.allocator.free(x);
    }
    _ = try store.harvest("L2", "g", 500);
    _ = try store.rack("L2", "B2", 500);
    // FSM holds both barrels; index holds only B1.
    const r = try reg.dispatch(testing.allocator, "tessera", "tessera.blend", "{\"outBarrelId\":\"Bo\",\"inBarrelIds\":[\"B1\",\"B2\"],\"declaredOutMl\":1000}");
    defer testing.allocator.free(r);
    try testing.expect(contains(r, "\"reason\":\"unknown_predecessor\""));
}

// ─── P4d — `consumedCellIds` on-cell audit trail ─────────────────────

test "P4d: payloadWithDomainId omits consumedCellIds when no predecessors" {
    const out = try payloadWithDomainId(testing.allocator, "{\"foo\":\"bar\"}", "X1", &.{});
    defer testing.allocator.free(out);
    try testing.expect(contains(out, "\"domainId\":\"X1\""));
    try testing.expect(!contains(out, "consumedCellIds"));
    try testing.expect(contains(out, "\"foo\":\"bar\""));
}

test "P4d: payloadWithDomainId emits consumedCellIds array with hex-encoded cell_ids" {
    const cid_a: [32]u8 = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF } ++ [_]u8{0} ** 28;
    const cid_b: [32]u8 = [_]u8{ 0xCA, 0xFE, 0xBA, 0xBE } ++ [_]u8{0} ** 28;
    const consumed = [_][32]u8{ cid_a, cid_b };
    const out = try payloadWithDomainId(testing.allocator, "{\"foo\":\"bar\"}", "out", &consumed);
    defer testing.allocator.free(out);
    try testing.expect(contains(out, "\"domainId\":\"out\""));
    try testing.expect(contains(out, "\"consumedCellIds\":[\"deadbeef"));
    try testing.expect(contains(out, ",\"cafebabe"));
    // Original fields preserved.
    try testing.expect(contains(out, "\"foo\":\"bar\""));
}

test "P4d: payloadWithDomainId handles empty inner object cleanly" {
    const cid: [32]u8 = [_]u8{0xFF} ** 32;
    const out_consume = try payloadWithDomainId(testing.allocator, "{}", "g", &[_][32]u8{cid});
    defer testing.allocator.free(out_consume);
    // Well-formed: opens {, has domainId, consumedCellIds, no trailing comma, closes }.
    try testing.expectEqual(out_consume[0], '{');
    try testing.expectEqual(out_consume[out_consume.len - 1], '}');
    try testing.expect(!contains(out_consume, ",}"));

    const out_no_consume = try payloadWithDomainId(testing.allocator, "{}", "g", &.{});
    defer testing.allocator.free(out_no_consume);
    try testing.expectEqualStrings("{\"domainId\":\"g\"}", out_no_consume);
}

test "P4d: rack-minted cell payload carries consumedCellIds[grape_lot_cell_id]" {
    // Drive a full mint chain through tessera_mint directly (same path
    // the walkers exercise — payloadWithDomainId then encodeCellByName),
    // then parse the encoded cells back to verify the audit edge:
    // a barrel cell's `consumedCellIds` references the grape-lot cell.
    const tessera_mint_test = @import("tessera_mint");
    const owner = [_]u8{0} ** 16;

    // 1. Harvest's grape-lot — no predecessors.
    const lot_payload = try payloadWithDomainId(testing.allocator, "{\"grower\":\"alice\"}", "L1", &.{});
    defer testing.allocator.free(lot_payload);
    const lot_enc = try tessera_mint_test.encodeCellByName("tessera.grape-lot", owner, lot_payload, 1);

    // 2. Rack's barrel — consumes the grape-lot's cell_id.
    const barrel_payload = try payloadWithDomainId(
        testing.allocator,
        "{\"volumeMl\":500}",
        "B1",
        &[_][32]u8{lot_enc.cell_id},
    );
    defer testing.allocator.free(barrel_payload);

    // Verify the barrel's payload JSON carries the lot's cell_id in
    // consumedCellIds[0] (hex-encoded).
    var hex_buf: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (lot_enc.cell_id, 0..) |byte, i| {
        hex_buf[i * 2] = hex_chars[byte >> 4];
        hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    try testing.expect(contains(barrel_payload, "\"consumedCellIds\":[\""));
    try testing.expect(std.mem.indexOf(u8, barrel_payload, &hex_buf) != null);
}

test "P4d: AFFINE event mints carry NO consumedCellIds (no payload wrap at all)" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    // Set up: bottle to tamper against.
    inline for (.{
        .{ "tessera.harvest", "{\"lotId\":\"L\",\"grower\":\"g\",\"volumeMl\":100}" },
        .{ "tessera.rack", "{\"lotId\":\"L\",\"barrelId\":\"B\",\"volumeMl\":100}" },
        .{ "tessera.bottle", "{\"barrelId\":\"B\",\"bottleIds\":[\"b1\"]}" },
    }) |step| {
        const x = try reg.dispatch(testing.allocator, "tessera", step[0], step[1]);
        testing.allocator.free(x);
    }
    // tamper is AFFINE — record_domain_id=null, predecessors=null. The
    // body is still well-formed; the cell payload (not surfaced) stays
    // the raw verb input. Index entry count unchanged.
    const pre = store.domainIdIndexCount();
    const t = try reg.dispatch(testing.allocator, "tessera", "tessera.tamper", "{\"bottleId\":\"b1\"}");
    defer testing.allocator.free(t);
    try testing.expect(contains(t, "\"ok\":true"));
    try testing.expectEqual(pre, store.domainIdIndexCount());
}

// ─── P-custody-linear — transfer/confirm mint+consume custody chain ──

test "P-custody-linear: open → transfer → confirm chains 3 distinct cell_ids under one domain_id" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    // 1. open-container — first cell in the custody chain (no predecessor).
    const open = try reg.dispatch(testing.allocator, "tessera", "tessera.open-container", "{\"id\":\"S1\",\"kind\":\"shipment\",\"holder\":\"alice\"}");
    defer testing.allocator.free(open);
    try testing.expect(contains(open, "\"ok\":true"));
    const open_cell_id = hexDecode32(cellIdOf(open));
    try testing.expectEqualSlices(u8, &open_cell_id, &(store.cellIdByDomainId("S1").?));

    // 2. transfer-custody — mints a NEW shipment cell that consumes
    //    the open-container cell. Body now includes cellId + persisted
    //    (P-custody-linear: same shape as every other settleMinted verb).
    const tc = try reg.dispatch(testing.allocator, "tessera", "tessera.transfer-custody", "{\"id\":\"S1\",\"from\":\"alice\",\"to\":\"bob\"}");
    defer testing.allocator.free(tc);
    try testing.expect(contains(tc, "\"ok\":true"));
    try testing.expect(contains(tc, "\"cellId\":\""));
    const tc_cell_id = hexDecode32(cellIdOf(tc));
    try testing.expect(!std.mem.eql(u8, &open_cell_id, &tc_cell_id)); // new cell, different id
    // Index now points to the in-flight cell (overwrites prior entry).
    try testing.expectEqualSlices(u8, &tc_cell_id, &(store.cellIdByDomainId("S1").?));

    // 3. confirm-receipt — mints a NEW shipment cell that consumes the
    //    in-flight cell. Index advances again to the settled cell.
    const cr = try reg.dispatch(testing.allocator, "tessera", "tessera.confirm-receipt", "{\"id\":\"S1\",\"who\":\"bob\"}");
    defer testing.allocator.free(cr);
    try testing.expect(contains(cr, "\"ok\":true"));
    try testing.expect(contains(cr, "\"cellId\":\""));
    const cr_cell_id = hexDecode32(cellIdOf(cr));
    try testing.expect(!std.mem.eql(u8, &tc_cell_id, &cr_cell_id));
    try testing.expect(!std.mem.eql(u8, &open_cell_id, &cr_cell_id));
    try testing.expectEqualSlices(u8, &cr_cell_id, &(store.cellIdByDomainId("S1").?));

    // Index entry count: ONE entry per domain_id, regardless of chain length.
    try testing.expectEqual(@as(usize, 1), store.domainIdIndexCount());
}

test "P-custody-linear: FSM rejections still surface (transfer to wrong recipient at confirm)" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    inline for (.{
        .{ "tessera.open-container", "{\"id\":\"S2\",\"kind\":\"shipment\",\"holder\":\"alice\"}" },
        .{ "tessera.transfer-custody", "{\"id\":\"S2\",\"from\":\"alice\",\"to\":\"bob\"}" },
    }) |step| {
        const x = try reg.dispatch(testing.allocator, "tessera", step[0], step[1]);
        testing.allocator.free(x);
    }
    // Snapshot the index entry (the in-flight cell_id).
    const before = store.cellIdByDomainId("S2").?;

    // carol tries to confirm — FSM rejects `not_the_recipient`. The
    // settleMinted path surfaces it as the usual rejection body; NO
    // new cell minted; index entry UNCHANGED.
    const cr_bad = try reg.dispatch(testing.allocator, "tessera", "tessera.confirm-receipt", "{\"id\":\"S2\",\"who\":\"carol\"}");
    defer testing.allocator.free(cr_bad);
    try testing.expect(contains(cr_bad, "\"reason\":\"not_the_recipient\""));
    try testing.expectEqualSlices(u8, &before, &(store.cellIdByDomainId("S2").?));
}

test "P-custody-linear: confirm-receipt on a missing container surfaces shipment_not_found" {
    var store = Store.init(testing.allocator);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    // No open-container first; FSM rejects shipment_not_found. The
    // cell_name fallback ("tessera.case") never reaches the mint path.
    const r = try reg.dispatch(testing.allocator, "tessera", "tessera.confirm-receipt", "{\"id\":\"X\",\"who\":\"who\"}");
    defer testing.allocator.free(r);
    try testing.expect(contains(r, "\"reason\":\"shipment_not_found\""));
    try testing.expectEqual(@as(usize, 0), store.domainIdIndexCount());
}

```
