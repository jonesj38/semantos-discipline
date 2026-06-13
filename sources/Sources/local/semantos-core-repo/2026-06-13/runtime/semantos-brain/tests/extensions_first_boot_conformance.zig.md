---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/extensions_first_boot_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.207338+00:00
---

# runtime/semantos-brain/tests/extensions_first_boot_conformance.zig

```zig
// D-O3 — extensions first-boot capability mint conformance.
//
// Reference:
//   - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O3 (cap mint table),
//     §7 (boot-sequence integration), §9 (acceptance gates;
//     specifically §9.8 "no new top-level boot step")
//   - cartridges/oddjobz/brain/src/capabilities.ts (the canonical TS source
//     this Zig manifest mirrors)
//   - runtime/semantos-brain/src/extensions.zig (the unit under test)
//
// What this exercises:
//
//   • The §9.8 acceptance gate — `mintFirstBootCapabilities`'s
//     no_root_cert path returns the typed error cleanly so cmdServe
//     can swallow it as the expected first-run shape.
//   • The §O3 mint pass — after issue_root, calling
//     `mintFirstBootCapabilities` populates the operator-root cert's
//     allowlist with all six oddjobz cap names verbatim.
//   • Idempotence — a second call after the first is a no-op (set
//     semantics on cap names).
//   • Log replay — closing + reopening the cert store reconstructs
//     the merged allowlist exactly.

const std = @import("std");
const extensions = @import("extensions");
const identity_certs = @import("identity_certs");
const bkds = @import("bkds");

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    store: identity_certs.CertStore,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(data_dir);

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .data_dir = data_dir,
            .store = undefined,
        };
        self.store = try identity_certs.CertStore.init(allocator, data_dir, pinnedClock);
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.store.deinit();
        self.tmp_dir.cleanup();
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }
};

fn makeRootKey(seed: []const u8) ![bkds.KEY_LEN]u8 {
    return try bkds.pubFromSeed(seed);
}

test "D-O3 — mint with no root cert returns no_root_cert" {
    const allocator = std.testing.allocator;
    var fix = try Fixture.init(allocator);
    defer fix.deinit();

    const err = extensions.mintFirstBootCapabilities(allocator, &fix.store, null, null);
    try std.testing.expectError(extensions.ExtensionError.no_root_cert, err);
}

test "D-O3 — first mint after issue_root populates all six cap names" {
    const allocator = std.testing.allocator;
    var fix = try Fixture.init(allocator);
    defer fix.deinit();

    const root_pub = try makeRootKey("test-seed-d-o3-fresh");
    _ = try fix.store.issueRoot(root_pub, "operator-root");

    try extensions.mintFirstBootCapabilities(allocator, &fix.store, null, null);

    const root_id_arr = fix.store.root_id orelse return error.no_root_id;
    const root = try fix.store.get(root_id_arr[0..]);
    try std.testing.expectEqual(@as(usize, 6), root.capabilities.len);

    const expected = [_][]const u8{
        "cap.oddjobz.write_customer",
        "cap.oddjobz.quote",
        "cap.oddjobz.dispatch",
        "cap.oddjobz.invoice",
        "cap.oddjobz.close",
        "cap.oddjobz.public_chat_serve",
    };
    for (expected, root.capabilities) |want, got| {
        try std.testing.expectEqualStrings(want, got);
    }
}

test "D-O3 — second mint is idempotent (no duplicates)" {
    const allocator = std.testing.allocator;
    var fix = try Fixture.init(allocator);
    defer fix.deinit();

    const root_pub = try makeRootKey("test-seed-d-o3-idempotent");
    _ = try fix.store.issueRoot(root_pub, "operator-root");

    try extensions.mintFirstBootCapabilities(allocator, &fix.store, null, null);
    try extensions.mintFirstBootCapabilities(allocator, &fix.store, null, null);

    const root_id_arr = fix.store.root_id orelse return error.no_root_id;
    const root = try fix.store.get(root_id_arr[0..]);
    try std.testing.expectEqual(@as(usize, 6), root.capabilities.len);
}

test "D-O3 — log replay reconstructs the merged allowlist" {
    const allocator = std.testing.allocator;
    var fix = try Fixture.init(allocator);
    defer fix.deinit();

    const root_pub = try makeRootKey("test-seed-d-o3-replay");
    _ = try fix.store.issueRoot(root_pub, "operator-root");
    try extensions.mintFirstBootCapabilities(allocator, &fix.store, null, null);

    // Close + reopen the store — the on-disk log is now the only
    // source of truth.
    fix.store.deinit();
    fix.store = try identity_certs.CertStore.init(allocator, fix.data_dir, pinnedClock);

    const root_id_arr = fix.store.root_id orelse return error.no_root_id;
    const root = try fix.store.get(root_id_arr[0..]);
    try std.testing.expectEqual(@as(usize, 6), root.capabilities.len);
    try std.testing.expectEqualStrings(
        "cap.oddjobz.write_customer",
        root.capabilities[0],
    );
    try std.testing.expectEqualStrings(
        "cap.oddjobz.public_chat_serve",
        root.capabilities[5],
    );
}

```
