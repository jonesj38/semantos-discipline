---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/attachment_blobs_fs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.247653+00:00
---

# runtime/semantos-brain/src/attachment_blobs_fs.zig

```zig
// D-O5m.followup-8 capture+upload — Content-addressable blob store for
// attachments.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5m (mobile sensor
//            adapters); attachments_store_fs.zig (the metadata-cell
//            store keyed by content_hash); attachments_upload_http.zig
//            (the multipart upload endpoint that writes here);
//            attachments_blob_http.zig (the GET endpoint that reads
//            from here).
//
// Filesystem-backed store at `<data_dir>/oddjobz/blobs/<sha256>.bin`.
// Each blob is keyed by its sha256 hex; writes are atomic via temp-
// file rename; the metadata cell holding the hash is the canonical
// referrer.  No compression, no rotation logic — MVP posture.
//
// Threat model: the upload endpoint hashes the multipart blob bytes
// against the metadata cell's `contentHash` BEFORE calling write().
// Re-checking inside write() is belt-and-suspenders: if the cell-
// signing seam ever drifts (or a future caller skips the upstream
// check) the store still refuses to write a mismatched blob.
//
// Concurrency: each operation is independent FS I/O — no shared in-
// memory state.  Multiple concurrent writes to the same hash are safe
// (atomic rename) but redundant; callers that care about idempotency
// query exists() first.

const std = @import("std");

pub const BlobError = error{
    /// SHA256 of the supplied bytes did not match the supplied hash.
    hash_mismatch,
    /// Blob hex length wasn't 64 chars or contained non-hex chars.
    invalid_hash,
    /// The blob hash isn't present on disk (read/exists called
    /// before write or after manual deletion).
    not_found,
    /// FS-level I/O error wrapping the underlying os call.
    io_failed,
    /// Allocator failure.
    out_of_memory,
};

/// Length of the sha256 hex string used as the key.  64 lowercase hex
/// chars — same envelope the metadata cell carries in `contentHash`.
pub const HASH_HEX_LEN: usize = 64;

/// File-backed content-addressable blob store.
pub const BlobStore = struct {
    allocator: std.mem.Allocator,
    /// Owned absolute path to `<data_dir>/oddjobz/blobs`.
    blobs_dir: []u8,

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) BlobError!BlobStore {
        const oddjobz_dir = std.fs.path.join(allocator, &.{ data_dir, "oddjobz" }) catch return BlobError.out_of_memory;
        defer allocator.free(oddjobz_dir);
        std.fs.cwd().makePath(oddjobz_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return BlobError.io_failed,
        };
        const blobs_dir = std.fs.path.join(allocator, &.{ oddjobz_dir, "blobs" }) catch return BlobError.out_of_memory;
        errdefer allocator.free(blobs_dir);
        std.fs.cwd().makePath(blobs_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return BlobError.io_failed,
        };
        return .{
            .allocator = allocator,
            .blobs_dir = blobs_dir,
        };
    }

    pub fn deinit(self: *BlobStore) void {
        self.allocator.free(self.blobs_dir);
    }

    /// Validate hash hex is 64 lowercase hex chars.
    fn validateHash(hash_hex: []const u8) BlobError!void {
        if (hash_hex.len != HASH_HEX_LEN) return BlobError.invalid_hash;
        for (hash_hex) |c| {
            const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
            if (!ok) return BlobError.invalid_hash;
        }
    }

    fn blobPath(self: *const BlobStore, allocator: std.mem.Allocator, hash_hex: []const u8) BlobError![]u8 {
        var name_buf: [HASH_HEX_LEN + 4]u8 = undefined;
        std.mem.copyForwards(u8, name_buf[0..HASH_HEX_LEN], hash_hex);
        std.mem.copyForwards(u8, name_buf[HASH_HEX_LEN..][0..4], ".bin");
        return std.fs.path.join(allocator, &.{ self.blobs_dir, name_buf[0..(HASH_HEX_LEN + 4)] }) catch return BlobError.out_of_memory;
    }

    /// Compute SHA-256 of `bytes` and assert it matches `hash_hex`.
    /// Used by `write` and as a standalone check by callers that want
    /// to validate before deciding whether to upload.
    pub fn verifyHash(hash_hex: []const u8, bytes: []const u8) BlobError!void {
        try validateHash(hash_hex);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        var computed_hex: [HASH_HEX_LEN]u8 = undefined;
        hexEncode(&digest, &computed_hex);
        if (!std.mem.eql(u8, hash_hex, &computed_hex)) return BlobError.hash_mismatch;
    }

    /// Write `bytes` to disk keyed by its sha256.  Returns
    /// BlobError.hash_mismatch if SHA256(bytes) != `hash_hex`.  Atomic
    /// (write to temp file, rename).  Idempotent on the happy path —
    /// re-writing the same hash overwrites silently.
    pub fn write(self: *const BlobStore, hash_hex: []const u8, bytes: []const u8) BlobError!void {
        try verifyHash(hash_hex, bytes);

        const path = try self.blobPath(self.allocator, hash_hex);
        defer self.allocator.free(path);

        const tmp_path = std.fmt.allocPrint(self.allocator, "{s}.tmp", .{path}) catch return BlobError.out_of_memory;
        defer self.allocator.free(tmp_path);

        const cwd = std.fs.cwd();
        // Write to temp file first.
        const f = cwd.createFile(tmp_path, .{ .truncate = true }) catch return BlobError.io_failed;
        defer f.close();
        f.writeAll(bytes) catch return BlobError.io_failed;
        f.sync() catch return BlobError.io_failed;

        // Atomic rename.
        cwd.rename(tmp_path, path) catch return BlobError.io_failed;
    }

    /// True iff a blob with this hash exists on disk.  Useful for
    /// idempotent upload paths that want to short-circuit the
    /// multipart parse + signature verify when the blob is already
    /// present.
    pub fn exists(self: *const BlobStore, hash_hex: []const u8) bool {
        validateHash(hash_hex) catch return false;
        const path = self.blobPath(self.allocator, hash_hex) catch return false;
        defer self.allocator.free(path);
        const cwd = std.fs.cwd();
        cwd.access(path, .{}) catch return false;
        return true;
    }

    /// Read the blob bytes for `hash_hex`.  Caller owns the returned
    /// slice (must `allocator.free`).  Returns BlobError.not_found
    /// when the blob isn't on disk.
    pub fn read(self: *const BlobStore, allocator: std.mem.Allocator, hash_hex: []const u8) BlobError![]u8 {
        try validateHash(hash_hex);
        const path = try self.blobPath(allocator, hash_hex);
        defer allocator.free(path);
        const cwd = std.fs.cwd();
        const f = cwd.openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return BlobError.not_found,
            else => return BlobError.io_failed,
        };
        defer f.close();
        // Cap reads at the same 16 MiB ceiling the upload endpoint
        // enforces; defensive against a manually-placed blob > cap.
        const max_bytes = 16 * 1024 * 1024;
        const out = f.readToEndAlloc(allocator, max_bytes) catch |err| switch (err) {
            error.OutOfMemory => return BlobError.out_of_memory,
            else => return BlobError.io_failed,
        };
        return out;
    }
};

/// Hex-encode `bytes` into `out`.  Same shape as the
/// attachments_handler helper — keep a local copy to avoid coupling.
fn hexEncode(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

fn computeHashHex(bytes: []const u8) [HASH_HEX_LEN]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var hex: [HASH_HEX_LEN]u8 = undefined;
    hexEncode(&digest, &hex);
    return hex;
}

test "BlobStore: write → exists → read round-trip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try BlobStore.init(allocator, data_dir);
    defer store.deinit();

    const blob = "fake-jpeg-bytes-here";
    const hash_hex = computeHashHex(blob);

    try std.testing.expect(!store.exists(&hash_hex));

    try store.write(&hash_hex, blob);
    try std.testing.expect(store.exists(&hash_hex));

    const read = try store.read(allocator, &hash_hex);
    defer allocator.free(read);
    try std.testing.expectEqualStrings(blob, read);
}

test "BlobStore: write rejects hash mismatch" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try BlobStore.init(allocator, data_dir);
    defer store.deinit();

    const wrong_hash = "0" ** 64;
    const blob = "some-bytes";

    try std.testing.expectError(BlobError.hash_mismatch, store.write(wrong_hash, blob));
    try std.testing.expect(!store.exists(wrong_hash));
}

test "BlobStore: read returns not_found for missing hash" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try BlobStore.init(allocator, data_dir);
    defer store.deinit();

    const missing = "a" ** 64;
    try std.testing.expectError(BlobError.not_found, store.read(allocator, missing));
}

test "BlobStore: invalid hash hex (wrong length, uppercase, non-hex) rejected" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try BlobStore.init(allocator, data_dir);
    defer store.deinit();

    const blob = "x";
    try std.testing.expectError(BlobError.invalid_hash, store.write("tooshort", blob));
    try std.testing.expectError(BlobError.invalid_hash, store.write("A" ** 64, blob));
    try std.testing.expectError(BlobError.invalid_hash, store.write("g" ** 64, blob));
    try std.testing.expectError(BlobError.invalid_hash, store.read(allocator, "tooshort"));
}

test "BlobStore: idempotent re-write of same hash succeeds" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try BlobStore.init(allocator, data_dir);
    defer store.deinit();

    const blob = "deterministic-bytes";
    const hash_hex = computeHashHex(blob);

    try store.write(&hash_hex, blob);
    try store.write(&hash_hex, blob); // re-write should not error
    const read = try store.read(allocator, &hash_hex);
    defer allocator.free(read);
    try std.testing.expectEqualStrings(blob, read);
}

test "verifyHash standalone helper" {
    const blob = "abc";
    // SHA256 of "abc" — known test vector.
    const expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    try BlobStore.verifyHash(expected, blob);
    try std.testing.expectError(BlobError.hash_mismatch, BlobStore.verifyHash("0" ** 64, blob));
}

```
