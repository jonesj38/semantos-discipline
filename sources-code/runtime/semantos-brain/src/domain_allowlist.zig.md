---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/domain_allowlist.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.266028+00:00
---

# runtime/semantos-brain/src/domain_allowlist.zig

```zig
// W7.14 — Domain allowlist for Caddy on-demand TLS.
//
// Stores the set of operator-registered domains (brain_domain values) that
// Caddy is allowed to issue on-demand ACME certs for.  Backed by a flat
// text file (`domain_allowlist` under $data_dir) — one FQDN per line,
// empty lines and `#` comments ignored.
//
// The file is written by provisioning (W7.9) and read on each ask.
// Reads are synchronous; the ask path is cold (only fires on new
// TLS handshakes), so the per-request file read is acceptable.
//
// File location: <data_dir>/domain_allowlist
//
// Thread safety: each call opens + closes the file; no shared state.

const std = @import("std");

pub const AllowlistError = error{
    file_io,
    out_of_memory,
};

/// Check whether `domain` is in the allowlist file at
/// `<data_dir>/domain_allowlist`.  Returns `true` if found, `false` if
/// not found OR the file does not exist (conservative default: deny).
pub fn contains(allocator: std.mem.Allocator, data_dir: []const u8, domain: []const u8) AllowlistError!bool {
    const path = std.fs.path.join(allocator, &.{ data_dir, "domain_allowlist" }) catch
        return error.out_of_memory;
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch |e| switch (e) {
        error.FileNotFound => return false,
        else => return error.file_io,
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1 << 20) catch return error.file_io;
    defer allocator.free(content);

    return containsInContent(domain, content);
}

/// Add `domain` to the allowlist file, creating it if it does not exist.
/// Idempotent: no-op if domain is already present.
pub fn add(allocator: std.mem.Allocator, data_dir: []const u8, domain: []const u8) AllowlistError!void {
    const path = std.fs.path.join(allocator, &.{ data_dir, "domain_allowlist" }) catch
        return error.out_of_memory;
    defer allocator.free(path);

    // Read existing content.
    var existing: []u8 = &.{};
    defer if (existing.len > 0) allocator.free(existing);

    if (std.fs.cwd().openFile(path, .{})) |f| {
        defer f.close();
        existing = f.readToEndAlloc(allocator, 1 << 20) catch return error.file_io;
    } else |e| switch (e) {
        error.FileNotFound => {},
        else => return error.file_io,
    }

    if (containsInContent(domain, existing)) return; // already present

    // Append domain + newline.
    const file = std.fs.cwd().createFile(path, .{ .truncate = false }) catch return error.file_io;
    defer file.close();

    file.seekFromEnd(0) catch return error.file_io;
    // Ensure we start on a fresh line.
    if (existing.len > 0 and existing[existing.len - 1] != '\n') {
        file.writeAll("\n") catch return error.file_io;
    }
    file.writeAll(domain) catch return error.file_io;
    file.writeAll("\n") catch return error.file_io;
}

/// Remove `domain` from the allowlist file.
/// Idempotent: no-op if domain is not present or file does not exist.
pub fn remove(allocator: std.mem.Allocator, data_dir: []const u8, domain: []const u8) AllowlistError!void {
    const path = std.fs.path.join(allocator, &.{ data_dir, "domain_allowlist" }) catch
        return error.out_of_memory;
    defer allocator.free(path);

    const existing: []u8 = blk: {
        const f = std.fs.cwd().openFile(path, .{}) catch |e| switch (e) {
            error.FileNotFound => return,
            else => return error.file_io,
        };
        defer f.close();
        break :blk f.readToEndAlloc(allocator, 1 << 20) catch return error.file_io;
    };
    defer allocator.free(existing);

    if (!containsInContent(domain, existing)) return; // not present

    // Rewrite the file without the removed domain.
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(allocator);

    var it = std.mem.splitScalar(u8, existing, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            // Preserve blank lines and comments.
            out.appendSlice(allocator, line) catch return error.out_of_memory;
            out.append(allocator, '\n') catch return error.out_of_memory;
            continue;
        }
        if (std.mem.eql(u8, trimmed, domain)) continue; // skip removed domain
        out.appendSlice(allocator, line) catch return error.out_of_memory;
        out.append(allocator, '\n') catch return error.out_of_memory;
    }

    const file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch return error.file_io;
    defer file.close();
    file.writeAll(out.items) catch return error.file_io;
}

// ── Internal helpers ──────────────────────────────────────────────────────

fn containsInContent(domain: []const u8, content: []const u8) bool {
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (std.mem.eql(u8, trimmed, domain)) return true;
    }
    return false;
}

// ── Inline tests ──────────────────────────────────────────────────────────

test "containsInContent: finds domain" {
    const content = "# comment\n\nbrain.coastal.com.au\nbrain.plumbing.net\n";
    try std.testing.expect(containsInContent("brain.coastal.com.au", content));
    try std.testing.expect(containsInContent("brain.plumbing.net", content));
    try std.testing.expect(!containsInContent("brain.other.com", content));
}

test "containsInContent: empty content" {
    try std.testing.expect(!containsInContent("brain.coastal.com.au", ""));
}

test "containsInContent: ignores comments and blanks" {
    const content = "# brain.coastal.com.au\n\n  \n";
    try std.testing.expect(!containsInContent("brain.coastal.com.au", content));
}

test "containsInContent: trims whitespace" {
    const content = "  brain.coastal.com.au  \n";
    try std.testing.expect(containsInContent("brain.coastal.com.au", content));
}

```
