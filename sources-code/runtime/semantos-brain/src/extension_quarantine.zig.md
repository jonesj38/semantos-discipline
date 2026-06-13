---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/extension_quarantine.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.214815+00:00
---

# runtime/semantos-brain/src/extension_quarantine.zig

```zig
// Phase D-W2 Phase 4 — Extension quarantine: state machine + transitions
// + persistent index.
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
//   §7 Phase 4 (the deliverable), §3 (`quarantine_on_revoke` top-level
//   option), §6 / §10 (quarantine semantics).
//
// What this module does:
//
//   • Owns the `QuarantineState` enum + `QuarantineRecord` struct that
//     the brain uses to track each installed extension's reachability.
//
//   • Owns the persistent quarantine index — a JSON-lines file at
//     `<data_dir>/extension-quarantine.json`.  Records are append-only;
//     state transitions are documented in subsequent records (audit-
//     style) so the operator can see the full history of every
//     extension's quarantine lifecycle.
//
//   • Owns the per-extension metadata file (`meta.json`) the
//     subscriber drops next to each installed bundle.  The nullifier-
//     apply path reads this to identify which extensions belong to a
//     revoked signer.
//
//   • Provides `transitionToQuarantine` (called from the nullifier-
//     apply path on revocation) and `evaluateQuarantine` (called by
//     the operator post-rotation to re-enable an extension that's now
//     covered by a fresh signer entry).
//
//   • Provides `hardRemove` for the operator-driven "I don't want this
//     extension back" path, and the `quarantine_on_revoke = false`
//     opt-out where the apply path skips quarantine and goes straight
//     to hard remove.
//
// Trade-offs documented in the brief:
//
//   (a) Quarantine flag location — chosen as a parallel
//       `Dispatcher.quarantined_handlers` set (not a field on
//       `ResourceHandler`).  Cleaner separation; doesn't bloat the
//       handler vtable; multiple callers (CLI, REPL, audit) can consult
//       the set without going through a handler indirection.
//
//   (b) Per-extension metadata — `meta.json` is written by the
//       subscriber's apply path (extension_subscriber.zig).  Phase 4
//       adds the write because Phase 2 didn't.  Layout is documented
//       on `ExtensionMeta` below.
//
//   (c) Re-evaluation idempotency — `evaluateQuarantine` is callable
//       repeatedly; it's a no-op when the extension is already
//       `active`.  Documented on the function.

const std = @import("std");
const dispatcher_mod = @import("dispatcher");
const audit_log = @import("audit_log");
const tenant_manifest = @import("tenant_manifest");

// Inlined here (rather than importing extension_subscriber) to avoid a
// circular dep: extension_subscriber → extension_quarantine for
// `markQuarantined`; extension_quarantine → extension_subscriber for
// scope matching.  The helper is small + identical to
// `extension_subscriber.signerScopeMatches`; if it ever diverges,
// extract to a shared module.
fn signerScopeMatches(scopes: []const []const u8, extension_name: []const u8) bool {
    for (scopes) |scope| {
        if (scopeMatch(scope, extension_name)) return true;
    }
    return false;
}

fn scopeMatch(scope: []const u8, name: []const u8) bool {
    if (scope.len == 1 and scope[0] == '*') return true;
    if (std.mem.endsWith(u8, scope, ".*")) {
        const prefix = scope[0 .. scope.len - 2];
        if (prefix.len == 0) return false;
        if (name.len <= prefix.len + 1) return false;
        if (!std.mem.startsWith(u8, name, prefix)) return false;
        return name[prefix.len] == '.';
    }
    return std.mem.eql(u8, scope, name);
}

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

pub const QUARANTINE_INDEX_FILE: []const u8 = "extension-quarantine.json";
pub const META_FILE: []const u8 = "meta.json";
pub const PUBKEY_LEN: usize = 33;

/// Maximum quarantine-index size we'll read in one go.  Operators
/// running steady-state shouldn't have more than a handful of
/// transitions per signer; 4 MiB is plenty.
pub const MAX_INDEX_SIZE: usize = 4 * 1024 * 1024;

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const QuarantineError = error{
    out_of_memory,
    index_io_failed,
    index_parse_failed,
    index_too_large,
    meta_io_failed,
    meta_parse_failed,
    meta_missing,
    extension_not_found,
    bundle_remove_failed,
};

// ─────────────────────────────────────────────────────────────────────
// State + reason codes
// ─────────────────────────────────────────────────────────────────────

/// Lifecycle states an installed extension can occupy.
///
///   • `active` — normal: dispatcher routes calls to its handlers.
///   • `quarantined` — disabled: the dispatcher returns
///     `error.handler_quarantined` for any registered handler under
///     this extension's namespace.  Bundle bytes preserved on disk.
///   • `pending_evaluation` — operator has signalled they want to
///     re-evaluate this extension; the next `evaluateQuarantine` call
///     will check whether the bundle now verifies against a fresh
///     signer.  v0.1 transitions through this state implicitly when
///     `evaluateQuarantine` is invoked; reserved for a future
///     async-operator-flow where the brain marks something
///     "pending eval" and walks back to it.
///   • `removed` — operator hard-deleted: bundle bytes gone, dispatcher
///     entry gone.  Tombstone in the quarantine index for audit.
pub const QuarantineState = enum {
    active,
    quarantined,
    pending_evaluation,
    removed,

    pub fn name(self: QuarantineState) []const u8 {
        return switch (self) {
            .active => "active",
            .quarantined => "quarantined",
            .pending_evaluation => "pending_evaluation",
            .removed => "removed",
        };
    }

    pub fn parse(s: []const u8) ?QuarantineState {
        if (std.mem.eql(u8, s, "active")) return .active;
        if (std.mem.eql(u8, s, "quarantined")) return .quarantined;
        if (std.mem.eql(u8, s, "pending_evaluation")) return .pending_evaluation;
        if (std.mem.eql(u8, s, "removed")) return .removed;
        return null;
    }
};

/// Why the extension transitioned into its current state.
///
///   • `signer_revoked` — the signer's nullifier was applied (pure
///     revocation case).
///   • `signer_rotated_unsigned_bundle` — the signer's key was rotated
///     and this bundle is signed by the OLD pubkey; until a re-publish
///     under the NEW key, the bundle stays quarantined.
///   • `manual_quarantine` — operator-initiated quarantine without a
///     chain event (rare; for paranoid scenarios).
///   • `evaluation_passed` — the bundle re-verified against a fresh
///     signer entry; quarantined → active.
///   • `operator_remove` — operator-driven hard remove.
///   • `revoke_hard_delete` — applies when `quarantine_on_revoke =
///     false`; the apply path skips quarantine and goes straight to
///     remove.
pub const QuarantineReason = enum {
    signer_revoked,
    signer_rotated_unsigned_bundle,
    manual_quarantine,
    evaluation_passed,
    operator_remove,
    revoke_hard_delete,

    pub fn name(self: QuarantineReason) []const u8 {
        return switch (self) {
            .signer_revoked => "signer_revoked",
            .signer_rotated_unsigned_bundle => "signer_rotated_unsigned_bundle",
            .manual_quarantine => "manual_quarantine",
            .evaluation_passed => "evaluation_passed",
            .operator_remove => "operator_remove",
            .revoke_hard_delete => "revoke_hard_delete",
        };
    }

    pub fn parse(s: []const u8) ?QuarantineReason {
        if (std.mem.eql(u8, s, "signer_revoked")) return .signer_revoked;
        if (std.mem.eql(u8, s, "signer_rotated_unsigned_bundle")) return .signer_rotated_unsigned_bundle;
        if (std.mem.eql(u8, s, "manual_quarantine")) return .manual_quarantine;
        if (std.mem.eql(u8, s, "evaluation_passed")) return .evaluation_passed;
        if (std.mem.eql(u8, s, "operator_remove")) return .operator_remove;
        if (std.mem.eql(u8, s, "revoke_hard_delete")) return .revoke_hard_delete;
        return null;
    }
};

