---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/config_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.207070+00:00
---

# runtime/semantos-brain/tests/config_conformance.zig

```zig
// Phase Brain 1 — Config loader conformance tests.

const std = @import("std");
const config = @import("config");

test "Brain 1 config: round-trip default template parses cleanly" {
    const tmpl = try config.defaultJsonTemplate(std.testing.allocator);
    defer std.testing.allocator.free(tmpl);

    var cfg = try config.parseJson(std.testing.allocator, tmpl);
    defer cfg.deinit();

    const home = try std.process.getEnvVarOwned(std.testing.allocator, "HOME");
    defer std.testing.allocator.free(home);
    const expected_data_dir = try std.fs.path.join(std.testing.allocator, &.{ home, ".semantos/data" });
    defer std.testing.allocator.free(expected_data_dir);
    const expected_modules_dir = try std.fs.path.join(std.testing.allocator, &.{ home, ".semantos/wasm" });
    defer std.testing.allocator.free(expected_modules_dir);

    try std.testing.expectEqualStrings(expected_data_dir, cfg.shell.data_dir);
    try std.testing.expectEqualStrings(expected_modules_dir, cfg.shell.modules_dir);
    try std.testing.expectEqual(@as(usize, 0), cfg.modules.len);
}

test "Brain 1 config: default template has no phantom modules" {
    const tmpl = try config.defaultJsonTemplate(std.testing.allocator);
    defer std.testing.allocator.free(tmpl);
    var cfg = try config.parseJson(std.testing.allocator, tmpl);
    defer cfg.deinit();

    try std.testing.expectEqual(@as(usize, 0), cfg.modules.len);
    try std.testing.expect(cfg.moduleByName("wallet-engine") == null);
    try std.testing.expect(cfg.moduleByName("headers-verifier") == null);
    try std.testing.expect(cfg.moduleByName("missing") == null);
}

test "Brain 1 config: parses non-zero hex hashes" {
    const json =
        \\{
        \\  "shell": { "data_dir": "/d", "modules_dir": "/m" },
        \\  "modules": {
        \\    "x": {
        \\      "path": "x.wasm",
        \\      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        \\      "max_memory_bytes": 1048576
        \\    }
        \\  }
        \\}
    ;
    var cfg = try config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    const m = cfg.moduleByName("x") orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u8, 0x01), m.sha256[0]);
    try std.testing.expectEqual(@as(u8, 0xef), m.sha256[31]);
    try std.testing.expectEqual(@as(u64, 1_048_576), m.max_memory_bytes);
}

test "Brain 1 config: rejects malformed hex" {
    const json =
        \\{
        \\  "shell": { "data_dir": "/d", "modules_dir": "/m" },
        \\  "modules": {
        \\    "x": { "path": "x.wasm", "sha256": "deadbeef", "max_memory_bytes": 1 }
        \\  }
        \\}
    ;
    try std.testing.expectError(
        error.bad_hex,
        config.parseJson(std.testing.allocator, json),
    );
}

test "Brain 1 config: rejects missing top-level keys" {
    const json = "{ \"shell\": { \"data_dir\": \"/d\", \"modules_dir\": \"/m\" } }";
    try std.testing.expectError(
        error.schema_mismatch,
        config.parseJson(std.testing.allocator, json),
    );
}

test "Brain 1 config: rejects malformed JSON" {
    const json = "{ this is not json";
    try std.testing.expectError(
        error.parse_failed,
        config.parseJson(std.testing.allocator, json),
    );
}

test "Brain 1 config: encodeHex round-trips with the parser" {
    const original: [32]u8 = .{
        0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
        0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10,
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
    };
    const hex = try config.encodeHex(std.testing.allocator, &original);
    defer std.testing.allocator.free(hex);
    try std.testing.expectEqual(@as(usize, 64), hex.len);

    // Build a config that uses this hex; assert the parser recovers the bytes.
    const json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{
        \\  "shell": {{ "data_dir": "/d", "modules_dir": "/m" }},
        \\  "modules": {{
        \\    "y": {{ "path": "y.wasm", "sha256": "{s}", "max_memory_bytes": 1 }}
        \\  }}
        \\}}
    ,
        .{hex},
    );
    defer std.testing.allocator.free(json);

    var cfg = try config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    const m = cfg.moduleByName("y") orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, &original, &m.sha256);
}

```
