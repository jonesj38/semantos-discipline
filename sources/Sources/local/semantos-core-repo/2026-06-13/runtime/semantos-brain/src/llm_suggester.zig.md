---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/llm_suggester.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.229646+00:00
---

# runtime/semantos-brain/src/llm_suggester.zig

```zig
// Phase Brain 5.2 — ParseResponse → suggested REPL command.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 5).
//
// Bridge between the LLM adapter's structured `ParseResponse` and the
// brain REPL's free-text command surface. Given a parse:
//
//   {modal=find, who=self, what="recent-jobs", why="", confidence=0.9}
//
// produce a suggested REPL line:
//
//   audit --tail 10
//
// or — if no rule matches — a `.no_suggestion` outcome that signals
// the REPL to fall back to manual operator entry.
//
// ─── Trust boundary ─────────────────────────────────────────────────
//
// Mapping table is INTENTIONALLY conservative:
//
// • Only `find` (read-only) modals get hard-coded mappings to specific
//   brain REPL verbs.
// • `do` and `talk` always return `.no_suggestion` for v0.1 — those
//   verbs would need sat amounts / addresses / contact resolution that
//   the LLM can't safely guess. Operator types the literal command.
// • Even when we DO suggest, the REPL caller still requires an explicit
//   `[y/N]` confirmation before dispatching.  And any signing op the
//   suggested command would trigger goes through the wallet engine's
//   own confirmation gate (the second layer of safety).
//
// As brain's verb vocabulary grows (PR #?: gloss table), this file gains
// more exact-match rules. For now: tiny, deterministic, safe.

const std = @import("std");
const llm = @import("llm_adapter");

pub const Suggestion = union(enum) {
    /// A best-effort command string the operator can run. Allocated;
    /// caller frees.
    line: []u8,
    /// No rule matched. Operator should type the command manually.
    /// `hint` is a short string that explains what the LLM understood,
    /// rendered alongside the manual-entry prompt.  Allocated; caller
    /// frees.
    no_suggestion: []u8,
};

/// Compute a Suggestion from a ParseResponse.  All returned slices are
/// allocator-owned.
pub fn suggest(
    allocator: std.mem.Allocator,
    parse: llm.ParseResponse,
) !Suggestion {
    // Gate everything below a confidence floor — low-confidence parses
    // never become suggestions, even for read-only `find` verbs.
    if (parse.confidence < 0.5) {
        const hint = try std.fmt.allocPrint(
            allocator,
            "low confidence ({d:.2}); type the command manually",
            .{parse.confidence},
        );
        return .{ .no_suggestion = hint };
    }

    return switch (parse.modal) {
        .find => suggestFind(allocator, parse),
        .do_, .talk => noSuggestion(allocator, parse, "type the command manually — `do` and `talk` modals not yet wired"),
    };
}

fn suggestFind(allocator: std.mem.Allocator, parse: llm.ParseResponse) !Suggestion {
    // Match `what` (case-insensitive, contains) against the small set of
    // read-only brain verbs. Keep this list narrow — every entry here is a
    // verb the operator might say AND a known brain REPL command we trust
    // with no further confirmation.
    const what = parse.what;

    if (containsAny(what, &.{ "status", "health", "alive" })) {
        return ownedLine(allocator, "status");
    }
    if (containsAny(what, &.{ "module", "loaded" })) {
        return ownedLine(allocator, "modules");
    }
    if (containsAny(what, &.{ "audit", "log", "event", "history", "recent" })) {
        return ownedLine(allocator, "audit --tail 10");
    }
    if (containsAny(what, &.{ "identit", "pubkey", "public-key", "who-am-i" })) {
        return ownedLine(allocator, "call wallet-engine identify");
    }
    if (containsAny(what, &.{ "header", "tip", "block-height", "chain-tip" })) {
        return ownedLine(allocator, "call headers-verifier tip");
    }

    return noSuggestion(allocator, parse, "no mapping for that find target");
}

// ─── Helpers ────────────────────────────────────────────────────────

fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (asciiContainsCaseInsensitive(haystack, needle)) return true;
    }
    return false;
}

fn asciiContainsCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn ownedLine(allocator: std.mem.Allocator, line: []const u8) !Suggestion {
    return .{ .line = try allocator.dupe(u8, line) };
}

fn noSuggestion(
    allocator: std.mem.Allocator,
    parse: llm.ParseResponse,
    reason: []const u8,
) !Suggestion {
    const hint = try std.fmt.allocPrint(
        allocator,
        "{s}: parsed modal={s} who={s} what={s}",
        .{ reason, parse.modal.toString(), parse.who, parse.what },
    );
    return .{ .no_suggestion = hint };
}

pub fn freeSuggestion(allocator: std.mem.Allocator, s: Suggestion) void {
    switch (s) {
        .line => |l| allocator.free(l),
        .no_suggestion => |h| allocator.free(h),
    }
}

// ─── Tests ───────────────────────────────────────────────────────────

test "find: status maps to brain status" {
    const allocator = std.testing.allocator;
    const parse = llm.ParseResponse{
        .modal = .find,
        .who = "self",
        .what = "status",
        .why = "",
        .confidence = 0.9,
    };
    const s = try suggest(allocator, parse);
    defer freeSuggestion(allocator, s);
    try std.testing.expectEqualSlices(u8, "status", s.line);
}

test "find: 'recent emails' falls back to audit --tail 10" {
    const allocator = std.testing.allocator;
    const parse = llm.ParseResponse{
        .modal = .find,
        .who = "self",
        .what = "recent emails",
        .why = "",
        .confidence = 0.85,
    };
    const s = try suggest(allocator, parse);
    defer freeSuggestion(allocator, s);
    try std.testing.expectEqualSlices(u8, "audit --tail 10", s.line);
}

test "find: 'who am I' maps to identify" {
    const allocator = std.testing.allocator;
    const parse = llm.ParseResponse{
        .modal = .find,
        .who = "self",
        .what = "who-am-I",
        .why = "",
        .confidence = 0.9,
    };
    const s = try suggest(allocator, parse);
    defer freeSuggestion(allocator, s);
    try std.testing.expectEqualSlices(u8, "call wallet-engine identify", s.line);
}

test "find: unknown target → no_suggestion" {
    const allocator = std.testing.allocator;
    const parse = llm.ParseResponse{
        .modal = .find,
        .who = "self",
        .what = "completely-unrelated-thing",
        .why = "",
        .confidence = 0.85,
    };
    const s = try suggest(allocator, parse);
    defer freeSuggestion(allocator, s);
    try std.testing.expect(s == .no_suggestion);
    try std.testing.expect(std.mem.indexOf(u8, s.no_suggestion, "no mapping") != null);
}

test "do: never suggests in v0.1" {
    const allocator = std.testing.allocator;
    const parse = llm.ParseResponse{
        .modal = .do_,
        .who = "alice",
        .what = "send-payment",
        .why = "for pizza",
        .confidence = 0.95,
    };
    const s = try suggest(allocator, parse);
    defer freeSuggestion(allocator, s);
    try std.testing.expect(s == .no_suggestion);
    try std.testing.expect(std.mem.indexOf(u8, s.no_suggestion, "do") != null);
}

test "talk: never suggests in v0.1" {
    const allocator = std.testing.allocator;
    const parse = llm.ParseResponse{
        .modal = .talk,
        .who = "alice",
        .what = "hi",
        .why = "",
        .confidence = 0.9,
    };
    const s = try suggest(allocator, parse);
    defer freeSuggestion(allocator, s);
    try std.testing.expect(s == .no_suggestion);
}

test "low confidence → no_suggestion regardless of modal" {
    const allocator = std.testing.allocator;
    const parse = llm.ParseResponse{
        .modal = .find,
        .who = "self",
        .what = "status",
        .why = "",
        .confidence = 0.3,
    };
    const s = try suggest(allocator, parse);
    defer freeSuggestion(allocator, s);
    try std.testing.expect(s == .no_suggestion);
    try std.testing.expect(std.mem.indexOf(u8, s.no_suggestion, "low confidence") != null);
}

```