// ─────────────────────────────────────────────────────────────────────
// Records
// ─────────────────────────────────────────────────────────────────────

/// One transition record in the quarantine index.  The index file is
/// JSON-lines; each line is one record.  `previous_state` enables the
/// operator to diff transitions over time without having to walk the
/// whole index — most readers care about the latest record per
/// (extension_name) tuple.
pub const QuarantineRecord = struct {
    extension_name: []const u8,
    version: []const u8,
    /// 66 hex chars — the SEC1-compressed signer pubkey at install
    /// time.  This is the load-bearing "which signer owned this
    /// install?" field.
    signer_pubkey_hex: []const u8,
    state: QuarantineState,
    /// Unix-seconds.
    quarantined_at: i64,
    reason: QuarantineReason,
    /// `<data_dir>/extensions/<name>/<version>/`.  Borrowed.
    original_install_path: []const u8,
    /// The state immediately before this transition (for diffing).
    previous_state: QuarantineState,
};

/// Per-extension metadata written next to the bundle by the
/// subscriber's apply path.  Format: JSON object on disk at
/// `<data_dir>/extensions/<name>/<version>/meta.json`.
///
/// Phase 4 reads this to identify which extensions belong to a
/// revoked signer.  See ambiguity (b) in the brief.
pub const ExtensionMeta = struct {
    /// 66 hex chars — signer pubkey at install time.
    signer_pubkey_hex: []const u8,
    /// 64 hex chars — publish-tx-id (display order).  Carried so the
    /// operator can correlate quarantine transitions back to the
    /// on-chain publish event.
    publish_txid_hex: []const u8,
    /// Unix-seconds when the apply path wrote this file.
    applied_at: i64,
    /// The signer's manifest name at install time (e.g. "platform",
    /// "acme_extensions").  Carried for audit clarity; the canonical
    /// "did this extension belong to signer X?" check is via pubkey.
    signer_name: []const u8 = "",
};

