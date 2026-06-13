---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/llm_http_adapter_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.194915+00:00
---

# runtime/semantos-brain/tests/llm_http_adapter_conformance.zig

```zig
// Phase Brain 5.1 — HTTP adapter conformance.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 5).
//
// Coverage:
//   • config gating: enabled=false → config_error (no network call)
//   • per-backend end-to-end: spin up a localhost HTTP listener that
//     simulates each backend's response shape (openai chat completions,
//     anthropic messages, local llama.cpp /completion), drive
//     HttpLlmAdapter.parse, assert the ParseResponse came back correctly
//   • error mapping: 401 → config_error, 429 → rate_limited
//   • missing api_key_env returns config_error (catches the env-not-set
//     path before any network I/O)

const std = @import("std");
const llm = @import("llm_adapter");
const http_adapter = @import("llm_http_adapter");

/// Bring up a localhost listener bound to a free port. Returns the
/// listener (caller `defer listener.deinit()`) and the spawned
/// server thread (caller `defer t.join()`). Writes the URL into
/// `url_buf` and the slice into `url_out`.
fn startFakeServer(
    response_status: u16,
    response_body: []const u8,
    url_buf: *[64]u8,
    listener_out: *std.net.Server,
    url_out: *[]const u8,
) !std.Thread {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    listener_out.* = try addr.listen(.{ .reuse_address = true });
    const port = listener_out.*.listen_address.in.getPort();
    url_out.* = try std.fmt.bufPrint(url_buf, "http://127.0.0.1:{d}/v1", .{port});
    return std.Thread.spawn(.{}, serveOne, .{ listener_out, response_status, response_body });
}

fn serveOne(listener: *std.net.Server, status: u16, body: []const u8) void {
    const conn = listener.accept() catch return;
    defer conn.stream.close();

    // Slurp the request headers + body (don't bother validating).
    var req_buf: [16 * 1024]u8 = undefined;
    var total: usize = 0;
    while (total < req_buf.len) {
        const n = conn.stream.read(req_buf[total..]) catch return;
        if (n == 0) break;
        total += n;
        if (std.mem.indexOf(u8, req_buf[0..total], "\r\n\r\n")) |hdr_end| {
            const headers = req_buf[0..hdr_end];
            if (findContentLength(headers)) |cl| {
                while (total - (hdr_end + 4) < cl and total < req_buf.len) {
                    const n2 = conn.stream.read(req_buf[total..]) catch return;
                    if (n2 == 0) break;
                    total += n2;
                }
            }
            break;
        }
    }

    var resp: [4096]u8 = undefined;
    const r = std.fmt.bufPrint(
        &resp,
        "HTTP/1.1 {d} OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
        .{ status, body.len, body },
    ) catch return;
    conn.stream.writeAll(r) catch return;
}

fn findContentLength(headers: []const u8) ?usize {
    var it = std.mem.splitSequence(u8, headers, "\r\n");
    while (it.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, "content-length:")) {
            const v = std.mem.trim(u8, line["content-length:".len..], " \t");
            return std.fmt.parseInt(usize, v, 10) catch null;
        }
    }
    return null;
}

fn setEnvForTest(name: [:0]const u8, value: [:0]const u8) void {
    if (@import("builtin").os.tag == .linux or @import("builtin").os.tag == .macos) {
        const c = @cImport(@cInclude("stdlib.h"));
        _ = c.setenv(name.ptr, value.ptr, 1);
    }
}

// ── Tests ────────────────────────────────────────────────────────────

test "Brain 5.1 enabled=false returns config_error before any network call" {
    const allocator = std.testing.allocator;
    var adapter = http_adapter.HttpLlmAdapter.init(allocator, .{
        .enabled = false,
        .backend = .openai,
        .endpoint = "http://example.com/never-called",
        .model = "gpt-4o",
        .api_key_env = "OPENAI_API_KEY",
    });
    const result = adapter.parse(allocator, .{
        .utterance = "send alice 5 bucks",
        .available_verbs = "send,find,talk",
    });
    try std.testing.expectError(llm.LlmError.config_error, result);
}

test "Brain 5.1 empty endpoint returns config_error" {
    const allocator = std.testing.allocator;
    var adapter = http_adapter.HttpLlmAdapter.init(allocator, .{
        .enabled = true,
        .backend = .openai,
        .endpoint = "",
        .model = "gpt-4o",
        .api_key_env = "OPENAI_API_KEY",
    });
    const result = adapter.parse(allocator, .{
        .utterance = "x",
        .available_verbs = "y",
    });
    try std.testing.expectError(llm.LlmError.config_error, result);
}

test "Brain 5.1 openai end-to-end against localhost fake" {
    const allocator = std.testing.allocator;
    setEnvForTest("OPENAI_API_KEY_TEST", "test-key");

    var url_buf: [64]u8 = undefined;
    var listener: std.net.Server = undefined;
    var url: []const u8 = undefined;
    const t = try startFakeServer(
        200,
        \\{"choices":[{"message":{"content":"{\"modal\":\"do\",\"who\":\"alice\",\"what\":\"send-payment\",\"why\":\"for pizza\",\"confidence\":0.9}"}}]}
        ,
        &url_buf,
        &listener,
        &url,
    );
    defer t.join();
    defer listener.deinit();

    var adapter = http_adapter.HttpLlmAdapter.init(allocator, .{
        .enabled = true,
        .backend = .openai,
        .endpoint = url,
        .model = "gpt-4o",
        .api_key_env = "OPENAI_API_KEY_TEST",
    });
    const result = try adapter.parse(allocator, .{
        .utterance = "send alice 5 bucks for the pizza",
        .available_verbs = "send,find,talk",
    });
    defer {
        allocator.free(result.who);
        allocator.free(result.what);
        allocator.free(result.why);
    }
    try std.testing.expectEqual(llm.Modal.do_, result.modal);
    try std.testing.expectEqualSlices(u8, "alice", result.who);
    try std.testing.expectEqualSlices(u8, "send-payment", result.what);
    try std.testing.expectEqualSlices(u8, "for pizza", result.why);
    try std.testing.expect(result.confidence > 0.85);
}

test "Brain 5.1 anthropic end-to-end against localhost fake" {
    const allocator = std.testing.allocator;
    setEnvForTest("ANTHROPIC_API_KEY_TEST", "test-key");

    var url_buf: [64]u8 = undefined;
    var listener: std.net.Server = undefined;
    var url: []const u8 = undefined;
    const t = try startFakeServer(
        200,
        \\{"content":[{"type":"text","text":"{\"modal\":\"find\",\"who\":\"self\",\"what\":\"recent-jobs\",\"why\":\"\",\"confidence\":0.8}"}]}
        ,
        &url_buf,
        &listener,
        &url,
    );
    defer t.join();
    defer listener.deinit();

    var adapter = http_adapter.HttpLlmAdapter.init(allocator, .{
        .enabled = true,
        .backend = .anthropic,
        .endpoint = url,
        .model = "claude-sonnet-4-5",
        .api_key_env = "ANTHROPIC_API_KEY_TEST",
    });
    const result = try adapter.parse(allocator, .{
        .utterance = "find my recent jobs",
        .available_verbs = "send,find,talk",
    });
    defer {
        allocator.free(result.who);
        allocator.free(result.what);
        allocator.free(result.why);
    }
    try std.testing.expectEqual(llm.Modal.find, result.modal);
    try std.testing.expectEqualSlices(u8, "recent-jobs", result.what);
}

test "Brain 5.1 local llama.cpp end-to-end against localhost fake" {
    const allocator = std.testing.allocator;

    var url_buf: [64]u8 = undefined;
    var listener: std.net.Server = undefined;
    var url: []const u8 = undefined;
    const t = try startFakeServer(
        200,
        \\{"content":"{\"modal\":\"talk\",\"who\":\"alice\",\"what\":\"hi\",\"why\":\"\",\"confidence\":0.7}"}
        ,
        &url_buf,
        &listener,
        &url,
    );
    defer t.join();
    defer listener.deinit();

    var adapter = http_adapter.HttpLlmAdapter.init(allocator, .{
        .enabled = true,
        .backend = .local,
        .endpoint = url,
        .model = "llama-3.1-8b-instruct",
        .api_key_env = "",
    });
    const result = try adapter.parse(allocator, .{
        .utterance = "say hi to alice",
        .available_verbs = "send,find,talk",
    });
    defer {
        allocator.free(result.who);
        allocator.free(result.what);
        allocator.free(result.why);
    }
    try std.testing.expectEqual(llm.Modal.talk, result.modal);
    try std.testing.expectEqualSlices(u8, "alice", result.who);
}

test "Brain 5.1 401 maps to config_error" {
    const allocator = std.testing.allocator;
    setEnvForTest("OPENAI_API_KEY_TEST", "test-key");

    var url_buf: [64]u8 = undefined;
    var listener: std.net.Server = undefined;
    var url: []const u8 = undefined;
    const t = try startFakeServer(
        401,
        "{\"error\":\"unauthorized\"}",
        &url_buf,
        &listener,
        &url,
    );
    defer t.join();
    defer listener.deinit();

    var adapter = http_adapter.HttpLlmAdapter.init(allocator, .{
        .enabled = true,
        .backend = .openai,
        .endpoint = url,
        .model = "gpt-4o",
        .api_key_env = "OPENAI_API_KEY_TEST",
    });
    try std.testing.expectError(llm.LlmError.config_error, adapter.parse(allocator, .{
        .utterance = "x",
        .available_verbs = "y",
    }));
}

test "Brain 5.1 429 maps to rate_limited" {
    const allocator = std.testing.allocator;
    setEnvForTest("OPENAI_API_KEY_TEST", "test-key");

    var url_buf: [64]u8 = undefined;
    var listener: std.net.Server = undefined;
    var url: []const u8 = undefined;
    const t = try startFakeServer(
        429,
        "{\"error\":\"too many requests\"}",
        &url_buf,
        &listener,
        &url,
    );
    defer t.join();
    defer listener.deinit();

    var adapter = http_adapter.HttpLlmAdapter.init(allocator, .{
        .enabled = true,
        .backend = .openai,
        .endpoint = url,
        .model = "gpt-4o",
        .api_key_env = "OPENAI_API_KEY_TEST",
    });
    try std.testing.expectError(llm.LlmError.rate_limited, adapter.parse(allocator, .{
        .utterance = "x",
        .available_verbs = "y",
    }));
}

test "Brain 5.1 missing api_key_env returns config_error" {
    const allocator = std.testing.allocator;

    // No fake server needed — we expect the env-var check to short-circuit
    // before any network call. Use an unreachable URL so a regression
    // (network call happening anyway) would surface as a different error.
    var adapter = http_adapter.HttpLlmAdapter.init(allocator, .{
        .enabled = true,
        .backend = .openai,
        .endpoint = "http://127.0.0.1:1/never-called",
        .model = "gpt-4o",
        .api_key_env = "VAR_THAT_DEFINITELY_DOES_NOT_EXIST_8675309",
    });
    try std.testing.expectError(llm.LlmError.config_error, adapter.parse(allocator, .{
        .utterance = "x",
        .available_verbs = "y",
    }));
}

```
