---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/oddjobz_ingest_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.550607+00:00
---

# cartridges/oddjobz/brain/zig/src/oddjobz_ingest_handler.zig

```zig
// LI-2 — `ingest` operator resource: spawn the legacy-ingest mint spine.
//
// The operator-facing surface for legacy ingestion, reached via the `do` grammar
// (`do import legacy lead file=<name>`) → dispatcher `ingest` resource → spawns the
// cartridge-shipped legacy-ingest-handler.ts (LI-1), which mints a ratified
// Proposal's full entity set (site → customer → job → attachment) as CANONICAL,
// owner-bound cells via entity.encode. So a legacy-imported lead becomes a parity
// cell the semantos app reads via cell.query, exactly like a widget lead.
//
// Commands (cap.brain.admin):
//   import_lead — { file } → reads <data_dir>/imports/<file> (a ratified Proposal
//                 JSON the operator dropped there), forwards it on stdin to the bun
//                 handler, returns { ok, outcome } (the minted cell-id graph).
//
// The proposal-management surface (connect/ingest/extract/ratify by id) lands in
// LI-3; this resource is the import/mint operator action over LI-1's spine.

const std = @import("std");
const dispatcher = @import("dispatcher");

pub const RESOURCE_NAME = "ingest";

pub const HandlerError = error{
    invalid_args,
    bad_file_name,
    file_not_found,
    bad_proposal_json,
    spawn_failed,
    out_of_memory,
};

pub const Handler = struct {
    allocator: std.mem.Allocator,
    /// Absolute path to the cartridge-shipped legacy-ingest-handler.ts (LI-1).
    script_path: []const u8,
    /// The brain data dir (the bun handler's data_dir + the imports/ root).
    data_dir: []const u8,
    /// Operator cell ownerId as 32-hex ("" when unknown → bun handler zero-fills).
    owner_id_hex: []const u8,
    mu: std.Thread.Mutex,

    pub fn init(
        allocator: std.mem.Allocator,
        script_path: []const u8,
        data_dir: []const u8,
        owner_id_hex: []const u8,
    ) Handler {
        return .{
            .allocator = allocator,
            .script_path = script_path,
            .data_dir = data_dir,
            .owner_id_hex = owner_id_hex,
            .mu = .{},
        };
    }

    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
            .audit_reads = true,
            .is_read_fn = isRead,
        };
    }
};

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "import_lead")) return .{ .require = "cap.brain.admin" };
    return error.unknown_command;
}

pub fn isRead(cmd: []const u8) bool {
    _ = cmd;
    return false; // import_lead mints cells — always a write.
}

fn handle(
    state: ?*anyopaque,
    _: *const dispatcher.DispatchContext,
    cmd: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    if (std.mem.eql(u8, cmd, "import_lead")) return handleImportLead(self, allocator, args_json);
    return error.unknown_command;
}

fn handleImportLead(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch
        return HandlerError.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return HandlerError.invalid_args;
    const fv = parsed.value.object.get("file") orelse return HandlerError.invalid_args;
    if (fv != .string or !isSafeName(fv.string)) return HandlerError.bad_file_name;

    // Read the operator-dropped ratified Proposal from <data_dir>/imports/<file>.
    const path = try std.fs.path.join(allocator, &.{ self.data_dir, "imports", fv.string });
    defer allocator.free(path);
    const proposal_json = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch
        return HandlerError.file_not_found;
    defer allocator.free(proposal_json);

    // Validate it parses (so the stdin envelope is well-formed JSON).
    var pp = std.json.parseFromSlice(std.json.Value, allocator, proposal_json, .{}) catch
        return HandlerError.bad_proposal_json;
    pp.deinit();

    // Build the bun handler's stdin: {proposal, data_dir, owner_id_hex}.
    var stdin_buf: std.ArrayList(u8) = .{};
    defer stdin_buf.deinit(allocator);
    try stdin_buf.appendSlice(allocator, "{\"proposal\":");
    try stdin_buf.appendSlice(allocator, proposal_json); // verbatim (validated object)
    try stdin_buf.appendSlice(allocator, ",\"data_dir\":");
    try writeJsonString(allocator, &stdin_buf, self.data_dir);
    try stdin_buf.appendSlice(allocator, ",\"owner_id_hex\":");
    try writeJsonString(allocator, &stdin_buf, self.owner_id_hex);
    try stdin_buf.appendSlice(allocator, "}");

    const out = spawnHandler(allocator, self.script_path, stdin_buf.items) catch
        return HandlerError.spawn_failed;
    // out is the bun handler's stdout ({ok, outcome}) — return it verbatim.
    return dispatcher.Result.ownedPayload(allocator, out);
}

/// Spawn `bun run <script>`, write `stdin_json`, return its stdout (≤256 KB).
/// Mirrors web_chat_http.callScript; stderr inherited for diagnostics.
fn spawnHandler(allocator: std.mem.Allocator, script: []const u8, stdin_json: []const u8) ![]u8 {
    var child = std.process.Child.init(&.{ "bun", "run", script }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    if (child.stdin) |stdin| {
        try stdin.writeAll(stdin_json);
        stdin.close();
        child.stdin = null;
    }
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    if (child.stdout) |stdout| {
        const buf = try allocator.alloc(u8, 256 * 1024);
        defer allocator.free(buf);
        var total: usize = 0;
        while (true) {
            const n = stdout.read(buf[total..]) catch break;
            if (n == 0) break;
            total += n;
            if (total >= buf.len) break;
        }
        try out.appendSlice(allocator, buf[0..total]);
    }
    _ = child.wait() catch {};
    return out.toOwnedSlice(allocator);
}

/// A safe imports/ filename: non-empty, no path separators, no "..", printable.
fn isSafeName(name: []const u8) bool {
    if (name.len == 0 or name.len > 128) return false;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return false;
    if (std.mem.indexOfScalar(u8, name, '\\') != null) return false;
    if (std.mem.indexOf(u8, name, "..") != null) return false;
    for (name) |c| if (c < 0x20 or c == 0x7f) return false;
    return true;
}

fn writeJsonString(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    const enc = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(enc);
    try buf.appendSlice(allocator, enc);
}

// ── inline tests ──────────────────────────────────────────────────────────
const testing = std.testing;

test "LI-2 isSafeName: rejects traversal + separators, accepts plain names" {
    try testing.expect(isSafeName("acme-lead.json"));
    try testing.expect(isSafeName("p1.json"));
    try testing.expect(!isSafeName(""));
    try testing.expect(!isSafeName("../etc/passwd"));
    try testing.expect(!isSafeName("a/b.json"));
    try testing.expect(!isSafeName("a\\b.json"));
    try testing.expect(!isSafeName("x..y"));
}

test "LI-2 capForCmd: import_lead requires cap.brain.admin; unknown rejected" {
    const decl = try capForCmd(null, "import_lead");
    try testing.expectEqualStrings("cap.brain.admin", decl.require);
    try testing.expectError(error.unknown_command, capForCmd(null, "nope"));
    try testing.expect(!isRead("import_lead"));
}

```