// ─────────────────────────────────────────────────────────────────────
// Outcome of `evaluateQuarantine`
// ─────────────────────────────────────────────────────────────────────

/// What `evaluateQuarantine` returns to the operator-facing CLI.
pub const EvaluationOutcome = struct {
    /// What the extension's state is AFTER evaluation.
    state: QuarantineState,
    /// True when this evaluation rewound a `quarantined` extension
    /// back to `active` (the canonical happy path post-rotation).
    transitioned_to_active: bool,
    /// True when the extension was already `active` and this call was
    /// a no-op (idempotent).  See ambiguity (c) in the brief.
    no_op: bool,
    /// Free-form human-readable reason for the outcome (e.g. "no
    /// matching signer entry covers this namespace").  Borrowed —
    /// caller treats lifetime as the call's.
    detail: []const u8,
};

// ─────────────────────────────────────────────────────────────────────
// Per-extension meta read/write
// ─────────────────────────────────────────────────────────────────────

/// Write a per-extension meta file at
/// `<data_dir>/extensions/<extension_name>/<version>/meta.json`.
/// Called from the subscriber's apply path on first install.
pub fn writeExtensionMeta(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    extension_name: []const u8,
    version: []const u8,
    meta: ExtensionMeta,
) QuarantineError!void {
    const ext_dir = std.fs.path.join(allocator, &.{ data_dir, "extensions", extension_name, version }) catch
        return error.out_of_memory;
    defer allocator.free(ext_dir);
    std.fs.cwd().makePath(ext_dir) catch return error.meta_io_failed;

    const meta_path = std.fs.path.join(allocator, &.{ ext_dir, META_FILE }) catch
        return error.out_of_memory;
    defer allocator.free(meta_path);

    const json = std.fmt.allocPrint(
        allocator,
        "{{\"signer_pubkey\":\"{s}\",\"publish_txid\":\"{s}\",\"applied_at\":{d},\"signer_name\":\"{s}\"}}\n",
        .{
            meta.signer_pubkey_hex,
            meta.publish_txid_hex,
            meta.applied_at,
            meta.signer_name,
        },
    ) catch return error.out_of_memory;
    defer allocator.free(json);

    const f = std.fs.cwd().createFile(meta_path, .{ .truncate = true }) catch return error.meta_io_failed;
    defer f.close();
    f.writeAll(json) catch return error.meta_io_failed;
}

/// Read a per-extension meta file.  Caller frees the returned slice
/// pointers in the result via `freeExtensionMeta`.
pub fn readExtensionMeta(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    extension_name: []const u8,
    version: []const u8,
) QuarantineError!ExtensionMeta {
    const meta_path = std.fs.path.join(allocator, &.{ data_dir, "extensions", extension_name, version, META_FILE }) catch
        return error.out_of_memory;
    defer allocator.free(meta_path);

    const f = std.fs.cwd().openFile(meta_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.meta_missing,
        else => return error.meta_io_failed,
    };
    defer f.close();
    const stat = f.stat() catch return error.meta_io_failed;
    if (stat.size > 64 * 1024) return error.meta_io_failed;
    const buf = allocator.alloc(u8, stat.size) catch return error.out_of_memory;
    defer allocator.free(buf);
    _ = f.readAll(buf) catch return error.meta_io_failed;

    return parseExtensionMeta(allocator, buf);
}

pub fn freeExtensionMeta(allocator: std.mem.Allocator, meta: ExtensionMeta) void {
    if (meta.signer_pubkey_hex.len > 0) allocator.free(meta.signer_pubkey_hex);
    if (meta.publish_txid_hex.len > 0) allocator.free(meta.publish_txid_hex);
    if (meta.signer_name.len > 0) allocator.free(meta.signer_name);
}

/// Tiny JSON parser pinned to the meta.json shape.  Avoids a full JSON
/// dep; the format is byte-stable per writeExtensionMeta.
fn parseExtensionMeta(allocator: std.mem.Allocator, bytes: []const u8) QuarantineError!ExtensionMeta {
    var meta = ExtensionMeta{
        .signer_pubkey_hex = "",
        .publish_txid_hex = "",
        .applied_at = 0,
        .signer_name = "",
    };

    if (extractStringField(bytes, "signer_pubkey")) |v| {
        meta.signer_pubkey_hex = allocator.dupe(u8, v) catch return error.out_of_memory;
    } else return error.meta_parse_failed;

    if (extractStringField(bytes, "publish_txid")) |v| {
        meta.publish_txid_hex = allocator.dupe(u8, v) catch return error.out_of_memory;
    } else {
        if (meta.signer_pubkey_hex.len > 0) allocator.free(meta.signer_pubkey_hex);
        return error.meta_parse_failed;
    }

    if (extractIntField(bytes, "applied_at")) |v| {
        meta.applied_at = v;
    }

    if (extractStringField(bytes, "signer_name")) |v| {
        meta.signer_name = allocator.dupe(u8, v) catch return error.out_of_memory;
    }

    return meta;
}

