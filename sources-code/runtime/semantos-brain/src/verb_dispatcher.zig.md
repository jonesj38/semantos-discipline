---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/verb_dispatcher.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.264310+00:00
---

# runtime/semantos-brain/src/verb_dispatcher.zig

```zig
// Generic verb dispatcher — the uniform write-seam for declared extension
// action verbs (the L5 layer that was missing from the SIR pipeline).
//
// Reference:
//   docs/design/PLATFORM-WALLET-SHELL-EXPLORATION.md §6.1 (write-seam gap)
//   docs/design/PLATFORM-WALLET-SHELL-EXPLORATION.md §11.5 (item 3)
//   runtime/semantos-brain/src/oddjobz_ratify_handler.zig (the prototype
//     walker pattern this generalises)
//
// Why this exists:
//
//   Today's SIR pipeline validates declared verbs (attach_photos,
//   report_issue, approve_quote, ...) but has no per-verb dispatcher.
//   The ratification handler is invoked imperatively under one hard-
//   coded JSON-RPC name (oddjobz.ratify_proposal). Multi-experience
//   shells need a uniform way to fire any extension's declared verb
//   without adding a new JSON-RPC method per verb.
//
//   The dispatcher:
//     • Holds a registry of (extension_id, verb) → walker function
//     • Exposes one JSON-RPC method (verb.dispatch) that the field
//       shell calls with {extensionId, verb, params}
//     • Routes the call to the registered walker
//     • Returns the walker's JSON result back through JSON-RPC
//
//   Extensions provide their own walkers and register them at brain
//   boot. The wss_wallet handler stays uniform; new extensions add
//   walkers without touching dispatch code.
//
// Walker contract:
//
//   A walker is a function that takes:
//     • allocator     — for any result allocation (the dispatcher frees
//                       the returned slice after writing the response)
//     • ctx           — opaque per-walker state (typed stores, log
//                       paths, mutexes etc.); the walker casts it back
//                       to its own struct
//     • params_json   — the JSON-RPC `params.params` payload as a
//                       newly-allocated UTF-8 slice (owned by the
//                       dispatcher caller; walker may not retain after
//                       return)
//
//   And returns a newly-allocated UTF-8 slice containing the JSON-RPC
//   `result` body (the dispatcher frees it after writing).
//
//   Errors map onto the four DispatchError variants below — the
//   dispatcher translates them to JSON-RPC error codes.

const std = @import("std");

pub const DispatchError = error{
    /// No walker registered for the (extensionId, verb) tuple.
    walker_not_found,
    /// Params validation failed inside the walker.
    invalid_params,
    /// Walker ran but failed for a domain-specific reason
    /// (state mismatch, persistence failure, etc.). The walker may
    /// include a human-readable explanation in the result JSON.
    walker_failed,
    out_of_memory,
};

/// Opaque function pointer type for walker callbacks. Each registered
/// walker provides one of these alongside an opaque context pointer.
pub const WalkerFn = *const fn (
    allocator: std.mem.Allocator,
    ctx: *anyopaque,
    params_json: []const u8,
) DispatchError![]u8;

/// One registered walker entry.
pub const Walker = struct {
    /// Extension identifier (e.g. "oddjobz", "jambox").
    extension_id: []const u8,
    /// Verb name as declared in the extension's grammar spec
    /// (e.g. "ratify_proposal", "attach_photos", "approve_quote").
    verb: []const u8,
    /// Walker callback.
    walker_fn: WalkerFn,
    /// Per-walker context — opaque to the dispatcher; the walker casts
    /// this back to its own state struct (e.g. *RatifyHandler).
    ctx: *anyopaque,
};

/// Registry of walkers. Owns the ArrayList; walker entries borrow their
/// extension_id / verb / ctx pointers from the caller (typically static
/// or backed by the brain-lifetime allocator).
pub const Registry = struct {
    allocator: std.mem.Allocator,
    walkers: std.ArrayList(Walker),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .walkers = .{},
        };
    }

    pub fn deinit(self: *Registry) void {
        self.walkers.deinit(self.allocator);
    }

    /// Register a walker. Duplicates (same extension_id + verb) are
    /// rejected so misconfiguration surfaces at boot rather than
    /// causing surprise dispatch behavior later.
    pub fn register(self: *Registry, walker: Walker) !void {
        for (self.walkers.items) |existing| {
            if (std.mem.eql(u8, existing.extension_id, walker.extension_id) and
                std.mem.eql(u8, existing.verb, walker.verb))
            {
                return error.duplicate_walker;
            }
        }
        try self.walkers.append(self.allocator, walker);
    }

    /// Dispatch a verb call to the registered walker. Returns the
    /// walker's JSON result body, allocated with [allocator]. Caller
    /// frees.
    pub fn dispatch(
        self: *const Registry,
        allocator: std.mem.Allocator,
        extension_id: []const u8,
        verb: []const u8,
        params_json: []const u8,
    ) DispatchError![]u8 {
        for (self.walkers.items) |entry| {
            if (std.mem.eql(u8, entry.extension_id, extension_id) and
                std.mem.eql(u8, entry.verb, verb))
            {
                return entry.walker_fn(allocator, entry.ctx, params_json);
            }
        }
        return DispatchError.walker_not_found;
    }

    /// Count of registered walkers — useful for boot-log telemetry.
    pub fn count(self: *const Registry) usize {
        return self.walkers.items.len;
    }

    /// True if at least one walker is registered for [extension_id].
    pub fn hasExtension(self: *const Registry, extension_id: []const u8) bool {
        for (self.walkers.items) |entry| {
            if (std.mem.eql(u8, entry.extension_id, extension_id)) return true;
        }
        return false;
    }
};

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

const FixtureCtx = struct {
    last_seen: []const u8 = "",
};

fn fixtureWalker(
    allocator: std.mem.Allocator,
    ctx: *anyopaque,
    params_json: []const u8,
) DispatchError![]u8 {
    const f: *FixtureCtx = @ptrCast(@alignCast(ctx));
    f.last_seen = params_json;
    return allocator.dupe(u8, "{\"ok\":true}") catch DispatchError.out_of_memory;
}

test "Registry dispatches to a registered walker" {
    var fix = FixtureCtx{};
    var reg = Registry.init(testing.allocator);
    defer reg.deinit();
    try reg.register(.{
        .extension_id = "test_ext",
        .verb = "test_verb",
        .walker_fn = fixtureWalker,
        .ctx = &fix,
    });
    const result = try reg.dispatch(testing.allocator, "test_ext", "test_verb", "{\"x\":1}");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{\"ok\":true}", result);
    try testing.expectEqualStrings("{\"x\":1}", fix.last_seen);
}

test "Registry rejects duplicate walkers" {
    var fix = FixtureCtx{};
    var reg = Registry.init(testing.allocator);
    defer reg.deinit();
    try reg.register(.{
        .extension_id = "test_ext",
        .verb = "test_verb",
        .walker_fn = fixtureWalker,
        .ctx = &fix,
    });
    try testing.expectError(error.duplicate_walker, reg.register(.{
        .extension_id = "test_ext",
        .verb = "test_verb",
        .walker_fn = fixtureWalker,
        .ctx = &fix,
    }));
}

test "Registry returns walker_not_found for unregistered (ext, verb)" {
    var reg = Registry.init(testing.allocator);
    defer reg.deinit();
    try testing.expectError(
        DispatchError.walker_not_found,
        reg.dispatch(testing.allocator, "unknown", "verb", "{}"),
    );
}

test "Registry hasExtension reports correctly" {
    var fix = FixtureCtx{};
    var reg = Registry.init(testing.allocator);
    defer reg.deinit();
    try testing.expect(!reg.hasExtension("oddjobz"));
    try reg.register(.{
        .extension_id = "oddjobz",
        .verb = "ratify_proposal",
        .walker_fn = fixtureWalker,
        .ctx = &fix,
    });
    try testing.expect(reg.hasExtension("oddjobz"));
    try testing.expect(!reg.hasExtension("jambox"));
}

```
