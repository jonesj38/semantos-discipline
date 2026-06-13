---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/instance_manager.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.237313+00:00
---

# runtime/semantos-brain/src/instance_manager.zig

```zig
// Phase Brain 1 — In-process module instance manager.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 1 deliverable 3).
//
// Tracks which modules are loaded, their state (LOADED / RUNNING /
// CRASHED / STOPPED), uptime, and last-restart time. Brain 1 doesn't actually
// instantiate WASM via wasmtime — that lands in Brain 2. But the lifecycle
// state machine + restart bookkeeping is reusable across both phases:
// Brain 2 just wires `transition(.RUNNING)` to a wasmtime instantiation
// callback and the rest is unchanged.
//
// State transitions:
//
//                ┌──────────────────────┐
//                │                      ▼
//   (init) → LOADED ──→ RUNNING ──→ STOPPED
//                            │
//                            └─→ CRASHED ──┐
//                                          │
//                                          ▼
//                                    (restart) → RUNNING
//
// CRASHED is a terminal state until `restart()` is called explicitly —
// the shell does NOT auto-restart on crash. An operator inspects the
// audit log + `brain status`, decides whether the failure is transient or
// indicative of a real bug, then issues `brain restart <module>`.

const std = @import("std");
const module_loader = @import("module_loader");

pub const ModuleState = enum {
    LOADED,
    RUNNING,
    STOPPED,
    CRASHED,
};

pub const InstanceError = error{
    not_found,
    already_loaded,
    invalid_transition,
    out_of_memory,
};

pub const Instance = struct {
    /// Same name as the config key + the LoadedModule.
    name: []const u8,
    state: ModuleState,
    /// Verified bytes the loader handed us. Owned by the loader's
    /// allocator — the manager just borrows.
    loaded: *const module_loader.LoadedModule,
    /// Wall-clock seconds when the module entered its current state.
    /// `brain status` displays this as "uptime: 12m" or "crashed 3h ago".
    state_entered_at: i64,
    /// Count of state transitions of the form CRASHED → RUNNING. Operator
    /// signal — chronic restarts indicate a real problem.
    restart_count: u32,
};

/// Single-process registry of loaded modules. v0.1 holds them in a small
/// ArrayList — N is 2-4 in practice.
pub const InstanceManager = struct {
    allocator: std.mem.Allocator,
    instances: std.ArrayList(Instance),
    clock_fn: *const fn () i64,

    pub fn init(allocator: std.mem.Allocator) InstanceManager {
        return .{
            .allocator = allocator,
            .instances = .empty,
            .clock_fn = defaultClock,
        };
    }

    pub fn deinit(self: *InstanceManager) void {
        self.instances.deinit(self.allocator);
    }

    /// Tests can pin the clock for deterministic uptime assertions.
    pub fn setClockFn(self: *InstanceManager, f: *const fn () i64) void {
        self.clock_fn = f;
    }

    /// Register a freshly verified module. Initial state is LOADED;
    /// caller transitions to RUNNING once instantiation succeeds.
    pub fn register(
        self: *InstanceManager,
        loaded: *const module_loader.LoadedModule,
    ) InstanceError!void {
        if (self.findIndex(loaded.name) != null) return error.already_loaded;
        self.instances.append(self.allocator, .{
            .name = loaded.name,
            .state = .LOADED,
            .loaded = loaded,
            .state_entered_at = self.clock_fn(),
            .restart_count = 0,
        }) catch return error.out_of_memory;
    }

    pub fn get(self: *const InstanceManager, name: []const u8) ?*const Instance {
        const idx = self.findIndex(name) orelse return null;
        return &self.instances.items[idx];
    }

    fn findIndex(self: *const InstanceManager, name: []const u8) ?usize {
        for (self.instances.items, 0..) |*inst, i| {
            if (std.mem.eql(u8, inst.name, name)) return i;
        }
        return null;
    }

    /// Move `name` to `next` if the transition is allowed; otherwise
    /// `error.invalid_transition`. Updates `state_entered_at`. The
    /// `restart_count` is bumped by `restart()` itself, not here, so
    /// that restart-from-CRASHED is counted exactly once even though
    /// the post-restart state machine passes through LOADED → RUNNING.
    pub fn transition(
        self: *InstanceManager,
        name: []const u8,
        next: ModuleState,
    ) InstanceError!void {
        const idx = self.findIndex(name) orelse return error.not_found;
        var inst = &self.instances.items[idx];
        if (!isValidTransition(inst.state, next)) return error.invalid_transition;
        inst.state = next;
        inst.state_entered_at = self.clock_fn();
    }

    /// Force-reset to LOADED so the operator can attempt a fresh start.
    /// Used by `brain restart <module>` after a crash. Bumps
    /// `restart_count` when called from CRASHED — operator signal for
    /// chronic-failure detection.
    pub fn restart(self: *InstanceManager, name: []const u8) InstanceError!void {
        const idx = self.findIndex(name) orelse return error.not_found;
        var inst = &self.instances.items[idx];
        if (inst.state != .CRASHED and inst.state != .STOPPED) {
            return error.invalid_transition;
        }
        const was_crashed = inst.state == .CRASHED;
        inst.state = .LOADED;
        inst.state_entered_at = self.clock_fn();
        if (was_crashed) inst.restart_count += 1;
    }

    pub fn list(self: *const InstanceManager) []const Instance {
        return self.instances.items;
    }
};

fn isValidTransition(cur: ModuleState, next: ModuleState) bool {
    return switch (cur) {
        .LOADED => next == .RUNNING or next == .STOPPED or next == .CRASHED,
        .RUNNING => next == .STOPPED or next == .CRASHED,
        .STOPPED => false, // restart() resets to LOADED first
        .CRASHED => false, // restart() resets to LOADED first
    };
}

fn defaultClock() i64 {
    return std.time.timestamp();
}

```