fn extractStringField(bytes: []const u8, field: []const u8) ?[]const u8 {
    var key_buf: [128]u8 = undefined;
    if (field.len + 4 > key_buf.len) return null;
    const key = std.fmt.bufPrint(&key_buf, "\"{s}\":\"", .{field}) catch return null;
    const idx = std.mem.indexOf(u8, bytes, key) orelse return null;
    const start = idx + key.len;
    const end_rel = std.mem.indexOfScalarPos(u8, bytes, start, '"') orelse return null;
    return bytes[start..end_rel];
}

fn extractIntField(bytes: []const u8, field: []const u8) ?i64 {
    var key_buf: [128]u8 = undefined;
    if (field.len + 3 > key_buf.len) return null;
    const key = std.fmt.bufPrint(&key_buf, "\"{s}\":", .{field}) catch return null;
    const idx = std.mem.indexOf(u8, bytes, key) orelse return null;
    var i = idx + key.len;
    // Skip whitespace.
    while (i < bytes.len and (bytes[i] == ' ' or bytes[i] == '\t')) : (i += 1) {}
    if (i >= bytes.len) return null;
    var negative = false;
    if (bytes[i] == '-') {
        negative = true;
        i += 1;
    }
    var v: i64 = 0;
    var any = false;
    while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {
        v = v * 10 + @as(i64, bytes[i] - '0');
        any = true;
    }
    if (!any) return null;
    return if (negative) -v else v;
}

// ─────────────────────────────────────────────────────────────────────
// Index — append-only JSON-lines log of transitions
// ─────────────────────────────────────────────────────────────────────

/// Append one record to the quarantine index at
/// `<data_dir>/extension-quarantine.json`.  Format: one JSON object
/// per line (matches the audit + revoked-keys index conventions).
pub fn appendQuarantineRecord(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    rec: QuarantineRecord,
) QuarantineError!void {
    const path = std.fs.path.join(allocator, &.{ data_dir, QUARANTINE_INDEX_FILE }) catch
        return error.out_of_memory;
    defer allocator.free(path);

    if (std.fs.path.dirname(path)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }

    const line = std.fmt.allocPrint(
        allocator,
        "{{\"extension_name\":\"{s}\",\"version\":\"{s}\",\"signer_pubkey\":\"{s}\",\"state\":\"{s}\",\"quarantined_at\":{d},\"reason\":\"{s}\",\"original_install_path\":\"{s}\",\"previous_state\":\"{s}\"}}\n",
        .{
            rec.extension_name,
            rec.version,
            rec.signer_pubkey_hex,
            rec.state.name(),
            rec.quarantined_at,
            rec.reason.name(),
            rec.original_install_path,
            rec.previous_state.name(),
        },
    ) catch return error.out_of_memory;
    defer allocator.free(line);

    const f = std.fs.cwd().createFile(path, .{ .read = false, .truncate = false }) catch
        return error.index_io_failed;
    defer f.close();
    f.seekFromEnd(0) catch return error.index_io_failed;
    f.writeAll(line) catch return error.index_io_failed;
}

/// Read the quarantine index and return the LATEST record per
/// (extension_name).  Caller owns the returned slice via
/// `freeRecords` (which frees both the slice and every record's
/// owned strings).
pub fn loadLatestRecords(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
) QuarantineError![]QuarantineRecord {
    const path = std.fs.path.join(allocator, &.{ data_dir, QUARANTINE_INDEX_FILE }) catch
        return error.out_of_memory;
    defer allocator.free(path);

    const f = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return allocator.alloc(QuarantineRecord, 0) catch error.out_of_memory,
        else => return error.index_io_failed,
    };
    defer f.close();

    const stat = f.stat() catch return error.index_io_failed;
    if (stat.size > MAX_INDEX_SIZE) return error.index_too_large;
    const buf = allocator.alloc(u8, stat.size) catch return error.out_of_memory;
    defer allocator.free(buf);
    _ = f.readAll(buf) catch return error.index_io_failed;

    // Parse line-by-line; later records for the same extension_name
    // override earlier ones.  Strategy: keep a list of records in
    // append order, plus a name→index map.  When a duplicate name
    // arrives, replace the prior record's contents (after freeing
    // its owned strings) at the same index.
    var records: std.ArrayList(QuarantineRecord) = .empty;
    errdefer {
        for (records.items) |r| freeRecord(allocator, r);
        records.deinit(allocator);
    }
    var index_by_name = std.StringHashMap(usize).init(allocator);
    defer {
        var it = index_by_name.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        index_by_name.deinit();
    }

    var line_start: usize = 0;
    while (line_start < buf.len) {
        const nl = std.mem.indexOfScalarPos(u8, buf, line_start, '\n') orelse buf.len;
        const line = std.mem.trim(u8, buf[line_start..nl], " \t\r");
        if (line.len > 0) {
            if (parseRecord(allocator, line)) |rec| {
                if (index_by_name.get(rec.extension_name)) |idx| {
                    // Replace prior record at the same index.
                    freeRecord(allocator, records.items[idx]);
                    records.items[idx] = rec;
                } else {
                    const key = allocator.dupe(u8, rec.extension_name) catch {
                        freeRecord(allocator, rec);
                        return error.out_of_memory;
                    };
                    index_by_name.put(key, records.items.len) catch {
                        allocator.free(key);
                        freeRecord(allocator, rec);
                        return error.out_of_memory;
                    };
                    records.append(allocator, rec) catch {
                        // The map now has the key but no list entry.
                        // Roll the map back so we don't leak.
                        if (index_by_name.fetchRemove(key)) |kv| allocator.free(kv.key);
                        freeRecord(allocator, rec);
                        return error.out_of_memory;
                    };
                }
            } else |_| {
                // Skip malformed lines; the audit log will note the
                // append site, but the index isn't load-bearing for
                // safety — quarantine state is also reflected in the
                // dispatcher's in-memory set + the meta.json.
            }
        }
        if (nl == buf.len) break;
        line_start = nl + 1;
    }

    return records.toOwnedSlice(allocator) catch return error.out_of_memory;
}

