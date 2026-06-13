---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/hat_registry_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.182108+00:00
---

# runtime/semantos-brain/tests/hat_registry_conformance.zig

```zig
// W0.6 — HatRegistry conformance tests.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md W0.6 (hat-switching).
//
// What this closes:
//
//   • addHat / listHats round-trip — two hats added → both returned by
//     listHats().
//
//   • removeHat — after removing a hat it no longer appears in listHats().
//
//   • getCapabilities for oddjobz domain_flag (0x000101 = 257) → returns
//     the expected hardcoded capability set for that domain.
//
//   • Domain-flag isolation — capabilities for hat 0x000101 (oddjobz)
//     are not visible when querying hat 0x000102 (a different domain).
//
// The capability set is hardcoded per domain_flag for W0.6; full
// capability_utxo change-feed integration is M3.5's concern.

const std = @import("std");
const hat_registry = @import("hat_registry");

const HatRegistry = hat_registry.HatRegistry;

/// oddjobz domain flag (decimal 257).
const DOMAIN_FLAG_ODDJOBZ: u32 = 0x000101;
/// A second, distinct domain flag (carpenter = 0x000102).
const DOMAIN_FLAG_CARPENTER: u32 = 0x000102;

test "W0.6 HatRegistry: addHat + listHats — two hats are both returned" {
    const allocator = std.testing.allocator;
    var reg = HatRegistry.init(allocator);
    defer reg.deinit();

    try reg.addHat(DOMAIN_FLAG_ODDJOBZ, "oddjobz.local");
    try reg.addHat(DOMAIN_FLAG_CARPENTER, "carpenter.local");

    const hats = try reg.listHats();
    defer allocator.free(hats);

    try std.testing.expectEqual(@as(usize, 2), hats.len);

    var found_oddjobz = false;
    var found_carpenter = false;
    for (hats) |h| {
        if (h.domain_flag == DOMAIN_FLAG_ODDJOBZ) found_oddjobz = true;
        if (h.domain_flag == DOMAIN_FLAG_CARPENTER) found_carpenter = true;
    }
    try std.testing.expect(found_oddjobz);
    try std.testing.expect(found_carpenter);
}

test "W0.6 HatRegistry: removeHat — removed hat no longer appears in listHats" {
    const allocator = std.testing.allocator;
    var reg = HatRegistry.init(allocator);
    defer reg.deinit();

    try reg.addHat(DOMAIN_FLAG_ODDJOBZ, "oddjobz.local");
    try reg.addHat(DOMAIN_FLAG_CARPENTER, "carpenter.local");

    try reg.removeHat(DOMAIN_FLAG_ODDJOBZ);

    const hats = try reg.listHats();
    defer allocator.free(hats);

    try std.testing.expectEqual(@as(usize, 1), hats.len);
    try std.testing.expectEqual(DOMAIN_FLAG_CARPENTER, hats[0].domain_flag);
}

test "W0.6 HatRegistry: getCapabilities for oddjobz (0x000101) returns non-empty set" {
    const allocator = std.testing.allocator;
    var reg = HatRegistry.init(allocator);
    defer reg.deinit();

    try reg.addHat(DOMAIN_FLAG_ODDJOBZ, "oddjobz.local");

    const caps = try reg.getCapabilities(allocator, DOMAIN_FLAG_ODDJOBZ);
    defer allocator.free(caps);

    // W0.6: oddjobz has a hardcoded capability set.  At minimum the
    // canonical oddjobz capabilities must be present.
    try std.testing.expect(caps.len > 0);

    var found_jobs_read = false;
    for (caps) |cap| {
        if (std.mem.eql(u8, cap, "cap.oddjobz.read_jobs")) {
            found_jobs_read = true;
        }
    }
    try std.testing.expect(found_jobs_read);
}

test "W0.6 HatRegistry: domain_flag isolation — hat 0x000102 cannot see hat 0x000101 capabilities" {
    const allocator = std.testing.allocator;
    var reg = HatRegistry.init(allocator);
    defer reg.deinit();

    try reg.addHat(DOMAIN_FLAG_ODDJOBZ, "oddjobz.local");
    try reg.addHat(DOMAIN_FLAG_CARPENTER, "carpenter.local");

    // Capabilities for oddjobz are non-empty.
    const oddjobz_caps = try reg.getCapabilities(allocator, DOMAIN_FLAG_ODDJOBZ);
    defer allocator.free(oddjobz_caps);
    try std.testing.expect(oddjobz_caps.len > 0);

    // Capabilities for carpenter are distinct (no oddjobz-specific cap
    // leaks across domain boundaries).
    const carpenter_caps = try reg.getCapabilities(allocator, DOMAIN_FLAG_CARPENTER);
    defer allocator.free(carpenter_caps);

    for (carpenter_caps) |cap| {
        // An oddjobz-scoped capability must not appear under the carpenter hat.
        const is_oddjobz_cap = std.mem.startsWith(u8, cap, "cap.oddjobz.");
        try std.testing.expect(!is_oddjobz_cap);
    }
}

test "W0.6 HatRegistry: getCapabilities for unknown domain_flag returns error" {
    const allocator = std.testing.allocator;
    var reg = HatRegistry.init(allocator);
    defer reg.deinit();

    // 0xDEAD is not registered.
    const result = reg.getCapabilities(allocator, 0xDEAD);
    try std.testing.expectError(hat_registry.Error.hat_not_found, result);
}

test "W0.6 HatRegistry: removeHat for unknown domain_flag returns error" {
    const allocator = std.testing.allocator;
    var reg = HatRegistry.init(allocator);
    defer reg.deinit();

    const result = reg.removeHat(0xBEEF);
    try std.testing.expectError(hat_registry.Error.hat_not_found, result);
}

test "W0.6 HatRegistry: addHat duplicate domain_flag returns error" {
    const allocator = std.testing.allocator;
    var reg = HatRegistry.init(allocator);
    defer reg.deinit();

    try reg.addHat(DOMAIN_FLAG_ODDJOBZ, "oddjobz.local");
    const result = reg.addHat(DOMAIN_FLAG_ODDJOBZ, "oddjobz-dup.local");
    try std.testing.expectError(hat_registry.Error.hat_already_exists, result);
}

test "W0.6 HatRegistry: listHats on empty registry returns empty slice" {
    const allocator = std.testing.allocator;
    var reg = HatRegistry.init(allocator);
    defer reg.deinit();

    const hats = try reg.listHats();
    defer allocator.free(hats);

    try std.testing.expectEqual(@as(usize, 0), hats.len);
}

test "W0.6 HatRegistry: startCapabilityWatcher stub is callable" {
    const allocator = std.testing.allocator;
    var reg = HatRegistry.init(allocator);
    defer reg.deinit();

    try reg.addHat(DOMAIN_FLAG_ODDJOBZ, "oddjobz.local");

    // The capability watcher hook is a stub for W0.6; the test just
    // verifies the API is callable and doesn't panic.
    const Handler = struct {
        fn onCapabilityChange(domain_flag: u32, caps: []const []const u8) void {
            _ = domain_flag;
            _ = caps;
        }
    };
    hat_registry.startCapabilityWatcher(DOMAIN_FLAG_ODDJOBZ, Handler.onCapabilityChange);
}

```
