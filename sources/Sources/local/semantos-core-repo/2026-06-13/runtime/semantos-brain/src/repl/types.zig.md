---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/repl/types.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.296099+00:00
---

# runtime/semantos-brain/src/repl/types.zig

```zig
// Shared public types for the REPL, extracted from src/repl.zig as
// Phase 1 of the modularize.  Pure code motion: no behaviour change.
//
// Owns: Session (the aggregate state every REPL command takes), the
// supporting NamedInstance / Output / ReplExit types, and the
// ReplError set.
//
// src/repl.zig re-exports each so external callers (cli/repl.zig,
// tests) keep reaching them as `repl.X`.

const std = @import("std");
const config_mod = @import("config");
const audit_log_mod = @import("audit_log");
const broker_mod = @import("broker");
const instance_manager = @import("instance_manager");
const runner_mod = @import("runner");
const header_store_mod = @import("header_store");
const dispatcher_mod = @import("dispatcher");
const repl_verb_registry_mod = @import("repl_verb_registry"); // C4 PR-R3
const do_verb_registry_mod = @import("do_verb_registry"); // DO-1 — `do` operator-action grammar
const identity_certs_mod = @import("identity_certs");
const cell_query_handler_mod = @import("cell_query_handler"); // `query <noun>` → cell.query

pub const ReplError = error{
    out_of_memory,
    write_failed,
    history_failed,
};

pub const NamedInstance = struct {
    name: []const u8,
    instance: runner_mod.Instance,
};

/// Aggregate state the REPL handlers operate over. Caller (cmdRepl) owns
/// the underlying objects; Session just borrows them.
pub const Session = struct {
    allocator: std.mem.Allocator,
    cfg: *const config_mod.Config,
    audit_path: []const u8,
    audit: *audit_log_mod.AuditLog,
    broker: *broker_mod.Broker,
    manager: *instance_manager.InstanceManager,
    runner: *runner_mod.Runner,
    /// One entry per loaded module.  `name` matches the config key so
    /// the `call <module>` command can find the right instance.
    instances: []NamedInstance,
    header_store: *const header_store_mod.HeaderStore,
    /// D-W1 Phase 0 — when non-null, status/help/exit are routed
    /// through this dispatcher's `repl` resource shim handlers (see
    /// `registerReplShims`).  When null (e.g. legacy fixtures), the
    /// `handleLine` if-chain falls through to the direct-call path.
    /// In production (`cli.cmdRepl`) the dispatcher is always set.
    dispatcher: ?*dispatcher_mod.Dispatcher = null,
    /// C4 PR-R3 — cartridge-registered REPL verb forms (`find jobs`, `jobs quote`).
    /// When set (REPL boot, after the cartridge seam's dispatchRegistrations),
    /// handleLine consults it before the generic `<resource> <verb>` path. null in
    /// fixtures / pre-R3 → no cartridge verbs.
    repl_verb_registry: ?*repl_verb_registry_mod.ReplVerbRegistry = null,
    /// DO-1 — the `do <verb> <resource> <target>` operator-action registry.
    /// Set on the serve path (cmdServe) so the helm reaches `do` verbs over the
    /// HTTP REPL; null in fixtures / standalone repl until wired.
    do_verb_registry: ?*do_verb_registry_mod.DoVerbRegistry = null,
    /// D-W1 Phase 1 Part 2 — when non-null, the `device list` / `device
    /// revoke <id>` REPL verbs dispatch through this cert store (via
    /// the dispatcher's identity_certs resource).  When null (no cert
    /// store wired into the session — the legacy default), `device`
    /// prints a hint pointing the operator at `brain device` instead.
    cert_store: ?*identity_certs_mod.CertStore = null,
    /// D-OJ-conv-turns-query — when non-null, `find turns job <id>` and
    /// `find turns conv <id>` spawn a bun subprocess at this path to query
    /// Postgres for canonical conversation turns.  Absent → prints a hint.
    conv_turns_query_script: ?[]const u8 = null,
    /// The shell-native `query <noun> [filters]` REPL primitive routes here —
    /// the generic cell.query substrate (typeHash/alias/collection_key →
    /// cell_decoder_registry → cells). Set on the serve path once the handler
    /// is built (serve.zig); null in fixtures → `query` prints a hint. This is
    /// the seam that makes cell-querying shell-native + cartridge-agnostic
    /// (find → cell.query unification).
    cell_query_handler: ?*const cell_query_handler_mod.Handler = null,
};

/// C4 PR-R1 — the REPL writer is now a concrete type shared with the cli layer
/// (the `repl_output` std-only leaf), so handleLine + every `cmd*` take
/// `*const Output` (was `out: anytype`) and the ReplVerbRegistry can hold
/// runtime fn-pointers over them. cli.Output re-exports the same leaf type.
pub const Output = @import("repl_output").Output;

/// Compare two strings for equality.  REPL verbs use this for case-
/// sensitive command-name matching.
pub fn matches(actual: []const u8, expected: []const u8) bool {
    return std.mem.eql(u8, actual, expected);
}

pub const ReplExit = enum {
    /// User issued `exit` / `quit` / EOF.
    quit,
    /// User issued an unknown command. The dispatcher already printed
    /// a hint; the loop continues.
    @"continue",
};

```