pub fn freeRecord(allocator: std.mem.Allocator, rec: QuarantineRecord) void {
    if (rec.extension_name.len > 0) allocator.free(rec.extension_name);
    if (rec.version.len > 0) allocator.free(rec.version);
    if (rec.signer_pubkey_hex.len > 0) allocator.free(rec.signer_pubkey_hex);
    if (rec.original_install_path.len > 0) allocator.free(rec.original_install_path);
}

pub fn freeRecords(allocator: std.mem.Allocator, recs: []QuarantineRecord) void {
    for (recs) |r| freeRecord(allocator, r);
    allocator.free(recs);
}

fn parseRecord(allocator: std.mem.Allocator, line: []const u8) QuarantineError!QuarantineRecord {
    const ext = extractStringField(line, "extension_name") orelse return error.index_parse_failed;
    const ver = extractStringField(line, "version") orelse return error.index_parse_failed;
    const pk = extractStringField(line, "signer_pubkey") orelse return error.index_parse_failed;
    const st = extractStringField(line, "state") orelse return error.index_parse_failed;
    const ts = extractIntField(line, "quarantined_at") orelse 0;
    const reason_str = extractStringField(line, "reason") orelse return error.index_parse_failed;
    const path = extractStringField(line, "original_install_path") orelse return error.index_parse_failed;
    const prev_st = extractStringField(line, "previous_state") orelse return error.index_parse_failed;

    const state = QuarantineState.parse(st) orelse return error.index_parse_failed;
    const reason = QuarantineReason.parse(reason_str) orelse return error.index_parse_failed;
    const previous_state = QuarantineState.parse(prev_st) orelse return error.index_parse_failed;

    return .{
        .extension_name = allocator.dupe(u8, ext) catch return error.out_of_memory,
        .version = allocator.dupe(u8, ver) catch return error.out_of_memory,
        .signer_pubkey_hex = allocator.dupe(u8, pk) catch return error.out_of_memory,
        .state = state,
        .quarantined_at = ts,
        .reason = reason,
        .original_install_path = allocator.dupe(u8, path) catch return error.out_of_memory,
        .previous_state = previous_state,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Transition primitives
// ─────────────────────────────────────────────────────────────────────

/// Mark an extension as quarantined: append a transition record to
/// the index + flip the dispatcher's in-memory `quarantined_handlers`
/// flag for the corresponding handler (when a dispatcher is supplied).
///
/// The handler name registered with the dispatcher is the
/// extension_name itself (per the §7 Phase 2 metadata-only
/// registration shape).
pub fn transitionToQuarantine(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    rec: QuarantineRecord,
    dispatcher: ?*dispatcher_mod.Dispatcher,
    audit: ?*audit_log.AuditLog,
) QuarantineError!void {
    try appendQuarantineRecord(allocator, data_dir, rec);

    if (dispatcher) |d| {
        d.markQuarantined(rec.extension_name) catch |err| switch (err) {
            error.OutOfMemory => return error.out_of_memory,
        };
    }

    if (audit) |a| {
        var detail_buf: [512]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "phase=transition kind=quarantine ext={s} version={s} reason={s} previous={s}",
            .{ rec.extension_name, rec.version, rec.reason.name(), rec.previous_state.name() },
        ) catch detail_buf[0..0];
        a.record(allocator, .{
            .module = "extension_quarantine",
            .op = "extension.quarantine",
            .result = .denied,
            .detail = detail,
        }) catch {};
    }
}

/// Hard-remove an extension: delete the bundle file + meta.json,
/// remove the dispatcher entry (if registered), append a `removed`
/// record to the index.  Used by:
///
///   1. The operator-driven `brain extension quarantine remove` path.
///   2. The `quarantine_on_revoke = false` apply path (skips
///      quarantine entirely).
pub fn hardRemove(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    rec: QuarantineRecord,
    dispatcher: ?*dispatcher_mod.Dispatcher,
    audit: ?*audit_log.AuditLog,
) QuarantineError!void {
    // Delete the per-version directory + its contents.  We use
    // deleteTree because the bundle dir may contain bundle.bin +
    // meta.json + arbitrary auxiliary files written by the
    // extension itself.
    // deleteTree's error set in Zig 0.15.2 doesn't include
    // FileNotFound (it returns success when the target is missing) so
    // we just map every other I/O error to bundle_remove_failed.
    std.fs.cwd().deleteTree(rec.original_install_path) catch
        return error.bundle_remove_failed;

    if (dispatcher) |d| {
        d.unmarkQuarantined(rec.extension_name);
    }

    try appendQuarantineRecord(allocator, data_dir, rec);

    if (audit) |a| {
        var detail_buf: [512]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "phase=transition kind=remove ext={s} version={s} reason={s}",
            .{ rec.extension_name, rec.version, rec.reason.name() },
        ) catch detail_buf[0..0];
        a.record(allocator, .{
            .module = "extension_quarantine",
            .op = "extension.remove",
            .result = .denied,
            .detail = detail,
        }) catch {};
    }
}

