---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cell_script_handler_loader.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.262340+00:00
---

# runtime/semantos-brain/src/cell_script_handler_loader.zig

```zig
// C11 PR4a — cell-script handler loader.
//
// Parses a `cellTypes[i].handler` entry (a parsed `std.json.Value`)
// from cartridge JSON, verifies `scriptHash` against `sha256(script)`,
// and registers the resulting HandlerEntry in
// `cell_script_handler_registry`.
//
// Manifest shape (mirror of the TS `HandlerDeclaration` interface in
// `core/protocol-types/src/extension-manifest.ts`, restored at
// commit f7d7c4d):
//
//   {
//     "script":        "<hex-encoded cell-engine bytecode>",
//     "scriptHash":    "<sha256 of script bytes, 64-char lowercase hex>",
//     "capabilities":  ["cap.bsv.beef.verify", "cap.bsv.header.read", ...],
//     "opcountBudget": 500000,        // optional, defaults to 500_000
//     "emits":         ["bsv.spv.verify.result", ...]
//   }
//
// PR4a scope ENDS at the loader: 4a does NOT execute any script.
// Dispatch wiring (typeHash → look up → cell-engine 2-PDA execute →
// drain emits → persist) lands in PR4b. The loader's contract is
// "the registry contains a verified HandlerEntry for every
// well-formed handler in every well-formed cartridge."
//
// Capability strings — for now we accept any non-empty string
// starting with `cap.`. We do NOT cross-check against
// `host_capability_table` because the table may not be initialised
// at the time `cartridge_cell_boot` runs (boot ordering). PR4b's
// dispatcher gates per-hostcall at execute time, when the table is
// guaranteed populated.

const std = @import("std");
const cell_script_handler_registry = @import("cell_script_handler_registry");

/// Default executor opcount budget when the manifest omits
/// `opcountBudget`. Matches the cell-engine executor's
/// `DEFAULT_MAX_OPS = 500_000` knob.
pub const DEFAULT_OPCOUNT_BUDGET: u32 = 500_000;

/// Required `capabilities[]` entry prefix. Any string failing this
/// test is rejected as `invalid_handler_json` — caller intent is
/// always `cap.<…>` per the manifest TS validator's
/// `/^[a-z][a-z0-9._-]*$/` (which `cap.…` matches; we use the
/// stricter "cap." prefix here as a defence-in-depth check for the
/// hostcall-tag namespace).
const CAPABILITY_PREFIX: []const u8 = "cap.";

pub const LoadError = error{
    /// Handler value isn't a JSON object, or a required field is
    /// missing / has the wrong JSON type / is empty.
    invalid_handler_json,
    /// `script` or `scriptHash` couldn't be decoded as hex (odd
    /// length, non-hex char).
    hex_decode_failed,
    /// Manifest's `scriptHash` doesn't match `sha256(script_bytes)`.
    script_hash_mismatch,
    /// Allocator failure duping bytes / strings into the boot
    /// arena.
    out_of_memory,
    /// Two cartridges declared handlers for the same typeHash.
    /// Bubbled up from the registry.
    type_hash_collision,
    /// Registry capacity exceeded.
    registry_full,
};

/// Load one handler, register in the script-handler registry.
///
/// `arena` is the boot-lifetime allocator that owns every
/// `[]const u8` field on the resulting HandlerEntry. In production
/// this is `cartridge_cell_boot`'s arena (never deinit'd); in tests
/// the caller deinits at end-of-test.
///
/// `type_hash` is the 32-byte structured typeHash for the cellType
/// declaring this handler. The caller (cartridge_cell_boot) has
/// already computed it.
///
/// `handler_value` is the JSON value for the `handler` field —
/// always an object per the manifest schema.
pub fn loadHandler(
    arena: std.mem.Allocator,
    type_hash: [32]u8,
    handler_value: std.json.Value,
) LoadError!void {
    // Step 1: must be an object.
    if (handler_value != .object) return error.invalid_handler_json;
    const obj = handler_value.object;

    // Step 2: pull required fields.
    const script_v = obj.get("script") orelse return error.invalid_handler_json;
    const script_hash_v = obj.get("scriptHash") orelse return error.invalid_handler_json;
    const capabilities_v = obj.get("capabilities") orelse return error.invalid_handler_json;
    const emits_v = obj.get("emits") orelse return error.invalid_handler_json;

    if (script_v != .string) return error.invalid_handler_json;
    if (script_hash_v != .string) return error.invalid_handler_json;
    if (capabilities_v != .array) return error.invalid_handler_json;
    if (emits_v != .array) return error.invalid_handler_json;

    const script_hex = script_v.string;
    const script_hash_hex = script_hash_v.string;
    if (script_hex.len == 0) return error.invalid_handler_json;
    if (script_hash_hex.len != 64) return error.hex_decode_failed;

    // Step 3: hex-decode script into arena-allocated bytes.
    if (script_hex.len % 2 != 0) return error.hex_decode_failed;
    const script_bytes = arena.alloc(u8, script_hex.len / 2) catch
        return error.out_of_memory;
    decodeHex(script_hex, script_bytes) catch return error.hex_decode_failed;

    // Step 4: compute sha256.
    var actual_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(script_bytes, &actual_hash, .{});

    // Step 5: hex-decode manifest's scriptHash and compare.
    var expected_hash: [32]u8 = undefined;
    decodeHex(script_hash_hex, &expected_hash) catch return error.hex_decode_failed;
    if (!std.mem.eql(u8, &actual_hash, &expected_hash)) return error.script_hash_mismatch;

    // Step 6: dup capabilities into arena.
    const caps_dup = dupStringArray(arena, capabilities_v.array.items, true) catch |err| switch (err) {
        error.out_of_memory => return error.out_of_memory,
        error.invalid_string => return error.invalid_handler_json,
    };

    // Step 7: dup emits into arena (no cap-prefix check).
    const emits_dup = dupStringArray(arena, emits_v.array.items, false) catch |err| switch (err) {
        error.out_of_memory => return error.out_of_memory,
        error.invalid_string => return error.invalid_handler_json,
    };

    // Step 8: opcountBudget (optional).
    var opcount_budget: u32 = DEFAULT_OPCOUNT_BUDGET;
    if (obj.get("opcountBudget")) |b| {
        switch (b) {
            .integer => |n| {
                if (n <= 0 or n > std.math.maxInt(u32)) return error.invalid_handler_json;
                opcount_budget = @intCast(n);
            },
            else => return error.invalid_handler_json,
        }
    }

    // Step 9: register.
    cell_script_handler_registry.register(type_hash, .{
        .script_bytes = script_bytes,
        .script_hash = actual_hash,
        .capabilities = caps_dup,
        .opcount_budget = opcount_budget,
        .emits = emits_dup,
    }) catch |err| switch (err) {
        cell_script_handler_registry.RegisterError.type_hash_collision => return error.type_hash_collision,
        cell_script_handler_registry.RegisterError.registry_full => return error.registry_full,
    };
}

const DupError = error{ out_of_memory, invalid_string };

fn dupStringArray(
    arena: std.mem.Allocator,
    items: []const std.json.Value,
    require_cap_prefix: bool,
) DupError![]const []const u8 {
    if (items.len == 0) {
        return @as([]const []const u8, &.{});
    }
    var out = arena.alloc([]const u8, items.len) catch return error.out_of_memory;
    for (items, 0..) |item, i| {
        if (item != .string) return error.invalid_string;
        const s = item.string;
        if (s.len == 0) return error.invalid_string;
        if (require_cap_prefix and !std.mem.startsWith(u8, s, CAPABILITY_PREFIX)) {
            return error.invalid_string;
        }
        out[i] = arena.dupe(u8, s) catch return error.out_of_memory;
    }
    return out;
}

const HexError = error{bad_hex};

fn decodeHex(hex: []const u8, out: []u8) HexError!void {
    if (hex.len != out.len * 2) return error.bad_hex;
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        const hi = nybble(hex[i * 2]) catch return error.bad_hex;
        const lo = nybble(hex[i * 2 + 1]) catch return error.bad_hex;
        out[i] = (hi << 4) | lo;
    }
}

fn nybble(c: u8) HexError!u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.bad_hex,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Test helpers — re-exports of registry test surfaces so consumers
// (cartridge_cell_boot.zig integration tests) can drive the loader
// without taking a direct dep on `cell_script_handler_registry`.
// ─────────────────────────────────────────────────────────────────────

pub fn resetRegistryForTest() void {
    cell_script_handler_registry.resetRegistryForTest();
}

pub fn registryCountForTest() usize {
    return cell_script_handler_registry.registryCountForTest();
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — JSON shape → registry round-trip.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn fakeHash(byte: u8) [32]u8 {
    var h: [32]u8 = undefined;
    @memset(&h, byte);
    return h;
}

fn sha256Hex(bytes: []const u8, out: *[64]u8) void {
    var raw: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &raw, .{});
    const HEX: []const u8 = "0123456789abcdef";
    for (raw, 0..) |b, i| {
        out[i * 2] = HEX[b >> 4];
        out[i * 2 + 1] = HEX[b & 0x0f];
    }
}

test "loadHandler — happy path round-trip" {
    resetRegistryForTest();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // script = OP_1 (0x51) — sha256 hex computed at test time.
    var script_hash_hex: [64]u8 = undefined;
    sha256Hex(&[_]u8{0x51}, &script_hash_hex);

    var json_buf: [256]u8 = undefined;
    const json_text = try std.fmt.bufPrint(
        &json_buf,
        "{{\"script\":\"51\",\"scriptHash\":\"{s}\",\"capabilities\":[\"cap.bsv.beef.verify\"],\"emits\":[\"bsv.spv.verify.result\"]}}",
        .{script_hash_hex[0..64]},
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json_text, .{});
    defer parsed.deinit();

    try loadHandler(arena, fakeHash(0xAA), parsed.value);

    try testing.expectEqual(@as(usize, 1), registryCountForTest());

    const h = fakeHash(0xAA);
    const entry = cell_script_handler_registry.lookup(&h).?;
    try testing.expectEqual(@as(usize, 1), entry.script_bytes.len);
    try testing.expectEqual(@as(u8, 0x51), entry.script_bytes[0]);
    try testing.expectEqual(@as(u32, DEFAULT_OPCOUNT_BUDGET), entry.opcount_budget);
    try testing.expectEqual(@as(usize, 1), entry.capabilities.len);
    try testing.expectEqualStrings("cap.bsv.beef.verify", entry.capabilities[0]);
    try testing.expectEqual(@as(usize, 1), entry.emits.len);
    try testing.expectEqualStrings("bsv.spv.verify.result", entry.emits[0]);
}

test "loadHandler — honours opcountBudget override" {
    resetRegistryForTest();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var script_hash_hex: [64]u8 = undefined;
    sha256Hex(&[_]u8{0x51}, &script_hash_hex);

    var json_buf: [256]u8 = undefined;
    const json_text = try std.fmt.bufPrint(
        &json_buf,
        "{{\"script\":\"51\",\"scriptHash\":\"{s}\",\"capabilities\":[\"cap.x\"],\"emits\":[],\"opcountBudget\":12345}}",
        .{script_hash_hex[0..64]},
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json_text, .{});
    defer parsed.deinit();

    try loadHandler(arena, fakeHash(0xAA), parsed.value);

    const h = fakeHash(0xAA);
    const entry = cell_script_handler_registry.lookup(&h).?;
    try testing.expectEqual(@as(u32, 12345), entry.opcount_budget);
    try testing.expectEqual(@as(usize, 0), entry.emits.len);
}

test "loadHandler — rejects scriptHash mismatch" {
    resetRegistryForTest();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // scriptHash is the sha256 of 0x52 but script bytes are 0x51.
    var wrong_hash_hex: [64]u8 = undefined;
    sha256Hex(&[_]u8{0x52}, &wrong_hash_hex);

    var json_buf: [256]u8 = undefined;
    const json_text = try std.fmt.bufPrint(
        &json_buf,
        "{{\"script\":\"51\",\"scriptHash\":\"{s}\",\"capabilities\":[\"cap.x\"],\"emits\":[]}}",
        .{wrong_hash_hex[0..64]},
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json_text, .{});
    defer parsed.deinit();

    try testing.expectError(
        error.script_hash_mismatch,
        loadHandler(arena, fakeHash(0xAA), parsed.value),
    );
    try testing.expectEqual(@as(usize, 0), registryCountForTest());
}

test "loadHandler — rejects missing required field (no scriptHash)" {
    resetRegistryForTest();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const json_text = "{\"script\":\"51\",\"capabilities\":[\"cap.x\"],\"emits\":[]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json_text, .{});
    defer parsed.deinit();

    try testing.expectError(
        error.invalid_handler_json,
        loadHandler(arena, fakeHash(0xAA), parsed.value),
    );
}

test "loadHandler — rejects non-object handler value" {
    resetRegistryForTest();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, "\"not-an-object\"", .{});
    defer parsed.deinit();

    try testing.expectError(
        error.invalid_handler_json,
        loadHandler(arena, fakeHash(0xAA), parsed.value),
    );
}

test "loadHandler — rejects bad hex in script" {
    resetRegistryForTest();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var script_hash_hex: [64]u8 = undefined;
    sha256Hex(&[_]u8{0x51}, &script_hash_hex);

    var json_buf: [256]u8 = undefined;
    // "ZZ" is non-hex.
    const json_text = try std.fmt.bufPrint(
        &json_buf,
        "{{\"script\":\"ZZ\",\"scriptHash\":\"{s}\",\"capabilities\":[\"cap.x\"],\"emits\":[]}}",
        .{script_hash_hex[0..64]},
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json_text, .{});
    defer parsed.deinit();

    try testing.expectError(
        error.hex_decode_failed,
        loadHandler(arena, fakeHash(0xAA), parsed.value),
    );
}

test "loadHandler — rejects capability without cap. prefix" {
    resetRegistryForTest();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var script_hash_hex: [64]u8 = undefined;
    sha256Hex(&[_]u8{0x51}, &script_hash_hex);

    var json_buf: [256]u8 = undefined;
    const json_text = try std.fmt.bufPrint(
        &json_buf,
        "{{\"script\":\"51\",\"scriptHash\":\"{s}\",\"capabilities\":[\"bsv.beef.verify\"],\"emits\":[]}}",
        .{script_hash_hex[0..64]},
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json_text, .{});
    defer parsed.deinit();

    try testing.expectError(
        error.invalid_handler_json,
        loadHandler(arena, fakeHash(0xAA), parsed.value),
    );
}

```
