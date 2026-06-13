---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/verb_schema.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.235039+00:00
---

# runtime/semantos-brain/src/verb_schema.zig

```zig
//! Resource verb self-description — C4 PR-R2, the generic-REPL seam.
//!
//! A dispatcher ResourceHandler can self-describe its verbs + each verb's
//! argument shape via an optional `verbs_fn`. The generic REPL path
//! (`<resource> <verb> [args]`) uses this to: parse CLI args into the JSON
//! envelope `disp.dispatch(resource, verb, json)` expects, validate required
//! args, and derive help — with NO per-cartridge verb code in the brain. This
//! is transport-agnostic resource metadata (not REPL-specific), so it lives on
//! the dispatcher's ResourceHandler; the REPL is just the first consumer.
//!
//! Leaf deps: std only.

const std = @import("std");

pub const ArgKind = enum { string, int, bool };

/// One argument of a verb. `positional` args are filled (in declaration order)
/// from bare tokens; the rest are `--name value` / `name=value` flags. A `bool`
/// flag is true when present bare (`--force`) or `--force true`.
pub const ArgSpec = struct {
    name: []const u8, // the JSON key in the dispatch envelope
    kind: ArgKind = .string,
    required: bool = false,
    positional: bool = false,
    help: []const u8 = "",
};

pub const VerbSpec = struct {
    verb: []const u8,
    summary: []const u8 = "",
    args: []const ArgSpec = &.{},
};

pub const BuildError = error{
    unknown_arg,
    missing_required,
    bad_int,
    out_of_memory,
};

/// Find a verb spec by name.
pub fn findVerb(specs: []const VerbSpec, verb: []const u8) ?VerbSpec {
    for (specs) |s| {
        if (std.mem.eql(u8, s.verb, verb)) return s;
    }
    return null;
}

/// Build the JSON envelope `disp.dispatch` expects from CLI `args`, per `spec`.
/// Supports `--name value`, `name=value`, bare positionals (in declared order),
/// and bare `--flag` for bools. Validates unknown flags + required args.
/// Returns an owned JSON object string (caller frees).
pub fn buildEnvelope(
    allocator: std.mem.Allocator,
    spec: VerbSpec,
    args: []const []const u8,
) BuildError![]u8 {
    var seen = std.ArrayList([]const u8){}; // names that got a value
    defer seen.deinit(allocator);

    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    buf.append(allocator, '{') catch return BuildError.out_of_memory;
    var first = true;

    var pos_idx: usize = 0; // next positional slot to fill
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const tok = args[i];
        var key: []const u8 = "";
        var val: []const u8 = "";

        if (std.mem.startsWith(u8, tok, "--")) {
            const flag = tok[2..];
            if (std.mem.indexOfScalar(u8, flag, '=')) |eq| {
                key = flag[0..eq];
                val = flag[eq + 1 ..];
            } else {
                key = flag;
                const a = specForName(spec, key) orelse return BuildError.unknown_arg;
                if (a.kind == .bool) {
                    // `--flag` bare → true, unless next token is true/false.
                    if (i + 1 < args.len and (std.mem.eql(u8, args[i + 1], "true") or std.mem.eql(u8, args[i + 1], "false"))) {
                        i += 1;
                        val = args[i];
                    } else {
                        val = "true";
                    }
                } else {
                    if (i + 1 >= args.len) return BuildError.missing_required;
                    i += 1;
                    val = args[i];
                }
            }
        } else if (std.mem.indexOfScalar(u8, tok, '=')) |eq| {
            key = tok[0..eq];
            val = tok[eq + 1 ..];
        } else {
            // positional
            const a = nthPositional(spec, pos_idx) orelse return BuildError.unknown_arg;
            pos_idx += 1;
            key = a.name;
            val = tok;
        }

        const a = specForName(spec, key) orelse return BuildError.unknown_arg;
        if (!first) buf.append(allocator, ',') catch return BuildError.out_of_memory;
        first = false;
        appendKv(allocator, &buf, a, val) catch |e| return mapErr(e);
        seen.append(allocator, a.name) catch return BuildError.out_of_memory;
    }

    // required check
    for (spec.args) |a| {
        if (a.required and !containsName(seen.items, a.name)) return BuildError.missing_required;
    }

    buf.append(allocator, '}') catch return BuildError.out_of_memory;
    return buf.toOwnedSlice(allocator) catch return BuildError.out_of_memory;
}

fn mapErr(e: anyerror) BuildError {
    return switch (e) {
        error.OutOfMemory => BuildError.out_of_memory,
        error.bad_int => BuildError.bad_int,
        else => BuildError.out_of_memory,
    };
}

fn appendKv(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), a: ArgSpec, val: []const u8) !void {
    try buf.append(allocator, '"');
    try appendEscaped(allocator, buf, a.name);
    try buf.appendSlice(allocator, "\":");
    switch (a.kind) {
        .string => {
            try buf.append(allocator, '"');
            try appendEscaped(allocator, buf, val);
            try buf.append(allocator, '"');
        },
        .int => {
            _ = std.fmt.parseInt(i64, val, 10) catch return error.bad_int;
            try buf.appendSlice(allocator, val);
        },
        .bool => {
            const b = std.mem.eql(u8, val, "true");
            try buf.appendSlice(allocator, if (b) "true" else "false");
        },
    }
}

fn appendEscaped(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |c| switch (c) {
        '"' => try buf.appendSlice(allocator, "\\\""),
        '\\' => try buf.appendSlice(allocator, "\\\\"),
        '\n' => try buf.appendSlice(allocator, "\\n"),
        '\r' => try buf.appendSlice(allocator, "\\r"),
        else => try buf.append(allocator, c),
    };
}

fn specForName(spec: VerbSpec, name: []const u8) ?ArgSpec {
    for (spec.args) |a| if (std.mem.eql(u8, a.name, name)) return a;
    return null;
}

fn nthPositional(spec: VerbSpec, n: usize) ?ArgSpec {
    var k: usize = 0;
    for (spec.args) |a| {
        if (!a.positional) continue;
        if (k == n) return a;
        k += 1;
    }
    return null;
}

fn containsName(names: []const []const u8, name: []const u8) bool {
    for (names) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

// ── inline tests ──────────────────────────────────────────────────────────

const testing = std.testing;

const JOBS_FIND = VerbSpec{
    .verb = "find",
    .args = &.{
        .{ .name = "state", .kind = .string },
        .{ .name = "limit", .kind = .int },
    },
};
const JOBS_GET = VerbSpec{
    .verb = "find_by_id",
    .args = &.{.{ .name = "id", .kind = .string, .required = true, .positional = true }},
};

test "findVerb" {
    const specs = [_]VerbSpec{ JOBS_FIND, JOBS_GET };
    try testing.expect(findVerb(&specs, "find") != null);
    try testing.expect(findVerb(&specs, "nope") == null);
}

test "buildEnvelope: flags + int coercion" {
    const out = try buildEnvelope(testing.allocator, JOBS_FIND, &.{ "--state", "lead", "--limit", "10" });
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{\"state\":\"lead\",\"limit\":10}", out);
}

test "buildEnvelope: key=value form" {
    const out = try buildEnvelope(testing.allocator, JOBS_FIND, &.{"state=lead"});
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{\"state\":\"lead\"}", out);
}

test "buildEnvelope: positional + required" {
    const out = try buildEnvelope(testing.allocator, JOBS_GET, &.{"abc123"});
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{\"id\":\"abc123\"}", out);
    try testing.expectError(BuildError.missing_required, buildEnvelope(testing.allocator, JOBS_GET, &.{}));
}

test "buildEnvelope: unknown flag rejected" {
    try testing.expectError(BuildError.unknown_arg, buildEnvelope(testing.allocator, JOBS_FIND, &.{ "--bogus", "x" }));
}

test "buildEnvelope: empty" {
    const out = try buildEnvelope(testing.allocator, JOBS_FIND, &.{});
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{}", out);
}

```