// ─────────────────────────────────────────────────────────────────────
// Re-evaluation (operator-driven, post-rotation)
// ─────────────────────────────────────────────────────────────────────

/// Post-rotation re-evaluation: check whether `extension_name`'s
/// installed bundle is now covered by a fresh signer entry whose
/// scope includes this namespace.  If so, transition `quarantined →
/// active` (clear the dispatcher flag + append a record).  If not,
/// stay quarantined.
///
/// IDEMPOTENCY (per ambiguity (c) in the brief): callable repeatedly.
/// If the latest record for `extension_name` is already `active` or
/// `removed`, this is a no-op that returns `no_op = true`.
///
/// The caller supplies the current `manifest_signers` slice from a
/// freshly-loaded TenantManifest (the tenant.toml on disk, post-
/// rotation, will have the new pubkey for the signer entry whose
/// scope covers this extension).
pub fn evaluateQuarantine(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    extension_name: []const u8,
    manifest_signers: []const tenant_manifest.TrustedSigner,
    dispatcher: ?*dispatcher_mod.Dispatcher,
    audit: ?*audit_log.AuditLog,
) QuarantineError!EvaluationOutcome {
    // 1. Find the latest record for this extension.
    const records = try loadLatestRecords(allocator, data_dir);
    defer freeRecords(allocator, records);

    var latest: ?QuarantineRecord = null;
    for (records) |r| {
        if (std.mem.eql(u8, r.extension_name, extension_name)) {
            latest = r;
            break;
        }
    }
    const rec = latest orelse {
        return .{
            .state = .active,
            .transitioned_to_active = false,
            .no_op = true,
            .detail = "no quarantine record found — extension is in default active state",
        };
    };

    // 2. Idempotency: already active or already removed → no-op.
    if (rec.state == .active) {
        return .{
            .state = .active,
            .transitioned_to_active = false,
            .no_op = true,
            .detail = "extension already active",
        };
    }
    if (rec.state == .removed) {
        return .{
            .state = .removed,
            .transitioned_to_active = false,
            .no_op = true,
            .detail = "extension was hard-removed; cannot re-evaluate",
        };
    }

    // 3. Find a signer entry whose scope covers this extension.  Any
    //    matching signer in the post-rotation manifest signals the
    //    operator has re-published (or rotated) under a new key that
    //    legitimately covers the namespace.  Production deployments
    //    SHOULD additionally re-run the full bundle verify (SPV +
    //    hash + signature) against the new signer's pubkey before
    //    flipping back to active; v0.1 trusts the manifest entry as
    //    the signal because the signer's `plexus_identity_tx` was
    //    SPV-verified at manifest-load time.
    var matched: ?tenant_manifest.TrustedSigner = null;
    for (manifest_signers) |s| {
        if (signerScopeMatches(s.scopes, extension_name)) {
            matched = s;
            break;
        }
    }

    if (matched == null) {
        return .{
            .state = .quarantined,
            .transitioned_to_active = false,
            .no_op = false,
            .detail = "no matching signer entry covers this namespace — staying quarantined",
        };
    }

    // 4. Transition quarantined → active.
    const new_rec = QuarantineRecord{
        .extension_name = rec.extension_name,
        .version = rec.version,
        .signer_pubkey_hex = matched.?.pubkey_hex,
        .state = .active,
        .quarantined_at = std.time.timestamp(),
        .reason = .evaluation_passed,
        .original_install_path = rec.original_install_path,
        .previous_state = rec.state,
    };
    try appendQuarantineRecord(allocator, data_dir, new_rec);

    if (dispatcher) |d| {
        d.unmarkQuarantined(extension_name);
    }

    if (audit) |a| {
        var detail_buf: [512]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "phase=transition kind=reactivate ext={s} version={s} signer={s}",
            .{ extension_name, rec.version, matched.?.name },
        ) catch detail_buf[0..0];
        a.record(allocator, .{
            .module = "extension_quarantine",
            .op = "extension.reactivate",
            .result = .ok,
            .detail = detail,
        }) catch {};
    }

    return .{
        .state = .active,
        .transitioned_to_active = true,
        .no_op = false,
        .detail = "bundle covered by fresh signer entry — re-enabled",
    };
}

