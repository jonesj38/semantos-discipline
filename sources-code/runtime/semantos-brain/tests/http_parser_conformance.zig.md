---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/http_parser_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.205929+00:00
---

# runtime/semantos-brain/tests/http_parser_conformance.zig

```zig
// http_parser_conformance.zig — Additional parser conformance tests
//
// The unit tests embedded in http_parser.zig cover core correctness.
// This file adds conformance cases that exercise the parser through the
// build system's test runner (with the module properly imported via the
// build graph), covering edge cases from real HTTP clients.

const std = @import("std");
const http_parser = @import("http_parser");

test "http_parser_conformance: multiple headers parsed in order" {
    const input =
        "POST /api/v1/repl HTTP/1.1\r\n" ++
        "Host: localhost:8080\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 15\r\n" ++
        "Authorization: Bearer " ++ ("0" ** 64) ++ "\r\n" ++
        "\r\n" ++
        "{\"command\":\"p\"}";
    var parser = http_parser.Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: http_parser.HttpRequest = undefined;
    const r = parser.feed(input, &req);
    try std.testing.expect(r == .complete);
    try std.testing.expectEqualStrings("POST", req.method);
    try std.testing.expectEqualStrings("/api/v1/repl", req.path);
    try std.testing.expectEqual(@as(usize, 4), req.header_count);
    try std.testing.expectEqualStrings("{\"command\":\"p\"}", req.body);
}

test "http_parser_conformance: chunked input with boundary mid-CRLF" {
    // Split the input right in the middle of a \r\n
    const full = "GET / HTTP/1.1\r\nHost: x\r\n\r\n";
    // Feed up to and including the \r of the final \r\n\r\n
    const part1 = full[0 .. full.len - 3]; // up to last "\r"
    const part2 = full[full.len - 3 ..];   // "\n\r\n"

    var parser = http_parser.Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: http_parser.HttpRequest = undefined;

    const r1 = parser.feed(part1, &req);
    try std.testing.expect(r1 == .incomplete);

    const r2 = parser.feed(part2, &req);
    try std.testing.expect(r2 == .complete);
    try std.testing.expectEqualStrings("GET", req.method);
}

test "http_parser_conformance: WebSocket upgrade from browser with ?bearer query" {
    const hex64 = "abcdef0123456789" ** 4;
    const input =
        "GET /api/v1/wallet?bearer=" ++ hex64 ++ " HTTP/1.1\r\n" ++
        "Host: brain.example.com\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "\r\n";
    var parser = http_parser.Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: http_parser.HttpRequest = undefined;
    const r = parser.feed(input, &req);
    try std.testing.expect(r == .complete);
    try std.testing.expectEqualStrings("/api/v1/wallet", req.path);
    // Query string should contain the bearer parameter.
    try std.testing.expect(std.mem.startsWith(u8, req.query, "bearer="));
    // Upgrade header should be found.
    const upg = req.header("Upgrade");
    try std.testing.expect(upg != null);
    try std.testing.expectEqualStrings("websocket", upg.?);
}

test "http_parser_conformance: OPTIONS preflight" {
    const input =
        "OPTIONS /api/v1/repl HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "Origin: https://app.example.com\r\n" ++
        "Access-Control-Request-Method: POST\r\n" ++
        "\r\n";
    var parser = http_parser.Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: http_parser.HttpRequest = undefined;
    const r = parser.feed(input, &req);
    try std.testing.expect(r == .complete);
    try std.testing.expectEqualStrings("OPTIONS", req.method);
    try std.testing.expectEqualStrings("POST",
        req.header("access-control-request-method").?);
}

test "http_parser_conformance: EOF mid-headers returns incomplete not error" {
    // Simulate a client that sends a partial request line and nothing more.
    // The caller should treat the connection as EOF and close it; the parser
    // just says "incomplete" for as long as bytes keep arriving.
    const partial = "GET /";
    var parser = http_parser.Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: http_parser.HttpRequest = undefined;
    const r = parser.feed(partial, &req);
    try std.testing.expect(r == .incomplete);
}

test "http_parser_conformance: header value with leading and trailing whitespace" {
    const input = "GET / HTTP/1.1\r\nX-Custom:  value with spaces  \r\n\r\n";
    var parser = http_parser.Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: http_parser.HttpRequest = undefined;
    _ = parser.feed(input, &req);
    const val = req.header("x-custom");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("value with spaces", val.?);
}

```
