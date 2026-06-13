---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/ipv6_iface.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.225419+00:00
---

# runtime/semantos-brain/src/ipv6_iface.zig

```zig
// D-network-ipv6-session-keys — Linux interface /128 management.
//
// Wraps `ip -6 addr add/del <addr>/128 dev <iface>` via subprocess.
// Requires CAP_NET_ADMIN (or root).  On a VPS running as root under
// systemd this is available by default; non-root units need:
//
//   AmbientCapabilities = CAP_NET_ADMIN
//   CapabilityBoundingSet = CAP_NET_ADMIN
//
// in the [Service] section of the systemd unit.
//
// Design: fire-and-forget subprocess.  The brain is single-threaded;
// `ip` commands are fast (kernel netlink, <1ms).  We run them
// synchronously (waitPid) so startup/shutdown are deterministic.
//
// Error handling: non-fatal on add (address may already exist from a
// previous run that didn't clean up cleanly).  Fatal on del only if
// the caller opts in; otherwise best-effort on shutdown.

const std = @import("std");

pub const IpError = error{
    SpawnFailed,
    CommandFailed,
    OutOfMemory,
};

/// Assign a /128 to the given interface.
/// Idempotent — if the address already exists the kernel returns EEXIST
/// and `ip` exits 2; we treat that as success.
pub fn addAddr(
    allocator: std.mem.Allocator,
    iface: []const u8,
    addr_text: []const u8, // e.g. "2404:9400:17e5:1e00:dead:beef:cafe:0001"
) IpError!void {
    return runIp(allocator, iface, addr_text, .add);
}

/// Remove a /128 from the given interface.
/// Idempotent — if the address is already absent we treat it as success.
pub fn delAddr(
    allocator: std.mem.Allocator,
    iface: []const u8,
    addr_text: []const u8,
) IpError!void {
    return runIp(allocator, iface, addr_text, .del);
}

// ── Session address table ─────────────────────────────────────────────────
//
// Tracks which /128s were added by this brain process so shutdown can
// clean up even if the caller doesn't track them.

pub const AddrTable = struct {
    allocator: std.mem.Allocator,
    iface: []const u8,      // owned
    entries: std.ArrayListUnmanaged(Entry),

    pub const Entry = struct {
        addr_text: []u8, // owned, 39 chars
        label: []u8,     // owned, e.g. contact cert_id (for logging)
    };

    pub fn init(allocator: std.mem.Allocator, iface: []const u8) !AddrTable {
        return .{
            .allocator = allocator,
            .iface = try allocator.dupe(u8, iface),
            .entries = .{},
        };
    }

    /// Add a /128 and record it in the table.
    pub fn add(
        self: *AddrTable,
        addr_text: []const u8,
        label: []const u8,
    ) !void {
        try addAddr(self.allocator, self.iface, addr_text);
        const owned_addr = try self.allocator.dupe(u8, addr_text);
        errdefer self.allocator.free(owned_addr);
        const owned_label = try self.allocator.dupe(u8, label);
        errdefer self.allocator.free(owned_label);
        try self.entries.append(self.allocator, .{
            .addr_text = owned_addr,
            .label = owned_label,
        });
    }

    /// Remove all tracked addresses and free the table.
    /// Best-effort: logs errors but continues.
    pub fn deinitAndRemoveAll(self: *AddrTable) void {
        for (self.entries.items) |*e| {
            delAddr(self.allocator, self.iface, e.addr_text) catch |err| {
                std.log.warn("ipv6_iface: failed to remove {s} ({s}): {s}",
                    .{ e.addr_text, e.label, @errorName(err) });
            };
            self.allocator.free(e.addr_text);
            self.allocator.free(e.label);
        }
        self.entries.deinit(self.allocator);
        self.allocator.free(self.iface);
    }
};

// ── Internal ──────────────────────────────────────────────────────────────

const Op = enum { add, del };

fn runIp(
    allocator: std.mem.Allocator,
    iface: []const u8,
    addr_text: []const u8,
    op: Op,
) IpError!void {
    // Build: ip -6 addr <add|del> <addr>/128 dev <iface>
    const op_str: []const u8 = if (op == .add) "add" else "del";

    const cidr = std.fmt.allocPrint(allocator, "{s}/128", .{addr_text})
        catch return error.OutOfMemory;
    defer allocator.free(cidr);

    var argv = [_][]const u8{ "ip", "-6", "addr", op_str, cidr, "dev", iface };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior  = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return error.SpawnFailed;
    const term = child.wait() catch return error.SpawnFailed;

    switch (term) {
        .Exited => |code| {
            if (code == 0) return;
            // exit 2 from `ip addr add` means EEXIST — already present.
            // exit 2 from `ip addr del` means ENODEV/not-found — already absent.
            // Both are acceptable for idempotent callers.
            if (code == 2) return;
            return error.CommandFailed;
        },
        else => return error.CommandFailed,
    }
}

```
