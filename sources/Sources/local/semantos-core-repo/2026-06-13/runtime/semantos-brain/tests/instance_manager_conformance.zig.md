---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/instance_manager_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.201936+00:00
---

# runtime/semantos-brain/tests/instance_manager_conformance.zig

```zig
// Phase Brain 1 — Instance manager conformance tests.

const std = @import("std");
const module_loader = @import("module_loader");
const instance_manager = @import("instance_manager");

fn fakeLoaded(name: []const u8, allocator: std.mem.Allocator) !module_loader.LoadedModule {
    const bytes = try allocator.dupe(u8, &module_loader.WASM_MAGIC);
    const sha = module_loader.computeSha256(bytes);
    return .{
        .name = try allocator.dupe(u8, name),
        .path = try allocator.dupe(u8, "/dev/null"),
        .bytes = bytes,
        .sha256 = sha,
        .allocator = allocator,
    };
}

var clock_value: i64 = 1_700_000_000;
fn pinnedClock() i64 {
    return clock_value;
}

test "Brain 1 manager: register + get round-trip" {
    var mgr = instance_manager.InstanceManager.init(std.testing.allocator);
    defer mgr.deinit();
    var lm = try fakeLoaded("wallet-engine", std.testing.allocator);
    defer lm.deinit();
    try mgr.register(&lm);

    const inst = mgr.get("wallet-engine") orelse return error.TestFailed;
    try std.testing.expectEqualStrings("wallet-engine", inst.name);
    try std.testing.expectEqual(instance_manager.ModuleState.LOADED, inst.state);
    try std.testing.expectEqual(@as(u32, 0), inst.restart_count);
}

test "Brain 1 manager: double-register fails" {
    var mgr = instance_manager.InstanceManager.init(std.testing.allocator);
    defer mgr.deinit();
    var lm = try fakeLoaded("dup", std.testing.allocator);
    defer lm.deinit();
    try mgr.register(&lm);
    try std.testing.expectError(
        error.already_loaded,
        mgr.register(&lm),
    );
}

test "Brain 1 manager: state transitions follow the documented FSM" {
    var mgr = instance_manager.InstanceManager.init(std.testing.allocator);
    defer mgr.deinit();
    var lm = try fakeLoaded("m", std.testing.allocator);
    defer lm.deinit();
    try mgr.register(&lm);

    try mgr.transition("m", .RUNNING);
    try std.testing.expectEqual(instance_manager.ModuleState.RUNNING, mgr.get("m").?.state);

    // RUNNING → STOPPED is allowed; STOPPED → anything except restart() is not.
    try mgr.transition("m", .STOPPED);
    try std.testing.expectError(
        error.invalid_transition,
        mgr.transition("m", .RUNNING),
    );

    try mgr.restart("m");
    try std.testing.expectEqual(instance_manager.ModuleState.LOADED, mgr.get("m").?.state);
}

test "Brain 1 manager: CRASHED → restart bumps restart_count" {
    var mgr = instance_manager.InstanceManager.init(std.testing.allocator);
    mgr.setClockFn(pinnedClock);
    defer mgr.deinit();
    var lm = try fakeLoaded("flap", std.testing.allocator);
    defer lm.deinit();
    try mgr.register(&lm);

    try mgr.transition("flap", .RUNNING);
    try mgr.transition("flap", .CRASHED);
    try mgr.restart("flap");
    // restart resets to LOADED; the next RUNNING transition is what bumps.
    try mgr.transition("flap", .RUNNING);
    try std.testing.expectEqual(@as(u32, 1), mgr.get("flap").?.restart_count);

    try mgr.transition("flap", .CRASHED);
    try mgr.restart("flap");
    try mgr.transition("flap", .RUNNING);
    try std.testing.expectEqual(@as(u32, 2), mgr.get("flap").?.restart_count);
}

test "Brain 1 manager: list returns all registered" {
    var mgr = instance_manager.InstanceManager.init(std.testing.allocator);
    defer mgr.deinit();
    var lm1 = try fakeLoaded("a", std.testing.allocator);
    defer lm1.deinit();
    var lm2 = try fakeLoaded("b", std.testing.allocator);
    defer lm2.deinit();
    try mgr.register(&lm1);
    try mgr.register(&lm2);
    const list = mgr.list();
    try std.testing.expectEqual(@as(usize, 2), list.len);
}

test "Brain 1 manager: get on unknown returns null" {
    var mgr = instance_manager.InstanceManager.init(std.testing.allocator);
    defer mgr.deinit();
    try std.testing.expect(mgr.get("nope") == null);
}

```
