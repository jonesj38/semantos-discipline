---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/wss_subprotocol_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.252568+00:00
---

# runtime/semantos-brain/src/wss_subprotocol_registry.zig

```zig
// DLBA.1b — WSS subprotocol registry.
//
// Reference: docs/prd/D-LIFT-BSV-ANCHOR.md §Deliverables / DLBA.1b;
//            DECISION-3 resolution (brain owns WSS transport;
//            cartridges own subprotocols).
//
// ── What this module is ──────────────────────────────────────────────
//
// A small substrate primitive that lets cartridges register their WSS
// subprotocol handlers at brain boot. The brain-core WSS transport
// (`wss_codec.zig` + `wss_frame_parser.zig`) consults this registry
// during the WebSocket handshake per RFC 6455 §1.9 (`Sec-WebSocket-
// Protocol`) and dispatches subsequent frames to the registered handler.
//
// Subprotocol registration is the seam by which a cartridge (e.g.
// `bsv-anchor-bundle`) can own its own protocol (e.g. wallet WSS) while
// brain-core retains the transport layer + framing + handshake +
// authentication. Same pattern as HTTP — brain-core has the parser, but
// per-route handlers own per-route logic.
//
// Behavior contract:
//   • register(name, handler, capability_required, ctx) appends to the
//     registry. Duplicate names return error.duplicate_subprotocol.
//   • lookup(name) returns the registered Entry or null. Caller decides
//     whether null → 1002 Protocol Error (the canonical default).
//   • unregister(name) removes a registration. Used in extension
//     revocation / quarantine flows.
//
// Capability checks: this module records the capability *name* declared
// by the cartridge for its subprotocol. The actual capability-gate
// invocation happens at the dispatcher layer (`dispatcher.zig`'s
// CapabilitySet check) before the frame reaches the registered handler.
// This module is the routing seam; the auth gate is still where it was.
//
// ── Handler signature note ──────────────────────────────────────────
//
// The handler function pointer type stays generic in this scaffold
// (`*const anyopaque` for the function pointer + an opaque `ctx`) to
// avoid coupling to wss_codec internals before integration. DLBA.1b's
// follow-up integration into `wss_codec.zig` will introduce a typed
// HandlerFn signature once the AuthContext + frame-bytes shape is final.
// For now: register / lookup / unregister are exercised; frame dispatch
// is the next layer's concern.

const std = @import("std");

pub const MAX_SUBPROTOCOLS: usize = 64;
pub const MAX_NAME_LEN: usize = 64;

pub const RegistryError = error{
    /// A subprotocol with this name is already registered.
    duplicate_subprotocol,
    /// Subprotocol name violates the safe-name contract (empty, too
    /// long, control chars, etc.).
    invalid_subprotocol_name,
    /// Capability name violates the safe-name contract.
    invalid_capability_name,
    /// Registry is full (MAX_SUBPROTOCOLS reached).
    registry_full,
    /// Underlying allocator failed.
    out_of_memory,
};

/// One registered subprotocol entry.
pub const Entry = struct {
    /// The subprotocol name claimed in the WSS handshake (Sec-WebSocket-Protocol).
    /// Stable, lowercase, format `<scope>.<version>` (e.g. `wallet.v1`, `jam.v2`).
    name: []const u8,
    /// Opaque handler function pointer. Typed once wss_codec integration lands.
    handler: *const anyopaque,
    /// Opaque per-handler context (the cartridge's state pointer).
    ctx: *anyopaque,
    /// Capability the dispatcher checks before invoking handler.
    /// Cartridge declares this in its manifest.json wssSubprotocols entry.
    capability_required: []const u8,
};

/// Safe-name shape: lowercase, hyphen, dot, digits. Lengths bounded.
fn isValidName(name: []const u8) bool {
    if (name.len == 0 or name.len > MAX_NAME_LEN) return false;
    for (name) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or
            c == '.' or c == '-' or c == '_';
        if (!ok) return false;
    }
    return true;
}

/// Safe-capability-name shape: matches the cap.* pattern in capabilities.ts.
/// Allows lowercase, digits, dot, hyphen, underscore.
fn isValidCapability(cap: []const u8) bool {
    if (cap.len == 0 or cap.len > 128) return false;
    for (cap) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or
            c == '.' or c == '-' or c == '_';
        if (!ok) return false;
    }
    return true;
}

pub const Registry = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(Entry).empty,
        };
    }

    pub fn deinit(self: *Registry) void {
        for (self.entries.items) |e| {
            self.allocator.free(e.name);
            self.allocator.free(e.capability_required);
        }
        self.entries.deinit(self.allocator);
    }

    /// Register a subprotocol handler. Duplicate names fail loud.
    pub fn register(
        self: *Registry,
        name: []const u8,
        handler: *const anyopaque,
        ctx: *anyopaque,
        capability_required: []const u8,
    ) RegistryError!void {
        if (!isValidName(name)) return error.invalid_subprotocol_name;
        if (!isValidCapability(capability_required)) return error.invalid_capability_name;
        if (self.entries.items.len >= MAX_SUBPROTOCOLS) return error.registry_full;

        for (self.entries.items) |existing| {
            if (std.mem.eql(u8, existing.name, name)) return error.duplicate_subprotocol;
        }

        const name_dup = self.allocator.dupe(u8, name) catch return error.out_of_memory;
        errdefer self.allocator.free(name_dup);
        const cap_dup = self.allocator.dupe(u8, capability_required) catch return error.out_of_memory;
        errdefer self.allocator.free(cap_dup);

        self.entries.append(self.allocator, .{
            .name = name_dup,
            .handler = handler,
            .ctx = ctx,
            .capability_required = cap_dup,
        }) catch return error.out_of_memory;
    }

    /// Look up a registered subprotocol by name. null = not found
    /// (caller's responsibility to send 1002 Protocol Error close frame).
    pub fn lookup(self: *const Registry, name: []const u8) ?Entry {
        for (self.entries.items) |e| {
            if (std.mem.eql(u8, e.name, name)) return e;
        }
        return null;
    }

    /// Remove a registered subprotocol. Returns true if removed, false if
    /// not present. Used in extension revocation / quarantine flows.
    pub fn unregister(self: *Registry, name: []const u8) bool {
        var i: usize = 0;
        while (i < self.entries.items.len) : (i += 1) {
            if (std.mem.eql(u8, self.entries.items[i].name, name)) {
                const removed = self.entries.swapRemove(i);
                self.allocator.free(removed.name);
                self.allocator.free(removed.capability_required);
                return true;
            }
        }
        return false;
    }

    pub fn count(self: *const Registry) usize {
        return self.entries.items.len;
    }
};

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

