---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/content_store_local_fs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.235325+00:00
---

# runtime/semantos-brain/src/content_store_local_fs.zig

```zig
// M4.1 — ContentStoreLocalFs: local-filesystem-backed octave-1 content store.
//
// Stores 1024-byte-aligned slot files under:
//   <data_dir>/content/o1/<slot_hex8>.slot
//
// File naming: %08x.slot (8-char lowercase hex of u32 slot number).
// fetchWindow uses pread semantics (positional read) so it is O(1) per call
// regardless of file size — it never reads the entire file.
//
// Octave-2+ (UHRP-HTTP) is handled by a separate ContentStoreUhrpHttp
// in M4.2. This module only covers octave-1.

const std = @import("std");

pub const ContentStoreLocalFs = struct {
    allocator: std.mem.Allocator,
    /// Owned path to the octave-1 content directory: "<data_dir>/content/o1".
    dir_path: []u8,

    /// Initialise a ContentStoreLocalFs rooted at `data_dir`.
    /// Creates <data_dir>/content/o1/ on first call (idempotent).
    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !ContentStoreLocalFs {
        const subdir = try std.fs.path.join(allocator, &.{ data_dir, "content", "o1" });
        errdefer allocator.free(subdir);
        std.fs.cwd().makePath(subdir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        return .{
            .allocator = allocator,
            .dir_path = subdir,
        };
    }

    pub fn deinit(self: *ContentStoreLocalFs) void {
        self.allocator.free(self.dir_path);
        self.dir_path = &.{};
    }

    /// Build the slot file path into `buf`.
    /// Format: "<dir_path>/<slot_hex8>.slot"
    fn slotPath(self: *const ContentStoreLocalFs, slot: u32, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{s}/{x:0>8}.slot", .{ self.dir_path, slot });
    }

    /// Read exactly 1024 bytes starting at `offset` within the slot file.
    ///
    /// Returns:
    ///   - `void` on success (1024 bytes written to `out`).
    ///   - `error.FileNotFound` if the slot file does not exist.
    ///   - `error.EndOfStream` if `offset + 1024 > file_size`.
    ///
    /// O(1): uses positional read (pread), never loads the whole file.
    pub fn fetchWindow(
        self: *ContentStoreLocalFs,
        slot: u32,
        offset: u32,
        out: *[1024]u8,
    ) !void {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try self.slotPath(slot, &path_buf);

        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            else => return err,
        };
        defer file.close();

        // Check that the window fits within the file.
        const stat = try file.stat();
        const end: u64 = @as(u64, offset) + 1024;
        if (end > stat.size) return error.EndOfStream;

        // Positional read: seek then read.
        try file.seekTo(offset);
        var total: usize = 0;
        while (total < 1024) {
            const n = try file.read(out[total..]);
            if (n == 0) return error.EndOfStream;
            total += n;
        }
    }

    /// Write `data` into the slot file, creating or overwriting it.
    /// Used by tests to set up fixture data, and by the runtime to persist
    /// newly fetched octave-1 content.
    pub fn writeSlot(self: *ContentStoreLocalFs, slot: u32, data: []const u8) !void {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try self.slotPath(slot, &path_buf);

        // Write-then-rename for atomicity.
        var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
        const tmp_path = try std.fmt.bufPrint(
            &tmp_buf,
            "{s}.tmp",
            .{path},
        );

        const tmp = try std.fs.cwd().createFile(tmp_path, .{ .truncate = true });
        var ok = false;
        defer if (!ok) std.fs.cwd().deleteFile(tmp_path) catch {};

        var written: usize = 0;
        while (written < data.len) {
            const n = try tmp.write(data[written..]);
            if (n == 0) {
                tmp.close();
                return error.NoSpaceLeft;
            }
            written += n;
        }
        try tmp.sync();
        tmp.close();

        try std.fs.cwd().rename(tmp_path, path);
        ok = true;
    }

    /// Read the ENTIRE slot file. Octave-1 overflow content is frequently
    /// smaller than 1024 bytes (a long-but-not-huge job-sheet work
    /// description), and `fetchWindow` structurally cannot serve a slot
    /// smaller than one 1024-byte window (`offset + 1024 > file_size` →
    /// `error.EndOfStream`). The escalation read path MUST go through
    /// here, never `fetchWindow`. Caller owns the returned slice.
    ///
    /// Returns `error.FileNotFound` if the slot file does not exist.
    pub fn readSlot(
        self: *ContentStoreLocalFs,
        slot: u32,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try self.slotPath(slot, &path_buf);

        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            else => return err,
        };
        defer file.close();

        const stat = try file.stat();
        const buf = try allocator.alloc(u8, @intCast(stat.size));
        errdefer allocator.free(buf);
        var total: usize = 0;
        while (total < buf.len) {
            const n = try file.read(buf[total..]);
            if (n == 0) break;
            total += n;
        }
        return buf[0..total];
    }
};

test "readSlot round-trips sub-1024B content (fetchWindow cannot)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const base = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base);

    var store = try ContentStoreLocalFs.init(allocator, base);
    defer store.deinit();

    const payload = "the full job-sheet work scope text that exceeds the 768-byte inline cell budget but is well under 1 KiB";
    try store.writeSlot(7, payload);

    const got = try store.readSlot(7, allocator);
    defer allocator.free(got);
    try std.testing.expectEqualStrings(payload, got);

    // The exact trap this method exists to avoid: a <1024B slot is
    // unreadable via fetchWindow.
    var win: [1024]u8 = undefined;
    try std.testing.expectError(error.EndOfStream, store.fetchWindow(7, 0, &win));

    // Missing slot surfaces a clean FileNotFound.
    try std.testing.expectError(error.FileNotFound, store.readSlot(999, allocator));
}

```
