---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/repl_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.250827+00:00
---

# runtime/semantos-brain/src/repl_http.zig

```zig
// Phase Brain 4 — HTTP REPL helper functions.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 4).
//
// This module USED to host a blocking `maybeHandle` that served
// `POST /api/v1/repl` directly off `std.http.Server.Request`. That
// path was superseded by the single-threaded reactor: the live
// handler is `site_server/reactor.zig::reactorHandleRepl`, which
// re-implements the request/auth/dispatch flow on the poll loop
// (see the brain-wedge B-pragmatic reactor, 2026-05-07). The dead
// `maybeHandle` (+ its private `respondJson`/`headerValue`/
// `readBody` helpers, `HandlerError`, and the `bearer_tokens`/`repl`
// imports it alone needed) was cauterised once it had zero callers
// in source and tests — `repl_http_conformance.zig` covers the
// helpers below, `repl_http_reactor_conformance.zig` covers the
// reactor path.
//
// What remains are the three pure helpers `reactorHandleRepl`
// imports (`site_server/reactor.zig:951/981/1017`):
//   • parseBearerHeader — `Authorization: Bearer <hex64>` → hex slice
//   • parseCmdField     — `{"cmd":"..."}` → owned cmd string
//   • jsonEncodeString  — RFC-8259 string escaping for the response
// Module name kept (`repl_http`) so the reactor import + build wiring
// are unchanged; it is now a helper module, not an HTTP handler.

const std = @import("std");

/// Parse `Authorization: Bearer <hex64>` → returns the hex string slice.
pub fn parseBearerHeader(value: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, value, " \t");
    if (!std.mem.startsWith(u8, trimmed, "Bearer ") and !std.mem.startsWith(u8, trimmed, "bearer ")) {
        return null;
    }
    const tok = std.mem.trim(u8, trimmed[7..], " \t");
    if (tok.len != 64) return null;
    for (tok) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
        if (!ok) return null;
    }
    return tok;
}

/// Parse `{"cmd": "..."}` and return the cmd value as an owned slice.
pub fn parseCmdField(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.bad_format;
    const cmd = parsed.value.object.get("cmd") orelse return error.bad_format;
    if (cmd != .string) return error.bad_format;
    return allocator.dupe(u8, cmd.string);
}

/// JSON-encode a string (RFC 8259 — escape control chars, ", \).
pub fn jsonEncodeString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    s: []const u8,
) !void {
    try out.append(allocator, '"');
    for (s) |c| switch (c) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        0x08 => try out.appendSlice(allocator, "\\b"),
        0x0c => try out.appendSlice(allocator, "\\f"),
        0...0x07, 0x0b, 0x0e...0x1f => {
            var buf: [8]u8 = undefined;
            const slice = try std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c});
            try out.appendSlice(allocator, slice);
        },
        else => try out.append(allocator, c),
    };
    try out.append(allocator, '"');
}

```
