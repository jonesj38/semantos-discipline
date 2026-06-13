---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cartridge_cell_boot.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.221129+00:00
---

# runtime/semantos-brain/src/cartridge_cell_boot.zig

```zig
// BRAIN-GENERIC-MINT-VERB M1.d — cartridge cellType boot wiring.
//
// Reads a cartridge's `cartridge.json` `cellTypes[]` array, computes
// the canonical structured |8|8|8|8| typeHash for each entry via the
// kernel `buildTypeHash` primitive, and registers the result in
// `cartridge_cell_registry` so the generic mint handler can resolve
// typeHashes at request time.
//
// Lifetime contract:
//   - Strings stored in the registry are `[]const u8` references with
//     no embedded length-prefix or refcount; they must outlive every
//     mint request.  In practice this means "the brain process
//     lifetime."
//   - The boot module's `populate…` functions allocate every duped
//     string out of a CALLER-PROVIDED ArenaAllocator.  The caller owns
//     the arena.  In production (cmdServe) the arena is never deinit'd
//     — strings live for the brain process.  In tests the arena is
//     deinit'd at end-of-test for leak-free coverage.  Single
//     deallocation, no per-string bookkeeping.
//
// Failure posture:
//   - A malformed cartridge.json (bad JSON, missing required fields,
//     unknown linearity) is SKIPPED — the brain logs and continues.
//     A bad cartridge MUST NOT prevent the brain from booting.
//   - A typeHash collision between cartridges is fatal — that's a real
//     identity clash, not a tolerable misconfiguration. Surfaces as
//     `error.type_hash_collision` from the registry.
//
// What this does NOT do:
//   - Schema validation against a master cartridge.json schema (that's
//     M2's concern — structural-only Zig validation against each
//     cellType's `payloadSchema` happens at mint request time, not
//     boot).
//   - Capability sanity-checking — we read the cartridge's first
//     declared capability and use it as the per-cellType capability
//     name (Q-mint-3 = B per-cartridge gate).  When the cartridge
//     declares zero capabilities, capability_name is "" (registry's
//     "no capability check required" sentinel).

const std = @import("std");
const cartridge_cell_registry = @import("cartridge_cell_registry");
const type_hash = @import("type_hash");
const extension_manifest_loader = @import("extension_manifest_loader");
// C11 PR4a — cell-script handler load infrastructure. The boot
// path registers the substrate cellType (linearity, capability,
// payload schema) AND, when the manifest entry carries a `handler`
// field, additionally registers the verified script bytecode in
// the script-handler registry. Execution-side dispatch lands in
// PR4b.
const cell_script_handler_loader = @import("cell_script_handler_loader");

/// Maximum size of a `cartridge.json` file we'll parse.  1 MiB — same
/// as `extension_manifest_loader.MAX_MANIFEST_BYTES`.  A cartridge.json
/// larger than this is almost certainly something the operator should
/// look at by hand before the brain ingests it.
pub const MAX_CARTRIDGE_JSON_BYTES: usize = 1024 * 1024;

pub const BootError = error{
    /// JSON parse / shape failure surfaced as a soft skip via
    /// `populateRegistryFromExtensionsDir`; surfaced as hard for the
    /// `populateRegistryFromCartridgeJson` direct call so tests can
    /// assert on it.
    invalid_cartridge_json,
    /// cellTypes[] entry has unknown linearity — same defensive posture
    /// as substrate_entity.linearityFor (no silent flips).
    unknown_linearity,
    /// Two cellTypes in different cartridges produced the same typeHash.
    /// Always a real bug — let it surface.
    type_hash_collision,
    /// Registry capacity exceeded.
    registry_full,
    /// Filesystem I/O failure walking <data_dir>/extensions/.
    io_failed,
    /// Allocator failure duping strings into boot-lifetime storage.
    out_of_memory,
    /// C11 PR4a — a `cellTypes[i].handler` entry was structurally
    /// invalid AND the caller asked for hard-fail mode. The
    /// per-cartridge boot path (cf. `populateRegistryFromExtensionsDir`)
    /// soft-skips handler load failures and bumps a counter instead;
    /// only direct callers wanting strict semantics see this.
    handler_load_failed,
};

/// JSON shape the parser understands.  `std.json` ignores unknown
/// fields by default, so cartridges with extra metadata don't trip us.
const CartridgeJson = struct {
    id: []const u8,
    capabilities: ?[]const CapabilityJson = null,
    cellTypes: ?[]const CellTypeJson = null,
};

const CapabilityJson = struct {
    name: []const u8,
};

const TripleJson = struct {
    segment1: []const u8,
    segment2: []const u8,
    segment3: []const u8,
    segment4: []const u8,
};

const CellTypeJson = struct {
    name: []const u8,
    triple: TripleJson,
    linearity: []const u8,
    /// payloadSchema is opaque to the boot module; M2's validator
    /// parses it.  We capture as raw `std.json.Value` and re-stringify
    /// when persisting into the registry.
    payloadSchema: ?std.json.Value = null,
    /// C11 PR4a — optional handler block. When present, after the
    /// cellType is registered in `cartridge_cell_registry`, the
    /// boot loop hands the raw JSON value to
    /// `cell_script_handler_loader.loadHandler` which verifies
    /// scriptHash + registers the bytecode in
    /// `cell_script_handler_registry`. Shape:
    ///   { script, scriptHash, capabilities[], opcountBudget?,
    ///     emits[] }
    handler: ?std.json.Value = null,
};

/// Result of a single cartridge-json populate call. `cell_types` is
/// the count registered in `cartridge_cell_registry`; the two
/// handler fields cover the C11 PR4a script-handler registry.
pub const CartridgeJsonResult = struct {
    cell_types: usize,
    /// Handlers landed in `cell_script_handler_registry`.
    handlers_registered: usize = 0,
    /// Handlers that were present but failed to load (bad hex,
    /// scriptHash mismatch, missing required field). Soft-skipped
    /// rather than failing the whole cartridge boot.
    handlers_skipped: usize = 0,
};

/// Direct API — register every cellType in the supplied cartridge.json
/// bytes.  Returns a `CartridgeJsonResult` summarising what landed.
///
/// `boot_arena` owns the duped strings for every registered cellType
/// (cartridge_id, cell_type_name, capability_name, payload_schema_raw)
/// AND every duped slice owned by registered HandlerEntry values.
/// In production the arena is the brain-process-lifetime arena and
/// never deinit'd; in tests the caller deinits at end.
///
/// `cartridge_root_path` is the absolute filesystem path of the
/// cartridge directory. Reserved for follow-on script-handler
/// resolution; currently unused (pass `""`).
pub fn populateRegistryFromCartridgeJson(
    boot_arena: *std.heap.ArenaAllocator,
    cartridge_json: []const u8,
    cartridge_root_path: []const u8,
) BootError!CartridgeJsonResult {
    _ = cartridge_root_path;
    if (cartridge_json.len == 0) return error.invalid_cartridge_json;
    if (cartridge_json.len > MAX_CARTRIDGE_JSON_BYTES) return error.invalid_cartridge_json;

    const boot_alloc = boot_arena.allocator();

    // Parse into a scratch arena that goes away when we return — only
    // the dupes into `boot_arena` survive.
    var parse_scratch = std.heap.ArenaAllocator.init(boot_arena.child_allocator);
    defer parse_scratch.deinit();
    const scratch = parse_scratch.allocator();

    const parsed = std.json.parseFromSlice(CartridgeJson, scratch, cartridge_json, .{
        .ignore_unknown_fields = true,
    }) catch return error.invalid_cartridge_json;

    // Pull the per-cartridge capability name (Q-mint-3 = B: per-cartridge
    // gate).  First entry wins; absent capabilities[] → "" sentinel.
    const cartridge_id_dup = boot_alloc.dupe(u8, parsed.value.id) catch
        return error.out_of_memory;

    var capability_name_dup: []const u8 = "";
    if (parsed.value.capabilities) |caps| {
        if (caps.len > 0) {
            capability_name_dup = boot_alloc.dupe(u8, caps[0].name) catch
                return error.out_of_memory;
        }
    }

    const cell_types = parsed.value.cellTypes orelse return CartridgeJsonResult{ .cell_types = 0 };
    var result: CartridgeJsonResult = .{ .cell_types = 0 };

    for (cell_types) |ct| {
        const linearity = cartridge_cell_registry.Linearity.fromManifestString(ct.linearity) orelse
            return error.unknown_linearity;

        const hash = type_hash.buildTypeHash(
            ct.triple.segment1,
            ct.triple.segment2,
            ct.triple.segment3,
            ct.triple.segment4,
        );

        const name_dup = boot_alloc.dupe(u8, ct.name) catch
            return error.out_of_memory;

        var schema_dup: ?[]const u8 = null;
        if (ct.payloadSchema) |schema| {
            schema_dup = std.json.Stringify.valueAlloc(boot_alloc, schema, .{}) catch
                return error.out_of_memory;
        }

        cartridge_cell_registry.register(.{
            .type_hash = hash,
            .cartridge_id = cartridge_id_dup,
            .cell_type_name = name_dup,
            .linearity = linearity,
            .capability_name = capability_name_dup,
            .payload_schema_raw = schema_dup,
        }) catch |err| switch (err) {
            cartridge_cell_registry.RegisterError.type_hash_collision => return error.type_hash_collision,
            cartridge_cell_registry.RegisterError.registry_full => return error.registry_full,
        };
        result.cell_types += 1;

        // C11 PR4a — if the cellType declares a handler, hand the
        // raw JSON value to the script-handler loader.
        //
        // Soft-skip pattern: a malformed handler block bumps the
        // skipped counter + logs but doesn't fail the whole
        // cartridge boot. Operators can fix and re-install without
        // bouncing the brain. The two hard errors that DO surface
        // are typeHash collision and registry_full — same posture
        // as the cellType registry above (real structural problems).
        if (ct.handler) |hval| {
            cell_script_handler_loader.loadHandler(boot_alloc, hash, hval) catch |err| switch (err) {
                error.type_hash_collision => return error.type_hash_collision,
                error.registry_full => return error.registry_full,
                error.out_of_memory => return error.out_of_memory,
                else => {
                    std.log.warn(
                        "cartridge_cell_boot: script-handler load failed for cellType '{s}': {s}; skipping handler, cellType remains registered",
                        .{ ct.name, @errorName(err) },
                    );
                    result.handlers_skipped += 1;
                    continue;
                },
            };
            result.handlers_registered += 1;
        }
    }

    return result;
}

/// Convenience API — scan `<data_dir>/extensions/`, read each
/// cartridge.json found, and register its cellTypes.  Malformed
/// cartridges are SKIPPED (logged via `audit_log_fn` if supplied);
/// the function returns a `BootSummary` summarising what landed.
///
/// Used by `cmdServe` at brain boot, after extensions are installed
/// but before the HTTP server starts accepting requests.
pub const BootSummary = struct {
    cartridges_scanned: usize,
    cartridges_loaded: usize,
    cell_types_registered: usize,
    cartridges_skipped: usize,
    /// C11 PR4a — count of `cellTypes[i].handler` entries that landed
    /// in `cell_script_handler_registry`. Substrate state records
    /// (no handler) don't contribute.
    handlers_registered: usize = 0,
    /// C11 PR4a — count of `cellTypes[i].handler` entries that were
    /// present but failed to load (bad hex, scriptHash mismatch,
    /// missing required field, etc.). Bumped instead of failing the
    /// whole cartridge boot — operators can fix and re-install
    /// without bouncing the brain.
    handlers_skipped: usize = 0,
};

pub fn populateRegistryFromExtensionsDir(
    boot_arena: *std.heap.ArenaAllocator,
    scratch_allocator: std.mem.Allocator,
    data_dir_path: []const u8,
) BootError!BootSummary {
    var summary: BootSummary = .{
        .cartridges_scanned = 0,
        .cartridges_loaded = 0,
        .cell_types_registered = 0,
        .cartridges_skipped = 0,
        .handlers_registered = 0,
        .handlers_skipped = 0,
    };

    const manifests = extension_manifest_loader.loadAll(scratch_allocator, data_dir_path) catch |err| switch (err) {
        extension_manifest_loader.LoaderError.out_of_memory => return error.out_of_memory,
        else => return error.io_failed,
    };
    defer extension_manifest_loader.deinitManifests(scratch_allocator, manifests);

    for (manifests) |m| {
        summary.cartridges_scanned += 1;

        // Read this extension's cartridge.json.  Same file the manifest
        // loader already parsed — re-read here for the full cellTypes[]
        // array (loader only exposes the minimal top-level fields).
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const json_path = std.fmt.bufPrint(&path_buf, "{s}/cartridge.json", .{m.dir_path}) catch {
            summary.cartridges_skipped += 1;
            continue;
        };

        const json_file = std.fs.cwd().openFile(json_path, .{}) catch {
            summary.cartridges_skipped += 1;
            continue;
        };
        defer json_file.close();

        const stat = json_file.stat() catch {
            summary.cartridges_skipped += 1;
            continue;
        };
        if (stat.size == 0 or stat.size > MAX_CARTRIDGE_JSON_BYTES) {
            summary.cartridges_skipped += 1;
            continue;
        }

        const bytes = scratch_allocator.alloc(u8, stat.size) catch return error.out_of_memory;
        defer scratch_allocator.free(bytes);
        const n = json_file.readAll(bytes) catch {
            summary.cartridges_skipped += 1;
            continue;
        };
        if (n != bytes.len) {
            summary.cartridges_skipped += 1;
            continue;
        }

        const cartridge_result = populateRegistryFromCartridgeJson(boot_arena, bytes, m.dir_path) catch |err| switch (err) {
            // Soft skip on cartridge-content issues — operator can fix
            // and re-install without rebooting the brain.
            error.invalid_cartridge_json, error.unknown_linearity => {
                summary.cartridges_skipped += 1;
                continue;
            },
            // Hard fail on collision / capacity / OOM — these are
            // structural and must surface.
            error.type_hash_collision => return error.type_hash_collision,
            error.registry_full => return error.registry_full,
            error.out_of_memory => return error.out_of_memory,
            else => {
                summary.cartridges_skipped += 1;
                continue;
            },
        };
        summary.cartridges_loaded += 1;
        summary.cell_types_registered += cartridge_result.cell_types;
        summary.handlers_registered += cartridge_result.handlers_registered;
        summary.handlers_skipped += cartridge_result.handlers_skipped;
    }

    return summary;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — populate from JSON in isolation, then exercise the
// filesystem-walk path against a tmpDir fixture.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

const SAMPLE_CARTRIDGE_JSON =
    \\{
    \\  "id": "betterment",
    \\  "name": "Betterment",
    \\  "version": "0.1.0",
    \\  "description": "Test cartridge",
    \\  "capabilities": [{"id":1,"name":"BETTERMENT_INQUIRY","description":""}],
    \\  "cellTypes": [
    \\    {
    \\      "name": "betterment.practice.release",
    \\      "triple": {"segment1":"betterment","segment2":"practice","segment3":"release","segment4":""},
    \\      "linearity": "LINEAR"
    \\    },
    \\    {
    \\      "name": "betterment.practice.intention",
    \\      "triple": {"segment1":"betterment","segment2":"practice","segment3":"intention","segment4":""},
    \\      "linearity": "AFFINE",
    \\      "payloadSchema": {"text": {"type":"string"}}
    \\    }
    \\  ]
    \\}
;

test "populateRegistryFromCartridgeJson — round-trip 2 cellTypes" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try populateRegistryFromCartridgeJson(&arena, SAMPLE_CARTRIDGE_JSON, "");
    try testing.expectEqual(@as(usize, 2), r.cell_types);
    try testing.expectEqual(@as(usize, 0), r.handlers_registered);
    try testing.expectEqual(@as(usize, 0), r.handlers_skipped);
    try testing.expectEqual(@as(usize, 2), cartridge_cell_registry.count());

    // Recompute the typeHash for betterment.practice.release and look it up.
    const release_hash = type_hash.buildTypeHash("betterment", "practice", "release", "");
    const release = cartridge_cell_registry.lookup(&release_hash).?;
    try testing.expectEqualStrings("betterment", release.cartridge_id);
    try testing.expectEqualStrings("betterment.practice.release", release.cell_type_name);
    try testing.expectEqual(cartridge_cell_registry.Linearity.LINEAR, release.linearity);
    try testing.expectEqualStrings("BETTERMENT_INQUIRY", release.capability_name);
    try testing.expectEqual(@as(?[]const u8, null), release.payload_schema_raw);

    // betterment.practice.intention has a payloadSchema → re-stringified.
    const intention_hash = type_hash.buildTypeHash("betterment", "practice", "intention", "");
    const intention = cartridge_cell_registry.lookup(&intention_hash).?;
    try testing.expectEqual(cartridge_cell_registry.Linearity.AFFINE, intention.linearity);
    try testing.expect(intention.payload_schema_raw != null);
    try testing.expect(std.mem.indexOf(u8, intention.payload_schema_raw.?, "text") != null);
}

test "populateRegistryFromCartridgeJson — rejects malformed JSON" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(
        error.invalid_cartridge_json,
        populateRegistryFromCartridgeJson(&arena, "{ not valid", ""),
    );
}

test "populateRegistryFromCartridgeJson — rejects empty body" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(
        error.invalid_cartridge_json,
        populateRegistryFromCartridgeJson(&arena, "", ""),
    );
}

test "populateRegistryFromCartridgeJson — rejects oversize body" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const huge = "x" ** (MAX_CARTRIDGE_JSON_BYTES + 1);
    try testing.expectError(
        error.invalid_cartridge_json,
        populateRegistryFromCartridgeJson(&arena, huge, ""),
    );
}

test "populateRegistryFromCartridgeJson — rejects unknown linearity" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const bad =
        \\{
        \\  "id": "betterment",
        \\  "cellTypes": [{
        \\    "name": "betterment.bad",
        \\    "triple": {"segment1":"a","segment2":"b","segment3":"c","segment4":""},
        \\    "linearity": "BANANA"
        \\  }]
        \\}
    ;
    try testing.expectError(
        error.unknown_linearity,
        populateRegistryFromCartridgeJson(&arena, bad, ""),
    );
}

test "populateRegistryFromCartridgeJson — absent cellTypes returns 0" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const empty =
        \\{"id":"empty","version":"0.0.1","description":""}
    ;
    const r = try populateRegistryFromCartridgeJson(&arena, empty, "");
    try testing.expectEqual(@as(usize, 0), r.cell_types);
    try testing.expectEqual(@as(usize, 0), cartridge_cell_registry.count());
}

test "populateRegistryFromCartridgeJson — empty cellTypes[] returns 0" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const empty =
        \\{"id":"empty","cellTypes":[]}
    ;
    const r = try populateRegistryFromCartridgeJson(&arena, empty, "");
    try testing.expectEqual(@as(usize, 0), r.cell_types);
}

test "populateRegistryFromCartridgeJson — absent capabilities → empty capability_name" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const no_caps =
        \\{
        \\  "id": "substrate",
        \\  "cellTypes": [{
        \\    "name": "substrate.x",
        \\    "triple": {"segment1":"a","segment2":"b","segment3":"c","segment4":""},
        \\    "linearity": "PERSISTENT"
        \\  }]
        \\}
    ;
    _ = try populateRegistryFromCartridgeJson(&arena, no_caps, "");
    const h = type_hash.buildTypeHash("a", "b", "c", "");
    const entry = cartridge_cell_registry.lookup(&h).?;
    try testing.expectEqualStrings("", entry.capability_name);
    try testing.expectEqual(cartridge_cell_registry.Linearity.PERSISTENT, entry.linearity);
}

test "populateRegistryFromExtensionsDir — empty data_dir returns zero summary" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const s = try populateRegistryFromExtensionsDir(&arena, testing.allocator, tmp_path);
    try testing.expectEqual(@as(usize, 0), s.cartridges_scanned);
    try testing.expectEqual(@as(usize, 0), s.cell_types_registered);
    try testing.expectEqual(@as(usize, 0), s.handlers_registered);
}

test "populateRegistryFromExtensionsDir — reads one cartridge end-to-end" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Build `<tmp>/extensions/betterment/{cartridge.json,manifest.json}`.
    try tmp.dir.makePath("extensions/betterment");
    var ext_sub = try tmp.dir.openDir("extensions/betterment", .{});
    defer ext_sub.close();

    // extension_manifest_loader requires id matching dirname.
    var manifest = try ext_sub.createFile("cartridge.json", .{});
    try manifest.writeAll(SAMPLE_CARTRIDGE_JSON);
    manifest.close();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const s = try populateRegistryFromExtensionsDir(&arena, testing.allocator, tmp_path);
    try testing.expectEqual(@as(usize, 1), s.cartridges_scanned);
    try testing.expectEqual(@as(usize, 1), s.cartridges_loaded);
    try testing.expectEqual(@as(usize, 2), s.cell_types_registered);
    try testing.expectEqual(@as(usize, 0), s.cartridges_skipped);

    // Spot-check: the registered entries should be findable.
    const release_hash = type_hash.buildTypeHash("betterment", "practice", "release", "");
    try testing.expect(cartridge_cell_registry.lookup(&release_hash) != null);
}

test "populateRegistryFromExtensionsDir — skips a cartridge with broken JSON, processes a good one" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Good cartridge: extensions/good/cartridge.json with id="good"
    try tmp.dir.makePath("extensions/good");
    var good_sub = try tmp.dir.openDir("extensions/good", .{});
    defer good_sub.close();
    var good_file = try good_sub.createFile("cartridge.json", .{});
    try good_file.writeAll(
        \\{
        \\  "id": "good",
        \\  "name": "Good",
        \\  "version": "0.1.0",
        \\  "description": "ok",
        \\  "cellTypes": [{
        \\    "name": "good.x",
        \\    "triple": {"segment1":"good","segment2":"x","segment3":"y","segment4":""},
        \\    "linearity": "LINEAR"
        \\  }]
        \\}
    );
    good_file.close();

    // Broken cartridge: extensions/bad/cartridge.json with garbage
    try tmp.dir.makePath("extensions/bad");
    var bad_sub = try tmp.dir.openDir("extensions/bad", .{});
    defer bad_sub.close();
    var bad_file = try bad_sub.createFile("cartridge.json", .{});
    try bad_file.writeAll(
        \\{"id": "bad", "name": "Bad", "version": "0.1.0",
        \\ "cellTypes": [{
        \\  "name":"bad.x","triple":{"segment1":"a","segment2":"b","segment3":"c","segment4":""},
        \\  "linearity":"BANANA"
        \\}]}
    );
    bad_file.close();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const s = try populateRegistryFromExtensionsDir(&arena, testing.allocator, tmp_path);
    try testing.expectEqual(@as(usize, 2), s.cartridges_scanned);
    try testing.expectEqual(@as(usize, 1), s.cartridges_loaded);
    try testing.expectEqual(@as(usize, 1), s.cell_types_registered);
    try testing.expectEqual(@as(usize, 1), s.cartridges_skipped);

    // Confirm: good.x landed, bad.x didn't.
    const good_hash = type_hash.buildTypeHash("good", "x", "y", "");
    try testing.expect(cartridge_cell_registry.lookup(&good_hash) != null);
    const bad_hash = type_hash.buildTypeHash("a", "b", "c", "");
    try testing.expect(cartridge_cell_registry.lookup(&bad_hash) == null);
}

test "populateRegistryFromCartridgeJson — registers a cellType handler block" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // sha256 of [0x51] = OP_1, lowercase hex.
    const SCRIPT_BYTES = [_]u8{0x51};
    var script_hash_hex: [64]u8 = undefined;
    {
        var raw: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&SCRIPT_BYTES, &raw, .{});
        const HEX = "0123456789abcdef";
        for (raw, 0..) |b, i| {
            script_hash_hex[i * 2] = HEX[b >> 4];
            script_hash_hex[i * 2 + 1] = HEX[b & 0x0f];
        }
    }

    var json_buf: [1024]u8 = undefined;
    const json_text = try std.fmt.bufPrint(
        &json_buf,
        \\{{"id":"selftest","capabilities":[{{"name":"SELF_INQUIRY"}}],"cellTypes":[
        \\{{"name":"selftest.handler.intent","triple":{{"segment1":"selftest","segment2":"handler","segment3":"intent","segment4":""}},"linearity":"LINEAR","handler":{{"script":"51","scriptHash":"{s}","capabilities":["cap.bsv.beef.verify"],"emits":["selftest.handler.result"]}}}}
        \\]}}
    ,
        .{script_hash_hex[0..64]},
    );

    const r = try populateRegistryFromCartridgeJson(&arena, json_text, "");
    try testing.expectEqual(@as(usize, 1), r.cell_types);
    try testing.expectEqual(@as(usize, 1), r.handlers_registered);
    try testing.expectEqual(@as(usize, 0), r.handlers_skipped);

    // Both registries should have this typeHash.
    const h = type_hash.buildTypeHash("selftest", "handler", "intent", "");
    try testing.expect(cartridge_cell_registry.lookup(&h) != null);
    try testing.expectEqual(@as(usize, 1), cell_script_handler_loader.registryCountForTest());
}

test "populateRegistryFromCartridgeJson — bad handler block soft-skips, cellType remains" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_loader.resetRegistryForTest();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // scriptHash that doesn't match script bytes — loader rejects,
    // cartridge_cell_boot soft-skips, cellType still lands.
    const bad_json =
        \\{"id":"selftest","capabilities":[{"name":"SELF_INQUIRY"}],"cellTypes":[
        \\{"name":"selftest.bad.intent","triple":{"segment1":"selftest","segment2":"bad","segment3":"intent","segment4":""},"linearity":"LINEAR","handler":{"script":"51","scriptHash":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef","capabilities":["cap.x"],"emits":[]}}
        \\]}
    ;
    const r = try populateRegistryFromCartridgeJson(&arena, bad_json, "");
    try testing.expectEqual(@as(usize, 1), r.cell_types);
    try testing.expectEqual(@as(usize, 0), r.handlers_registered);
    try testing.expectEqual(@as(usize, 1), r.handlers_skipped);

    // cellType is registered; handler is NOT.
    const h = type_hash.buildTypeHash("selftest", "bad", "intent", "");
    try testing.expect(cartridge_cell_registry.lookup(&h) != null);
    try testing.expectEqual(@as(usize, 0), cell_script_handler_loader.registryCountForTest());
}


```
