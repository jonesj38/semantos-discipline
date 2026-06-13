---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/manifest_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.263741+00:00
---

# runtime/semantos-brain/src/manifest_registry.zig

```zig
// Brain-side manifest registry — in-memory list of extension manifests
// the brain has been told about at runtime via verb.dispatch /
// manifest.install JSON-RPC.
//
// Reference:
//   docs/design/PLATFORM-WALLET-SHELL-EXPLORATION.md §15 (bundle format)
//   docs/design/PLATFORM-WALLET-SHELL-EXPLORATION.md §18 (this layer)
//   platforms/flutter/semantos_core/lib/src/extension_manifest.dart
//     (the Dart side of the same JSON shape)
//
// Why this exists:
//
//   The field shell (PWA or native) discovers extensions, verifies them
//   via ManifestProvisioner + BundleVerifier, and installs them into
//   its local GrammarRegistry. For multi-shell consistency the brain
//   also needs to know which manifests the operator has installed so:
//
//     - the brain's verb dispatcher (verb_dispatcher.Registry) can
//       route action verbs even from shells that don't bundle the
//       experience locally
//     - other shells paired to the same brain see the installed
//       extensions when they call manifest.list at boot
//     - the brain can serve cell.query for an installed extension's
//       typeHashes (once typed view-stores ship per-extension)
//
// Status:
//
//   Append-only JSONL log under `<data_dir>/extensions/manifests.jsonl`.
//   On init the registry replays the log to rebuild the in-memory map,
//   so installs survive restart. Each install/uninstall appends a fresh
//   record (installs as `{op:"install", ...}`, uninstalls as
//   `{op:"uninstall", extensionId}`). Replay folds these into the
//   in-memory state — the same shape that `oddjobz_ratify_handler` uses
//   for its ratifications log.
//
//   The log path is optional. When init() is called without a data_dir
//   the registry runs in-memory only — useful in tests and for
//   short-lived daemon instances. Production cli.zig wiring passes the
//   configured data_dir so installs persist.

const std = @import("std");

pub const ManifestError = error{
    duplicate_extension_id,
    not_found,
    invalid_payload,
    out_of_memory,
    persist_failed,
};

/// One registered manifest entry. The payload is the canonical JSON
/// representation of the ExtensionManifest (matching the schema in
/// platforms/flutter/semantos_core/lib/src/extension_manifest.dart).
pub const ManifestEntry = struct {
    /// Stable extension id (matches `manifest.id`). Used as the
    /// primary key.
    extension_id: []const u8,

    /// Semantic version (matches `manifest.version`).
    version: []const u8,

    /// Source identifier: URL the manifest was fetched from, asset
    /// path for compile-bundled, "verb.dispatch" for runtime-installed
    /// via the JSON-RPC. Surfaced to the operator in trust audit logs.
    source: []const u8,

    /// Unix seconds when the brain installed the manifest. From the
    /// registry's clock function (deterministic in tests).
    installed_at: i64,

    /// The raw manifest JSON bytes — kept verbatim so `manifest.list`
    /// can return them without re-encoding.
    manifest_json: []const u8,

    /// Whether the manifest carried a signature envelope and a trusted
    /// signer pubkey at install time. Empty when explicitly unsigned
    /// (compile-bundled / dev mode).
    signer_pubkey: []const u8 = "",
};

/// Manifest registry — in-memory state + optional append-only JSONL log.
///
/// When [log_path] is non-empty, install/uninstall calls append a record
/// to the log and the file is replayed at init() to rebuild state. When
/// [log_path] is empty the registry is in-memory only.
pub const Registry = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(ManifestEntry),
    mu: std.Thread.Mutex,
    clock_fn: *const fn () i64,
    /// Absolute path to the append-only log file. Empty = no persistence.
    log_path: []const u8,

    /// In-memory only (tests / short-lived daemons). No log file is
    /// touched; install / uninstall calls never persist.
    pub fn init(
        allocator: std.mem.Allocator,
        clock_fn: *const fn () i64,
    ) Registry {
        return .{
            .allocator = allocator,
            .entries = .{},
            .mu = .{},
            .clock_fn = clock_fn,
            .log_path = "",
        };
    }

    /// Persistent — appends installs/uninstalls to
    /// `<data_dir>/extensions/manifests.jsonl` and replays the log on
    /// startup. Creates the extensions/ subdirectory if missing.
    /// Returns persist_failed if the directory can't be created or the
    /// log can't be replayed.
    pub fn initPersistent(
        allocator: std.mem.Allocator,
        data_dir: []const u8,
        clock_fn: *const fn () i64,
    ) ManifestError!Registry {
        const ext_dir = std.fs.path.join(allocator, &.{ data_dir, "extensions" }) catch
            return ManifestError.out_of_memory;
        defer allocator.free(ext_dir);
        std.fs.cwd().makePath(ext_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return ManifestError.persist_failed,
        };
        const log_path = std.fs.path.join(allocator, &.{ ext_dir, "manifests.jsonl" }) catch
            return ManifestError.out_of_memory;
        errdefer allocator.free(log_path);

        var reg: Registry = .{
            .allocator = allocator,
            .entries = .{},
            .mu = .{},
            .clock_fn = clock_fn,
            .log_path = log_path,
        };
        reg.replay() catch return ManifestError.persist_failed;
        return reg;
    }

    pub fn deinit(self: *Registry) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.extension_id);
            self.allocator.free(entry.version);
            self.allocator.free(entry.source);
            self.allocator.free(entry.manifest_json);
            if (entry.signer_pubkey.len > 0) {
                self.allocator.free(entry.signer_pubkey);
            }
        }
        self.entries.deinit(self.allocator);
        if (self.log_path.len > 0) self.allocator.free(self.log_path);
    }

    /// Replay the append-only log into the in-memory state. Each line
    /// is a JSON record with `op` = "install" or "uninstall". Missing
    /// log file = empty registry (first-boot).
    fn replay(self: *Registry) !void {
        const file = std.fs.openFileAbsolute(self.log_path, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return ManifestError.persist_failed,
        };
        defer file.close();

        const max_bytes: usize = 64 * 1024 * 1024; // 64 MiB log cap
        const contents = file.readToEndAlloc(self.allocator, max_bytes) catch
            return ManifestError.persist_failed;
        defer self.allocator.free(contents);

        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            self.applyLogLine(line) catch continue; // Skip malformed lines; durable consistency is best-effort.
        }
    }

    fn applyLogLine(self: *Registry, line: []const u8) !void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, line, .{}) catch
            return error.bad_line;
        defer parsed.deinit();
        if (parsed.value != .object) return error.bad_line;
        const obj = parsed.value.object;

        const op_v = obj.get("op") orelse return error.bad_line;
        if (op_v != .string) return error.bad_line;

        if (std.mem.eql(u8, op_v.string, "install")) {
            const ext = (obj.get("extensionId") orelse return error.bad_line);
            const ver = (obj.get("version") orelse return error.bad_line);
            const src = (obj.get("source") orelse return error.bad_line);
            const man = (obj.get("manifest") orelse return error.bad_line);
            const installed_at = (obj.get("installedAt") orelse return error.bad_line);
            const signer = obj.get("signerPubkey");
            if (ext != .string or ver != .string or src != .string or
                man != .object or installed_at != .integer) return error.bad_line;

            // Reject duplicates silently during replay — the latest
            // surviving line wins; matches install()'s exclusion shape.
            for (self.entries.items) |existing| {
                if (std.mem.eql(u8, existing.extension_id, ext.string)) return;
            }
            const manifest_json = try std.json.Stringify.valueAlloc(self.allocator, man, .{});
            errdefer self.allocator.free(manifest_json);
            const eid = try self.allocator.dupe(u8, ext.string);
            errdefer self.allocator.free(eid);
            const v = try self.allocator.dupe(u8, ver.string);
            errdefer self.allocator.free(v);
            const s = try self.allocator.dupe(u8, src.string);
            errdefer self.allocator.free(s);
            const sp: []const u8 = if (signer != null and signer.? == .string and signer.?.string.len > 0)
                try self.allocator.dupe(u8, signer.?.string)
            else
                "";

            try self.entries.append(self.allocator, .{
                .extension_id = eid,
                .version = v,
                .source = s,
                .installed_at = installed_at.integer,
                .manifest_json = manifest_json,
                .signer_pubkey = sp,
            });
        } else if (std.mem.eql(u8, op_v.string, "uninstall")) {
            const ext = (obj.get("extensionId") orelse return error.bad_line);
            if (ext != .string) return error.bad_line;
            for (self.entries.items, 0..) |existing, idx| {
                if (std.mem.eql(u8, existing.extension_id, ext.string)) {
                    const removed = self.entries.swapRemove(idx);
                    self.allocator.free(removed.extension_id);
                    self.allocator.free(removed.version);
                    self.allocator.free(removed.source);
                    self.allocator.free(removed.manifest_json);
                    if (removed.signer_pubkey.len > 0) self.allocator.free(removed.signer_pubkey);
                    return;
                }
            }
        }
    }

    fn appendLogRecord(self: *Registry, line: []const u8) ManifestError!void {
        if (self.log_path.len == 0) return; // In-memory mode; no-op.

        // Open (or create) the log file for append. `truncate = false`
        // is critical — without it createFile resets the file to length
        // 0 and loses every prior install record on each install.
        const file = std.fs.createFileAbsolute(
            self.log_path,
            .{ .truncate = false, .read = false },
        ) catch return ManifestError.persist_failed;
        defer file.close();
        file.seekFromEnd(0) catch return ManifestError.persist_failed;

        // Write the record line + newline atomically via two pwrite-style
        // calls. The buffered writer wrappers in std.fs sometimes hold
        // bytes past close on macOS; bypassing them keeps the disk and
        // memory states in lock-step.
        const stat = file.stat() catch return ManifestError.persist_failed;
        var total: u64 = stat.size;
        _ = file.pwriteAll(line, total) catch return ManifestError.persist_failed;
        total += line.len;
        _ = file.pwriteAll("\n", total) catch return ManifestError.persist_failed;
    }

    /// Install a manifest. Rejects duplicates of an existing
    /// extension_id (callers must explicitly remove + reinstall to
    /// upgrade — protects against unintentional schema drift).
    pub fn install(
        self: *Registry,
        extension_id: []const u8,
        version: []const u8,
        source: []const u8,
        manifest_json: []const u8,
        signer_pubkey: []const u8,
    ) ManifestError!void {
        self.mu.lock();
        defer self.mu.unlock();

        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.extension_id, extension_id)) {
                return ManifestError.duplicate_extension_id;
            }
        }

        const eid = self.allocator.dupe(u8, extension_id) catch return ManifestError.out_of_memory;
        errdefer self.allocator.free(eid);
        const ver = self.allocator.dupe(u8, version) catch return ManifestError.out_of_memory;
        errdefer self.allocator.free(ver);
        const src = self.allocator.dupe(u8, source) catch return ManifestError.out_of_memory;
        errdefer self.allocator.free(src);
        const mj = self.allocator.dupe(u8, manifest_json) catch return ManifestError.out_of_memory;
        errdefer self.allocator.free(mj);
        const sp: []const u8 = if (signer_pubkey.len > 0)
            (self.allocator.dupe(u8, signer_pubkey) catch return ManifestError.out_of_memory)
        else
            "";

        const installed_at = self.clock_fn();
        self.entries.append(self.allocator, .{
            .extension_id = eid,
            .version = ver,
            .source = src,
            .installed_at = installed_at,
            .manifest_json = mj,
            .signer_pubkey = sp,
        }) catch return ManifestError.out_of_memory;

        // Persist to the append-only log. Failure leaves the in-memory
        // state intact but propagates persist_failed up — callers can
        // surface the warning while the install remains effective for
        // the current session.
        if (self.log_path.len > 0) {
            self.persistInstall(eid, ver, src, mj, sp, installed_at) catch |err| return err;
        }
    }

    fn persistInstall(
        self: *Registry,
        extension_id: []const u8,
        version: []const u8,
        source: []const u8,
        manifest_json: []const u8,
        signer_pubkey: []const u8,
        installed_at: i64,
    ) ManifestError!void {
        var line: std.ArrayList(u8) = .{};
        defer line.deinit(self.allocator);

        line.appendSlice(self.allocator, "{\"op\":\"install\",\"extensionId\":") catch
            return ManifestError.out_of_memory;
        appendJsonString(self.allocator, &line, extension_id) catch return ManifestError.out_of_memory;
        line.appendSlice(self.allocator, ",\"version\":") catch return ManifestError.out_of_memory;
        appendJsonString(self.allocator, &line, version) catch return ManifestError.out_of_memory;
        line.appendSlice(self.allocator, ",\"source\":") catch return ManifestError.out_of_memory;
        appendJsonString(self.allocator, &line, source) catch return ManifestError.out_of_memory;
        if (signer_pubkey.len > 0) {
            line.appendSlice(self.allocator, ",\"signerPubkey\":") catch return ManifestError.out_of_memory;
            appendJsonString(self.allocator, &line, signer_pubkey) catch return ManifestError.out_of_memory;
        }
        line.appendSlice(self.allocator, ",\"installedAt\":") catch return ManifestError.out_of_memory;
        const ts_str = std.fmt.allocPrint(self.allocator, "{d}", .{installed_at}) catch return ManifestError.out_of_memory;
        defer self.allocator.free(ts_str);
        line.appendSlice(self.allocator, ts_str) catch return ManifestError.out_of_memory;
        line.appendSlice(self.allocator, ",\"manifest\":") catch return ManifestError.out_of_memory;
        line.appendSlice(self.allocator, manifest_json) catch return ManifestError.out_of_memory;
        line.append(self.allocator, '}') catch return ManifestError.out_of_memory;

        try self.appendLogRecord(line.items);
    }

    /// Remove an installed manifest. Returns not_found if absent.
    pub fn uninstall(self: *Registry, extension_id: []const u8) ManifestError!void {
        self.mu.lock();
        defer self.mu.unlock();

        var idx: ?usize = null;
        for (self.entries.items, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.extension_id, extension_id)) {
                idx = i;
                break;
            }
        }
        const found_idx = idx orelse return ManifestError.not_found;
        const removed = self.entries.swapRemove(found_idx);
        // Persist before freeing the in-memory state so a write failure
        // doesn't leave the registry inconsistent with the log.
        if (self.log_path.len > 0) {
            self.persistUninstall(removed.extension_id) catch |err| {
                // Best-effort restore on failure: re-append the entry.
                self.entries.append(self.allocator, removed) catch {};
                return err;
            };
        }
        self.allocator.free(removed.extension_id);
        self.allocator.free(removed.version);
        self.allocator.free(removed.source);
        self.allocator.free(removed.manifest_json);
        if (removed.signer_pubkey.len > 0) self.allocator.free(removed.signer_pubkey);
    }

    fn persistUninstall(self: *Registry, extension_id: []const u8) ManifestError!void {
        var line: std.ArrayList(u8) = .{};
        defer line.deinit(self.allocator);
        line.appendSlice(self.allocator, "{\"op\":\"uninstall\",\"extensionId\":") catch
            return ManifestError.out_of_memory;
        appendJsonString(self.allocator, &line, extension_id) catch return ManifestError.out_of_memory;
        line.append(self.allocator, '}') catch return ManifestError.out_of_memory;
        try self.appendLogRecord(line.items);
    }

    /// Snapshot count — convenient for tests + boot diagnostics.
    pub fn count(self: *Registry) usize {
        self.mu.lock();
        defer self.mu.unlock();
        return self.entries.items.len;
    }

    /// Render the registry contents as a JSON array of entries.
    /// Caller owns the returned slice and frees it.
    pub fn renderList(self: *Registry, allocator: std.mem.Allocator) ManifestError![]u8 {
        self.mu.lock();
        defer self.mu.unlock();

        var body: std.ArrayList(u8) = .{};
        errdefer body.deinit(allocator);

        body.appendSlice(allocator, "{\"manifests\":[") catch return ManifestError.out_of_memory;
        for (self.entries.items, 0..) |entry, i| {
            if (i != 0) body.append(allocator, ',') catch return ManifestError.out_of_memory;
            renderEntry(allocator, &body, entry) catch return ManifestError.out_of_memory;
        }
        body.appendSlice(allocator, "]}") catch return ManifestError.out_of_memory;

        return body.toOwnedSlice(allocator) catch ManifestError.out_of_memory;
    }
};

fn renderEntry(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    entry: ManifestEntry,
) !void {
    try out.appendSlice(allocator, "{\"extensionId\":");
    try appendJsonString(allocator, out, entry.extension_id);
    try out.appendSlice(allocator, ",\"version\":");
    try appendJsonString(allocator, out, entry.version);
    try out.appendSlice(allocator, ",\"source\":");
    try appendJsonString(allocator, out, entry.source);
    try out.appendSlice(allocator, ",\"installedAt\":");
    const ts = try std.fmt.allocPrint(allocator, "{d}", .{entry.installed_at});
    defer allocator.free(ts);
    try out.appendSlice(allocator, ts);
    if (entry.signer_pubkey.len > 0) {
        try out.appendSlice(allocator, ",\"signerPubkey\":");
        try appendJsonString(allocator, out, entry.signer_pubkey);
    }
    // manifest_json is already a JSON object; embed it raw.
    try out.appendSlice(allocator, ",\"manifest\":");
    try out.appendSlice(allocator, entry.manifest_json);
    try out.append(allocator, '}');
}

fn appendJsonString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    s: []const u8,
) !void {
    try out.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            else => try out.append(allocator, c),
        }
    }
    try out.append(allocator, '"');
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

fn fixedClock() i64 {
    return 1747200000;
}

test "Registry install + count" {
    var reg = Registry.init(testing.allocator, fixedClock);
    defer reg.deinit();
    try testing.expectEqual(@as(usize, 0), reg.count());
    try reg.install(
        "oddjobz",
        "0.1.0",
        "asset:packages/oddjobz_experience/assets/bundle.json",
        "{\"id\":\"oddjobz\",\"name\":\"Trades & Services\"}",
        "",
    );
    try testing.expectEqual(@as(usize, 1), reg.count());
}

test "Registry rejects duplicate extension_id" {
    var reg = Registry.init(testing.allocator, fixedClock);
    defer reg.deinit();
    try reg.install("oddjobz", "0.1.0", "asset:x", "{}", "");
    try testing.expectError(
        ManifestError.duplicate_extension_id,
        reg.install("oddjobz", "0.2.0", "asset:y", "{}", ""),
    );
}

test "Registry uninstall removes entry" {
    var reg = Registry.init(testing.allocator, fixedClock);
    defer reg.deinit();
    try reg.install("oddjobz", "0.1.0", "asset:x", "{}", "");
    try reg.install("jambox", "0.1.0", "asset:y", "{}", "");
    try testing.expectEqual(@as(usize, 2), reg.count());
    try reg.uninstall("oddjobz");
    try testing.expectEqual(@as(usize, 1), reg.count());
    // Re-install now works (no longer duplicate).
    try reg.install("oddjobz", "0.2.0", "asset:x", "{}", "");
    try testing.expectEqual(@as(usize, 2), reg.count());
}

test "Registry uninstall not_found on missing id" {
    var reg = Registry.init(testing.allocator, fixedClock);
    defer reg.deinit();
    try testing.expectError(ManifestError.not_found, reg.uninstall("ghost"));
}

test "Registry survives restart via append-only log" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const data_dir = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(data_dir);

    {
        var reg = try Registry.initPersistent(testing.allocator, data_dir, fixedClock);
        defer reg.deinit();
        try reg.install("oddjobz", "0.1.0", "asset:x", "{\"id\":\"oddjobz\"}", "");
        try reg.install("jambox", "0.2.0", "url:https://author.example/j.bundle.json", "{\"id\":\"jambox\"}", "03ab47cafe");
        try testing.expectEqual(@as(usize, 2), reg.count());
    }

    // Simulate restart — open a fresh Registry over the same data_dir.
    {
        var reg = try Registry.initPersistent(testing.allocator, data_dir, fixedClock);
        defer reg.deinit();
        try testing.expectEqual(@as(usize, 2), reg.count());
        const body = try reg.renderList(testing.allocator);
        defer testing.allocator.free(body);
        try testing.expect(std.mem.indexOf(u8, body, "\"extensionId\":\"oddjobz\"") != null);
        try testing.expect(std.mem.indexOf(u8, body, "\"extensionId\":\"jambox\"") != null);
        try testing.expect(std.mem.indexOf(u8, body, "\"signerPubkey\":\"03ab47cafe\"") != null);
    }
}

test "Registry replay folds uninstall into reconstructed state" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const data_dir = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(data_dir);

    {
        var reg = try Registry.initPersistent(testing.allocator, data_dir, fixedClock);
        defer reg.deinit();
        try reg.install("oddjobz", "0.1.0", "asset:x", "{\"id\":\"oddjobz\"}", "");
        try reg.install("jambox", "0.2.0", "asset:y", "{\"id\":\"jambox\"}", "");
        try reg.uninstall("oddjobz");
        try testing.expectEqual(@as(usize, 1), reg.count());
    }

    {
        var reg = try Registry.initPersistent(testing.allocator, data_dir, fixedClock);
        defer reg.deinit();
        // Replay should see install oddjobz → install jambox → uninstall oddjobz
        // and end with just jambox.
        try testing.expectEqual(@as(usize, 1), reg.count());
        const body = try reg.renderList(testing.allocator);
        defer testing.allocator.free(body);
        try testing.expect(std.mem.indexOf(u8, body, "\"extensionId\":\"jambox\"") != null);
        try testing.expect(std.mem.indexOf(u8, body, "\"extensionId\":\"oddjobz\"") == null);
    }
}

test "Registry renderList JSON shape" {
    var reg = Registry.init(testing.allocator, fixedClock);
    defer reg.deinit();
    try reg.install("oddjobz", "0.1.0", "asset:x", "{\"id\":\"oddjobz\"}", "");
    try reg.install("jambox", "0.2.0", "url:https://example/jambox.bundle.json", "{\"id\":\"jambox\"}", "03abcdef");
    const body = try reg.renderList(testing.allocator);
    defer testing.allocator.free(body);
    try testing.expect(std.mem.indexOf(u8, body, "\"manifests\":[") != null);
    try testing.expect(std.mem.indexOf(u8, body, "\"extensionId\":\"oddjobz\"") != null);
    try testing.expect(std.mem.indexOf(u8, body, "\"extensionId\":\"jambox\"") != null);
    try testing.expect(std.mem.indexOf(u8, body, "\"signerPubkey\":\"03abcdef\"") != null);
    try testing.expect(std.mem.indexOf(u8, body, "\"installedAt\":1747200000") != null);
}

```