test "isValidName — accepts canonical subprotocol names" {
    try std.testing.expect(isValidName("wallet.v1"));
    try std.testing.expect(isValidName("jam.v2"));
    try std.testing.expect(isValidName("ext.test.v1"));
    try std.testing.expect(isValidName("a"));
}

test "isValidName — rejects unsafe names" {
    try std.testing.expect(!isValidName(""));
    try std.testing.expect(!isValidName("Wallet.V1")); // uppercase
    try std.testing.expect(!isValidName("with space"));
    try std.testing.expect(!isValidName("with/slash"));
    try std.testing.expect(!isValidName("\x00null"));
}

test "register + lookup — round-trips a subprotocol" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    var stub_ctx: u8 = 0;
    const stub_handler_addr: *const anyopaque = &stub_ctx;

    try registry.register("wallet.v1", stub_handler_addr, &stub_ctx, "cap.bsv-anchor.wallet.sign");

    try std.testing.expectEqual(@as(usize, 1), registry.count());
    const found = registry.lookup("wallet.v1") orelse return error.NotFound;
    try std.testing.expectEqualStrings("wallet.v1", found.name);
    try std.testing.expectEqualStrings("cap.bsv-anchor.wallet.sign", found.capability_required);
}

test "lookup — unknown subprotocol returns null" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    try std.testing.expect(registry.lookup("nonexistent.v1") == null);
}

test "register — duplicate name fails loud" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    var stub_ctx: u8 = 0;
    const stub_handler_addr: *const anyopaque = &stub_ctx;

    try registry.register("wallet.v1", stub_handler_addr, &stub_ctx, "cap.test.sign");
    try std.testing.expectError(
        error.duplicate_subprotocol,
        registry.register("wallet.v1", stub_handler_addr, &stub_ctx, "cap.test.sign"),
    );
    try std.testing.expectEqual(@as(usize, 1), registry.count());
}

test "register — invalid subprotocol name rejected" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    var stub_ctx: u8 = 0;
    const stub_handler_addr: *const anyopaque = &stub_ctx;

    try std.testing.expectError(
        error.invalid_subprotocol_name,
        registry.register("Wallet.V1", stub_handler_addr, &stub_ctx, "cap.test.sign"),
    );
    try std.testing.expectError(
        error.invalid_subprotocol_name,
        registry.register("", stub_handler_addr, &stub_ctx, "cap.test.sign"),
    );
    try std.testing.expectError(
        error.invalid_subprotocol_name,
        registry.register("with space", stub_handler_addr, &stub_ctx, "cap.test.sign"),
    );
}

test "register — invalid capability name rejected" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    var stub_ctx: u8 = 0;
    const stub_handler_addr: *const anyopaque = &stub_ctx;

    try std.testing.expectError(
        error.invalid_capability_name,
        registry.register("wallet.v1", stub_handler_addr, &stub_ctx, ""),
    );
    try std.testing.expectError(
        error.invalid_capability_name,
        registry.register("wallet.v1", stub_handler_addr, &stub_ctx, "CAP.Bad"),
    );
}

test "unregister — removes registration; lookup then returns null" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    var stub_ctx: u8 = 0;
    const stub_handler_addr: *const anyopaque = &stub_ctx;

    try registry.register("wallet.v1", stub_handler_addr, &stub_ctx, "cap.test.sign");
    try std.testing.expect(registry.unregister("wallet.v1"));
    try std.testing.expect(registry.lookup("wallet.v1") == null);
    try std.testing.expectEqual(@as(usize, 0), registry.count());
}

test "unregister — unknown name returns false" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    try std.testing.expect(!registry.unregister("nonexistent.v1"));
}

test "two cartridges register distinct subprotocols — no collision" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    var ctx_a: u8 = 0;
    var ctx_b: u8 = 0;
    const handler_addr: *const anyopaque = &ctx_a;

    try registry.register("wallet.v1", handler_addr, &ctx_a, "cap.bsv.sign");
    try registry.register("jam.v1", handler_addr, &ctx_b, "cap.jam.clip.launch");

    try std.testing.expectEqual(@as(usize, 2), registry.count());
    try std.testing.expect(registry.lookup("wallet.v1") != null);
    try std.testing.expect(registry.lookup("jam.v1") != null);
}

test "after unregister, the name can be re-registered (e.g. cartridge re-load)" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    var stub_ctx: u8 = 0;
    const stub_handler_addr: *const anyopaque = &stub_ctx;

    try registry.register("wallet.v1", stub_handler_addr, &stub_ctx, "cap.test.sign");
    _ = registry.unregister("wallet.v1");
    try registry.register("wallet.v1", stub_handler_addr, &stub_ctx, "cap.test.sign");
    try std.testing.expectEqual(@as(usize, 1), registry.count());
}

```