// ─────────────────────────────────────────────────────────────────────
// Bulk quarantine driven from the nullifier-apply path
// ─────────────────────────────────────────────────────────────────────

/// Walk `<data_dir>/extensions/`, find every installed extension whose
/// `meta.json` carries `signer_pubkey == revoked_pubkey_hex`, and:
///
///   • if `quarantine_on_revoke = true` (default): transition each
///     to `quarantined`.
///   • if `quarantine_on_revoke = false`: hard-remove each.
///
/// Returns the count of extensions affected.  Used from
/// `extension_nullifier.applyNullifier` post-mutation.
pub fn quarantineExtensionsBySigner(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    revoked_pubkey_hex: []const u8,
    signer_name: []const u8,
    quarantine_on_revoke: bool,
    dispatcher: ?*dispatcher_mod.Dispatcher,
    audit: ?*audit_log.AuditLog,
) QuarantineError!u32 {
    var affected: u32 = 0;

    const ext_dir = std.fs.path.join(allocator, &.{ data_dir, "extensions" }) catch
        return error.out_of_memory;
    defer allocator.free(ext_dir);

    var dir = std.fs.cwd().openDir(ext_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return error.index_io_failed,
    };
    defer dir.close();

    var ext_iter = dir.iterate();
    while (true) {
        const ext_entry = ext_iter.next() catch return error.index_io_failed;
        if (ext_entry == null) break;
        const e = ext_entry.?;
        if (e.kind != .directory) continue;
        // Skip dotfile-style entries.
        if (e.name.len > 0 and e.name[0] == '.') continue;

        const ext_name_owned = allocator.dupe(u8, e.name) catch return error.out_of_memory;
        defer allocator.free(ext_name_owned);

        // Walk versions under this extension.
        const ext_path = std.fs.path.join(allocator, &.{ ext_dir, ext_name_owned }) catch return error.out_of_memory;
        defer allocator.free(ext_path);
        var vdir = std.fs.cwd().openDir(ext_path, .{ .iterate = true }) catch continue;
        defer vdir.close();
        var v_iter = vdir.iterate();
        while (true) {
            const v_entry = v_iter.next() catch return error.index_io_failed;
            if (v_entry == null) break;
            const ve = v_entry.?;
            if (ve.kind != .directory) continue;

            const ver_owned = allocator.dupe(u8, ve.name) catch return error.out_of_memory;
            defer allocator.free(ver_owned);

            // Read meta.json.
            const meta = readExtensionMeta(allocator, data_dir, ext_name_owned, ver_owned) catch |err| switch (err) {
                error.meta_missing, error.meta_parse_failed => continue,
                else => return err,
            };
            defer freeExtensionMeta(allocator, meta);

            if (!std.mem.eql(u8, meta.signer_pubkey_hex, revoked_pubkey_hex)) continue;

            // This install belongs to the revoked signer.
            const install_path = std.fs.path.join(allocator, &.{ ext_path, ver_owned }) catch return error.out_of_memory;
            defer allocator.free(install_path);

            const rec = QuarantineRecord{
                .extension_name = ext_name_owned,
                .version = ver_owned,
                .signer_pubkey_hex = revoked_pubkey_hex,
                .state = if (quarantine_on_revoke) .quarantined else .removed,
                .quarantined_at = std.time.timestamp(),
                .reason = if (quarantine_on_revoke) .signer_revoked else .revoke_hard_delete,
                .original_install_path = install_path,
                .previous_state = .active,
            };

            if (quarantine_on_revoke) {
                transitionToQuarantine(allocator, data_dir, rec, dispatcher, audit) catch |err| switch (err) {
                    else => {
                        // Best-effort; one bad extension shouldn't
                        // stall the rest.  Audit-log the failure.
                        if (audit) |a| {
                            var buf: [256]u8 = undefined;
                            const d = std.fmt.bufPrint(&buf, "phase=fail kind=transition_err ext={s} signer={s} err={s}", .{
                                ext_name_owned, signer_name, @errorName(err),
                            }) catch buf[0..0];
                            a.record(allocator, .{
                                .module = "extension_quarantine",
                                .op = "extension.quarantine",
                                .result = .err,
                                .detail = d,
                            }) catch {};
                        }
                        continue;
                    },
                };
            } else {
                hardRemove(allocator, data_dir, rec, dispatcher, audit) catch |err| switch (err) {
                    else => {
                        if (audit) |a| {
                            var buf: [256]u8 = undefined;
                            const d = std.fmt.bufPrint(&buf, "phase=fail kind=remove_err ext={s} signer={s} err={s}", .{
                                ext_name_owned, signer_name, @errorName(err),
                            }) catch buf[0..0];
                            a.record(allocator, .{
                                .module = "extension_quarantine",
                                .op = "extension.remove",
                                .result = .err,
                                .detail = d,
                            }) catch {};
                        }
                        continue;
                    },
                };
            }
            affected += 1;
        }
    }

    return affected;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure logic
// ─────────────────────────────────────────────────────────────────────

test "QuarantineState round-trips via name/parse" {
    try std.testing.expectEqualStrings("active", QuarantineState.active.name());
    try std.testing.expectEqualStrings("quarantined", QuarantineState.quarantined.name());
    try std.testing.expectEqualStrings("removed", QuarantineState.removed.name());
    try std.testing.expectEqual(@as(?QuarantineState, .quarantined), QuarantineState.parse("quarantined"));
    try std.testing.expectEqual(@as(?QuarantineState, null), QuarantineState.parse("nope"));
}

test "QuarantineReason round-trips via name/parse" {
    try std.testing.expectEqualStrings("signer_revoked", QuarantineReason.signer_revoked.name());
    try std.testing.expectEqualStrings("revoke_hard_delete", QuarantineReason.revoke_hard_delete.name());
    try std.testing.expectEqual(@as(?QuarantineReason, .evaluation_passed), QuarantineReason.parse("evaluation_passed"));
    try std.testing.expectEqual(@as(?QuarantineReason, null), QuarantineReason.parse("xyz"));
}

test "extractStringField + extractIntField parse meta.json shape" {
    const json = "{\"signer_pubkey\":\"02aabb\",\"publish_txid\":\"deadbeef\",\"applied_at\":1700000000,\"signer_name\":\"acme\"}";
    try std.testing.expectEqualStrings("02aabb", extractStringField(json, "signer_pubkey").?);
    try std.testing.expectEqualStrings("deadbeef", extractStringField(json, "publish_txid").?);
    try std.testing.expectEqualStrings("acme", extractStringField(json, "signer_name").?);
    try std.testing.expectEqual(@as(?i64, 1700000000), extractIntField(json, "applied_at"));
    try std.testing.expectEqual(@as(?i64, null), extractIntField(json, "missing"));
}

test "writeExtensionMeta + readExtensionMeta round-trip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const meta = ExtensionMeta{
        .signer_pubkey_hex = "02" ++ ("aa" ** 32),
        .publish_txid_hex = "be" ** 32,
        .applied_at = 1_700_000_000,
        .signer_name = "platform",
    };
    try writeExtensionMeta(allocator, data_dir, "oddjobz.invoicer", "0.1.0", meta);

    const got = try readExtensionMeta(allocator, data_dir, "oddjobz.invoicer", "0.1.0");
    defer freeExtensionMeta(allocator, got);
    try std.testing.expectEqualStrings(meta.signer_pubkey_hex, got.signer_pubkey_hex);
    try std.testing.expectEqualStrings(meta.publish_txid_hex, got.publish_txid_hex);
    try std.testing.expectEqual(meta.applied_at, got.applied_at);
    try std.testing.expectEqualStrings(meta.signer_name, got.signer_name);
}

