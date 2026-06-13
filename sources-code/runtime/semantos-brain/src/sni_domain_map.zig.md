---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/sni_domain_map.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.239942+00:00
---

# runtime/semantos-brain/src/sni_domain_map.zig

```zig
// W7.15 — SNI hostname → op_pkh resolution map.
//
// Maintained in-process as an append-only HashMap backed by a JSON file
// (`$data_dir/sni_domain_map.json`).  The brain loads it at startup and
// uses it to resolve incoming `Host` header values to an op_pkh before the
// WSS handshake (W7.4) proceeds.
//
// File format (pretty-printed JSON object):
//   {
//     "brain.coastal.com.au": "a3f7b2c1d4e5f6a7",
//     "brain.plumbing.net":   "deadbeefcafefed0"
//   }
//
// Keys:   brain_domain FQDN (from the operators table).
// Values: op_pkh as 16-char lowercase hex string (8 bytes).
//
// Routing invariant:
//   Caddy routes `brain.<domain>` → brain WSS endpoint via per-operator
//   site block (W7.14).  The brain then calls `SniDomainMap.get(host)` to
//   bind the operator context for the lifetime of the connection.
//
// Thread safety: DomainMap is single-writer; calls from `cmdServe` are
// on the main thread.  Connection handlers should treat the returned slice
// as stable for the duration of the request (no concurrent writes during
// serving in v1).
//
// PRD: docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md W7.15

const std = @import("std");

pub const MapError = error{
    file_io,
    malformed_json,
    out_of_memory,
};

pub const DomainMap = struct {
    allocator: std.mem.Allocator,
    /// brain_domain → op_pkh16 (both owned by the map).
    entries: std.StringHashMap([16]u8),

    pub fn init(allocator: std.mem.Allocator) DomainMap {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap([16]u8).init(allocator),
        };
    }

    pub fn deinit(self: *DomainMap) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.deinit();
    }

    /// Look up a brain_domain; returns the op_pkh16 hex string or null.
    pub fn get(self: *const DomainMap, brain_domain: []const u8) ?[16]u8 {
        return self.entries.get(brain_domain);
    }

    /// Register or update a mapping.  Idempotent.
    pub fn set(self: *DomainMap, brain_domain: []const u8, op_pkh16: [16]u8) MapError!void {
        const result = self.entries.getOrPut(brain_domain) catch return error.out_of_memory;
        if (!result.found_existing) {
            result.key_ptr.* = self.allocator.dupe(u8, brain_domain) catch return error.out_of_memory;
        }
        result.value_ptr.* = op_pkh16;
    }

    /// Remove a mapping.  No-op if not present.
    pub fn remove(self: *DomainMap, brain_domain: []const u8) void {
        if (self.entries.fetchRemove(brain_domain)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    /// Load mappings from `$data_dir/sni_domain_map.json`.
    /// Returns `MapError.file_io` if the file cannot be opened (other than
    /// FileNotFound, which is treated as an empty map).
    /// Returns `MapError.malformed_json` if the file is not valid JSON in
    /// the expected format.
    pub fn loadFromFile(self: *DomainMap, data_dir: []const u8) MapError!void {
        const path = std.fs.path.join(self.allocator, &.{ data_dir, "sni_domain_map.json" }) catch
            return error.out_of_memory;
        defer self.allocator.free(path);

        const file = std.fs.cwd().openFile(path, .{}) catch |e| switch (e) {
            error.FileNotFound => return,
            else => return error.file_io,
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1 << 20) catch return error.file_io;
        defer self.allocator.free(content);

        try self.parseJson(content);
    }

    /// Write the current map to `$data_dir/sni_domain_map.json`.
    pub fn saveToFile(self: *const DomainMap, data_dir: []const u8) MapError!void {
        const path = std.fs.path.join(self.allocator, &.{ data_dir, "sni_domain_map.json" }) catch
            return error.out_of_memory;
        defer self.allocator.free(path);

        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);

        buf.appendSlice(self.allocator, "{\n") catch return error.out_of_memory;
        var it = self.entries.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) {
                buf.appendSlice(self.allocator, ",\n") catch return error.out_of_memory;
            }
            const line = std.fmt.allocPrint(
                self.allocator,
                "  \"{s}\": \"{s}\"",
                .{ entry.key_ptr.*, &entry.value_ptr.* },
            ) catch return error.out_of_memory;
            defer self.allocator.free(line);
            buf.appendSlice(self.allocator, line) catch return error.out_of_memory;
            first = false;
        }
        buf.appendSlice(self.allocator, "\n}\n") catch return error.out_of_memory;

        const file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch return error.file_io;
        defer file.close();
        file.writeAll(buf.items) catch return error.file_io;
    }

    // ── JSON parser (hand-rolled; no stdlib JSON dependency needed here) ──

    /// Parse a simple JSON object `{"key": "value", ...}` where all values
    /// are 16-char lowercase hex strings.
    fn parseJson(self: *DomainMap, json: []const u8) MapError!void {
        // Skip leading whitespace.
        var pos: usize = 0;
        pos = skipWs(json, pos);
        if (pos >= json.len or json[pos] != '{') return error.malformed_json;
        pos += 1;

        while (true) {
            pos = skipWs(json, pos);
            if (pos >= json.len) return error.malformed_json;
            if (json[pos] == '}') break;
            if (json[pos] == ',') { pos += 1; continue; }

            // Read key string.
            if (json[pos] != '"') return error.malformed_json;
            pos += 1;
            const key_start = pos;
            while (pos < json.len and json[pos] != '"') pos += 1;
            if (pos >= json.len) return error.malformed_json;
            const key = json[key_start..pos];
            pos += 1; // closing "

            pos = skipWs(json, pos);
            if (pos >= json.len or json[pos] != ':') return error.malformed_json;
            pos += 1;

            pos = skipWs(json, pos);
            if (pos >= json.len or json[pos] != '"') return error.malformed_json;
            pos += 1;
            const val_start = pos;
            while (pos < json.len and json[pos] != '"') pos += 1;
            if (pos >= json.len) return error.malformed_json;
            const val = json[val_start..pos];
            pos += 1; // closing "

            if (val.len != 16) return error.malformed_json;
            var pkh16: [16]u8 = undefined;
            @memcpy(&pkh16, val[0..16]);

            try self.set(key, pkh16);
        }
    }
};

fn skipWs(s: []const u8, start: usize) usize {
    var i = start;
    while (i < s.len and (s[i] == ' ' or s[i] == '\n' or s[i] == '\r' or s[i] == '\t')) i += 1;
    return i;
}

// ── Inline tests ──────────────────────────────────────────────────────────

test "DomainMap: get returns null for missing key" {
    var m = DomainMap.init(std.testing.allocator);
    defer m.deinit();
    try std.testing.expect(m.get("brain.coastal.com.au") == null);
}

test "DomainMap: set and get" {
    var m = DomainMap.init(std.testing.allocator);
    defer m.deinit();
    const pkh: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    try m.set("brain.coastal.com.au", pkh);
    const got = m.get("brain.coastal.com.au");
    try std.testing.expect(got != null);
    try std.testing.expectEqualStrings(&pkh, &got.?);
}

test "DomainMap: remove" {
    var m = DomainMap.init(std.testing.allocator);
    defer m.deinit();
    const pkh: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    try m.set("brain.coastal.com.au", pkh);
    m.remove("brain.coastal.com.au");
    try std.testing.expect(m.get("brain.coastal.com.au") == null);
}

test "DomainMap: remove non-existent is no-op" {
    var m = DomainMap.init(std.testing.allocator);
    defer m.deinit();
    m.remove("brain.nobody.com"); // must not crash
}

test "DomainMap: parseJson round-trips" {
    const json =
        \\{
        \\  "brain.coastal.com.au": "a3f7b2c1d4e5f6a7",
        \\  "brain.plumbing.net": "deadbeefcafefed0"
        \\}
    ;
    var m = DomainMap.init(std.testing.allocator);
    defer m.deinit();
    try m.parseJson(json);
    const a = m.get("brain.coastal.com.au");
    try std.testing.expect(a != null);
    try std.testing.expectEqualStrings("a3f7b2c1d4e5f6a7", &a.?);
    const b = m.get("brain.plumbing.net");
    try std.testing.expect(b != null);
    try std.testing.expectEqualStrings("deadbeefcafefed0", &b.?);
}

test "DomainMap: parseJson empty object" {
    var m = DomainMap.init(std.testing.allocator);
    defer m.deinit();
    try m.parseJson("{}");
    try std.testing.expect(m.get("anything") == null);
}

test "DomainMap: parseJson rejects malformed" {
    var m = DomainMap.init(std.testing.allocator);
    defer m.deinit();
    try std.testing.expectError(error.malformed_json, m.parseJson("not json"));
}

test "DomainMap: set is idempotent" {
    var m = DomainMap.init(std.testing.allocator);
    defer m.deinit();
    const pkh1: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    const pkh2: [16]u8 = "deadbeefcafefed0".*;
    try m.set("brain.coastal.com.au", pkh1);
    try m.set("brain.coastal.com.au", pkh2); // update
    const got = m.get("brain.coastal.com.au");
    try std.testing.expectEqualStrings("deadbeefcafefed0", &got.?);
}

```
