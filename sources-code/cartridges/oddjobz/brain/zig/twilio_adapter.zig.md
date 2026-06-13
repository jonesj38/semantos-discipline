---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/twilio_adapter.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.480850+00:00
---

# cartridges/oddjobz/brain/zig/twilio_adapter.zig

```zig
// Twilio adapter — operator-initiated SMS dispatch.
//
// Per docs/design/CUSTOMER-CONV-LOOP-PLAN.md W1 (TDD-strict).
//
// Public surface (W1.x as it lands):
//   - formatE164(raw, default_country_code) → []u8  (W1.1 + W1.2)
//   - sendSms(to_e164, body, sender_fn) → Result    (W1.3 + W1.4)
//   - loadConfig(path) → Config                      (W1.5 + W1.6)
//
// Design notes:
//   - Pure Zig. No HTTP client coupling at unit-test level; sendSms
//     takes an injectable sender_fn so tests run without a real
//     Twilio account.
//   - E.164 regex match target: ^\+[1-9]\d{1,14}$  (mirrors
//     customer.v2.ts:E164_RE so the validator on both ends agrees).
//   - Default country code is an operator config knob; the per-call
//     argument lets tests override it without loading config.

const std = @import("std");

pub const Error = error{
    invalid_phone,
    invalid_country_code,
    rate_limited,
    invalid_recipient,
    twilio_not_configured,
    http_error,
    out_of_memory,
};

// ────────────────────────────────────────────────────────────────────
// formatE164
//
// Takes messy user-input phone formats and normalises to E.164:
//   "0412 345 678"           + "+61"  → "+61412345678"  (AU mobile)
//   "+1 (555) 123-4567"       any     → "+15551234567"  (already E.164)
//   "0061412345678"          + any    → "+61412345678"  (00 intl prefix)
//   "0412345678"             + "+61"  → "+61412345678"  (no separators)
//   "abc"                    + any    → error.invalid_phone
//   ""                       + any    → error.invalid_phone
//   "5"                      + "+61"  → error.invalid_phone (too short)
//
// Caller owns the returned slice (allocator-allocated). The
// algorithm:
//   1. Strip whitespace + hyphens + parens + dots from raw.
//   2. If starts with "+", validate digits-only follow + length 2..16,
//      return as-is (idempotent on already-E.164 input).
//   3. If starts with "00", replace with "+" and re-validate.
//   4. If starts with "0", strip leading 0 + prefix default cc.
//   5. Otherwise, prefix default cc directly.
// ────────────────────────────────────────────────────────────────────

pub fn formatE164(
    allocator: std.mem.Allocator,
    raw: []const u8,
    default_country_code: []const u8,
) Error![]u8 {
    if (raw.len == 0) return Error.invalid_phone;

    // Step 1: strip whitespace, hyphens, parens, dots — preserve only
    // digits + leading '+'.
    var scratch_buf: [32]u8 = undefined;
    var scratch_len: usize = 0;
    var seen_plus = false;
    for (raw) |c| {
        if (c == '+') {
            if (scratch_len != 0) return Error.invalid_phone; // + only allowed at start
            seen_plus = true;
            if (scratch_len >= scratch_buf.len) return Error.invalid_phone;
            scratch_buf[scratch_len] = c;
            scratch_len += 1;
        } else if (c >= '0' and c <= '9') {
            if (scratch_len >= scratch_buf.len) return Error.invalid_phone;
            scratch_buf[scratch_len] = c;
            scratch_len += 1;
        } else if (c == ' ' or c == '\t' or c == '-' or c == '.' or c == '(' or c == ')') {
            // Separator — skip.
            continue;
        } else {
            // Any other character is garbage.
            return Error.invalid_phone;
        }
    }

    if (scratch_len == 0) return Error.invalid_phone;
    const scratch = scratch_buf[0..scratch_len];

    // Determine the canonical digits + which prefix to apply.
    //
    // Cases:
    //   "+15551234567"      → already E.164 (validate, return as-is)
    //   "0061412345678"     → "00" intl prefix → strip + prepend "+"
    //   "0412345678"        → leading 0 (national) → strip + prepend default_cc
    //   "412345678"         → no prefix → prepend default_cc
    //
    // For the non-E.164 branches, we need a valid default_country_code:
    //   must start with '+', followed by 1..4 digits, no other chars.
    var result_buf: [16]u8 = undefined;
    var result_len: usize = 0;

    if (seen_plus) {
        // Branch 1: input is +<digits>. Just validate length.
        // E.164: total 2..16 chars ("+" plus 1..15 digits), first digit non-zero.
        if (scratch.len < 2 or scratch.len > 16) return Error.invalid_phone;
        if (scratch[1] == '0') return Error.invalid_phone; // first digit non-zero
        @memcpy(result_buf[0..scratch.len], scratch);
        result_len = scratch.len;
    } else if (scratch.len >= 4 and scratch[0] == '0' and scratch[1] == '0') {
        // Branch 2: 00 intl prefix → +
        const digits = scratch[2..];
        if (digits.len < 1 or digits.len > 15) return Error.invalid_phone;
        if (digits[0] == '0') return Error.invalid_phone;
        result_buf[0] = '+';
        @memcpy(result_buf[1 .. 1 + digits.len], digits);
        result_len = 1 + digits.len;
    } else {
        // Branch 3 + 4: needs default_country_code.
        // Validate cc: starts with '+', then 1..4 digits, first digit non-zero.
        if (default_country_code.len < 2 or default_country_code.len > 5) {
            return Error.invalid_country_code;
        }
        if (default_country_code[0] != '+') return Error.invalid_country_code;
        if (default_country_code[1] == '0') return Error.invalid_country_code;
        for (default_country_code[1..]) |c| {
            if (c < '0' or c > '9') return Error.invalid_country_code;
        }

        // Strip leading single 0 if present (national format).
        const national_digits = if (scratch.len > 0 and scratch[0] == '0')
            scratch[1..]
        else
            scratch;
        // Realistic minimum national portion is 4 digits — rejects "5" etc.
        // E.164 technically allows 1 digit but no real PSTN does.
        if (national_digits.len < 4) return Error.invalid_phone;

        const total_len = default_country_code.len + national_digits.len;
        if (total_len < 2 or total_len > 16) return Error.invalid_phone;
        @memcpy(result_buf[0..default_country_code.len], default_country_code);
        @memcpy(result_buf[default_country_code.len .. default_country_code.len + national_digits.len], national_digits);
        result_len = total_len;
    }

    // Final E.164 sanity (defense-in-depth — mirror customer.v2.ts:E164_RE):
    //   ^\+[1-9]\d{1,14}$
    if (result_len < 2 or result_len > 16) return Error.invalid_phone;
    if (result_buf[0] != '+') return Error.invalid_phone;
    if (result_buf[1] < '1' or result_buf[1] > '9') return Error.invalid_phone;
    for (result_buf[2..result_len]) |c| {
        if (c < '0' or c > '9') return Error.invalid_phone;
    }

    const out = allocator.alloc(u8, result_len) catch return Error.out_of_memory;
    @memcpy(out, result_buf[0..result_len]);
    return out;
}

// ────────────────────────────────────────────────────────────────────
// Twilio config — loaded from /var/lib/semantos/twilio.json at boot.
// Used by sendSms + (later) verifyStart / verifyCheck.
// ────────────────────────────────────────────────────────────────────

pub const TwilioConfig = struct {
    account_sid: []const u8,
    auth_token: []const u8,
    sender_phone: []const u8, // E.164 from-number
    verify_service_sid: []const u8 = "", // optional; verify flow lands later
    default_country_code: []const u8 = "+61", // operator default for formatE164
};

// OwnedConfig wraps a TwilioConfig whose string fields are heap-allocated
// (so the source bytes — file/JSON buffer — can be freed independently).
//
// Callers that load config from disk receive OwnedConfig and must
// deinit() it when done. They pass `.config` to sendSms / verify / etc.
pub const OwnedConfig = struct {
    config: TwilioConfig,
    // Backing buffers — separately tracked so deinit() can free them.
    // String slices in `config` point into these.
    account_sid_buf: []u8 = &.{},
    auth_token_buf: []u8 = &.{},
    sender_phone_buf: []u8 = &.{},
    verify_service_sid_buf: []u8 = &.{},
    default_country_code_buf: []u8 = &.{},

    pub fn deinit(self: *OwnedConfig, allocator: std.mem.Allocator) void {
        if (self.account_sid_buf.len > 0) allocator.free(self.account_sid_buf);
        if (self.auth_token_buf.len > 0) allocator.free(self.auth_token_buf);
        if (self.sender_phone_buf.len > 0) allocator.free(self.sender_phone_buf);
        if (self.verify_service_sid_buf.len > 0) allocator.free(self.verify_service_sid_buf);
        if (self.default_country_code_buf.len > 0) allocator.free(self.default_country_code_buf);
        self.account_sid_buf = &.{};
        self.auth_token_buf = &.{};
        self.sender_phone_buf = &.{};
        self.verify_service_sid_buf = &.{};
        self.default_country_code_buf = &.{};
    }
};

// ────────────────────────────────────────────────────────────────────
// parseConfig — parse Twilio config JSON bytes into OwnedConfig.
//
// Required fields: account_sid, auth_token, sender_phone.
// Optional: verify_service_sid, default_country_code (defaults "+61").
//
// On any failure (malformed JSON, missing required field, empty
// required field) returns Error.twilio_not_configured. The operator
// runbook reads "either everything is wired or nothing is" — we don't
// want to half-boot the Twilio path on a malformed file.
//
// W1.5 RED: stub returns Error.twilio_not_configured for every input.
// W1.6 GREEN: real parser.
// ────────────────────────────────────────────────────────────────────

pub fn parseConfig(
    allocator: std.mem.Allocator,
    json_bytes: []const u8,
) Error!OwnedConfig {
    // Parse with std.json. Wrap parse errors in twilio_not_configured —
    // the operator-facing semantics is binary (configured / not).
    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_bytes,
        .{},
    ) catch return Error.twilio_not_configured;
    defer parsed.deinit();

    if (parsed.value != .object) return Error.twilio_not_configured;
    const obj = parsed.value.object;

    const account_sid = stringField(obj, "account_sid") orelse return Error.twilio_not_configured;
    const auth_token = stringField(obj, "auth_token") orelse return Error.twilio_not_configured;
    const sender_phone = stringField(obj, "sender_phone") orelse return Error.twilio_not_configured;
    if (account_sid.len == 0 or auth_token.len == 0 or sender_phone.len == 0) {
        return Error.twilio_not_configured;
    }

    const verify_sid = stringField(obj, "verify_service_sid") orelse "";
    const default_cc = stringField(obj, "default_country_code") orelse "+61";

    var owned = OwnedConfig{ .config = undefined };
    errdefer owned.deinit(allocator);

    owned.account_sid_buf = allocator.dupe(u8, account_sid) catch return Error.out_of_memory;
    owned.auth_token_buf = allocator.dupe(u8, auth_token) catch return Error.out_of_memory;
    owned.sender_phone_buf = allocator.dupe(u8, sender_phone) catch return Error.out_of_memory;
    owned.verify_service_sid_buf = allocator.dupe(u8, verify_sid) catch return Error.out_of_memory;
    owned.default_country_code_buf = allocator.dupe(u8, default_cc) catch return Error.out_of_memory;

    owned.config = TwilioConfig{
        .account_sid = owned.account_sid_buf,
        .auth_token = owned.auth_token_buf,
        .sender_phone = owned.sender_phone_buf,
        .verify_service_sid = owned.verify_service_sid_buf,
        .default_country_code = owned.default_country_code_buf,
    };

    return owned;
}

fn stringField(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

// ────────────────────────────────────────────────────────────────────
// loadConfig — read JSON file from disk, parse via parseConfig.
//
// Standard path: /var/lib/semantos/twilio.json
// File absent → Error.twilio_not_configured (gracefully tells the
// reactor "no Twilio path available; return 503 on send attempts").
//
// W1.5 RED: stub returns Error.twilio_not_configured.
// W1.6 GREEN: read file + delegate to parseConfig.
// ────────────────────────────────────────────────────────────────────

pub fn loadConfig(
    allocator: std.mem.Allocator,
    path: []const u8,
) Error!OwnedConfig {
    // Read the file. Any IO error (absent, permission denied, etc.)
    // collapses to twilio_not_configured — the reactor's downstream
    // 503 semantics is the same regardless of *why* config is missing.
    const file = std.fs.cwd().openFile(path, .{}) catch return Error.twilio_not_configured;
    defer file.close();

    const max_size: usize = 64 * 1024; // 64 KiB is generous for a small JSON config.
    const bytes = file.readToEndAlloc(allocator, max_size) catch return Error.twilio_not_configured;
    defer allocator.free(bytes);

    return parseConfig(allocator, bytes);
}

// ────────────────────────────────────────────────────────────────────
// SenderFn — injectable HTTP layer.
//
// The adapter constructs the SendRequest (URL, auth header, body)
// and passes it to the sender. The sender returns the raw HTTP
// response. Unit tests pass a mock; production passes the real HTTP
// client.
//
// This separation keeps the adapter's logic (URL construction,
// auth, response parsing) fully testable without a network stack.
// ────────────────────────────────────────────────────────────────────

pub const SendRequest = struct {
    url: []const u8,
    auth_header: []const u8,
    body: []const u8,
};

pub const SendResponse = struct {
    status_code: u16,
    body: []const u8,
};

pub const SenderFn = *const fn (req: SendRequest, ctx: ?*anyopaque) anyerror!SendResponse;

// ────────────────────────────────────────────────────────────────────
// sendSms result type — owned strings, deinit frees them.
// ────────────────────────────────────────────────────────────────────

pub const MessageSent = struct {
    sid: []u8,
    status: []u8,

    pub fn deinit(self: *MessageSent, allocator: std.mem.Allocator) void {
        if (self.sid.len > 0) allocator.free(self.sid);
        if (self.status.len > 0) allocator.free(self.status);
        self.sid = &.{};
        self.status = &.{};
    }
};

// ────────────────────────────────────────────────────────────────────
// sendSms — operator-initiated SMS send via Twilio API.
//
// Builds the Twilio Messages.json POST request, dispatches via the
// injectable sender_fn, parses the response.
//
// Success: 201 with JSON containing {"sid":"SMxx","status":"queued"}
//   → returns MessageSent (caller frees via deinit).
// 429:                       → Error.rate_limited
// 400 with body code 21211:  → Error.invalid_recipient
// Anything else:             → Error.http_error
//
// W1.3 RED: stub returns Error.http_error for every input.
// W1.4 GREEN: full implementation.
// ────────────────────────────────────────────────────────────────────

pub fn sendSms(
    allocator: std.mem.Allocator,
    config: TwilioConfig,
    to_e164: []const u8,
    body: []const u8,
    sender: SenderFn,
    sender_ctx: ?*anyopaque,
) Error!MessageSent {
    // 1. Build URL.
    const url = std.fmt.allocPrint(
        allocator,
        "https://api.twilio.com/2010-04-01/Accounts/{s}/Messages.json",
        .{config.account_sid},
    ) catch return Error.out_of_memory;
    defer allocator.free(url);

    // 2. Build basic auth header.
    //    "Basic " + base64(account_sid + ":" + auth_token)
    const credential = std.fmt.allocPrint(
        allocator,
        "{s}:{s}",
        .{ config.account_sid, config.auth_token },
    ) catch return Error.out_of_memory;
    defer allocator.free(credential);

    const enc = std.base64.standard.Encoder;
    const encoded_len = enc.calcSize(credential.len);
    const auth_header = allocator.alloc(u8, "Basic ".len + encoded_len) catch return Error.out_of_memory;
    defer allocator.free(auth_header);
    @memcpy(auth_header[0.."Basic ".len], "Basic ");
    _ = enc.encode(auth_header["Basic ".len..], credential);

    // 3. Build form-encoded body: From=<enc>&To=<enc>&Body=<enc>
    var body_buf: std.ArrayList(u8) = .{};
    defer body_buf.deinit(allocator);
    body_buf.appendSlice(allocator, "From=") catch return Error.out_of_memory;
    appendFormEncoded(allocator, &body_buf, config.sender_phone) catch return Error.out_of_memory;
    body_buf.appendSlice(allocator, "&To=") catch return Error.out_of_memory;
    appendFormEncoded(allocator, &body_buf, to_e164) catch return Error.out_of_memory;
    body_buf.appendSlice(allocator, "&Body=") catch return Error.out_of_memory;
    appendFormEncoded(allocator, &body_buf, body) catch return Error.out_of_memory;

    // 4. Dispatch via injectable sender.
    const req = SendRequest{
        .url = url,
        .auth_header = auth_header,
        .body = body_buf.items,
    };
    const resp = sender(req, sender_ctx) catch return Error.http_error;

    // 5. Map response.
    return switch (resp.status_code) {
        201 => parseMessageSent(allocator, resp.body),
        429 => Error.rate_limited,
        400 => if (isTwilioCode(resp.body, 21211))
            Error.invalid_recipient
        else
            Error.http_error,
        else => Error.http_error,
    };
}

// Append `text` to `out` form-url-encoded:
//   space     → '+'
//   unreserved (alnum, '-', '.', '_', '~')  → as-is
//   anything else → %XX (two hex digits, uppercase)
fn appendFormEncoded(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    text: []const u8,
) !void {
    const hex = "0123456789ABCDEF";
    for (text) |c| {
        if (c == ' ') {
            try out.append(allocator, '+');
        } else if ((c >= 'A' and c <= 'Z') or
                   (c >= 'a' and c <= 'z') or
                   (c >= '0' and c <= '9') or
                   c == '-' or c == '.' or c == '_' or c == '~')
        {
            try out.append(allocator, c);
        } else {
            try out.append(allocator, '%');
            try out.append(allocator, hex[(c >> 4) & 0xF]);
            try out.append(allocator, hex[c & 0xF]);
        }
    }
}

// Parse Twilio JSON response body for {"sid":"...", "status":"..."}.
// Lightweight string-scan to avoid pulling in std.json overhead; Twilio's
// wire format is well-known and we only extract two fields.
fn parseMessageSent(allocator: std.mem.Allocator, body: []const u8) Error!MessageSent {
    const sid = extractJsonString(body, "sid") orelse return Error.http_error;
    const status = extractJsonString(body, "status") orelse return Error.http_error;
    const sid_buf = allocator.dupe(u8, sid) catch return Error.out_of_memory;
    errdefer allocator.free(sid_buf);
    const status_buf = allocator.dupe(u8, status) catch return Error.out_of_memory;
    return MessageSent{ .sid = sid_buf, .status = status_buf };
}

// Find a JSON string field by key and return the value (no escape processing).
// Returns null if not found. Lightweight — assumes Twilio's well-formed
// shape (no embedded escapes in sid/status values).
fn extractJsonString(body: []const u8, key: []const u8) ?[]const u8 {
    // Match pattern: "key":"value"  (with optional whitespace around colon)
    var search_buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;
    const key_start = std.mem.indexOf(u8, body, needle) orelse return null;
    var i = key_start + needle.len;
    // Skip whitespace + colon.
    while (i < body.len and (body[i] == ' ' or body[i] == '\t' or body[i] == ':')) : (i += 1) {}
    if (i >= body.len or body[i] != '"') return null;
    i += 1; // skip opening quote
    const val_start = i;
    while (i < body.len and body[i] != '"') : (i += 1) {}
    if (i >= body.len) return null;
    return body[val_start..i];
}

// Check whether the Twilio JSON error body contains {"code":<n>,...}.
fn isTwilioCode(body: []const u8, code: u32) bool {
    var search_buf: [32]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_buf, "\"code\":{d}", .{code}) catch return false;
    return std.mem.indexOf(u8, body, needle) != null;
}

// ────────────────────────────────────────────────────────────────────
// Inline tests — happy + sad paths for formatE164.
// Run via `zig build twilio_adapter_inline_test` after W1.7 wires it
// into build.zig. Until then: `zig test src/twilio_adapter.zig` works
// standalone since this module has no external deps yet.
// ────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "formatE164 — AU mobile with spaces normalises to +614..." {
    const out = try formatE164(testing.allocator, "0412 345 678", "+61");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("+61412345678", out);
}

test "formatE164 — AU mobile compact" {
    const out = try formatE164(testing.allocator, "0412345678", "+61");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("+61412345678", out);
}

test "formatE164 — US +1 with parens and dashes" {
    const out = try formatE164(testing.allocator, "+1 (555) 123-4567", "+61");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("+15551234567", out);
}

test "formatE164 — already E.164 form is idempotent" {
    const out = try formatE164(testing.allocator, "+61412345678", "+61");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("+61412345678", out);
}

test "formatE164 — 00 international prefix replaced with +" {
    const out = try formatE164(testing.allocator, "0061412345678", "+61");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("+61412345678", out);
}

test "formatE164 — empty raw rejected" {
    try testing.expectError(Error.invalid_phone, formatE164(testing.allocator, "", "+61"));
}

test "formatE164 — non-digit garbage rejected" {
    try testing.expectError(Error.invalid_phone, formatE164(testing.allocator, "not a phone", "+61"));
}

test "formatE164 — too short rejected (single digit + AU prefix is still too short)" {
    try testing.expectError(Error.invalid_phone, formatE164(testing.allocator, "5", "+61"));
}

test "formatE164 — too long rejected (>15 digits after country code)" {
    try testing.expectError(
        Error.invalid_phone,
        formatE164(testing.allocator, "0412345678901234567", "+61"),
    );
}

test "formatE164 — country code without + rejected" {
    try testing.expectError(Error.invalid_country_code, formatE164(testing.allocator, "0412345678", "61"));
}

test "formatE164 — empty country code with national-format raw rejected" {
    try testing.expectError(Error.invalid_country_code, formatE164(testing.allocator, "0412345678", ""));
}

test "formatE164 — international with hyphen separator" {
    const out = try formatE164(testing.allocator, "+61-412-345-678", "+61");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("+61412345678", out);
}

test "formatE164 — international with dots" {
    const out = try formatE164(testing.allocator, "+61.412.345.678", "+61");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("+61412345678", out);
}

// ────────────────────────────────────────────────────────────────────
// sendSms tests — mock sender captures the request and returns
// pre-set responses.
// ────────────────────────────────────────────────────────────────────

const MockSender = struct {
    last_url: []u8 = &.{},
    last_auth: []u8 = &.{},
    last_body: []u8 = &.{},
    canned_status: u16 = 200,
    canned_response_body: []const u8 = "",
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) MockSender {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *MockSender) void {
        if (self.last_url.len > 0) self.allocator.free(self.last_url);
        if (self.last_auth.len > 0) self.allocator.free(self.last_auth);
        if (self.last_body.len > 0) self.allocator.free(self.last_body);
        self.last_url = &.{};
        self.last_auth = &.{};
        self.last_body = &.{};
    }

    fn send(req: SendRequest, ctx: ?*anyopaque) anyerror!SendResponse {
        const self: *MockSender = @ptrCast(@alignCast(ctx.?));
        // Capture the request — caller owns these buffers via deinit.
        self.last_url = try self.allocator.dupe(u8, req.url);
        self.last_auth = try self.allocator.dupe(u8, req.auth_header);
        self.last_body = try self.allocator.dupe(u8, req.body);
        return SendResponse{
            .status_code = self.canned_status,
            .body = self.canned_response_body,
        };
    }
};

const test_config = TwilioConfig{
    .account_sid = "AC0123456789abcdef",
    .auth_token = "secret-token",
    .sender_phone = "+61400000000",
};

test "sendSms — happy path: calls sender with correct URL + auth + body, returns parsed MessageSent" {
    var mock = MockSender.init(testing.allocator);
    defer mock.deinit();
    mock.canned_status = 201;
    mock.canned_response_body = "{\"sid\":\"SM1234567890abcdef\",\"status\":\"queued\"}";

    var result = try sendSms(
        testing.allocator,
        test_config,
        "+61412345678",
        "Hello",
        MockSender.send,
        &mock,
    );
    defer result.deinit(testing.allocator);

    // Sender was called with the expected URL.
    try testing.expectEqualStrings(
        "https://api.twilio.com/2010-04-01/Accounts/AC0123456789abcdef/Messages.json",
        mock.last_url,
    );
    // Basic auth header: 'Basic ' + base64("AC0123456789abcdef:secret-token")
    // base64 of "AC0123456789abcdef:secret-token" = "QUMwMTIzNDU2Nzg5YWJjZGVmOnNlY3JldC10b2tlbg=="
    try testing.expectEqualStrings(
        "Basic QUMwMTIzNDU2Nzg5YWJjZGVmOnNlY3JldC10b2tlbg==",
        mock.last_auth,
    );
    // Form-encoded body — order: From, To, Body
    try testing.expectEqualStrings(
        "From=%2B61400000000&To=%2B61412345678&Body=Hello",
        mock.last_body,
    );
    // Parsed response
    try testing.expectEqualStrings("SM1234567890abcdef", result.sid);
    try testing.expectEqualStrings("queued", result.status);
}

test "sendSms — 429 rate-limited maps to Error.rate_limited" {
    var mock = MockSender.init(testing.allocator);
    defer mock.deinit();
    mock.canned_status = 429;
    mock.canned_response_body = "{\"code\":20429,\"message\":\"Too Many Requests\"}";

    try testing.expectError(Error.rate_limited, sendSms(
        testing.allocator,
        test_config,
        "+61412345678",
        "Hello",
        MockSender.send,
        &mock,
    ));
}

test "sendSms — 400 code 21211 maps to Error.invalid_recipient" {
    var mock = MockSender.init(testing.allocator);
    defer mock.deinit();
    mock.canned_status = 400;
    mock.canned_response_body = "{\"code\":21211,\"message\":\"Invalid 'To' Phone Number\"}";

    try testing.expectError(Error.invalid_recipient, sendSms(
        testing.allocator,
        test_config,
        "+61412345678",
        "Hello",
        MockSender.send,
        &mock,
    ));
}

test "sendSms — 500 server error maps to Error.http_error" {
    var mock = MockSender.init(testing.allocator);
    defer mock.deinit();
    mock.canned_status = 500;
    mock.canned_response_body = "Internal Server Error";

    try testing.expectError(Error.http_error, sendSms(
        testing.allocator,
        test_config,
        "+61412345678",
        "Hello",
        MockSender.send,
        &mock,
    ));
}

test "sendSms — 400 with non-21211 code maps to Error.http_error (not invalid_recipient)" {
    var mock = MockSender.init(testing.allocator);
    defer mock.deinit();
    mock.canned_status = 400;
    mock.canned_response_body = "{\"code\":21610,\"message\":\"Message cannot be sent to this number\"}";

    try testing.expectError(Error.http_error, sendSms(
        testing.allocator,
        test_config,
        "+61412345678",
        "Hello",
        MockSender.send,
        &mock,
    ));
}

test "sendSms — body with special chars is form-url-encoded" {
    var mock = MockSender.init(testing.allocator);
    defer mock.deinit();
    mock.canned_status = 201;
    mock.canned_response_body = "{\"sid\":\"SM\",\"status\":\"queued\"}";

    var result = try sendSms(
        testing.allocator,
        test_config,
        "+61412345678",
        "Hi & welcome! 50% off?",
        MockSender.send,
        &mock,
    );
    defer result.deinit(testing.allocator);

    // & must be %26, % must be %25, space must be + or %20, ? must be %3F
    // Use + for space (form encoding convention) and percent-encode the rest.
    try testing.expectEqualStrings(
        "From=%2B61400000000&To=%2B61412345678&Body=Hi+%26+welcome%21+50%25+off%3F",
        mock.last_body,
    );
}

// ────────────────────────────────────────────────────────────────────
// parseConfig / loadConfig tests (W1.5 RED, W1.6 GREEN)
// ────────────────────────────────────────────────────────────────────

test "parseConfig — valid JSON with required fields → OwnedConfig" {
    const json =
        \\{
        \\  "account_sid": "ACabcdef0123456789",
        \\  "auth_token": "secret-shh",
        \\  "sender_phone": "+61400000000"
        \\}
    ;

    var owned = try parseConfig(testing.allocator, json);
    defer owned.deinit(testing.allocator);

    try testing.expectEqualStrings("ACabcdef0123456789", owned.config.account_sid);
    try testing.expectEqualStrings("secret-shh", owned.config.auth_token);
    try testing.expectEqualStrings("+61400000000", owned.config.sender_phone);
    // Optional fields default appropriately.
    try testing.expectEqualStrings("", owned.config.verify_service_sid);
    try testing.expectEqualStrings("+61", owned.config.default_country_code);
}

test "parseConfig — optional fields present are returned" {
    const json =
        \\{
        \\  "account_sid": "ACx",
        \\  "auth_token": "t",
        \\  "sender_phone": "+15550000000",
        \\  "verify_service_sid": "VAabc",
        \\  "default_country_code": "+1"
        \\}
    ;

    var owned = try parseConfig(testing.allocator, json);
    defer owned.deinit(testing.allocator);

    try testing.expectEqualStrings("VAabc", owned.config.verify_service_sid);
    try testing.expectEqualStrings("+1", owned.config.default_country_code);
}

test "parseConfig — missing account_sid → twilio_not_configured" {
    const json =
        \\{
        \\  "auth_token": "t",
        \\  "sender_phone": "+61400000000"
        \\}
    ;
    try testing.expectError(Error.twilio_not_configured, parseConfig(testing.allocator, json));
}

test "parseConfig — missing auth_token → twilio_not_configured" {
    const json =
        \\{
        \\  "account_sid": "ACx",
        \\  "sender_phone": "+61400000000"
        \\}
    ;
    try testing.expectError(Error.twilio_not_configured, parseConfig(testing.allocator, json));
}

test "parseConfig — missing sender_phone → twilio_not_configured" {
    const json =
        \\{
        \\  "account_sid": "ACx",
        \\  "auth_token": "t"
        \\}
    ;
    try testing.expectError(Error.twilio_not_configured, parseConfig(testing.allocator, json));
}

test "parseConfig — empty required field → twilio_not_configured" {
    const json =
        \\{
        \\  "account_sid": "",
        \\  "auth_token": "t",
        \\  "sender_phone": "+61400000000"
        \\}
    ;
    try testing.expectError(Error.twilio_not_configured, parseConfig(testing.allocator, json));
}

test "parseConfig — malformed JSON → twilio_not_configured" {
    const json = "{ not json at all";
    try testing.expectError(Error.twilio_not_configured, parseConfig(testing.allocator, json));
}

test "loadConfig — file absent → twilio_not_configured" {
    try testing.expectError(
        Error.twilio_not_configured,
        loadConfig(testing.allocator, "/nonexistent/path/to/twilio.json"),
    );
}

test "loadConfig — reads file and delegates to parseConfig" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const json =
        \\{
        \\  "account_sid": "ACfromfile",
        \\  "auth_token": "tokfromfile",
        \\  "sender_phone": "+61400000001"
        \\}
    ;

    var f = try tmp.dir.createFile("twilio.json", .{});
    try f.writeAll(json);
    f.close();

    // Resolve absolute path so loadConfig works regardless of CWD.
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath("twilio.json", &path_buf);

    var owned = try loadConfig(testing.allocator, abs_path);
    defer owned.deinit(testing.allocator);

    try testing.expectEqualStrings("ACfromfile", owned.config.account_sid);
    try testing.expectEqualStrings("tokfromfile", owned.config.auth_token);
    try testing.expectEqualStrings("+61400000001", owned.config.sender_phone);
}

```
