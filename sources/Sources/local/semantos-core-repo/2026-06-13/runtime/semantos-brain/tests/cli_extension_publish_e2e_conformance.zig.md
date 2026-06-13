---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/cli_extension_publish_e2e_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.179363+00:00
---

# runtime/semantos-brain/tests/cli_extension_publish_e2e_conformance.zig

```zig
// Phase D-W2 Phase 1 — CLI conformance for `brain extension publish`.
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.1
//   (publish flow), §7 Phase 1.
//
// This file drives the cli.cmdExtension argv parser + cmdExtensionPublish
// dry-run path end-to-end:
//
//   • argv shape (missing namespace/version/utxo, unknown flag, bad
//     subcommand, --version validation)
//   • bundle hash computed against a tmpdir fixture file
//   • --dry-run path: skips ARC + shard-proxy, prints the dry-run
//     banner + final "Published <ns>@<v> — DRY-RUN" line
//   • exit-code mapping (bad_args → 2, missing signer file → file_io)
//
// The full bsvz-tx-build round-trip is asserted in
// extension_publish_conformance.zig; this file's goal is the CLI shim's
// argv handling + dry-run gating + bundle-hash log line.

const std = @import("std");
const cli = @import("cli");

fn newOutput(buf: *std.ArrayList(u8)) cli.Output {
    return .{ .buffer = buf, .allocator = std.testing.allocator };
}

test "D-W2 P1 brain extension: no subcommand → bad_args + usage" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);
    const args: []const [:0]u8 = &.{};
    const code = try cli.cmdExtension(a, &out, args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage: brain extension") != null);
}

test "D-W2 P1 brain extension: unknown subcommand → bad_args" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);
    const args = [_][:0]u8{
        @constCast(@as([:0]const u8, "release")),
    };
    const code = try cli.cmdExtension(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "unknown subcommand") != null);
}

test "D-W2 P1 brain extension publish: no bundle path → bad_args + usage" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);
    const args = [_][:0]u8{
        @constCast(@as([:0]const u8, "publish")),
    };
    const code = try cli.cmdExtension(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage: brain extension") != null);
}

test "D-W2 P1 brain extension publish: missing --namespace → bad_args" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    // Make a tmp bundle file we can hash.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile("bundle.bin", .{});
    try f.writeAll("x");
    f.close();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("bundle.bin", &path_buf);
    const path_z = try a.dupeZ(u8, path);
    defer a.free(path_z);

    const args = [_][:0]u8{
        @constCast(@as([:0]const u8, "publish")),
        path_z,
        @constCast(@as([:0]const u8, "--version")),
        @constCast(@as([:0]const u8, "0.1.0")),
        @constCast(@as([:0]const u8, "--dry-run")),
    };
    const code = try cli.cmdExtension(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "--namespace is required") != null);
}

test "D-W2 P1 brain extension publish: invalid --version → bad_args" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile("bundle.bin", .{});
    try f.writeAll("x");
    f.close();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("bundle.bin", &path_buf);
    const path_z = try a.dupeZ(u8, path);
    defer a.free(path_z);

    const args = [_][:0]u8{
        @constCast(@as([:0]const u8, "publish")),
        path_z,
        @constCast(@as([:0]const u8, "--namespace")),
        @constCast(@as([:0]const u8, "oddjobz")),
        @constCast(@as([:0]const u8, "--version")),
        @constCast(@as([:0]const u8, "bad version with spaces")),
        @constCast(@as([:0]const u8, "--dry-run")),
    };
    const code = try cli.cmdExtension(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "not a valid semver-shaped version") != null);
}

test "D-W2 P1 brain extension publish: missing --utxo without --dry-run → bad_args" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile("bundle.bin", .{});
    try f.writeAll("x");
    f.close();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("bundle.bin", &path_buf);
    const path_z = try a.dupeZ(u8, path);
    defer a.free(path_z);

    const args = [_][:0]u8{
        @constCast(@as([:0]const u8, "publish")),
        path_z,
        @constCast(@as([:0]const u8, "--namespace")),
        @constCast(@as([:0]const u8, "oddjobz")),
        @constCast(@as([:0]const u8, "--version")),
        @constCast(@as([:0]const u8, "0.1.0")),
    };
    const code = try cli.cmdExtension(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "--utxo") != null);
}

test "D-W2 P1 brain extension publish: missing signer priv → file_io" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile("bundle.bin", .{});
    try f.writeAll("payload");
    f.close();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("bundle.bin", &path_buf);
    const path_z = try a.dupeZ(u8, path);
    defer a.free(path_z);

    // Point at a signer path that doesn't exist.
    const missing_path = try std.fs.path.joinZ(a, &.{ path, "nonexistent-priv.hex" });
    defer a.free(missing_path);

    const args = [_][:0]u8{
        @constCast(@as([:0]const u8, "publish")),
        path_z,
        @constCast(@as([:0]const u8, "--namespace")),
        @constCast(@as([:0]const u8, "oddjobz")),
        @constCast(@as([:0]const u8, "--version")),
        @constCast(@as([:0]const u8, "0.1.0")),
        @constCast(@as([:0]const u8, "--utxo")),
        // 64 hex chars + :0:5000.
        @constCast(@as([:0]const u8, "abababababababababababababababababababababababababababababababab:0:5000")),
        @constCast(@as([:0]const u8, "--signer")),
        missing_path,
    };
    const code = try cli.cmdExtension(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.file_io, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[publish] bundle_hash:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "failed to read signer priv") != null);
}

test "D-W2 P1 brain extension publish: --dry-run hits the dry-run path + emits banner" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    // Tmpdir for both bundle + signer priv hex.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const fb = try tmp.dir.createFile("fake-bundle.tar.gz", .{});
    try fb.writeAll("not-actually-a-tarball");
    fb.close();
    var bundle_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const bundle_path = try tmp.dir.realpath("fake-bundle.tar.gz", &bundle_path_buf);
    const bundle_z = try a.dupeZ(u8, bundle_path);
    defer a.free(bundle_z);

    // 32 bytes of priv hex (deterministic).
    const fp = try tmp.dir.createFile("test-priv.hex", .{});
    try fp.writeAll("aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899");
    fp.close();
    var priv_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const priv_path = try tmp.dir.realpath("test-priv.hex", &priv_path_buf);
    const priv_z = try a.dupeZ(u8, priv_path);
    defer a.free(priv_z);

    const args = [_][:0]u8{
        @constCast(@as([:0]const u8, "publish")),
        bundle_z,
        @constCast(@as([:0]const u8, "--namespace")),
        @constCast(@as([:0]const u8, "oddjobz")),
        @constCast(@as([:0]const u8, "--version")),
        @constCast(@as([:0]const u8, "0.1.0")),
        @constCast(@as([:0]const u8, "--signer")),
        priv_z,
        @constCast(@as([:0]const u8, "--dry-run")),
    };
    const code = try cli.cmdExtension(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.ok, code);
    // Byte-stable expected substrings for the dry-run path.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[publish] bundle_hash:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[publish] --dry-run: skipping tx construction") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[publish] --dry-run: would invoke `bun cartridges/oddjobz/brain/tools/publish-bundle.ts`") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Published oddjobz@0.1.0 — DRY-RUN") != null);
}

```