test "appendQuarantineRecord + loadLatestRecords (latest wins)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const r1 = QuarantineRecord{
        .extension_name = "oddjobz.invoicer",
        .version = "0.1.0",
        .signer_pubkey_hex = "02" ++ ("aa" ** 32),
        .state = .quarantined,
        .quarantined_at = 1_700_000_000,
        .reason = .signer_revoked,
        .original_install_path = "/tmp/x/extensions/oddjobz.invoicer/0.1.0",
        .previous_state = .active,
    };
    try appendQuarantineRecord(allocator, data_dir, r1);

    const r2 = QuarantineRecord{
        .extension_name = "oddjobz.invoicer",
        .version = "0.1.0",
        .signer_pubkey_hex = "03" ++ ("bb" ** 32),
        .state = .active,
        .quarantined_at = 1_700_000_500,
        .reason = .evaluation_passed,
        .original_install_path = "/tmp/x/extensions/oddjobz.invoicer/0.1.0",
        .previous_state = .quarantined,
    };
    try appendQuarantineRecord(allocator, data_dir, r2);

    const recs = try loadLatestRecords(allocator, data_dir);
    defer freeRecords(allocator, recs);
    try std.testing.expectEqual(@as(usize, 1), recs.len);
    try std.testing.expectEqualStrings("oddjobz.invoicer", recs[0].extension_name);
    try std.testing.expectEqual(QuarantineState.active, recs[0].state);
    try std.testing.expectEqual(QuarantineReason.evaluation_passed, recs[0].reason);
    try std.testing.expectEqual(QuarantineState.quarantined, recs[0].previous_state);
}

test "loadLatestRecords on missing file returns empty slice" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const recs = try loadLatestRecords(allocator, data_dir);
    defer freeRecords(allocator, recs);
    try std.testing.expectEqual(@as(usize, 0), recs.len);
}

```
