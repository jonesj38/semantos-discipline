---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/msg.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.288406+00:00
---

# runtime/semantos-brain/src/cli/msg.zig

```zig
// D-network-messagebox-first-class — `brain msg` CLI cluster.
//
// Thin HTTP wrapper around /api/v1/messages/{send,list,ack} so the
// operator can drive brain-to-brain messages from a shell without
// hand-rolling curl each time.
//
// Three subverbs:
//
//   brain msg send --to <brain-url> --recipient <hex66> [--kind <s>] --text <s>
//     Deposits a message into the remote brain's inbox.  Recipient is the
//     remote operator's BRC-52 cert pubkey (compressed hex, 66 chars).
//     Payload is sent as base64 of UTF-8 text; --kind defaults to "text".
//     No bearer required (unauthenticated deposit by design — see the
//     send handler in serve.zig).
//
//   brain msg list [--brain-url <url>] [--recipient <hex66>] [--bearer <hex64>]
//     Lists messages addressed to <recipient>.  Defaults: brain-url
//     http://127.0.0.1:8080, recipient = local operator root pubkey (read
//     from <data-dir>/identity-certs.log if present), bearer from
//     $BRAIN_BEARER env or interactive prompt.
//
//   brain msg ack --msg-id <hex32> [--brain-url <url>] [--bearer <hex64>]
//     Deletes a message after the operator has processed it.
//
// No Unix-socket dispatch — these are pure HTTP calls.  Works whether
// the brain is running locally or remotely, and never blocks on the
// brain's single-threaded reactor (HTTP requests fan in via the normal
// accept loop, separate from this caller's process).

const std = @import("std");
const cli_common = @import("common.zig");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;
const resolveDataDir = cli_common.resolveDataDir;

const DEFAULT_BRAIN_URL = "http://127.0.0.1:8080";
// Brain accepts "signed" (BRC-77 signed envelope) or "encrypted" (BRC-78).
// The send endpoint deposits without verifying the envelope payload — the
// kind is metadata the recipient uses to know how to decode.  We default to
// "signed" because that's the common case for plain-text-with-sender-proof
// brain-to-brain pings; richer end-to-end-encrypted payloads use "encrypted".
const DEFAULT_KIND = "signed";

pub fn cmdMsg(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    if (args.len < 1) {
        try out.print("{s}", .{HELP_TEXT});
        return .bad_args;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "send")) {
        return cmdSend(allocator, out, args[1..]);
    } else if (std.mem.eql(u8, sub, "list")) {
        return cmdList(allocator, out, args[1..]);
    } else if (std.mem.eql(u8, sub, "ack")) {
        return cmdAck(allocator, out, args[1..]);
    } else if (std.mem.eql(u8, sub, "help") or std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h")) {
        try out.print("{s}", .{HELP_TEXT});
        return .ok;
    }
    try out.print("unknown subcommand: {s}\n\n{s}", .{ sub, HELP_TEXT });
    return .bad_args;
}

// ── send ─────────────────────────────────────────────────────────────────

fn cmdSend(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var to_url: ?[]const u8 = null;
    var recipient: ?[]const u8 = null;
    var kind: []const u8 = DEFAULT_KIND;
    var text: ?[]const u8 = null;
    var payload_b64_arg: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--to") and i + 1 < args.len) {
            to_url = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--recipient") and i + 1 < args.len) {
            recipient = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--kind") and i + 1 < args.len) {
            kind = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--text") and i + 1 < args.len) {
            text = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--payload-b64") and i + 1 < args.len) {
            payload_b64_arg = args[i + 1];
            i += 1;
        } else {
            try out.print("unknown arg: {s}\n\n{s}", .{ a, SEND_HELP });
            return .bad_args;
        }
    }

    if (to_url == null) {
        try out.print("missing --to <brain-url>\n\n{s}", .{SEND_HELP});
        return .bad_args;
    }
    if (recipient == null) {
        try out.print("missing --recipient <hex66>\n\n{s}", .{SEND_HELP});
        return .bad_args;
    }
    if (text == null and payload_b64_arg == null) {
        try out.print("missing --text or --payload-b64\n\n{s}", .{SEND_HELP});
        return .bad_args;
    }
    if (text != null and payload_b64_arg != null) {
        try out.print("pass --text OR --payload-b64, not both\n", .{});
        return .bad_args;
    }

    const recipient_str = recipient.?;
    if (recipient_str.len != 66) {
        try out.print(
            "recipient must be a 66-char compressed pubkey hex (got {d} chars)\n",
            .{recipient_str.len},
        );
        return .bad_args;
    }

    // Encode payload as base64 if --text was given.
    var payload_b64_buf: []u8 = &.{};
    defer if (payload_b64_buf.len > 0) allocator.free(payload_b64_buf);
    const payload_b64: []const u8 = if (text) |t| blk: {
        const enc = std.base64.standard.Encoder;
        const out_len = enc.calcSize(t.len);
        payload_b64_buf = try allocator.alloc(u8, out_len);
        break :blk enc.encode(payload_b64_buf, t);
    } else payload_b64_arg.?;

    // Get our own pubkey (sender) — best-effort from identity-certs.log.
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    const sender = readOperatorPubkey(allocator, data_dir) catch null;
    defer if (sender) |s| allocator.free(s);

    // Build send URL + JSON body.
    const send_url = try std.fmt.allocPrint(allocator, "{s}/api/v1/messages/send", .{to_url.?});
    defer allocator.free(send_url);

    var body_buf: std.ArrayList(u8) = .{};
    defer body_buf.deinit(allocator);
    try body_buf.appendSlice(allocator, "{\"sender\":\"");
    try body_buf.appendSlice(allocator, sender orelse "");
    try body_buf.appendSlice(allocator, "\",\"recipient\":\"");
    try body_buf.appendSlice(allocator, recipient_str);
    try body_buf.appendSlice(allocator, "\",\"kind\":\"");
    try body_buf.appendSlice(allocator, kind);
    try body_buf.appendSlice(allocator, "\",\"payload\":\"");
    try body_buf.appendSlice(allocator, payload_b64);
    try body_buf.appendSlice(allocator, "\"}");

    const result = try httpPost(allocator, send_url, body_buf.items, null);
    defer allocator.free(result.body);

    try out.print("→ POST {s}\n  HTTP {d}\n  {s}\n", .{ send_url, result.status, result.body });
    return if (result.status >= 200 and result.status < 300) .ok else .bad_args;
}

// ── list ─────────────────────────────────────────────────────────────────

fn cmdList(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var brain_url: []const u8 = DEFAULT_BRAIN_URL;
    var recipient: ?[]const u8 = null;
    var bearer: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--brain-url") and i + 1 < args.len) {
            brain_url = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--recipient") and i + 1 < args.len) {
            recipient = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--bearer") and i + 1 < args.len) {
            bearer = args[i + 1];
            i += 1;
        } else {
            try out.print("unknown arg: {s}\n\n{s}", .{ a, LIST_HELP });
            return .bad_args;
        }
    }

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    // Default recipient = local operator root pubkey.
    var owned_recipient: ?[]u8 = null;
    defer if (owned_recipient) |r| allocator.free(r);
    if (recipient == null) {
        owned_recipient = readOperatorPubkey(allocator, data_dir) catch null;
        if (owned_recipient) |r| recipient = r;
    }
    if (recipient == null) {
        try out.print(
            "no --recipient given and could not auto-derive from {s}/identity-certs.log\n",
            .{data_dir},
        );
        return .bad_args;
    }

    // Bearer: --bearer wins; else $BRAIN_BEARER.
    var owned_bearer: ?[]u8 = null;
    defer if (owned_bearer) |b| allocator.free(b);
    if (bearer == null) {
        if (std.process.getEnvVarOwned(allocator, "BRAIN_BEARER")) |v| {
            owned_bearer = v;
            bearer = v;
        } else |_| {}
    }
    if (bearer == null) {
        try out.print("missing --bearer or $BRAIN_BEARER\n\n{s}", .{LIST_HELP});
        return .bad_args;
    }

    const list_url = try std.fmt.allocPrint(
        allocator,
        "{s}/api/v1/messages/list?recipient={s}",
        .{ brain_url, recipient.? },
    );
    defer allocator.free(list_url);

    const result = try httpGet(allocator, list_url, bearer.?);
    defer allocator.free(result.body);

    try out.print("← GET {s}\n  HTTP {d}\n  {s}\n", .{ list_url, result.status, result.body });
    return if (result.status >= 200 and result.status < 300) .ok else .bad_args;
}

// ── ack ──────────────────────────────────────────────────────────────────

fn cmdAck(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var brain_url: []const u8 = DEFAULT_BRAIN_URL;
    var msg_id: ?[]const u8 = null;
    var bearer: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--brain-url") and i + 1 < args.len) {
            brain_url = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--msg-id") and i + 1 < args.len) {
            msg_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--bearer") and i + 1 < args.len) {
            bearer = args[i + 1];
            i += 1;
        } else {
            try out.print("unknown arg: {s}\n\n{s}", .{ a, ACK_HELP });
            return .bad_args;
        }
    }
    if (msg_id == null) {
        try out.print("missing --msg-id <hex32>\n\n{s}", .{ACK_HELP});
        return .bad_args;
    }

    // Bearer fallback.
    var owned_bearer: ?[]u8 = null;
    defer if (owned_bearer) |b| allocator.free(b);
    if (bearer == null) {
        if (std.process.getEnvVarOwned(allocator, "BRAIN_BEARER")) |v| {
            owned_bearer = v;
            bearer = v;
        } else |_| {}
    }
    if (bearer == null) {
        try out.print("missing --bearer or $BRAIN_BEARER\n\n{s}", .{ACK_HELP});
        return .bad_args;
    }

    const ack_url = try std.fmt.allocPrint(allocator, "{s}/api/v1/messages/ack", .{brain_url});
    defer allocator.free(ack_url);

    // Brain ack handler expects {"id":"<hex32>"}, per messagebox_http.zig docstring.
    const body = try std.fmt.allocPrint(allocator, "{{\"id\":\"{s}\"}}", .{msg_id.?});
    defer allocator.free(body);

    const result = try httpPost(allocator, ack_url, body, bearer);
    defer allocator.free(result.body);

    try out.print("→ POST {s}\n  HTTP {d}\n  {s}\n", .{ ack_url, result.status, result.body });
    return if (result.status >= 200 and result.status < 300) .ok else .bad_args;
}

// ── HTTP helpers ─────────────────────────────────────────────────────────

const HttpResult = struct {
    status: u16,
    body: []u8, // owned by caller
};

fn httpPost(
    allocator: std.mem.Allocator,
    url: []const u8,
    body: []const u8,
    bearer: ?[]const u8,
) !HttpResult {
    var auth_buf: [256]u8 = undefined;
    var hdr_list: [2]std.http.Header = undefined;
    var hdr_count: usize = 1;
    hdr_list[0] = .{ .name = "Content-Type", .value = "application/json" };
    if (bearer) |b| {
        const auth = try std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{b});
        hdr_list[1] = .{ .name = "Authorization", .value = auth };
        hdr_count = 2;
    }

    var resp_writer = std.io.Writer.Allocating.init(allocator);
    defer resp_writer.deinit();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = body,
        .extra_headers = hdr_list[0..hdr_count],
        .response_writer = &resp_writer.writer,
    });

    return .{
        .status = @intFromEnum(result.status),
        .body = try allocator.dupe(u8, resp_writer.written()),
    };
}

fn httpGet(
    allocator: std.mem.Allocator,
    url: []const u8,
    bearer: []const u8,
) !HttpResult {
    var auth_buf: [256]u8 = undefined;
    const auth = try std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{bearer});
    var hdrs = [_]std.http.Header{
        .{ .name = "Authorization", .value = auth },
    };

    var resp_writer = std.io.Writer.Allocating.init(allocator);
    defer resp_writer.deinit();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .extra_headers = hdrs[0..],
        .response_writer = &resp_writer.writer,
    });

    return .{
        .status = @intFromEnum(result.status),
        .body = try allocator.dupe(u8, resp_writer.written()),
    };
}

// ── identity helper ──────────────────────────────────────────────────────

/// Best-effort: read the operator root pubkey from identity-certs.log.
/// Returns owned slice on success; null on any I/O / parse failure.
fn readOperatorPubkey(allocator: std.mem.Allocator, data_dir: []const u8) !?[]u8 {
    const path = try std.fs.path.join(allocator, &.{ data_dir, "identity-certs.log" });
    defer allocator.free(path);
    var f = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer f.close();
    var buf: [4096]u8 = undefined;
    const n = f.read(&buf) catch return null;
    const content = buf[0..n];
    // Find the first newline-delimited record and pluck "pubkey":"<66hex>"
    // — best-effort string scan, no full JSON parser pulled in.
    var line_iter = std.mem.splitScalar(u8, content, '\n');
    while (line_iter.next()) |line| {
        if (std.mem.indexOf(u8, line, "\"pubkey\":\"")) |idx| {
            const start = idx + "\"pubkey\":\"".len;
            if (start + 66 <= line.len) {
                return try allocator.dupe(u8, line[start .. start + 66]);
            }
        }
    }
    return null;
}

// ── help text ────────────────────────────────────────────────────────────

const HELP_TEXT =
    \\brain msg — brain-to-brain message inbox helpers
    \\
    \\USAGE:
    \\  brain msg send  --to <brain-url> --recipient <hex66> --text "..."
    \\  brain msg list  [--brain-url <url>] [--recipient <hex66>] [--bearer <hex64>]
    \\  brain msg ack   --msg-id <hex32> [--brain-url <url>] [--bearer <hex64>]
    \\
    \\Defaults:
    \\  --brain-url   http://127.0.0.1:8080
    \\  --recipient   local operator root pubkey (auto-read from identity-certs.log)
    \\  --bearer      $BRAIN_BEARER env var
    \\  --kind        signed       (one of: signed | encrypted)
    \\
    \\Examples:
    \\  # Reply to Bridget
    \\  brain msg send --to https://brain.utxoengineer.com \
    \\    --recipient 029cf8...etc-66hex \
    \\    --text "got your message — federation is live"
    \\
    \\  # Read your own inbox
    \\  brain msg list
    \\
    \\  # Ack after reading
    \\  brain msg ack --msg-id 42a69d70e918ff2d7c55cda84eb043f1
    \\
;

const SEND_HELP =
    \\brain msg send — deposit a message in a remote brain's inbox
    \\
    \\REQUIRED:
    \\  --to <brain-url>           e.g. https://brain.utxoengineer.com
    \\  --recipient <hex66>        BRC-52 cert pubkey of the recipient operator
    \\  --text "..." | --payload-b64 <b64>
    \\
    \\OPTIONAL:
    \\  --kind <s>                 signed | encrypted (default: signed)
    \\
;

const LIST_HELP =
    \\brain msg list — list messages addressed to <recipient>
    \\
    \\OPTIONAL:
    \\  --brain-url <url>          (default: http://127.0.0.1:8080)
    \\  --recipient <hex66>        (default: local operator root pubkey)
    \\  --bearer <hex64>           (default: $BRAIN_BEARER)
    \\
;

const ACK_HELP =
    \\brain msg ack — delete a message after reading
    \\
    \\REQUIRED:
    \\  --msg-id <hex32>
    \\
    \\OPTIONAL:
    \\  --brain-url <url>          (default: http://127.0.0.1:8080)
    \\  --bearer <hex64>           (default: $BRAIN_BEARER)
    \\
;

// ── Tests ────────────────────────────────────────────────────────────────

const testing = std.testing;

test "msg: readOperatorPubkey extracts 66-char hex from log line" {
    const tmp_dir = testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const log_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer tmp_dir.free(log_path);

    const log_file_path = try std.fs.path.join(testing.allocator, &.{ log_path, "identity-certs.log" });
    defer testing.allocator.free(log_file_path);

    const sample =
        \\{"ts":1779000000,"kind":"root","pubkey":"029cf8e43942bd9a3f1c58b3a843049d9b95ecbb0532f20021ac465bb62a08dfec","other":"stuff"}
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = log_file_path, .data = sample });

    const result = try readOperatorPubkey(testing.allocator, log_path);
    try testing.expect(result != null);
    defer testing.allocator.free(result.?);
    try testing.expectEqualStrings(
        "029cf8e43942bd9a3f1c58b3a843049d9b95ecbb0532f20021ac465bb62a08dfec",
        result.?,
    );
}

test "msg: readOperatorPubkey returns null on missing file" {
    const tmp_dir = testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const log_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer tmp_dir.free(log_path);

    const result = try readOperatorPubkey(testing.allocator, log_path);
    try testing.expect(result == null);
}

```
