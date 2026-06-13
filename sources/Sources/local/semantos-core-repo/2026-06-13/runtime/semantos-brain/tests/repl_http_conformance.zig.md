---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/repl_http_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.189852+00:00
---

# runtime/semantos-brain/tests/repl_http_conformance.zig

```zig
// Phase Brain 4 — HTTP REPL endpoint conformance tests.
//
// Covers the request-shape parsing helpers — the dispatch path through
// `maybeHandle` is exercised by integration tests in
// `tests/site_server_conformance.zig` since it needs a full SiteServer
// + REPL Session + TokenStore wiring.

const std = @import("std");
const repl_http = @import("repl_http");

// ── parseBearerHeader ──

test "Brain 4 parseBearerHeader: accepts well-formed header" {
    const hex64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const got = repl_http.parseBearerHeader("Bearer " ++ hex64);
    try std.testing.expect(got != null);
    try std.testing.expectEqualStrings(hex64, got.?);
}

test "Brain 4 parseBearerHeader: accepts case-insensitive scheme" {
    const hex64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const got = repl_http.parseBearerHeader("bearer " ++ hex64);
    try std.testing.expect(got != null);
}

test "Brain 4 parseBearerHeader: rejects wrong scheme" {
    const hex64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    try std.testing.expect(repl_http.parseBearerHeader("Basic " ++ hex64) == null);
}

test "Brain 4 parseBearerHeader: rejects short token" {
    try std.testing.expect(repl_http.parseBearerHeader("Bearer abcd") == null);
}

test "Brain 4 parseBearerHeader: rejects non-hex chars" {
    const len_64_with_g = "g123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    try std.testing.expect(repl_http.parseBearerHeader("Bearer " ++ len_64_with_g) == null);
}

test "Brain 4 parseBearerHeader: trims surrounding whitespace" {
    const hex64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const got = repl_http.parseBearerHeader("  Bearer " ++ hex64 ++ "  ");
    try std.testing.expect(got != null);
}

test "Brain 4 parseBearerHeader: rejects empty header" {
    try std.testing.expect(repl_http.parseBearerHeader("") == null);
    try std.testing.expect(repl_http.parseBearerHeader("Bearer") == null);
    try std.testing.expect(repl_http.parseBearerHeader("Bearer ") == null);
}

// ── parseCmdField ──

test "Brain 4 parseCmdField: extracts cmd from well-formed body" {
    const cmd = try repl_http.parseCmdField(std.testing.allocator, "{\"cmd\":\"headers tip\"}");
    defer std.testing.allocator.free(cmd);
    try std.testing.expectEqualStrings("headers tip", cmd);
}

test "Brain 4 parseCmdField: rejects non-object body" {
    try std.testing.expectError(error.bad_format, repl_http.parseCmdField(std.testing.allocator, "\"just a string\""));
}

test "Brain 4 parseCmdField: rejects body missing cmd" {
    try std.testing.expectError(error.bad_format, repl_http.parseCmdField(std.testing.allocator, "{\"other\":\"field\"}"));
}

test "Brain 4 parseCmdField: rejects non-string cmd" {
    try std.testing.expectError(error.bad_format, repl_http.parseCmdField(std.testing.allocator, "{\"cmd\":42}"));
}

test "Brain 4 parseCmdField: handles escapes correctly" {
    const cmd = try repl_http.parseCmdField(std.testing.allocator, "{\"cmd\":\"call mod export \\\"arg\\\"\"}");
    defer std.testing.allocator.free(cmd);
    try std.testing.expectEqualStrings("call mod export \"arg\"", cmd);
}

test "Brain 4 parseCmdField: handles ignored extra fields" {
    const cmd = try repl_http.parseCmdField(std.testing.allocator, "{\"cmd\":\"status\",\"extra\":true}");
    defer std.testing.allocator.free(cmd);
    try std.testing.expectEqualStrings("status", cmd);
}

// ── jsonEncodeString ──

test "Brain 4 jsonEncodeString: round-trips ASCII unchanged with quotes" {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try repl_http.jsonEncodeString(std.testing.allocator, &out, "hello");
    try std.testing.expectEqualStrings("\"hello\"", out.items);
}

test "Brain 4 jsonEncodeString: escapes embedded double-quote" {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try repl_http.jsonEncodeString(std.testing.allocator, &out, "she said \"hi\"");
    try std.testing.expectEqualStrings("\"she said \\\"hi\\\"\"", out.items);
}

test "Brain 4 jsonEncodeString: escapes backslash" {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try repl_http.jsonEncodeString(std.testing.allocator, &out, "a\\b");
    try std.testing.expectEqualStrings("\"a\\\\b\"", out.items);
}

test "Brain 4 jsonEncodeString: escapes newlines + tabs + cr" {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try repl_http.jsonEncodeString(std.testing.allocator, &out, "a\nb\tc\rd");
    try std.testing.expectEqualStrings("\"a\\nb\\tc\\rd\"", out.items);
}

test "Brain 4 jsonEncodeString: escapes other control chars as \\uXXXX" {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try repl_http.jsonEncodeString(std.testing.allocator, &out, "\x01\x1f");
    try std.testing.expectEqualStrings("\"\\u0001\\u001f\"", out.items);
}

test "Brain 4 jsonEncodeString: round-trips through JSON parser" {
    const tricky = "control \x07 chars \"and\" backslash \\ + newline\n";
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(std.testing.allocator);
    try repl_http.jsonEncodeString(std.testing.allocator, &out, tricky);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out.items, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .string);
    try std.testing.expectEqualStrings(tricky, parsed.value.string);
}

```
