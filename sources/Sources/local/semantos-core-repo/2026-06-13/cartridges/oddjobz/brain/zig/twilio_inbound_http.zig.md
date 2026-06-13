---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/twilio_inbound_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.481471+00:00
---

# cartridges/oddjobz/brain/zig/twilio_inbound_http.zig

```zig
// Twilio inbound SMS webhook — P1c (OJT-UNIFIED-QUOTE-INVOICE-PLAN).
//
// Endpoint: POST /api/v1/twilio/inbound  (no bearer — Twilio webhook)
// Body:     application/x-www-form-urlencoded
//           Key fields: From (E.164 phone), Body (message text), MessageSid
//
// Orchestration:
//   1. Parse form body → extract From + Body.
//   2. Normalise From to E.164 via twilio_adapter.formatE164.
//   3. Find customer by normalised phone (injected findCustomerByPhone).
//   4. Find their most-recent open job cell hash (injected findOpenJobCellId).
//   5. Route through intake pipeline with entity_cell_hash set (or null).
//      The TypeScript intake-handler writes a ConversationTurn anchored to
//      the job and runs intent extraction.  We discard the AI reply —
//      operator reviews and replies manually from ContactConversationScreen.
//   6. Return empty TwiML: <?xml version="1.0"?><Response></Response>
//
// Architecture note: this handler runs IN the reactor's poll loop, so
// the intake callScript spawn is synchronous from the reactor's perspective.
// That's the same behaviour as every other route that spawns the intake
// bun child (reactorHandleIntake).  The single-thread rule
// (semantos_brain_single_threaded_reactor) only forbids SYNC CALLS BACK
// INTO the reactor's HTTP surface from a child — this direction is safe.
//
// Error policy: all errors return 200 + empty TwiML.  Twilio re-sends on
// non-2xx; we never want Twilio to retry a message we already processed.

const std = @import("std");
const twilio_adapter = @import("twilio_adapter");
const intake_http = @import("intake_http");

// ────────────────────────────────────────────────────────────────────
// Injectable dependency types
// ────────────────────────────────────────────────────────────────────

/// Look up a customer by their normalised E.164 phone.
/// Returns the customer's cellId bytes on match; null if unknown.
/// The returned slice is NOT owned by the caller (points into the store).
pub const FindCustomerByPhoneFn = *const fn (
    ctx: ?*anyopaque,
    normalised_phone: []const u8,
) ?[32]u8;

/// Return the hex-encoded cellId of the customer's most-recent open job
/// (state is lead / quoted / scheduled).  Returns null when the customer
/// has no open jobs.  The returned 64-byte array is stack value; no alloc.
pub const FindOpenJobCellIdFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    customer_cell_id: [32]u8,
) anyerror!?[64]u8;

/// P4b — called when an inbound message is YES-like AND a job entity_cell_id
/// is resolved.  The implementation (serve.zig) checks the job is in `quoted`
/// state and, if so, transitions it to `authorized`.
/// null ⇒ P4b disabled (safe default).
pub const AuthorizeJobFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    entity_cell_id: [32]u8,
) anyerror!void;

/// Acceptor holds all the runtime deps for the inbound handler.
pub const Acceptor = struct {
    /// Injected dep: customer phone lookup.
    find_customer_by_phone_fn: FindCustomerByPhoneFn,
    find_customer_by_phone_ctx: ?*anyopaque,
    /// Injected dep: open job cellId lookup.
    find_open_job_cell_id_fn: FindOpenJobCellIdFn,
    find_open_job_cell_id_ctx: ?*anyopaque,
    /// Path to the bun intake handler script (borrowed, same lifetime as server).
    intake_script: []const u8,
    /// Default country code for E.164 normalisation (e.g. "+61" for AU).
    default_country_code: []const u8 = "+61",
    /// P4b — optional job authorisation hook.  Called after intake when the
    /// message is a YES-like customer approval and a job entity is resolved.
    authorize_job_fn: ?AuthorizeJobFn = null,
    authorize_job_ctx: ?*anyopaque = null,
};

// ────────────────────────────────────────────────────────────────────
// TwiML constants
// ────────────────────────────────────────────────────────────────────

const kEmptyTwiml =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>";
const kTwimlContentType = "application/xml";

// ────────────────────────────────────────────────────────────────────
// Public accept function
// ────────────────────────────────────────────────────────────────────

pub const AcceptResult = enum {
    ok,                // 200 + TwiML
    not_post,          // 405
    missing_body,      // 200 + empty TwiML (Twilio never retries on missing body)
};

/// Main handler. Always returns 200 with TwiML on any processing error
/// so Twilio doesn't retry.  Returns .not_post for non-POST verbs.
pub fn acceptInbound(
    acceptor: *const Acceptor,
    allocator: std.mem.Allocator,
    method: []const u8,
    body: []const u8,
    data_dir: []const u8,
) AcceptResult {
    if (!std.mem.eql(u8, method, "POST")) return .not_post;
    if (body.len == 0) return .missing_body;

    acceptInboundInner(acceptor, allocator, body, data_dir) catch |err| {
        std.log.warn("twilio_inbound: intake error: {s}", .{@errorName(err)});
        // Fall through — still return .ok (empty TwiML) so Twilio won't retry.
    };
    return .ok;
}

fn acceptInboundInner(
    acceptor: *const Acceptor,
    allocator: std.mem.Allocator,
    body: []const u8,
    data_dir: []const u8,
) !void {
    // 1. Parse form body.
    const from_raw = formField(body, "From") orelse {
        std.log.warn("twilio_inbound: missing From field", .{});
        return;
    };
    const msg_raw = formField(body, "Body") orelse "";

    const from_decoded = try urlDecode(allocator, from_raw);
    defer allocator.free(from_decoded);
    const msg_decoded = try urlDecode(allocator, msg_raw);
    defer allocator.free(msg_decoded);

    if (msg_decoded.len == 0) {
        std.log.info("twilio_inbound: empty Body from {s} — skipping intake", .{from_decoded});
        return;
    }

    // 2. Normalise phone.
    const e164 = twilio_adapter.formatE164(allocator, from_decoded, acceptor.default_country_code) catch |err| {
        std.log.warn("twilio_inbound: bad From phone {s}: {s}", .{ from_decoded, @errorName(err) });
        // Still submit to intake without entity anchoring.
        try routeToIntake(acceptor, allocator, msg_decoded, from_decoded, null, data_dir);
        return;
    };
    defer allocator.free(e164);

    // 3. Find customer by phone.
    const entity_cell_id: ?[64]u8 = blk: {
        const customer_cell_id = acceptor.find_customer_by_phone_fn(
            acceptor.find_customer_by_phone_ctx,
            e164,
        ) orelse {
            std.log.info("twilio_inbound: no customer for {s} — unanchored turn", .{e164});
            break :blk null;
        };

        // 4. Find open job for customer.
        const job_hex = try acceptor.find_open_job_cell_id_fn(
            acceptor.find_open_job_cell_id_ctx,
            allocator,
            customer_cell_id,
        ) orelse {
            std.log.info("twilio_inbound: no open job for customer {s} — unanchored turn", .{e164});
            break :blk null;
        };

        break :blk job_hex;
    };

    // 5. Route through intake.
    const entity_hex_slice: ?[]const u8 = if (entity_cell_id) |h| &h else null;
    try routeToIntake(acceptor, allocator, msg_decoded, e164, entity_hex_slice, data_dir);

    // 6. P4b — if the message is a YES-like customer approval and we have a
    //    resolved job entity, fire the authorize_job_fn so the brain can
    //    transition quoted → authorized without an HTTP self-call.
    if (entity_cell_id) |hex| {
        if (acceptor.authorize_job_fn) |auth_fn| {
            if (isYesLike(msg_decoded)) {
                var raw_id: [32]u8 = undefined;
                _ = std.fmt.hexToBytes(&raw_id, &hex) catch {
                    std.log.warn("twilio_inbound: bad hex cell_id in P4b path", .{});
                    return;
                };
                auth_fn(acceptor.authorize_job_ctx, allocator, raw_id) catch |err| {
                    std.log.warn("twilio_inbound: authorize_job error: {s}", .{@errorName(err)});
                    // Non-fatal: intake already recorded the turn.
                };
            }
        }
    }
}

fn routeToIntake(
    acceptor: *const Acceptor,
    allocator: std.mem.Allocator,
    message: []const u8,
    session_id: []const u8,
    entity_cell_hash: ?[]const u8,
    data_dir: []const u8,
) !void {
    const msg_owned = try allocator.dupe(u8, message);
    errdefer allocator.free(msg_owned);
    const sid_owned = try allocator.dupe(u8, session_id);
    errdefer allocator.free(sid_owned);
    const ech_owned = try allocator.dupe(u8, entity_cell_hash orelse "");
    errdefer allocator.free(ech_owned);

    const req = intake_http.IntakeRequest{
        .message = msg_owned,
        .session_id = sid_owned,
        .entity_cell_hash = ech_owned,
    };
    defer req.deinit(allocator);

    const response = try intake_http.callScript(
        allocator,
        acceptor.intake_script,
        req,
        data_dir,
        entity_cell_hash,
    );
    defer allocator.free(response);
    // Response (AI reply JSON) is intentionally discarded — operator
    // reviews in the conversation thread and replies manually.
}

// ────────────────────────────────────────────────────────────────────
// Form parsing helpers
// ────────────────────────────────────────────────────────────────────

/// Return the raw (URL-encoded) value for `key` in a
/// application/x-www-form-urlencoded body.  Returns null if not found.
/// The returned slice points into `body` (no allocation).
fn formField(body: []const u8, key: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, body, '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        const k = pair[0..eq];
        const v = pair[eq + 1 ..];
        if (std.mem.eql(u8, k, key)) return v;
    }
    return null;
}

/// URL-decode a percent-encoded + +-for-space string.  Caller owns result.
fn urlDecode(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '+') {
            try out.append(allocator, ' ');
            i += 1;
        } else if (s[i] == '%' and i + 2 < s.len) {
            const hi = hexNibble(s[i + 1]) orelse {
                try out.append(allocator, s[i]);
                i += 1;
                continue;
            };
            const lo = hexNibble(s[i + 2]) orelse {
                try out.append(allocator, s[i]);
                i += 1;
                continue;
            };
            try out.append(allocator, (hi << 4) | lo);
            i += 3;
        } else {
            try out.append(allocator, s[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}

fn hexNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

// ────────────────────────────────────────────────────────────────────
// P4b — YES-like approval detection
// ────────────────────────────────────────────────────────────────────

/// Returns true when `s` (trimmed, lowercased) is a common affirmative
/// customer reply.  The list is intentionally short — we only fire the
/// auto-authorize path on unambiguous YES-words; anything else stays as
/// a ConversationTurn for the operator to review manually.
pub fn isYesLike(s: []const u8) bool {
    const trimmed = std.mem.trim(u8, s, " \t\r\n");
    // Reject empty or suspiciously long strings.
    if (trimmed.len == 0 or trimmed.len > 16) return false;
    // Lowercase into a stack buffer (max 16 bytes).
    var lower: [16]u8 = undefined;
    for (trimmed, 0..) |c, i| lower[i] = std.ascii.toLower(c);
    const lk = lower[0..trimmed.len];
    return std.mem.eql(u8, lk, "yes") or
        std.mem.eql(u8, lk, "y") or
        std.mem.eql(u8, lk, "yep") or
        std.mem.eql(u8, lk, "yeah") or
        std.mem.eql(u8, lk, "ok") or
        std.mem.eql(u8, lk, "okay") or
        std.mem.eql(u8, lk, "sure") or
        std.mem.eql(u8, lk, "approve") or
        std.mem.eql(u8, lk, "approved");
}

// ────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────

test "formField: extracts From and Body" {
    const body = "SmsSid=SM123&Body=Hello+World&From=%2B61412345678&To=%2B61312345678";
    try std.testing.expectEqualStrings("%2B61412345678", formField(body, "From").?);
    try std.testing.expectEqualStrings("Hello+World", formField(body, "Body").?);
    try std.testing.expect(formField(body, "Missing") == null);
}

test "urlDecode: decodes + as space" {
    const r = try urlDecode(std.testing.allocator, "Hello+World");
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("Hello World", r);
}

test "urlDecode: decodes percent-encoded phone" {
    const r = try urlDecode(std.testing.allocator, "%2B61412345678");
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("+61412345678", r);
}

test "urlDecode: mixed encoding" {
    const r = try urlDecode(std.testing.allocator, "fix+the+%22tap%22%20please");
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("fix the \"tap\" please", r);
}

test "urlDecode: passthrough plain ascii" {
    const r = try urlDecode(std.testing.allocator, "plaintext");
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("plaintext", r);
}

test "isYesLike: detects affirmatives" {
    try std.testing.expect(isYesLike("yes"));
    try std.testing.expect(isYesLike("YES"));
    try std.testing.expect(isYesLike("Yes"));
    try std.testing.expect(isYesLike(" YES "));
    try std.testing.expect(isYesLike("y"));
    try std.testing.expect(isYesLike("Y"));
    try std.testing.expect(isYesLike("yep"));
    try std.testing.expect(isYesLike("yeah"));
    try std.testing.expect(isYesLike("ok"));
    try std.testing.expect(isYesLike("OK"));
    try std.testing.expect(isYesLike("okay"));
    try std.testing.expect(isYesLike("sure"));
    try std.testing.expect(isYesLike("approve"));
    try std.testing.expect(isYesLike("approved"));
}

test "isYesLike: rejects negatives and ambiguous" {
    try std.testing.expect(!isYesLike("no"));
    try std.testing.expect(!isYesLike("maybe"));
    try std.testing.expect(!isYesLike("yes please send someone out"));
    try std.testing.expect(!isYesLike(""));
    try std.testing.expect(!isYesLike("could you come Thursday?"));
}

```
