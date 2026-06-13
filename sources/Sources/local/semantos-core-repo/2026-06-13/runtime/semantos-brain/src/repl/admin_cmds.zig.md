---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/repl/admin_cmds.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.297545+00:00
---

# runtime/semantos-brain/src/repl/admin_cmds.zig

```zig
// Admin REPL cmd verbs — generic, cartridge-agnostic operations on
// installed cartridges' typed cells. Sibling to oddjobz_cmds.zig
// (per-type, hand-wired verbs for one cartridge) — admin_cmds.zig
// is the *generic* layer driven by the cartridge's declared schema.
//
// Phase B: REPL skeleton — argument parsing, usage errors, stub output.
// Phase C: schema lookup + field validation against installed cartridges.
// Phase D.3 (this revision): builds a self-describing cell payload JSON,
// dispatches to the "cell" resource's "create" command via the dispatcher.
// The cell_handler encodes a 1024-byte cell (entity_tag 0x10) and
// persists it via cell_store.put. When no dispatcher is attached (test
// mode), validation results are printed without persistence.
//
// Subcommands:
//
//   admin create-cell <cartridge-id>:<type-name> [field=value]...
//
//     Create a new cell of the given type in the named cartridge.
//     Fields are key=value pairs with no spaces in either side
//     (REPL splitArgs is whitespace-only — values with embedded
//     spaces are deferred to a future quoting story).
//
//     Example:
//       admin create-cell nonprofit-os:Fund name=Operating balance=50000
//
// The verb signature uses session: anytype rather than importing
// repl/types.zig (which transitively pulls in the full brain module
// web — config, audit_log, broker, dispatcher, …). The function body
// reads `session.allocator` and `session.cfg.shell.data_dir`; any
// session shape carrying those is acceptable. The real `*Session`
// satisfies the contract via duck typing.

const std = @import("std");
const cartridge_schemas = @import("cartridge_schemas");
const cartridge_schema = @import("cartridge_schema");
const dispatcher_mod = @import("dispatcher");

/// Top-level dispatcher for the `admin` verb family. Switches on the
/// first positional arg.
pub fn cmdAdmin(session: anytype, out: anytype, args: []const []const u8) !void {
    if (args.len == 0) {
        try printAdminUsage(out);
        return;
    }
    const sub = args[0];
    const rest = args[1..];

    if (std.mem.eql(u8, sub, "create-cell")) {
        try cmdAdminCreateCell(session, out, rest);
        return;
    }
    if (std.mem.eql(u8, sub, "list-cells")) {
        try cmdAdminListCells(session, out, rest);
        return;
    }
    if (std.mem.eql(u8, sub, "help") or std.mem.eql(u8, sub, "?")) {
        try printAdminUsage(out);
        return;
    }

    try out.print("admin: unknown subcommand '{s}'\n", .{sub});
    try printAdminUsage(out);
}

/// `admin create-cell <cartridge-id>:<type-name> [field=value]...`
///
/// Phase D.3: parses args, loads installed-cartridge schemas, resolves
/// the requested cartridge and type, validates every supplied field
/// against the type's schema, then builds a self-describing cell
/// payload and dispatches to cell.create for persistence.
pub fn cmdAdminCreateCell(session: anytype, out: anytype, args: []const []const u8) !void {
    // ── 1. Arg shape parsing (no I/O yet — fail fast on bad input) ──
    if (args.len == 0) {
        try printCreateCellUsage(out);
        return;
    }

    const qualified = args[0];
    const colon = std.mem.indexOfScalar(u8, qualified, ':') orelse {
        try out.print(
            "admin create-cell: expected <cartridge-id>:<type-name>, got '{s}'\n",
            .{qualified},
        );
        try printCreateCellUsage(out);
        return;
    };
    const cartridge_id = qualified[0..colon];
    const type_name = qualified[colon + 1 ..];

    if (cartridge_id.len == 0 or type_name.len == 0) {
        try out.print(
            "admin create-cell: cartridge id and type name must be non-empty (got '{s}')\n",
            .{qualified},
        );
        try printCreateCellUsage(out);
        return;
    }

    for (args[1..]) |arg| {
        const eq = std.mem.indexOfScalar(u8, arg, '=') orelse {
            try out.print(
                "admin create-cell: field arg '{s}' is not in name=value form\n",
                .{arg},
            );
            return;
        };
        if (eq == 0) {
            try out.print(
                "admin create-cell: field arg '{s}' has empty name\n",
                .{arg},
            );
            return;
        }
    }

    // ── 2. Load installed cartridges' schemas ──
    const data_dir = session.cfg.shell.data_dir;
    const schemas = cartridge_schemas.loadAllInstalled(session.allocator, data_dir) catch |err| {
        try out.print(
            "admin create-cell: failed to load installed cartridges ({s})\n",
            .{@errorName(err)},
        );
        return;
    };
    defer cartridge_schemas.deinit(session.allocator, schemas);

    // ── 3. Resolve cartridge + type ──
    const cart = cartridge_schemas.findCartridge(schemas, cartridge_id) orelse {
        try out.print(
            "admin create-cell: no installed cartridge with id '{s}'\n",
            .{cartridge_id},
        );
        try printInstalledCartridges(out, schemas);
        return;
    };

    const type_schema = cartridge_schema.findType(cart.types, type_name) orelse {
        try out.print(
            "admin create-cell: cartridge '{s}' declares no type '{s}'\n",
            .{ cartridge_id, type_name },
        );
        try printAvailableTypes(out, cart);
        return;
    };

    // ── 4. Validate each supplied field against the type's schema ──
    for (args[1..]) |arg| {
        const eq = std.mem.indexOfScalar(u8, arg, '=').?; // validated above
        const name = arg[0..eq];
        const value = arg[eq + 1 ..];

        const field = cartridge_schema.findField(type_schema, name) orelse {
            try out.print(
                "admin create-cell: type '{s}' has no field '{s}'\n",
                .{ type_name, name },
            );
            try printAvailableFields(out, type_schema);
            return;
        };

        const ok = try validateValue(out, field, value);
        if (!ok) return;
    }

    // ── 5. Check every required (non-optional) field was supplied ──
    var missing_count: usize = 0;
    for (type_schema.fields) |f| {
        if (f.optional) continue;
        if (!fieldSuppliedInArgs(args[1..], f.name)) {
            if (missing_count == 0) {
                try out.print(
                    "admin create-cell: missing required field(s) for type '{s}':\n",
                    .{type_name},
                );
            }
            try out.print("  - {s}\n", .{f.name});
            missing_count += 1;
        }
    }
    if (missing_count > 0) return;

    // ── 6. Build self-describing cell payload JSON ──
    var payload_buf: std.ArrayList(u8) = .empty;
    defer payload_buf.deinit(session.allocator);
    try payload_buf.appendSlice(session.allocator, "{\"cartridge_id\":");
    try appendJsonStr(session.allocator, &payload_buf, cartridge_id);
    try payload_buf.appendSlice(session.allocator, ",\"type_name\":");
    try appendJsonStr(session.allocator, &payload_buf, type_name);
    try payload_buf.appendSlice(session.allocator, ",\"type_hash\":");
    try appendJsonStr(session.allocator, &payload_buf, type_schema.type_hash_hex);
    try payload_buf.appendSlice(session.allocator, ",\"linearity\":");
    try appendJsonStr(session.allocator, &payload_buf, @tagName(type_schema.linearity));
    try payload_buf.appendSlice(session.allocator, ",\"fields\":{");
    {
        var first = true;
        for (args[1..]) |arg| {
            const eq = std.mem.indexOfScalar(u8, arg, '=').?;
            const name = arg[0..eq];
            const value = arg[eq + 1 ..];
            if (!first) try payload_buf.append(session.allocator, ',');
            first = false;
            try appendJsonStr(session.allocator, &payload_buf, name);
            try payload_buf.append(session.allocator, ':');
            try appendJsonStr(session.allocator, &payload_buf, value);
        }
    }
    try payload_buf.appendSlice(session.allocator, "}}");

    // ── 7. Build dispatch envelope + dispatch to cell.create ──
    const disp = session.dispatcher orelse {
        // No dispatcher attached — test mode or early boot. Print the
        // validated payload for inspection but don't persist.
        try out.print("admin create-cell: validated (no dispatcher — cell not persisted)\n", .{});
        try out.print("  cartridge: {s}\n", .{cartridge_id});
        try out.print("  type:      {s}\n", .{type_name});
        try out.print("  linearity: {s}\n", .{@tagName(type_schema.linearity)});
        try out.print("  payload:   {d} bytes\n", .{payload_buf.items.len});
        return;
    };

    var dispatch_args: std.ArrayList(u8) = .empty;
    defer dispatch_args.deinit(session.allocator);
    try dispatch_args.appendSlice(session.allocator, "{\"cell_payload\":");
    try appendJsonStr(session.allocator, &dispatch_args, payload_buf.items);
    try dispatch_args.append(session.allocator, '}');

    const ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{
            .request_id = "",
            .timestamp_unix = 0,
            .transport_label = "repl",
        },
    };

    var result = disp.dispatch(&ctx, "cell", "create", dispatch_args.items) catch |err| {
        try out.print("admin create-cell: dispatch error: {s}\n", .{@errorName(err)});
        return;
    };
    defer result.deinit();

    try out.print("admin create-cell: cell created\n", .{});
    try out.print("  cartridge: {s}\n", .{cartridge_id});
    try out.print("  type:      {s}\n", .{type_name});
    try out.print("  linearity: {s}\n", .{@tagName(type_schema.linearity)});
    if (result.payload.len > 0) {
        try out.print("  result:    {s}\n", .{result.payload});
    }
}

// ─────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────

/// `admin list-cells [<cartridge-id>[:<type-name>]]`
///
/// Lists all generic cartridge cells, optionally filtered by cartridge
/// and/or type. Dispatches to cell.list via the dispatcher.
pub fn cmdAdminListCells(session: anytype, out: anytype, args: []const []const u8) !void {
    const disp = session.dispatcher orelse {
        try out.print("admin list-cells: no dispatcher attached\n", .{});
        return;
    };

    var dispatch_args: std.ArrayList(u8) = .empty;
    defer dispatch_args.deinit(session.allocator);
    try dispatch_args.append(session.allocator, '{');

    if (args.len >= 1) {
        const qualified = args[0];
        const colon = std.mem.indexOfScalar(u8, qualified, ':');
        const cartridge_id = if (colon) |c| qualified[0..c] else qualified;
        const type_name = if (colon) |c| qualified[c + 1 ..] else null;

        try dispatch_args.appendSlice(session.allocator, "\"cartridge_id\":");
        try appendJsonStr(session.allocator, &dispatch_args, cartridge_id);

        if (type_name) |tn| {
            if (tn.len > 0) {
                try dispatch_args.appendSlice(session.allocator, ",\"type_name\":");
                try appendJsonStr(session.allocator, &dispatch_args, tn);
            }
        }
    }
    try dispatch_args.append(session.allocator, '}');

    const ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{
            .request_id = "",
            .timestamp_unix = 0,
            .transport_label = "repl",
        },
    };

    var result = disp.dispatch(&ctx, "cell", "list", dispatch_args.items) catch |err| {
        try out.print("admin list-cells: dispatch error: {s}\n", .{@errorName(err)});
        return;
    };
    defer result.deinit();

    if (result.payload.len > 0) {
        try out.print("{s}\n", .{result.payload});
    } else {
        try out.print("(no results)\n", .{});
    }
}

fn appendJsonStr(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            else => try buf.append(allocator, c),
        }
    }
    try buf.append(allocator, '"');
}

/// Returns true if `field_name` appears as `name=...` anywhere in
/// `field_args`. Phase C only — the eventual representation will be a
/// parsed map, but for stub-tier validation a linear scan is fine.
fn fieldSuppliedInArgs(field_args: []const []const u8, field_name: []const u8) bool {
    for (field_args) |arg| {
        const eq = std.mem.indexOfScalar(u8, arg, '=') orelse continue;
        if (std.mem.eql(u8, arg[0..eq], field_name)) return true;
    }
    return false;
}

/// Validate `value` against the field's declared type. On invalid
/// input, prints a descriptive error and returns false. Returns true
/// (no output) when the value passes.
fn validateValue(
    out: anytype,
    field: *const cartridge_schema.FieldSpec,
    value: []const u8,
) !bool {
    switch (field.type) {
        .string, .text, .date => {
            // Phase C: any non-empty value passes. Date-format
            // validation is deferred to Phase D / E when cell-encode
            // pins the canonical date form.
            if (value.len == 0) {
                try out.print(
                    "admin create-cell: field '{s}' value cannot be empty\n",
                    .{field.name},
                );
                return false;
            }
            return true;
        },
        .bool_t => {
            if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false")) return true;
            try out.print(
                "admin create-cell: field '{s}' expects bool ('true' or 'false'), got '{s}'\n",
                .{ field.name, value },
            );
            return false;
        },
        .number => |spec| {
            const n = std.fmt.parseFloat(f64, value) catch {
                try out.print(
                    "admin create-cell: field '{s}' expects number, got '{s}'\n",
                    .{ field.name, value },
                );
                return false;
            };
            if (spec.min) |min| if (n < min) {
                try out.print(
                    "admin create-cell: field '{s}' value {d} below min {d}\n",
                    .{ field.name, n, min },
                );
                return false;
            };
            if (spec.max) |max| if (n > max) {
                try out.print(
                    "admin create-cell: field '{s}' value {d} above max {d}\n",
                    .{ field.name, n, max },
                );
                return false;
            };
            return true;
        },
        .enum_t => |allowed| {
            for (allowed) |a| if (std.mem.eql(u8, value, a)) return true;
            try out.print(
                "admin create-cell: field '{s}' value '{s}' not in allowed set [",
                .{ field.name, value },
            );
            for (allowed, 0..) |a, i| {
                if (i > 0) try out.print(", ", .{});
                try out.print("{s}", .{a});
            }
            try out.print("]\n", .{});
            return false;
        },
        .ref, .list => {
            // Phase D handles ref-by-cell-id lookup and list parsing.
            // Phase C accepts any non-empty value as a passthrough.
            if (value.len == 0) {
                try out.print(
                    "admin create-cell: field '{s}' value cannot be empty\n",
                    .{field.name},
                );
                return false;
            }
            return true;
        },
    }
}

fn printAdminUsage(out: anytype) !void {
    try out.print("usage: admin <subcommand> [args...]\n", .{});
    try out.print("  subcommands:\n", .{});
    try out.print("    create-cell <cartridge-id>:<type-name> [field=value]...\n", .{});
    try out.print("    list-cells  [<cartridge-id>[:<type-name>]]\n", .{});
    try out.print("    help\n", .{});
}

fn printCreateCellUsage(out: anytype) !void {
    try out.print("usage: admin create-cell <cartridge-id>:<type-name> [field=value]...\n", .{});
    try out.print("  example: admin create-cell nonprofit-os:Fund name=Operating balance=50000\n", .{});
    try out.print("  note: field values must not contain whitespace (Phase B limitation).\n", .{});
}

fn printInstalledCartridges(out: anytype, schemas: []const cartridge_schemas.CartridgeSchemas) !void {
    if (schemas.len == 0) {
        try out.print("  (no cartridges installed at <data_dir>/extensions/)\n", .{});
        return;
    }
    try out.print("  installed cartridges:\n", .{});
    for (schemas) |cs| {
        try out.print("    {s}\n", .{cs.cartridge_id});
    }
}

fn printAvailableTypes(out: anytype, cart: *const cartridge_schemas.CartridgeSchemas) !void {
    if (cart.types.len == 0) {
        try out.print("  (cartridge declares no object types)\n", .{});
        return;
    }
    try out.print("  declared types:\n", .{});
    for (cart.types) |t| {
        try out.print("    {s} ({s})\n", .{ t.name, @tagName(t.linearity) });
    }
}

fn printAvailableFields(out: anytype, t: *const cartridge_schema.ObjectTypeSchema) !void {
    if (t.fields.len == 0) {
        try out.print("  (type declares no fields)\n", .{});
        return;
    }
    try out.print("  declared fields:\n", .{});
    for (t.fields) |f| {
        const req = if (f.optional) "optional" else "required";
        try out.print("    {s} : {s} ({s})\n", .{ f.name, @tagName(std.meta.activeTag(f.type)), req });
    }
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

/// Duck-typed test session that satisfies the (.allocator + .cfg.shell
/// .data_dir) contract the verb reads. The real *repl.Session has many
/// more fields, but the verb only touches these two.
const ShellCfg = struct { data_dir: []const u8 };
const TestCfg = struct { shell: ShellCfg };
const TestSession = struct {
    allocator: std.mem.Allocator,
    cfg: TestCfg,
    dispatcher: ?*dispatcher_mod.Dispatcher = null,
};

const TestOut = struct {
    buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn print(self: *const TestOut, comptime fmt: []const u8, args: anytype) !void {
        try self.buf.print(self.allocator, fmt, args);
    }
};

fn makeOut(allocator: std.mem.Allocator, buf: *std.ArrayList(u8)) TestOut {
    return TestOut{ .buf = buf, .allocator = allocator };
}

/// Writes a single cartridge with one type that exercises every
/// FieldType variant. Used by tests that hit the schema lookup path.
fn writeTestCartridge(parent: std.fs.Dir) !void {
    var sub = try parent.makeOpenPath("testcart", .{});
    defer sub.close();
    var f = try sub.createFile("cartridge.json", .{});
    defer f.close();
    try f.writeAll(
        \\{"id":"testcart","name":"Test","version":"0.1.0","objectTypes":[
        \\  {"typeHash":"00","name":"Item","linearity":"AFFINE","fields":[
        \\    {"name":"label","type":"string"},
        \\    {"name":"notes","type":"text","optional":true},
        \\    {"name":"quantity","type":"number","min":0,"max":1000},
        \\    {"name":"color","type":"enum","values":["red","green","blue"]},
        \\    {"name":"active","type":"bool"},
        \\    {"name":"releaseDate","type":"date","optional":true}
        \\  ]}
        \\]}
    );
}

/// Build a test session pointed at the given tmpdir. The tmpdir's
/// `extensions/` subdir should already be populated (or not, for
/// "no cartridges installed" tests).
fn makeTestSession(allocator: std.mem.Allocator, data_dir: []const u8) TestSession {
    return TestSession{
        .allocator = allocator,
        .cfg = .{ .shell = .{ .data_dir = data_dir } },
    };
}

// ── Arg-shape tests (don't reach schema lookup) ─────────────────────
// These tests still exercise the arg-parsing surface from Phase B.
// They use a session pointed at an empty tmpdir; schema loading is
// never reached because the function errors on bad input first.

test "cmdAdmin — no args prints top-level usage" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdmin(sess, out, &.{});

    try testing.expect(std.mem.indexOf(u8, buf.items, "usage: admin") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "create-cell") != null);
}

test "cmdAdmin — unknown subcommand reports it and prints usage" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdmin(sess, out, &.{"frobnicate"});

    try testing.expect(std.mem.indexOf(u8, buf.items, "unknown subcommand 'frobnicate'") != null);
}

test "cmdAdminCreateCell — no args prints usage" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{});

    try testing.expect(std.mem.indexOf(u8, buf.items, "usage: admin create-cell") != null);
}

test "cmdAdminCreateCell — missing colon in qualified name rejected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{ "Item", "label=x" });

    try testing.expect(std.mem.indexOf(u8, buf.items, "expected <cartridge-id>:<type-name>") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[stub]") == null);
}

test "cmdAdminCreateCell — field without `=` rejected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{ "testcart:Item", "label=x", "noequalshere" });

    try testing.expect(std.mem.indexOf(u8, buf.items, "is not in name=value form") != null);
}

// ── Schema-lookup tests ──────────────────────────────────────────────

test "cmdAdminCreateCell — unknown cartridge id reports installed ones" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeTestCartridge(ext);

    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{"ghost:Item"});

    try testing.expect(std.mem.indexOf(u8, buf.items, "no installed cartridge with id 'ghost'") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "installed cartridges:") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "testcart") != null);
}

test "cmdAdminCreateCell — unknown type reports declared ones" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeTestCartridge(ext);

    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{"testcart:Phantom"});

    try testing.expect(std.mem.indexOf(u8, buf.items, "cartridge 'testcart' declares no type 'Phantom'") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "declared types:") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Item (AFFINE)") != null);
}

test "cmdAdminCreateCell — unknown field reports declared ones" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeTestCartridge(ext);

    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{ "testcart:Item", "phantomfield=x" });

    try testing.expect(std.mem.indexOf(u8, buf.items, "type 'Item' has no field 'phantomfield'") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "declared fields:") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "label : string (required)") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "notes : text (optional)") != null);
}

test "cmdAdminCreateCell — number out of range rejected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeTestCartridge(ext);

    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{
        "testcart:Item",
        "label=x",
        "quantity=9999",
        "color=red",
        "active=true",
    });

    try testing.expect(std.mem.indexOf(u8, buf.items, "above max") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[stub]") == null);
}

test "cmdAdminCreateCell — number non-numeric rejected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeTestCartridge(ext);

    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{
        "testcart:Item",
        "label=x",
        "quantity=banana",
        "color=red",
        "active=true",
    });

    try testing.expect(std.mem.indexOf(u8, buf.items, "expects number") != null);
}

test "cmdAdminCreateCell — enum value not in allowed set rejected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeTestCartridge(ext);

    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{
        "testcart:Item",
        "label=x",
        "quantity=5",
        "color=violet",
        "active=true",
    });

    try testing.expect(std.mem.indexOf(u8, buf.items, "value 'violet' not in allowed set") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "red") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "blue") != null);
}

test "cmdAdminCreateCell — bool with non-bool value rejected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeTestCartridge(ext);

    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{
        "testcart:Item",
        "label=x",
        "quantity=5",
        "color=red",
        "active=maybe",
    });

    try testing.expect(std.mem.indexOf(u8, buf.items, "expects bool") != null);
}

test "cmdAdminCreateCell — missing required fields reported" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeTestCartridge(ext);

    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    // Supply only label; quantity, color, active are required, notes
    // and releaseDate are optional.
    try cmdAdminCreateCell(sess, out, &.{ "testcart:Item", "label=x" });

    try testing.expect(std.mem.indexOf(u8, buf.items, "missing required field(s)") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "quantity") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "color") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "active") != null);
    // optional fields should NOT be flagged as missing
    try testing.expect(std.mem.indexOf(u8, buf.items, "- notes") == null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "- releaseDate") == null);
}

test "cmdAdminCreateCell — happy path all-required-supplied prints stub" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeTestCartridge(ext);

    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{
        "testcart:Item",
        "label=Widget",
        "quantity=42",
        "color=green",
        "active=true",
    });

    try testing.expect(std.mem.indexOf(u8, buf.items, "validated (no dispatcher") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "cartridge: testcart") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "type:      Item") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "linearity: AFFINE") != null);
}

test "cmdAdminCreateCell — optional fields can be supplied or omitted" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions");
    var ext = try tmp.dir.openDir("extensions", .{});
    defer ext.close();
    try writeTestCartridge(ext);

    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dd = try tmp.dir.realpath(".", &pb);

    // Supply optional `notes` AND `releaseDate` along with required fields.
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    const sess = makeTestSession(testing.allocator, dd);
    const out = makeOut(testing.allocator, &buf);

    try cmdAdminCreateCell(sess, out, &.{
        "testcart:Item",
        "label=Widget",
        "quantity=42",
        "color=green",
        "active=true",
        "notes=some-notes",
        "releaseDate=2026-05-23",
    });

    try testing.expect(std.mem.indexOf(u8, buf.items, "validated (no dispatcher") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "cartridge: testcart") != null);
}

```
