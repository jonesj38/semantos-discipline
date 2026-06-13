---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/module_loader_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.196122+00:00
---

# runtime/semantos-brain/tests/module_loader_conformance.zig

```zig
// Phase Brain 1 — Module loader conformance tests.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 1).
//
// Builds tiny synthetic WASM blobs (just magic + version, no sections —
// the loader's WASM-shape check is intentionally minimal at this layer)
// and exercises hash-pinning on each.

const std = @import("std");
const module_loader = @import("module_loader");

fn writeTempFile(name: []const u8, bytes: []const u8) ![]u8 {
    var tmp_dir = std.testing.tmpDir(.{});
    // We deliberately don't `defer tmp_dir.cleanup()` — the file path
    // we return points into the system tmp; the caller is expected to
    // clean up by removing the file. For correctness here, copy the
    // realpath out before returning.
    const sub_path = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{name});
    errdefer std.testing.allocator.free(sub_path);
    const f = try tmp_dir.dir.createFile(sub_path, .{});
    defer f.close();
    try f.writeAll(bytes);
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp_dir.dir.realpath(sub_path, &buf);
    std.testing.allocator.free(sub_path);
    return std.testing.allocator.dupe(u8, real);
}

const MINIMAL_WASM = module_loader.WASM_MAGIC ++ [_]u8{};

test "Brain 1 module loader: isValidWasmShape recognises the magic prefix" {
    try std.testing.expect(module_loader.isValidWasmShape(&MINIMAL_WASM));
    const not_wasm = [_]u8{ 0x7f, 0x45, 0x4c, 0x46 }; // ELF
    try std.testing.expect(!module_loader.isValidWasmShape(&not_wasm));
    try std.testing.expect(!module_loader.isValidWasmShape(&[_]u8{}));
}

test "Brain 1 module loader: computeSha256 matches std.crypto" {
    const data = "hello BRAIN";
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &expected, .{});
    const actual = module_loader.computeSha256(data);
    try std.testing.expectEqualSlices(u8, &expected, &actual);
}

test "Brain 1 module loader: verifyBytes accepts matching hash" {
    const expected = module_loader.computeSha256(&MINIMAL_WASM);
    try module_loader.verifyBytes(&MINIMAL_WASM, &expected);
}

test "Brain 1 module loader: verifyBytes rejects mismatched hash" {
    const wrong_hash: [32]u8 = .{0xff} ** 32;
    try std.testing.expectError(
        error.hash_mismatch,
        module_loader.verifyBytes(&MINIMAL_WASM, &wrong_hash),
    );
}

test "Brain 1 module loader: verifyBytes rejects non-WASM input" {
    const elf = [_]u8{ 0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01, 0x01, 0x00 };
    const wrong_hash: [32]u8 = .{0xff} ** 32;
    try std.testing.expectError(
        error.not_wasm,
        module_loader.verifyBytes(&elf, &wrong_hash),
    );
}

test "Brain 1 module loader: loadAndVerify reads file + matches hash" {
    const path = try writeTempFile("loader_ok.wasm", &MINIMAL_WASM);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    const expected = module_loader.computeSha256(&MINIMAL_WASM);

    var lm = try module_loader.loadAndVerify(
        std.testing.allocator,
        "test-mod",
        path,
        &expected,
    );
    defer lm.deinit();

    try std.testing.expectEqualStrings("test-mod", lm.name);
    try std.testing.expectEqualSlices(u8, &MINIMAL_WASM, lm.bytes);
    try std.testing.expectEqualSlices(u8, &expected, &lm.sha256);
}

test "Brain 1 module loader: loadAndVerify rejects on hash mismatch" {
    const path = try writeTempFile("loader_bad.wasm", &MINIMAL_WASM);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    const wrong_hash: [32]u8 = .{0xff} ** 32;
    try std.testing.expectError(
        error.hash_mismatch,
        module_loader.loadAndVerify(std.testing.allocator, "x", path, &wrong_hash),
    );
}

test "Brain 1 module loader: loadAndVerify rejects non-WASM file" {
    const path = try writeTempFile("loader_notwasm", "this is not a wasm file");
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    const dummy_hash: [32]u8 = .{0} ** 32;
    try std.testing.expectError(
        error.not_wasm,
        module_loader.loadAndVerify(std.testing.allocator, "x", path, &dummy_hash),
    );
}

test "Brain 1 module loader: formatHashHex round-trips" {
    const h: [32]u8 = .{
        0xc0, 0x91, 0xc3, 0xad, 0xb2, 0xcd, 0x46, 0x01,
        0x59, 0x85, 0x5a, 0x43, 0xdc, 0x5b, 0x5d, 0xc8,
        0x78, 0x10, 0x7e, 0xfb, 0x0a, 0x25, 0xb4, 0xaa,
        0xe3, 0xc6, 0x1f, 0x9b, 0x60, 0x3f, 0x71, 0x3d,
    };
    const hex = try module_loader.formatHashHex(std.testing.allocator, &h);
    defer std.testing.allocator.free(hex);
    try std.testing.expectEqualStrings(
        "c091c3adb2cd460159855a43dc5b5dc878107efb0a25b4aae3c61f9b603f713d",
        hex,
    );
}

```
