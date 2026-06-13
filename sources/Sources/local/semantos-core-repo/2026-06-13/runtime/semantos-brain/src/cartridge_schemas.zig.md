---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cartridge_schemas.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.213362+00:00
---

# runtime/semantos-brain/src/cartridge_schemas.zig

```zig
// cartridge_schemas.zig — bridge between the manifest loader and the
// schema reader. Phase C of `admin create-cell`.
//
// The two underlying modules are deliberately decoupled:
//   • extension_manifest_loader.zig knows the filesystem convention
//     (`<data_dir>/extensions/<id>/cartridge.json` preferred, with
//     `manifest.json` as fallback) and parses cartridge meta.
//   • cartridge_schema.zig parses the `objectTypes[]` section given
//     raw cartridge JSON bytes.
//
// Bridging the two is "for every installed cartridge, hand me its
// declared types." That's what this module exposes:
//
//   pub fn loadAllInstalled(allocator, data_dir) ![]CartridgeSchemas
//   pub fn deinit(allocator, schemas)
//   pub fn findCartridge(schemas, id) ?*const CartridgeSchemas
//
// Consumers (admin_cmds.zig today; future cartridge-aware UIs) get a
// single read-only snapshot of every installed cartridge's typed
// surface without having to know either module's wire format.

const std = @import("std");
const loader = @import("extension_manifest_loader");
const schema = @import("cartridge_schema");

pub const LoadError = error{
    /// Underlying loader I/O / parse / size failure. Cartridges that
    /// loader-skip silently (malformed manifest etc.) don't surface
    /// here — only outright I/O failures from the loader bubble.
    loader_failed,
    /// A cartridge directory was discovered by the loader but the
    /// cartridge.json/manifest.json could not be re-read for schema
    /// parsing (e.g. removed between the two reads, permission denied).
    cartridge_read_failed,
    /// Cartridge JSON parsed by the loader but failed schema parsing
    /// (unknown linearity, unknown field type, missing required, etc.).
    /// The cartridge id is rendered into the audit hook (when wired).
    cartridge_schema_invalid,
    /// std.fs.path.join couldn't build a path.
    path_too_long,
    out_of_memory,
};

/// One installed cartridge's declared schema bundle.
pub const CartridgeSchemas = struct {
    /// Stable extension id (matches the directory name and the
    /// `id` field inside cartridge.json).
    cartridge_id: []const u8,
    /// Declared object types in declaration order.
    types: []schema.ObjectTypeSchema,
};

/// Scan `<data_dir>/extensions/` for every installed cartridge and
/// parse each one's declared schema. Returns a heap-allocated slice
/// caller must `deinit`.
pub fn loadAllInstalled(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
) LoadError![]CartridgeSchemas {
    const manifests = loader.loadAll(allocator, data_dir) catch return error.loader_failed;
    defer loader.deinitManifests(allocator, manifests);

    var list: std.ArrayList(CartridgeSchemas) = .empty;
    errdefer {
        for (list.items) |cs| deinitCartridge(allocator, cs);
        list.deinit(allocator);
    }

    for (manifests) |m| {
        const cs = try loadOneCartridge(allocator, m);
        list.append(allocator, cs) catch return error.out_of_memory;
    }

    return list.toOwnedSlice(allocator) catch return error.out_of_memory;
}

/// Free every heap allocation owned by a `[]CartridgeSchemas`.
pub fn deinit(allocator: std.mem.Allocator, schemas: []CartridgeSchemas) void {
    for (schemas) |cs| deinitCartridge(allocator, cs);
    allocator.free(schemas);
}

/// Lookup helper — find a cartridge by id within a loaded set.
/// Returns a pointer into the supplied slice; pointer is invalidated
/// when the slice is freed.
pub fn findCartridge(
    schemas: []const CartridgeSchemas,
    id: []const u8,
) ?*const CartridgeSchemas {
    for (schemas) |*cs| {
        if (std.mem.eql(u8, cs.cartridge_id, id)) return cs;
    }
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────

fn loadOneCartridge(
    allocator: std.mem.Allocator,
    m: loader.ExtensionManifest,
) LoadError!CartridgeSchemas {
    const bytes = readCartridgeJson(allocator, m.dir_path) catch
        return error.cartridge_read_failed;
    defer allocator.free(bytes);

    const types = schema.parseObjectTypes(allocator, bytes) catch
        return error.cartridge_schema_invalid;
    errdefer schema.deinitSchemas(allocator, types);

    const id_dup = allocator.dupe(u8, m.id) catch return error.out_of_memory;

    return CartridgeSchemas{
        .cartridge_id = id_dup,
        .types = types,
    };
}

fn deinitCartridge(allocator: std.mem.Allocator, cs: CartridgeSchemas) void {
    allocator.free(cs.cartridge_id);
    schema.deinitSchemas(allocator, cs.types);
}

/// Read `<dir>/cartridge.json` preferred, `<dir>/manifest.json` fallback.
/// Mirrors the loader's preference order (cartridge.json is the CC2b
/// canonical name; manifest.json is the legacy alias).
fn readCartridgeJson(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
) ![]u8 {
    const candidates = [_][]const u8{ "cartridge.json", "manifest.json" };
    for (candidates) |fname| {
        const file_path = std.fs.path.join(allocator, &.{ dir_path, fname }) catch
            return error.OutOfMemory;
        defer allocator.free(file_path);

        if (std.fs.cwd().openFile(file_path, .{})) |file| {
            defer file.close();
            return file.readToEndAlloc(allocator, schema.MAX_TYPES_PER_CARTRIDGE * 64 * 1024);
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
    }
    return error.FileNotFound;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

/// Write a cartridge dir with a cartridge.json into the given parent
/// `extensions/` dir. Mirrors the on-disk install layout the loader
/// expects.
fn writeCartridgeDir(
    parent: std.fs.Dir,
    id: []const u8,
    cartridge_json: []const u8,
) !void {
    var sub = try parent.makeOpenPath(id, .{});
    defer sub.close();
    var f = try sub.createFile("cartridge.json", .{});
    defer f.close();
    try f.writeAll(cartridge_json);
}

test "loadAllInstalled — empty data_dir/extensions returns empty slice" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const schemas = try loadAllInstalled(testing.allocator, tmp_path);
    defer deinit(testing.allocator, schemas);
    try testing.expectEqual(@as(usize, 0), schemas.len);
}

test "loadAllInstalled — single cartridge with declared types loads cleanly" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeCartridgeDir(ext, "np",
        \\{"id":"np","name":"NP","version":"0.1.0","objectTypes":[
        \\  {"typeHash":"00","name":"Fund","linearity":"RELEVANT","fields":[
        \\    {"name":"label","type":"string"}
        \\  ]}
        \\]}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const schemas = try loadAllInstalled(testing.allocator, tmp_path);
    defer deinit(testing.allocator, schemas);

    try testing.expectEqual(@as(usize, 1), schemas.len);
    try testing.expectEqualStrings("np", schemas[0].cartridge_id);
    try testing.expectEqual(@as(usize, 1), schemas[0].types.len);
    try testing.expectEqualStrings("Fund", schemas[0].types[0].name);
}

test "loadAllInstalled — cartridge.json preferred over manifest.json" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions/dual");
    var dual = try tmp.dir.openDir("extensions/dual", .{});
    defer dual.close();

    // Both files present; cartridge.json declares one type, manifest.json
    // declares another. Loader prefers cartridge.json — we should see
    // only the cartridge.json type.
    var cf = try dual.createFile("cartridge.json", .{});
    try cf.writeAll(
        \\{"id":"dual","name":"D","version":"1","objectTypes":[
        \\  {"typeHash":"00","name":"FromCartridge","linearity":"AFFINE","fields":[]}
        \\]}
    );
    cf.close();
    var mf = try dual.createFile("manifest.json", .{});
    try mf.writeAll(
        \\{"id":"dual","name":"D","version":"1","objectTypes":[
        \\  {"typeHash":"00","name":"FromManifest","linearity":"AFFINE","fields":[]}
        \\]}
    );
    mf.close();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const schemas = try loadAllInstalled(testing.allocator, tmp_path);
    defer deinit(testing.allocator, schemas);

    try testing.expectEqual(@as(usize, 1), schemas.len);
    try testing.expectEqual(@as(usize, 1), schemas[0].types.len);
    try testing.expectEqualStrings("FromCartridge", schemas[0].types[0].name);
}

test "loadAllInstalled — manifest.json fallback when cartridge.json absent" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions/legacy");
    var legacy = try tmp.dir.openDir("extensions/legacy", .{});
    defer legacy.close();
    var f = try legacy.createFile("manifest.json", .{});
    try f.writeAll(
        \\{"id":"legacy","name":"L","version":"1","objectTypes":[
        \\  {"typeHash":"00","name":"OldType","linearity":"AFFINE","fields":[]}
        \\]}
    );
    f.close();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const schemas = try loadAllInstalled(testing.allocator, tmp_path);
    defer deinit(testing.allocator, schemas);

    try testing.expectEqual(@as(usize, 1), schemas.len);
    try testing.expectEqualStrings("OldType", schemas[0].types[0].name);
}

test "loadAllInstalled — two cartridges both load with independent schemas" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();

    try writeCartridgeDir(ext, "alpha",
        \\{"id":"alpha","name":"A","version":"1","objectTypes":[
        \\  {"typeHash":"00","name":"AlphaType","linearity":"AFFINE","fields":[]}
        \\]}
    );
    try writeCartridgeDir(ext, "beta",
        \\{"id":"beta","name":"B","version":"2","objectTypes":[
        \\  {"typeHash":"00","name":"BetaType","linearity":"RELEVANT","fields":[]}
        \\]}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const schemas = try loadAllInstalled(testing.allocator, tmp_path);
    defer deinit(testing.allocator, schemas);

    try testing.expectEqual(@as(usize, 2), schemas.len);

    const alpha = findCartridge(schemas, "alpha") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("AlphaType", alpha.types[0].name);
    const beta = findCartridge(schemas, "beta") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("BetaType", beta.types[0].name);
    try testing.expect(findCartridge(schemas, "ghost") == null);
}

test "loadAllInstalled — schema-invalid cartridge surfaces typed error" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();

    // Loader accepts the manifest meta (id/name/version), but the
    // objectTypes section has an unknown linearity. parseObjectTypes
    // rejects it; we surface cartridge_schema_invalid.
    try writeCartridgeDir(ext, "bad",
        \\{"id":"bad","name":"B","version":"1","objectTypes":[
        \\  {"typeHash":"00","name":"X","linearity":"PHANTOM","fields":[]}
        \\]}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const result = loadAllInstalled(testing.allocator, tmp_path);
    try testing.expectError(error.cartridge_schema_invalid, result);
}

test "loadAllInstalled — cartridge with no objectTypes returns empty types slice" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();

    try writeCartridgeDir(ext, "metaonly",
        \\{"id":"metaonly","name":"M","version":"1","objectTypes":[]}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const schemas = try loadAllInstalled(testing.allocator, tmp_path);
    defer deinit(testing.allocator, schemas);

    try testing.expectEqual(@as(usize, 1), schemas.len);
    try testing.expectEqual(@as(usize, 0), schemas[0].types.len);
}

```
