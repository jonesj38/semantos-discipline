---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/shell_attention_sources.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.224364+00:00
---

# runtime/semantos-brain/src/shell_attention_sources.zig

```zig
//! Shell-native attention sources — SH7 / DECISION D15.
//!
//! Registered under the "shell" namespace (unconditionally, at serve boot) so
//! a PURE-BRAIN shell — no cartridges — still surfaces a useful attention feed
//! via attention.poll(ns=["shell"]):
//!   1. identity/recovery nudges — bearer(capability)-token expiry + a standing
//!      "set up recovery" nudge (PlexusRecoveryEnvelope is future / C6b, so
//!      there is no recovery-envelope store on origin/main yet).
//!   2. pending ratifications — PLACEHOLDER: origin/main has no queryable
//!      pending-ratification queue (ratify is a synchronous submit flow;
//!      ratify_builder_registry holds builders, not pending proposals). Emits
//!      [] until such a queue exists; registered so the seam/namespace is ready.
//!
//! This module is PURE (std only) so the JSON builders are isolate-testable
//! (`zig test src/shell_attention_sources.zig`). The CollectFn adapters that
//! read the real TokenStore live in cli/serve.zig (which owns the stores),
//! mirroring the oddjobz attention sources.

const std = @import("std");

/// Minimal token-expiry view — decoupled from bearer_tokens so this module
/// stays std-only. serve.zig maps TokenRecord → this.
pub const TokenExpiry = struct {
    /// Stable token id (hex) — used as the signal `ref`.
    id: []const u8,
    /// Operator label, e.g. "Todd (tradie)".
    label: []const u8,
    /// Unix-SECONDS expiry; 0 = never expires.
    expires_at: i64,
};

/// Surface a token-expiry signal once it is within this window of expiring.
pub const WARN_SECS: i64 = 7 * 24 * 3600;

/// Build the "shell" identity/recovery signal array as a JSON string
/// `[ {kind,score,ref,summary,[expiresAt]}, … ]` (caller frees). `now` is
/// unix-seconds. Emits a recovery-setup nudge (when `has_recovery` is false)
/// plus a token-expiry signal per token expiring within WARN_SECS, capped at
/// `limit`.
pub fn buildShellIdentityJson(
    allocator: std.mem.Allocator,
    tokens: []const TokenExpiry,
    has_recovery: bool,
    now: i64,
    limit: usize,
) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '[');
    var n: usize = 0;

    // Standing recovery-setup nudge (until a recovery-envelope store exists).
    if (!has_recovery and n < limit) {
        try appendSignal(&buf, allocator, n, "recovery", 0.5, "recovery-setup", "Set up account recovery (no recovery envelope yet)", null);
        n += 1;
    }

    for (tokens) |t| {
        if (n >= limit) break;
        if (t.expires_at == 0) continue; // never expires
        const remaining = t.expires_at - now;
        if (remaining < 0 or remaining > WARN_SECS) continue; // already-expired / outside window
        // Score rises 0→1 as expiry approaches (linear across the warn window).
        const score: f64 = 1.0 - (@as(f64, @floatFromInt(remaining)) / @as(f64, @floatFromInt(WARN_SECS)));
        var sb: [160]u8 = undefined;
        const summary = std.fmt.bufPrint(&sb, "Bearer hat '{s}' expires soon", .{t.label}) catch "Bearer token expires soon";
        // helm AttentionSignal.expiresAt is ms-epoch; token expires_at is seconds.
        try appendSignal(&buf, allocator, n, "token-expiry", score, t.id, summary, t.expires_at * 1000);
        n += 1;
    }

    try buf.append(allocator, ']');
    return buf.toOwnedSlice(allocator);
}

/// Pending ratifications — placeholder (see module header). Always "[]".
pub fn buildPendingRatificationsJson(allocator: std.mem.Allocator) ![]u8 {
    return allocator.dupe(u8, "[]");
}

// ── JSON helpers ────────────────────────────────────────────────────────────

fn appendSignal(
    buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    index: usize,
    kind: []const u8,
    score: f64,
    ref: []const u8,
    summary: []const u8,
    expires_at_ms: ?i64,
) !void {
    if (index > 0) try buf.append(allocator, ',');
    try buf.appendSlice(allocator, "{\"kind\":\"");
    try appendEscaped(buf, allocator, kind);
    try buf.appendSlice(allocator, "\",\"score\":");
    var sbuf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&sbuf, "{d:.3}", .{score}) catch "0";
    try buf.appendSlice(allocator, s);
    try buf.appendSlice(allocator, ",\"ref\":\"");
    try appendEscaped(buf, allocator, ref);
    try buf.appendSlice(allocator, "\",\"summary\":\"");
    try appendEscaped(buf, allocator, summary);
    try buf.append(allocator, '"');
    if (expires_at_ms) |e| {
        var ebuf: [32]u8 = undefined;
        const es = std.fmt.bufPrint(&ebuf, "{d}", .{e}) catch "0";
        try buf.appendSlice(allocator, ",\"expiresAt\":");
        try buf.appendSlice(allocator, es);
    }
    try buf.append(allocator, '}');
}

fn appendEscaped(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, sx: []const u8) !void {
    for (sx) |c| switch (c) {
        '"' => try buf.appendSlice(allocator, "\\\""),
        '\\' => try buf.appendSlice(allocator, "\\\\"),
        else => try buf.append(allocator, c),
    };
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "buildShellIdentityJson: recovery nudge + token-expiry within window" {
    const a = std.testing.allocator;
    const now: i64 = 1_700_000_000;
    const tokens = [_]TokenExpiry{
        .{ .id = "aa", .label = "laptop", .expires_at = now + 2 * 24 * 3600 }, // 2d → in window
        .{ .id = "bb", .label = "old", .expires_at = now + 30 * 24 * 3600 },   // 30d → outside
        .{ .id = "cc", .label = "forever", .expires_at = 0 },                  // never
    };
    const out = try buildShellIdentityJson(a, &tokens, false, now, 10);
    defer a.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"kind\":\"recovery\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"kind\":\"token-expiry\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"ref\":\"aa\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "laptop") != null);
    // the 30d + never tokens do NOT surface
    try std.testing.expect(std.mem.indexOf(u8, out, "\"ref\":\"bb\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"ref\":\"cc\"") == null);
    // ms-epoch expiresAt present for the in-window token
    try std.testing.expect(std.mem.indexOf(u8, out, "\"expiresAt\":") != null);
}

test "buildShellIdentityJson: has_recovery suppresses the recovery nudge" {
    const a = std.testing.allocator;
    const out = try buildShellIdentityJson(a, &[_]TokenExpiry{}, true, 1_700_000_000, 10);
    defer a.free(out);
    try std.testing.expectEqualStrings("[]", out);
}

test "buildShellIdentityJson: limit caps the signal count" {
    const a = std.testing.allocator;
    const now: i64 = 1_700_000_000;
    const tokens = [_]TokenExpiry{
        .{ .id = "aa", .label = "a", .expires_at = now + 3600 },
        .{ .id = "bb", .label = "b", .expires_at = now + 7200 },
    };
    // limit 1 → only the recovery nudge fits, no token signals.
    const out = try buildShellIdentityJson(a, &tokens, false, now, 1);
    defer a.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"kind\":\"recovery\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"kind\":\"token-expiry\"") == null);
}

test "buildPendingRatificationsJson: placeholder empty array" {
    const a = std.testing.allocator;
    const out = try buildPendingRatificationsJson(a);
    defer a.free(out);
    try std.testing.expectEqualStrings("[]", out);
}

```
