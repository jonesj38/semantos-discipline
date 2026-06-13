---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/extension_manifest_loader.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.256468+00:00
---

# runtime/semantos-brain/src/extension_manifest_loader.zig

```zig
// DLO.1a — Generic cartridge manifest loader.
//
// Reference: docs/prd/D-LIFT-ODDJOBZ.md §Deliverables / DLO.1a;
//            docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md §10.3 (D-Lift-oddjobz deliverable);
//            core/protocol-types/src/extension-manifest.ts (Phase 36A config.json shape).
//
// ── What this module is ──────────────────────────────────────────────
//
// Scans `<data_dir>/extensions/` for subdirectories; for each subdir, reads
// `manifest.json`, parses it, validates basic shape, returns the list. This
// is the generic loader that supersedes the hardcoded oddjobz pass in
// `extensions.zig` per DECISION-2 (full D-W1 user-installed loader scope).
//
// Behavior contract:
//   • Empty `<data_dir>/extensions/` (no subdirs)        → returns empty slice, no error
//   • Subdir with valid manifest.json                    → parsed + appended
//   • Subdir with missing manifest.json                  → skip + audit warning
//   • Subdir with malformed JSON                         → skip + audit warning
//   • Subdir with schema-invalid manifest                → skip + audit warning
//   • ID collision across two manifests                  → error.duplicate_extension_id
//   • Reserved/unsafe id (path traversal, empty string)  → error.invalid_extension_id
//
// The caller owns the returned slice and each manifest's heap-allocated
// string fields via the supplied allocator. Call deinitManifest(allocator, &m)
// to free.

const std = @import("std");

/// Maximum manifest.json size — pathological manifests are rejected.
pub const MAX_MANIFEST_BYTES: u64 = 1024 * 1024; // 1 MiB
/// Maximum number of extensions loadable per data_dir. Pathological prevention.
pub const MAX_EXTENSIONS: usize = 256;

pub const LoaderError = error{
    /// Two manifests declared the same `id`.
    duplicate_extension_id,
    /// Manifest's `id` field violates the safe-id contract (empty, path-traversal, etc.).
    invalid_extension_id,
    /// Manifest.json present but exceeds MAX_MANIFEST_BYTES.
    manifest_too_large,
    /// Exceeded MAX_EXTENSIONS limit while scanning.
    too_many_extensions,
    /// Underlying allocator failed.
    out_of_memory,
    /// I/O failure while scanning data_dir or reading manifest files.
    io_failed,
};

/// Minimal Phase 36A ExtensionManifest fields the loader requires.
/// Optional fields (taxonomyPath, flowsDir, etc.) are parsed but not
/// surfaced here — handlers consuming the loaded manifest re-parse the
/// raw JSON for their domain-specific fields. This keeps the substrate
/// contract narrow.
pub const ExtensionManifest = struct {
    /// Stable extension id. Must match the directory name (`extensions/<id>/`).
    id: []const u8,
    /// Human-readable name.
    name: []const u8,
    /// Semver version string.
    version: []const u8,
    /// Optional description.
    description: ?[]const u8,
    /// Absolute path to the extension's directory on disk.
    /// Useful for subsequent loaders (capabilities path, walker bundle path).
    dir_path: []const u8,
    /// CC0a/CC2b — canonical cartridge role
    /// (`infra`|`experience`|`grammar-lexicon`). null for legacy
    /// manifests with no `role`.
    role: ?[]const u8 = null,
    /// CC3 binding — the cartridge's PWA-experience Flutter package
    /// (`experience.flutterPackage`), surfaced for the Brain→PWA
    /// discovery endpoint so the shell loads the right surface.
    experience_flutter_package: ?[]const u8 = null,
    /// C5 PR-5a (2026-05-28) — cartridge-supplied brain handlers.
    /// Each entry names a .zig module under cartridges/<id>/brain/zig/
    /// and the entry-point function exported by that module (default
    /// "registerInto"). The boot loader in cli/serve.zig dispatches to
    /// each entry's registerInto(disp, verb_registry, allocator, &deps)
    /// in place of hardcoded register() calls. Optional — PWA-only
    /// cartridges omit it. See docs/design/BRAIN-EXTENSION-LOADER.md §2.
    brain_handlers: []const BrainHandlerDecl = &.{},
    /// SH1 (svelte-helm matrix, DECISION D9) — the DECLARATIVE UI layer,
    /// promoted into cartridge.json so the brain is the single source of
    /// truth for /api/v1/cartridges. `surfacing_mode` is the SEMANTIC
    /// surface intent ("default"|"dedicated"|"passive"), not a layout;
    /// `ui_verbs` is the form-factor-agnostic verb vocabulary each helm
    /// renders into its own real estate. Per-helm RENDERING
    /// (chrome/layout/bespoke views) is deliberately NOT here. Legacy
    /// `ui` blocks ({primaryAnchor, hierarchy}) leave both at the default.
    surfacing_mode: ?[]const u8 = null,
    ui_verbs: []const UiVerbDecl = &.{},
};

/// C5 PR-5a — one declared brain handler the cartridge ships.
pub const BrainHandlerDecl = struct {
    /// .zig module name under cartridges/<id>/brain/zig/ (without .zig).
    /// Build-time discovery uses this to resolve the comptime module ref.
    module: []const u8,
    /// Entry-point function exported by `module`. Default "registerInto".
    /// Lets a cartridge colocate multiple handlers in one .zig file by
    /// exporting per-handler entry-points (e.g. "registerJobs",
    /// "registerCustomers").
    register_into: []const u8,
};

/// SH1 (DECISION D9) — one declarative UI verb the cartridge surfaces.
/// Matches the Flutter manifest verb shape; form-factor-agnostic (nothing
/// here is positional — each helm decides how to render it).
pub const UiVerbDecl = struct {
    /// Semantic modal bucket: "do" | "talk" | "find".
    modal: []const u8,
    /// Operator-facing label (e.g. "New job").
    label: []const u8,
    /// Intent the helm dispatches (REPL verb / cell mint), e.g.
    /// "oddjobz.job.create".
    intent_type: []const u8,
    /// Optional one-line subtitle.
    subtitle: ?[]const u8 = null,
    /// Optional named glyph (semantic, not a pixel position).
    icon: ?[]const u8 = null,
    /// SH14 / D12 — hat role this verb is visible to: "operator" (default,
    /// every hat) | "admin" (+managerial). Always owned; defaults to
    /// "operator" when the manifest omits it (fail-safe: never elevates).
    role: []const u8 = "operator",
};

pub fn deinitManifest(allocator: std.mem.Allocator, m: *const ExtensionManifest) void {
    allocator.free(m.id);
    allocator.free(m.name);
    allocator.free(m.version);
    if (m.description) |d| allocator.free(d);
    allocator.free(m.dir_path);
    if (m.role) |r| allocator.free(r);
    if (m.experience_flutter_package) |e| allocator.free(e);
    // C5 PR-5a — free each brain_handler entry's owned strings.
    for (m.brain_handlers) |h| {
        allocator.free(h.module);
        allocator.free(h.register_into);
    }
    if (m.brain_handlers.len > 0) allocator.free(m.brain_handlers);
    // SH1 (DECISION D9) — free the declarative UI block.
    if (m.surfacing_mode) |s| allocator.free(s);
    for (m.ui_verbs) |v| {
        allocator.free(v.modal);
        allocator.free(v.label);
        allocator.free(v.intent_type);
        if (v.subtitle) |s| allocator.free(s);
        if (v.icon) |ic| allocator.free(ic);
        allocator.free(v.role);
    }
    if (m.ui_verbs.len > 0) allocator.free(m.ui_verbs);
}

pub fn deinitManifests(allocator: std.mem.Allocator, list: []ExtensionManifest) void {
    for (list) |*m| deinitManifest(allocator, m);
    allocator.free(list);
}

/// JSON parsing helper struct — captures only the fields we surface,
/// std.json ignores unknown fields by default.
const ManifestJson = struct {
    id: []const u8,
    name: []const u8,
    version: []const u8,
    description: ?[]const u8 = null,
    // CC0a canonical cartridge.json fields (std.json ignores unknown,
    // so optional defaults keep legacy manifests parsing).
    role: ?[]const u8 = null,
    experience: ?struct { flutterPackage: []const u8 } = null,
    // C5 PR-5a — optional brain.handlers[] block declaring cartridge-
    // owned brain handler modules. Cartridges without brain code omit.
    brain: ?BrainBlockJson = null,
    // SH1 (DECISION D9) — optional declarative UI block. Legacy `ui`
    // blocks ({primaryAnchor, hierarchy}) parse fine: unknown fields are
    // ignored, surfacingMode/verbs fall back to null/empty.
    ui: ?UiBlockJson = null,
};

const BrainBlockJson = struct {
    handlers: []const BrainHandlerJson = &.{},
};

const BrainHandlerJson = struct {
    module: []const u8,
    /// JSON field is "registerInto" (camelCase to match cartridge.json
    /// convention). Default lands in the loader if the field is omitted.
    registerInto: ?[]const u8 = null,
};

const UiBlockJson = struct {
    surfacingMode: ?[]const u8 = null,
    verbs: []const UiVerbJson = &.{},
};

const UiVerbJson = struct {
    modal: []const u8,
    label: []const u8,
    intentType: []const u8,
    subtitle: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    role: ?[]const u8 = null,
};

/// `id` safe-shape check. Rejects empty, slashes, parent-dir escapes, dots-only,
/// hidden-dir style starts, control chars. Allows: letters, digits, hyphen, underscore.
fn isValidId(id: []const u8) bool {
    if (id.len == 0) return false;
    if (id.len > 128) return false;
    if (std.mem.eql(u8, id, ".") or std.mem.eql(u8, id, "..")) return false;
    if (id[0] == '.') return false;
    for (id) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or c == '-' or c == '_';
        if (!ok) return false;
    }
    return true;
}

/// Scan `<data_dir>/extensions/` and load every well-formed manifest.
/// Returns a heap-allocated slice; caller must deinitManifests().
pub fn loadAll(allocator: std.mem.Allocator, data_dir_path: []const u8) LoaderError![]ExtensionManifest {
    var list = std.ArrayList(ExtensionManifest).empty;
    errdefer {
        for (list.items) |*m| deinitManifest(allocator, m);
        list.deinit(allocator);
    }

    // Build the extensions/ subpath. data_dir_path is the operator's data dir.
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const ext_path = std.fmt.bufPrint(&path_buf, "{s}/extensions", .{data_dir_path}) catch return error.io_failed;

    var ext_dir = std.fs.cwd().openDir(ext_path, .{ .iterate = true }) catch |err| switch (err) {
        // No extensions dir = zero cartridges loaded; this is a valid configuration.
        error.FileNotFound => return list.toOwnedSlice(allocator) catch return error.out_of_memory,
        else => return error.io_failed,
    };
    defer ext_dir.close();

    var it = ext_dir.iterate();
    var count: usize = 0;
    while (it.next() catch return error.io_failed) |entry| {
        if (entry.kind != .directory) {
            if (entry.kind != .sym_link) continue;
            // Verify the symlink resolves to a directory; skip broken links and file symlinks.
            var sym_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const sym_path = std.fmt.bufPrint(&sym_path_buf, "{s}/{s}", .{ ext_path, entry.name }) catch return error.io_failed;
            var sym_dir = std.fs.cwd().openDir(sym_path, .{}) catch continue;
            sym_dir.close();
        }
        if (count >= MAX_EXTENSIONS) return error.too_many_extensions;
        count += 1;

        // Directory entry name is the candidate id.
        if (!isValidId(entry.name)) continue; // skip; not a valid extension dir

        // CC2b: canonical `cartridge.json` preferred; legacy
        // `manifest.json` fallback (CC4 collapses the rest).
        var manifest_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const manifest_file = blk: {
            for ([_][]const u8{ "cartridge.json", "manifest.json" }) |fname| {
                const p = std.fmt.bufPrint(&manifest_path_buf, "{s}/{s}/{s}", .{ ext_path, entry.name, fname }) catch return error.io_failed;
                if (std.fs.cwd().openFile(p, .{})) |f| {
                    break :blk f;
                } else |err| switch (err) {
                    error.FileNotFound => {},
                    else => return error.io_failed,
                }
            }
            continue; // neither present, skip silently
        };
        defer manifest_file.close();

        const stat = manifest_file.stat() catch return error.io_failed;
        if (stat.size > MAX_MANIFEST_BYTES) return error.manifest_too_large;

        const bytes = allocator.alloc(u8, stat.size) catch return error.out_of_memory;
        defer allocator.free(bytes);
        const n = manifest_file.readAll(bytes) catch return error.io_failed;
        if (n != bytes.len) return error.io_failed;

        const parsed = std.json.parseFromSlice(ManifestJson, allocator, bytes, .{
            .ignore_unknown_fields = true,
        }) catch |err| {
            std.log.warn(
                "extension_manifest_loader: skipping {s}/{s}: JSON parse failed ({s}) — check required fields: id, name, version",
                .{ ext_path, entry.name, @errorName(err) },
            );
            continue;
        };
        defer parsed.deinit();

        // Schema check: id must match directory name (prevents shadowing).
        if (!std.mem.eql(u8, parsed.value.id, entry.name)) {
            std.log.warn(
                "extension_manifest_loader: skipping {s}/{s}: manifest id \"{s}\" does not match directory name",
                .{ ext_path, entry.name, parsed.value.id },
            );
            continue;
        }
        if (!isValidId(parsed.value.id)) return error.invalid_extension_id;

        // Collision check: id must not already be in the list.
        for (list.items) |existing| {
            if (std.mem.eql(u8, existing.id, parsed.value.id)) return error.duplicate_extension_id;
        }

        // Build the dir_path for downstream consumers.
        var dir_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const dir_path = std.fmt.bufPrint(&dir_path_buf, "{s}/{s}", .{ ext_path, entry.name }) catch return error.io_failed;

        // C5 PR-5a — own-copy brain.handlers[] entries (resolve
        // registerInto default + dupe strings into our allocator).
        var brain_handlers: []BrainHandlerDecl = &.{};
        if (parsed.value.brain) |brain_block| {
            if (brain_block.handlers.len > 0) {
                brain_handlers = allocator.alloc(BrainHandlerDecl, brain_block.handlers.len) catch
                    return error.out_of_memory;
                errdefer allocator.free(brain_handlers);
                for (brain_block.handlers, 0..) |h, i| {
                    const reg_into = h.registerInto orelse "registerInto";
                    brain_handlers[i] = .{
                        .module = allocator.dupe(u8, h.module) catch return error.out_of_memory,
                        .register_into = allocator.dupe(u8, reg_into) catch return error.out_of_memory,
                    };
                }
            }
        }

        // SH1 (DECISION D9) — own-copy the declarative UI block.
        var surfacing_mode: ?[]const u8 = null;
        var ui_verbs: []UiVerbDecl = &.{};
        if (parsed.value.ui) |ui_block| {
            if (ui_block.surfacingMode) |sm| {
                surfacing_mode = allocator.dupe(u8, sm) catch return error.out_of_memory;
            }
            errdefer {
                if (surfacing_mode) |s| allocator.free(s);
            }
            if (ui_block.verbs.len > 0) {
                ui_verbs = allocator.alloc(UiVerbDecl, ui_block.verbs.len) catch return error.out_of_memory;
                errdefer allocator.free(ui_verbs);
                for (ui_block.verbs, 0..) |v, i| {
                    // SH14 / D12 — role defaults to "operator" when omitted or
                    // not the literal "admin" (fail-safe: unknown never elevates).
                    const role_in = v.role orelse "operator";
                    const role_norm: []const u8 = if (std.mem.eql(u8, role_in, "admin")) "admin" else "operator";
                    ui_verbs[i] = .{
                        .modal = allocator.dupe(u8, v.modal) catch return error.out_of_memory,
                        .label = allocator.dupe(u8, v.label) catch return error.out_of_memory,
                        .intent_type = allocator.dupe(u8, v.intentType) catch return error.out_of_memory,
                        .subtitle = if (v.subtitle) |s| (allocator.dupe(u8, s) catch return error.out_of_memory) else null,
                        .icon = if (v.icon) |ic| (allocator.dupe(u8, ic) catch return error.out_of_memory) else null,
                        .role = allocator.dupe(u8, role_norm) catch return error.out_of_memory,
                    };
                }
            }
        }

        const m = ExtensionManifest{
            .id = allocator.dupe(u8, parsed.value.id) catch return error.out_of_memory,
            .name = allocator.dupe(u8, parsed.value.name) catch return error.out_of_memory,
            .version = allocator.dupe(u8, parsed.value.version) catch return error.out_of_memory,
            .description = if (parsed.value.description) |d| (allocator.dupe(u8, d) catch return error.out_of_memory) else null,
            .dir_path = allocator.dupe(u8, dir_path) catch return error.out_of_memory,
            .role = if (parsed.value.role) |r| (allocator.dupe(u8, r) catch return error.out_of_memory) else null,
            .experience_flutter_package = if (parsed.value.experience) |e| (allocator.dupe(u8, e.flutterPackage) catch return error.out_of_memory) else null,
            .brain_handlers = brain_handlers,
            .surfacing_mode = surfacing_mode,
            .ui_verbs = ui_verbs,
        };
        list.append(allocator, m) catch return error.out_of_memory;
    }

    return list.toOwnedSlice(allocator) catch return error.out_of_memory;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

fn writeManifestFile(allocator: std.mem.Allocator, dir: std.fs.Dir, name: []const u8, contents: []const u8) !void {
    _ = allocator;
    var sub = try dir.makeOpenPath(name, .{});
    defer sub.close();
    var file = try sub.createFile("manifest.json", .{});
    defer file.close();
    try file.writeAll(contents);
}

test "isValidId — accepts canonical extension ids" {
    try std.testing.expect(isValidId("oddjobz"));
    try std.testing.expect(isValidId("bsv-anchor-bundle"));
    try std.testing.expect(isValidId("jam_room"));
    try std.testing.expect(isValidId("ext123"));
}

test "isValidId — rejects path-traversal and empty ids" {
    try std.testing.expect(!isValidId(""));
    try std.testing.expect(!isValidId("."));
    try std.testing.expect(!isValidId(".."));
    try std.testing.expect(!isValidId(".hidden"));
    try std.testing.expect(!isValidId("a/b"));
    try std.testing.expect(!isValidId("a\\b"));
    try std.testing.expect(!isValidId("with space"));
    try std.testing.expect(!isValidId("with.dot"));
}

test "loadAll — missing data_dir/extensions returns empty list" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "loadAll — empty extensions/ dir returns empty list" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "loadAll — one valid manifest loads cleanly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext_dir = try tmp.dir.openDir("extensions", .{});
    defer ext_dir.close();

    try writeManifestFile(allocator, ext_dir, "oddjobz",
        \\{"id":"oddjobz","name":"Oddjobz","version":"1.0.0","description":"trades vertical"}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("oddjobz", result[0].id);
    try std.testing.expectEqualStrings("Oddjobz", result[0].name);
    try std.testing.expectEqualStrings("1.0.0", result[0].version);
    try std.testing.expectEqualStrings("trades vertical", result[0].description.?);
}

test "loadAll — malformed JSON is skipped silently" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext_dir = try tmp.dir.openDir("extensions", .{});
    defer ext_dir.close();

    try writeManifestFile(allocator, ext_dir, "broken", "{ not valid json");
    try writeManifestFile(allocator, ext_dir, "good",
        \\{"id":"good","name":"Good","version":"0.1.0"}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("good", result[0].id);
}

test "loadAll — id-mismatch-with-dirname is skipped" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext_dir = try tmp.dir.openDir("extensions", .{});
    defer ext_dir.close();

    // Directory "foo" with manifest claiming id "bar" — anti-shadowing.
    try writeManifestFile(allocator, ext_dir, "foo",
        \\{"id":"bar","name":"Bar","version":"0.1.0"}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "loadAll — missing manifest.json is skipped" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions/lonely");

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "loadAll — two manifests with distinct ids both load" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext_dir = try tmp.dir.openDir("extensions", .{});
    defer ext_dir.close();

    try writeManifestFile(allocator, ext_dir, "alpha",
        \\{"id":"alpha","name":"Alpha","version":"0.1.0"}
    );
    try writeManifestFile(allocator, ext_dir, "beta",
        \\{"id":"beta","name":"Beta","version":"0.2.0"}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);

    try std.testing.expectEqual(@as(usize, 2), result.len);
}

test "loadAll — symlink to extension directory is discovered correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    try tmp.dir.makePath("real-ext");

    // Write manifest inside the real (non-extensions/) directory.
    var real_ext = try tmp.dir.openDir("real-ext", .{});
    defer real_ext.close();
    var mf = try real_ext.createFile("manifest.json", .{});
    defer mf.close();
    try mf.writeAll(
        \\{"id":"my-ext","name":"My Ext","version":"1.0.0"}
    );

    // Resolve absolute path for the symlink target.
    var real_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real_path = try tmp.dir.realpath("real-ext", &real_buf);

    // Create extensions/my-ext -> real_path (absolute symlink).
    var ext_dir = try tmp.dir.openDir("extensions", .{});
    defer ext_dir.close();
    try ext_dir.symLink(real_path, "my-ext", .{});

    var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &tmp_buf);

    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("my-ext", result[0].id);
    try std.testing.expectEqualStrings("My Ext", result[0].name);
}

// ─────────────────────────────────────────────────────────────────────
// C5 PR-5a tests — brain.handlers[] parsing
// ─────────────────────────────────────────────────────────────────────

test "loadAll — brain.handlers[] absent → empty list (PWA-only cartridge)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext_dir = try tmp.dir.openDir("extensions", .{});
    defer ext_dir.close();

    // Cartridge with no brain.handlers block — common case for
    // PWA-only cartridges (e.g. early jam_experience before its
    // brain code lands).
    try writeManifestFile(allocator, ext_dir, "pwa-only",
        \\{"id":"pwa-only","name":"PWA Only","version":"0.1.0"}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(usize, 0), result[0].brain_handlers.len);
}

test "loadAll — brain.handlers[] populated, default registerInto" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext_dir = try tmp.dir.openDir("extensions", .{});
    defer ext_dir.close();

    // Two handlers; first uses default registerInto, second names
    // an explicit colocated entry-point.
    try writeManifestFile(allocator, ext_dir, "oddjobz",
        \\{"id":"oddjobz","name":"Oddjobz","version":"1.0.0",
        \\ "brain":{"handlers":[
        \\   {"module":"jobs_handler"},
        \\   {"module":"customers_handler","registerInto":"registerCustomers"}
        \\ ]}}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    const m = result[0];
    try std.testing.expectEqual(@as(usize, 2), m.brain_handlers.len);

    try std.testing.expectEqualStrings("jobs_handler", m.brain_handlers[0].module);
    try std.testing.expectEqualStrings("registerInto", m.brain_handlers[0].register_into);

    try std.testing.expectEqualStrings("customers_handler", m.brain_handlers[1].module);
    try std.testing.expectEqualStrings("registerCustomers", m.brain_handlers[1].register_into);
}

test "loadAll — brain block present but handlers[] empty → no handlers" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext_dir = try tmp.dir.openDir("extensions", .{});
    defer ext_dir.close();

    try writeManifestFile(allocator, ext_dir, "no-handlers-yet",
        \\{"id":"no-handlers-yet","name":"WIP","version":"0.1.0",
        \\ "brain":{"handlers":[]}}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(usize, 0), result[0].brain_handlers.len);
}

// ─────────────────────────────────────────────────────────────────────
// SH1 tests (svelte-helm matrix / DECISION D9) — ui.surfacingMode + ui.verbs[]
// ─────────────────────────────────────────────────────────────────────

test "loadAll — ui.surfacingMode + ui.verbs[] parsed (SH1 / D9)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext_dir = try tmp.dir.openDir("extensions", .{});
    defer ext_dir.close();

    try writeManifestFile(allocator, ext_dir, "oddjobz",
        \\{"id":"oddjobz","name":"Oddjobz","version":"1.0.0",
        \\ "ui":{"surfacingMode":"default","verbs":[
        \\   {"modal":"do","label":"New job","intentType":"oddjobz.job.create","subtitle":"log a new job","icon":"build"},
        \\   {"modal":"do","label":"Edit website","intentType":"site.edit","role":"admin"},
        \\   {"modal":"find","label":"Find job","intentType":"oddjobz.job.find"}
        \\ ]}}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    const m = result[0];
    try std.testing.expectEqualStrings("default", m.surfacing_mode.?);
    try std.testing.expectEqual(@as(usize, 3), m.ui_verbs.len);
    try std.testing.expectEqualStrings("do", m.ui_verbs[0].modal);
    try std.testing.expectEqualStrings("New job", m.ui_verbs[0].label);
    try std.testing.expectEqualStrings("oddjobz.job.create", m.ui_verbs[0].intent_type);
    try std.testing.expectEqualStrings("log a new job", m.ui_verbs[0].subtitle.?);
    try std.testing.expectEqualStrings("build", m.ui_verbs[0].icon.?);
    // SH14 / D12 — role defaults to operator; explicit admin is honoured.
    try std.testing.expectEqualStrings("operator", m.ui_verbs[0].role);
    try std.testing.expectEqualStrings("admin", m.ui_verbs[1].role);
    try std.testing.expectEqualStrings("find", m.ui_verbs[2].modal);
    try std.testing.expectEqualStrings("operator", m.ui_verbs[2].role);
    try std.testing.expect(m.ui_verbs[2].subtitle == null);
    try std.testing.expect(m.ui_verbs[2].icon == null);
}

test "loadAll — legacy ui block (primaryAnchor/hierarchy) → null surfacingMode, empty verbs" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext_dir = try tmp.dir.openDir("extensions", .{});
    defer ext_dir.close();

    // The shape oddjobz cartridge.json ships today — must still parse,
    // leaving the new declarative fields at their defaults (back-compat).
    try writeManifestFile(allocator, ext_dir, "legacy",
        \\{"id":"legacy","name":"Legacy","version":"0.1.0",
        \\ "ui":{"primaryAnchor":"legacy.site","hierarchy":["legacy.site","legacy.job"]}}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const result = try loadAll(allocator, tmp_path);
    defer deinitManifests(allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(result[0].surfacing_mode == null);
    try std.testing.expectEqual(@as(usize, 0), result[0].ui_verbs.len);
}

```
