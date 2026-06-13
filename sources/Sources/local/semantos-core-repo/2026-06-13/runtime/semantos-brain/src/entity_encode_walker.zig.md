---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/entity_encode_walker.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.259740+00:00
---

# runtime/semantos-brain/src/entity_encode_walker.zig

```zig
// D-RTC.4 brain-side counterpart — `entity.encode` walker.
//
// Reference:
//   docs/prd/D-Reingest-Typed-Cells.md §Resolved decisions / DECISION-10
//   runtime/legacy-ingest/src/cell-encoder.ts (TS-side request shape)
//   runtime/semantos-brain/src/substrate_entity.zig (encoder + SPECs)
//   runtime/semantos-brain/src/verb_dispatcher.zig (WalkerFn contract)
//
// DECISION-10 resolution: the brain's substrate_entity.zig is the
// single source of truth for typehash + 1024-byte cell encoding.
// TS reingest builds `EntityEncodeRequest` envelopes and dispatches
// them through this walker, which:
//
//   1. Parses the request JSON (tag, linearity, owner_id_hex,
//      payload_json, optional timestamp).
//   2. Looks up the SPEC by tag via substrate_entity.specByTag(); the
//      type_hash is the brain's responsibility, NEVER the TS caller's.
//   3. Encodes the 1024-byte cell.
//   4. Persists to the entity cell store when wired (best-effort —
//      the walker still returns the cell_id even when the store is
//      absent so dry-run / boot-without-LMDB paths work end-to-end).
//   5. Returns {cell_id, type_hash, persisted} as JSON.
//
// Wire-shape (params for verb.dispatch):
//
//   {
//     "tag": 7,                                  // u32, matches TAG_*
//     "linearity": "affine",                     // "linear|affine|relevant|debug"
//     "owner_id_hex": "00...00",                 // 32-char (16 bytes hex)
//     "payload_json": "{\"...\":\"...\"}",       // ≤ 768 bytes
//     "timestamp_ns": null                       // optional i64
//   }
//
// Result:
//   {
//     "cell_id": "<64-hex>",
//     "type_hash": "<64-hex>",
//     "persisted": true,
//     "tag": 7
//   }

const std = @import("std");
const verb_dispatcher = @import("verb_dispatcher");
const substrate_entity = @import("substrate_entity");
const cell_store_mod = @import("cell_store");
const content_store_local_fs = @import("content_store_local_fs");

const Sha256 = std.crypto.hash.sha2.Sha256;

/// Walker state — holds the optional cell store handle. The walker is
/// resilient to a null store (returns persisted=false) so the dispatch
/// path remains testable end-to-end without bringing up LMDB.
pub const State = struct {
    /// Entity cell store. When non-null, encoded cells are persisted
    /// via `store.put(&cell)`. When null, the walker still returns
    /// the cell_id (sha256 of the encoded cell) so callers can build
    /// the cell graph in dry-run / test contexts.
    cell_store: ?*const cell_store_mod.CellStore = null,

    /// Octave-1 content store. When non-null, any payload exceeding the
    /// 768-byte inline budget is transparently escalated: the full
    /// bytes are written to a content-addressed slot and the cell
    /// carries a tiny pointer descriptor (see
    /// substrate_entity.encodeEntityEscalating). When null, an
    /// over-budget payload is rejected as before (no silent dangling
    /// pointers) — production always wires this.
    content_store: ?*content_store_local_fs.ContentStoreLocalFs = null,
};

// ─── Walker ──────────────────────────────────────────────────────────

pub fn entityEncodeWalker(
    allocator: std.mem.Allocator,
    ctx: *anyopaque,
    params_json: []const u8,
) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch {
        std.debug.print("[entity_encode] reject: JSON parse failed (params_json.len={})\n", .{params_json.len});
        return verb_dispatcher.DispatchError.invalid_params;
    };
    defer parsed.deinit();
    if (parsed.value != .object) {
        std.debug.print("[entity_encode] reject: parsed.value != .object\n", .{});
        return verb_dispatcher.DispatchError.invalid_params;
    }
    const obj = parsed.value.object;

    // tag
    const tag_v = obj.get("tag") orelse {
        std.debug.print("[entity_encode] reject: missing tag\n", .{});
        return verb_dispatcher.DispatchError.invalid_params;
    };
    if (tag_v != .integer) {
        std.debug.print("[entity_encode] reject: tag not integer (type={s})\n", .{@tagName(tag_v)});
        return verb_dispatcher.DispatchError.invalid_params;
    }
    if (tag_v.integer < 0 or tag_v.integer > std.math.maxInt(u32)) {
        std.debug.print("[entity_encode] reject: tag out of range ({})\n", .{tag_v.integer});
        return verb_dispatcher.DispatchError.invalid_params;
    }
    const tag: u32 = @intCast(tag_v.integer);

    const spec = substrate_entity.specByTag(tag) orelse {
        std.debug.print("[entity_encode] reject: unknown tag {}\n", .{tag});
        return verb_dispatcher.DispatchError.invalid_params;
    };

    // linearity
    const lin_v = obj.get("linearity") orelse {
        std.debug.print("[entity_encode] reject: missing linearity (tag={})\n", .{tag});
        return verb_dispatcher.DispatchError.invalid_params;
    };
    if (lin_v != .string) {
        std.debug.print("[entity_encode] reject: linearity not string (tag={})\n", .{tag});
        return verb_dispatcher.DispatchError.invalid_params;
    }
    const linearity = parseLinearity(lin_v.string) orelse {
        std.debug.print("[entity_encode] reject: bad linearity '{s}' (tag={})\n", .{ lin_v.string, tag });
        return verb_dispatcher.DispatchError.invalid_params;
    };

    // owner_id_hex (32 chars → 16 bytes)
    const oid_v = obj.get("owner_id_hex") orelse {
        std.debug.print("[entity_encode] reject: missing owner_id_hex (tag={})\n", .{tag});
        return verb_dispatcher.DispatchError.invalid_params;
    };
    if (oid_v != .string or oid_v.string.len != 32) {
        std.debug.print("[entity_encode] reject: owner_id_hex bad (tag={})\n", .{tag});
        return verb_dispatcher.DispatchError.invalid_params;
    }
    var owner_id: [16]u8 = undefined;
    decodeHex(oid_v.string, &owner_id) catch {
        std.debug.print("[entity_encode] reject: owner_id_hex decode (tag={})\n", .{tag});
        return verb_dispatcher.DispatchError.invalid_params;
    };

    // payload_json
    const pl_v = obj.get("payload_json") orelse {
        std.debug.print("[entity_encode] reject: missing payload_json (tag={})\n", .{tag});
        return verb_dispatcher.DispatchError.invalid_params;
    };
    if (pl_v != .string or pl_v.string.len == 0) {
        std.debug.print("[entity_encode] reject: payload_json empty/non-string (tag={} type={s})\n", .{ tag, @tagName(pl_v) });
        return verb_dispatcher.DispatchError.invalid_params;
    }

    // timestamp_ns — optional
    var timestamp_ns: ?i128 = null;
    if (obj.get("timestamp_ns")) |ts_v| {
        switch (ts_v) {
            .integer => |i| timestamp_ns = i,
            .null => timestamp_ns = null,
            else => return verb_dispatcher.DispatchError.invalid_params,
        }
    }

    const input = substrate_entity.EncodeInput{
        .spec = spec,
        .linearity = linearity,
        .owner_id = owner_id,
        .payload_json = pl_v.string,
        .timestamp_ns = timestamp_ns,
    };
    // Octave escalation is the DEFAULT path for anything bigger than
    // the inline budget — no truncation, no rejection. ≤768B payloads
    // are byte-identical to the old encodeEntity path (full backward
    // compat); >768B payloads go to the octave-1 content store and the
    // cell carries a pointer descriptor.
    const enc = substrate_entity.encodeEntityEscalating(input) catch |err| switch (err) {
        substrate_entity.EncodeError.payload_too_large => {
            // Only reachable if even the pointer descriptor doesn't fit
            // (impossible in practice) — keep the explicit guard.
            std.debug.print("[entity_encode] reject: descriptor_too_large (tag={} len={})\n", .{ tag, pl_v.string.len });
            return verb_dispatcher.DispatchError.invalid_params;
        },
    };
    const cell = enc.cell;

    // Persist the overflow BEFORE the pointer cell so a reader can
    // never observe a dangling pointer. Escalation without a content
    // store wired is a hard error (never silently drop the body).
    if (enc.overflow) |overflow_bytes| {
        const cs = state.content_store orelse {
            std.debug.print("[entity_encode] reject: payload needs octave-1 escalation but no content store wired (tag={} len={})\n", .{ tag, pl_v.string.len });
            return verb_dispatcher.DispatchError.walker_failed;
        };
        cs.writeSlot(enc.slot, overflow_bytes) catch |err| {
            std.debug.print("[entity_encode] reject: octave-1 writeSlot failed ({s}) (tag={} slot={})\n", .{ @errorName(err), tag, enc.slot });
            return verb_dispatcher.DispatchError.walker_failed;
        };
    }

    // cell_id = sha256(cell_bytes). Mirrors the cell-engine convention
    // and matches what cell_store.put() computes internally — but the
    // store may be absent, so we compute it here unconditionally.
    var cell_id: [32]u8 = undefined;
    Sha256.hash(&cell, &cell_id, .{});

    var persisted = false;
    if (state.cell_store) |store| {
        const stored_id = store.put(&cell) catch |err| switch (err) {
            else => return verb_dispatcher.DispatchError.walker_failed,
        };
        // Defensive — sanity-check the store's id matches our own. If
        // it doesn't, we surface walker_failed so the operator can
        // investigate drift rather than silently accept divergence.
        if (!std.mem.eql(u8, &stored_id, &cell_id)) {
            return verb_dispatcher.DispatchError.walker_failed;
        }
        persisted = true;
    }

    const type_hash = substrate_entity.computeTypeHash(spec);
    return buildResult(allocator, &cell_id, &type_hash, tag, persisted) catch |err| switch (err) {
        error.OutOfMemory => verb_dispatcher.DispatchError.out_of_memory,
    };
}

// ─── Registration ────────────────────────────────────────────────────

/// Register the entity.encode walker into [registry]. CLI calls this
/// at brain boot alongside the oddjobz / jambox walker registrations.
pub fn registerInto(
    registry: *verb_dispatcher.Registry,
    state: *State,
) !void {
    try registry.register(.{
        .extension_id = "substrate",
        .verb = "entity.encode",
        .walker_fn = entityEncodeWalker,
        .ctx = @ptrCast(state),
    });
}

// ─── Helpers ─────────────────────────────────────────────────────────

fn parseLinearity(s: []const u8) ?substrate_entity.LinearityClass {
    if (std.mem.eql(u8, s, "linear")) return .linear;
    if (std.mem.eql(u8, s, "affine")) return .affine;
    if (std.mem.eql(u8, s, "relevant")) return .relevant;
    if (std.mem.eql(u8, s, "debug")) return .debug;
    return null;
}

fn decodeHex(in: []const u8, out: []u8) !void {
    if (in.len != out.len * 2) return error.bad_length;
    for (0..out.len) |i| {
        const hi = try nibble(in[i * 2]);
        const lo = try nibble(in[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

fn nibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.bad_hex,
    };
}

fn hexEncode(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, bytes.len * 2);
    const HEX = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = HEX[b >> 4];
        out[i * 2 + 1] = HEX[b & 0x0f];
    }
    return out;
}

fn buildResult(
    allocator: std.mem.Allocator,
    cell_id: *const [32]u8,
    type_hash: *const [32]u8,
    tag: u32,
    persisted: bool,
) ![]u8 {
    var body: std.ArrayList(u8) = .{};
    errdefer body.deinit(allocator);

    try body.appendSlice(allocator, "{\"cell_id\":\"");
    const cid_hex = try hexEncode(allocator, cell_id);
    defer allocator.free(cid_hex);
    try body.appendSlice(allocator, cid_hex);

    try body.appendSlice(allocator, "\",\"type_hash\":\"");
    const th_hex = try hexEncode(allocator, type_hash);
    defer allocator.free(th_hex);
    try body.appendSlice(allocator, th_hex);

    try body.appendSlice(allocator, "\",\"tag\":");
    try body.writer(allocator).print("{d}", .{tag});

    try body.appendSlice(allocator, ",\"persisted\":");
    try body.appendSlice(allocator, if (persisted) "true" else "false");

    try body.appendSlice(allocator, "}");
    return body.toOwnedSlice(allocator);
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

test "entityEncodeWalker rejects missing tag" {
    var state = State{};
    const params = "{\"linearity\":\"affine\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"{}\"}";
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        entityEncodeWalker(testing.allocator, &state, params),
    );
}

test "entityEncodeWalker rejects unknown tag" {
    var state = State{};
    const params = "{\"tag\":99,\"linearity\":\"affine\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"{}\"}";
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        entityEncodeWalker(testing.allocator, &state, params),
    );
}

test "entityEncodeWalker rejects bad linearity" {
    var state = State{};
    const params = "{\"tag\":7,\"linearity\":\"bogus\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"{}\"}";
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        entityEncodeWalker(testing.allocator, &state, params),
    );
}

test "entityEncodeWalker rejects malformed owner_id_hex" {
    var state = State{};
    const params = "{\"tag\":7,\"linearity\":\"affine\",\"owner_id_hex\":\"short\",\"payload_json\":\"{}\"}";
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        entityEncodeWalker(testing.allocator, &state, params),
    );
}

test "entityEncodeWalker rejects empty payload_json" {
    var state = State{};
    const params = "{\"tag\":7,\"linearity\":\"affine\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"\"}";
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        entityEncodeWalker(testing.allocator, &state, params),
    );
}

test "entityEncodeWalker: oversized payload without a content store fails (no dangling pointer)" {
    // Escalation replaces the old hard-reject. With no content store
    // wired the body can't be persisted, so the walker must fail
    // rather than mint a pointer to nothing.
    var state = State{};
    var huge: [1200]u8 = undefined;
    @memset(&huge, 'x');
    const payload = huge[0..900]; // > PAYLOAD_BUDGET (768)

    var params_buf: [1400]u8 = undefined;
    const params = try std.fmt.bufPrint(
        &params_buf,
        "{{\"tag\":7,\"linearity\":\"affine\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"{s}\"}}",
        .{payload},
    );
    try testing.expectError(
        verb_dispatcher.DispatchError.walker_failed,
        entityEncodeWalker(testing.allocator, &state, params),
    );
}

test "entityEncodeWalker: oversized payload WITH a content store escalates to octave-1" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const base = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(base);
    var cs = try content_store_local_fs.ContentStoreLocalFs.init(testing.allocator, base);
    defer cs.deinit();

    var state = State{ .content_store = &cs };
    var huge: [1200]u8 = undefined;
    @memset(&huge, 'x');
    const payload = huge[0..900];

    var params_buf: [1400]u8 = undefined;
    const params = try std.fmt.bufPrint(
        &params_buf,
        "{{\"tag\":7,\"linearity\":\"affine\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"{s}\"}}",
        .{payload},
    );
    const result = try entityEncodeWalker(testing.allocator, &state, params);
    defer testing.allocator.free(result);
    // Walker succeeds and returns a normal cell_id; the overflow is
    // now readable from the content store at the deterministic slot.
    try testing.expect(std.mem.indexOf(u8, result, "\"tag\":7") != null);
    const slot = substrate_entity.slotForPayload(payload);
    const got = try cs.readSlot(slot, testing.allocator);
    defer testing.allocator.free(got);
    try testing.expectEqualSlices(u8, payload, got);
}

test "entityEncodeWalker emits a 64-hex cell_id + type_hash for TAG_SITE" {
    var state = State{};
    const params = "{\"tag\":7,\"linearity\":\"affine\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"{\\\"lookup_key\\\":\\\"10 list lane brisbane qld 4000|\\\"}\",\"timestamp_ns\":1700000000000000000}";
    const result = try entityEncodeWalker(testing.allocator, &state, params);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\"tag\":7") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"persisted\":false") != null);
    // cell_id is 64 hex chars between quotes.
    const cid_marker = "\"cell_id\":\"";
    const cid_idx = std.mem.indexOf(u8, result, cid_marker).?;
    const hex_start = cid_idx + cid_marker.len;
    try testing.expectEqual(@as(u8, '"'), result[hex_start + 64]);
}

test "entityEncodeWalker emits stable cell_id for identical inputs (deterministic timestamp)" {
    var state = State{};
    const params = "{\"tag\":1,\"linearity\":\"affine\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"{\\\"name\\\":\\\"x\\\"}\",\"timestamp_ns\":1700000000000000000}";
    const r1 = try entityEncodeWalker(testing.allocator, &state, params);
    defer testing.allocator.free(r1);
    const r2 = try entityEncodeWalker(testing.allocator, &state, params);
    defer testing.allocator.free(r2);
    try testing.expectEqualStrings(r1, r2);
}

test "entityEncodeWalker different tags produce different type_hash" {
    var state = State{};
    const p_site = "{\"tag\":7,\"linearity\":\"affine\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"{}\",\"timestamp_ns\":0}";
    const p_cust = "{\"tag\":1,\"linearity\":\"affine\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"{}\",\"timestamp_ns\":0}";
    const r_site = try entityEncodeWalker(testing.allocator, &state, p_site);
    defer testing.allocator.free(r_site);
    const r_cust = try entityEncodeWalker(testing.allocator, &state, p_cust);
    defer testing.allocator.free(r_cust);
    // type_hash differs across SPECs.
    const th_marker = "\"type_hash\":\"";
    const th_site_idx = std.mem.indexOf(u8, r_site, th_marker).?;
    const th_cust_idx = std.mem.indexOf(u8, r_cust, th_marker).?;
    const th_site = r_site[th_site_idx + th_marker.len .. th_site_idx + th_marker.len + 64];
    const th_cust = r_cust[th_cust_idx + th_marker.len .. th_cust_idx + th_marker.len + 64];
    try testing.expect(!std.mem.eql(u8, th_site, th_cust));
}

test "registerInto wires the walker under (substrate, entity.encode)" {
    var state = State{};
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerInto(&reg, &state);

    const params = "{\"tag\":7,\"linearity\":\"affine\",\"owner_id_hex\":\"00000000000000000000000000000000\",\"payload_json\":\"{}\",\"timestamp_ns\":0}";
    const result = try reg.dispatch(testing.allocator, "substrate", "entity.encode", params);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"cell_id\":\"") != null);
}

// ── CC6.2 — adapter-config round-trip via verb.dispatch ──────────────
//
// Acceptance (`docs/design/CC6-SOURCE-ADAPTER-IMPL-SPEC.md` §6 row CC6.2):
//
//   > a source config round-trips as `verb.dispatch`→cell→read; no new
//   > endpoint; brain `zig build test -j1` exit 0
//
// CC6.2 design: adapter-config is a platform-level cell type
// (TAG_ADAPTER_CONFIG = 0x10, SPEC_ADAPTER_CONFIG). The substrate's
// `entity.encode` walker is the canonical persistence primitive — no
// new walker is added. Operator-meaningful intents like "configure
// source" live SHELL-SIDE and compose `verb.dispatch` →
// `substrate.entity.encode` with `tag = TAG_ADAPTER_CONFIG`. This keeps
// substrate verbs orthogonal (encode/get/query) and substrate-spine §5
// intact: domain semantics at the edge, primitives in the substrate.

test "CC6.2 — adapter-config cell round-trips through verb.dispatch (encode → decode → payload preserved)" {
    var state = State{};
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerInto(&reg, &state);

    // A representative adapter-config payload. JSON is escaped per the
    // intent envelope: payload_json is a STRING field, so inner quotes
    // are \\\".
    const params =
        "{\"tag\":16," ++
        "\"linearity\":\"relevant\"," ++
        "\"owner_id_hex\":\"abcdef0123456789abcdef0123456789\"," ++
        "\"payload_json\":\"{\\\"extensionId\\\":\\\"oddjobz\\\"," ++
        "\\\"sourceId\\\":\\\"todd-gmail-propertyme\\\"," ++
        "\\\"providerId\\\":\\\"gmail\\\"," ++
        "\\\"grammarId\\\":\\\"g-abc123\\\"," ++
        "\\\"status\\\":\\\"active\\\"," ++
        "\\\"metadata\\\":\\\"{}\\\"}\"," ++
        "\"timestamp_ns\":1700000000000000000}";
    const result = try reg.dispatch(testing.allocator, "substrate", "entity.encode", params);
    defer testing.allocator.free(result);

    // Walker returned the canonical envelope shape — tag echoed,
    // 64-hex cell_id and type_hash present.
    try testing.expect(std.mem.indexOf(u8, result, "\"tag\":16") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"cell_id\":\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"type_hash\":\"") != null);

    // Pull the cell_id out and verify it matches an independent encode
    // of the same input — this is the "→ cell → read" half of the
    // round-trip done deterministically without a backing store.
    const cid_marker = "\"cell_id\":\"";
    const cid_idx = std.mem.indexOf(u8, result, cid_marker).?;
    const cell_id_hex = result[cid_idx + cid_marker.len .. cid_idx + cid_marker.len + 64];

    const inner_payload =
        "{\"extensionId\":\"oddjobz\",\"sourceId\":\"todd-gmail-propertyme\"," ++
        "\"providerId\":\"gmail\",\"grammarId\":\"g-abc123\"," ++
        "\"status\":\"active\",\"metadata\":\"{}\"}";
    var owner_id: [16]u8 = undefined;
    try decodeHex("abcdef0123456789abcdef0123456789", &owner_id);
    const cell = try substrate_entity.encodeEntity(.{
        .spec = substrate_entity.SPEC_ADAPTER_CONFIG,
        .linearity = .relevant,
        .owner_id = owner_id,
        .payload_json = inner_payload,
        .timestamp_ns = 1_700_000_000_000_000_000,
    });
    var expected_id: [32]u8 = undefined;
    Sha256.hash(&cell, &expected_id, .{});
    const expected_hex = try hexEncode(testing.allocator, &expected_id);
    defer testing.allocator.free(expected_hex);
    try testing.expectEqualStrings(expected_hex, cell_id_hex);

    // Decode the cell directly — the payload bytes survive the
    // round-trip byte-for-byte, the linearity_class is `relevant`,
    // and the domain_flag is the adapter-config slot.
    const decoded = substrate_entity.decodeEntity(&cell);
    try testing.expect(decoded.magic_ok);
    try testing.expectEqual(substrate_entity.LinearityClass.relevant, decoded.linearity);
    try testing.expectEqual(substrate_entity.SPEC_ADAPTER_CONFIG.domain_flag, decoded.domain_flag);
    try testing.expectEqualSlices(u8, inner_payload, decoded.payload);
}

test "CC6.2 — adapter-config + AFFINE (draft) is accepted by the walker" {
    // CC6.1's draft-then-ratify pattern carries through: an
    // adapter-config emitted with `status:"draft"` rides AFFINE
    // linearity. The walker (substrate, encode-primitive) accepts any
    // linearity from the intent; the operator-ratification step
    // (shell-handler, CC6.3+) is what later supersedes with a RELEVANT
    // cell. Verify the AFFINE path round-trips identically.
    var state = State{};
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerInto(&reg, &state);

    const params =
        "{\"tag\":16,\"linearity\":\"affine\"," ++
        "\"owner_id_hex\":\"00000000000000000000000000000000\"," ++
        "\"payload_json\":\"{\\\"extensionId\\\":\\\"oddjobz\\\"," ++
        "\\\"sourceId\\\":\\\"draft-source\\\"," ++
        "\\\"status\\\":\\\"draft\\\"}\"," ++
        "\"timestamp_ns\":1700000000000000000}";
    const result = try reg.dispatch(testing.allocator, "substrate", "entity.encode", params);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"tag\":16") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"persisted\":false") != null);
}

```
