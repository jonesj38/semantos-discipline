---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/image_extract_shell.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.246798+00:00
---

# runtime/semantos-brain/src/image_extract_shell.zig

```zig
// Betterment OCR — image-extract shell impl.
//
// Spawns `bun cartridges/betterment/brain/tools/image-extract.ts` per request,
// handing it the image page(s) + optional metadata via temp files (matching the
// CLI's documented argv contract), and reads the ExtractResult JSON from stdout.
//
// Mirror of voice_extract_shell.zig.  Differences: writes N image files (one per
// page, extension derived from the part's media type) and passes them as a
// single comma-separated `--images` arg; metadata is optional.
//
// ShellError mapping (identical to voice):
//   spawn fails (bun/script missing) → bun_unavailable
//   wait fails / non-zero exit       → pipeline_failed (incl. missing ANTHROPIC_API_KEY)
//   exit 0                            → return stdout
//
// The subprocess inherits the brain's environment, so ANTHROPIC_API_KEY must be
// present in the brain process for the vision call to succeed.
//
// V1 limitations match voice_extract_shell: no timeout, stderr discarded.

const std = @import("std");
const image_extract_http = @import("image_extract_http");

pub const Config = struct {
    /// Path to the `bun` executable.  Defaults to "bun" (PATH lookup).
    bun_path: []const u8 = "bun",
    /// Absolute path to cartridges/betterment/brain/tools/image-extract.ts.
    script_path: []const u8,
    /// Working directory (workspace root, so @semantos/* imports resolve).
    cwd: []const u8,
    /// Cap on stdout bytes.  ExtractResult JSON for a multi-page release is
    /// typically <64 KiB; 4 MiB is comfortable headroom.
    max_stdout_bytes: usize = 4 * 1024 * 1024,
    /// Directory for the per-request temp files.  Created if missing.
    tmp_dir: []const u8 = "/tmp/brain-image-extract",
};

pub const Shell = struct {
    config: Config,

    pub fn asInterface(self: *const Shell) image_extract_http.ImageExtractShell {
        return .{
            .ctx = @ptrCast(@constCast(self)),
            .runFn = runImpl,
        };
    }
};

fn extForMediaType(media_type: []const u8) []const u8 {
    if (std.mem.eql(u8, media_type, "image/png")) return "png";
    if (std.mem.eql(u8, media_type, "image/webp")) return "webp";
    if (std.mem.eql(u8, media_type, "image/gif")) return "gif";
    return "jpg";
}

fn runImpl(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    images: []const image_extract_http.ImageInput,
    metadata_json: ?[]const u8,
    api_key: ?[]const u8,
    model: ?[]const u8,
) image_extract_http.ShellError![]u8 {
    const self: *const Shell = @ptrCast(@alignCast(ctx));
    const E = image_extract_http.ShellError;

    if (images.len == 0) return E.pipeline_failed;

    var random_bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    var suffix_hex: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&suffix_hex, "{x:0>16}", .{std.mem.readInt(u64, &random_bytes, .little)}) catch {
        return E.out_of_memory;
    };

    std.fs.cwd().makePath(self.config.tmp_dir) catch return E.bun_unavailable;

    // Track temp files so we can defer-delete them all (even on error).
    var img_paths: std.ArrayList([]u8) = .{};
    defer {
        for (img_paths.items) |p| {
            std.fs.cwd().deleteFile(p) catch {};
            allocator.free(p);
        }
        img_paths.deinit(allocator);
    }

    for (images, 0..) |img, i| {
        const ext = extForMediaType(img.media_type);
        const path = std.fmt.allocPrint(allocator, "{s}/img-{s}-{d}.{s}", .{ self.config.tmp_dir, &suffix_hex, i, ext }) catch
            return E.out_of_memory;
        img_paths.append(allocator, path) catch {
            allocator.free(path);
            return E.out_of_memory;
        };
        writeAll(path, img.bytes) catch return E.bun_unavailable;
    }

    // Join image paths with ',' for the --images arg.
    var images_arg: std.ArrayList(u8) = .{};
    defer images_arg.deinit(allocator);
    for (img_paths.items, 0..) |p, i| {
        if (i > 0) images_arg.append(allocator, ',') catch return E.out_of_memory;
        images_arg.appendSlice(allocator, p) catch return E.out_of_memory;
    }

    var meta_path_opt: ?[]u8 = null;
    if (metadata_json) |meta| {
        const mp = std.fmt.allocPrint(allocator, "{s}/meta-{s}.json", .{ self.config.tmp_dir, &suffix_hex }) catch
            return E.out_of_memory;
        meta_path_opt = mp;
        writeAll(mp, meta) catch return E.bun_unavailable;
    }
    defer if (meta_path_opt) |p| {
        std.fs.cwd().deleteFile(p) catch {};
        allocator.free(p);
    };

    // Build argv.
    var argv: std.ArrayList([]const u8) = .{};
    defer argv.deinit(allocator);
    argv.append(allocator, self.config.bun_path) catch return E.out_of_memory;
    argv.append(allocator, self.config.script_path) catch return E.out_of_memory;
    argv.append(allocator, "--images") catch return E.out_of_memory;
    argv.append(allocator, images_arg.items) catch return E.out_of_memory;
    if (meta_path_opt) |p| {
        argv.append(allocator, "--metadata") catch return E.out_of_memory;
        argv.append(allocator, p) catch return E.out_of_memory;
    }
    if (model) |m| {
        argv.append(allocator, "--model") catch return E.out_of_memory;
        argv.append(allocator, m) catch return E.out_of_memory;
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.cwd = self.config.cwd;
    child.stdin_behavior = .Close;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    // BYOK: when an operator-supplied key is present, run the subprocess with a
    // per-call env where ANTHROPIC_API_KEY is overridden — the rest of the brain
    // env is inherited. The key is never written to disk or logged. When absent,
    // leave env_map null so the subprocess inherits the brain's own env key.
    var env_map: ?std.process.EnvMap = null;
    defer if (env_map) |*em| em.deinit();
    if (api_key) |key| {
        env_map = std.process.getEnvMap(allocator) catch return E.out_of_memory;
        env_map.?.put("ANTHROPIC_API_KEY", key) catch return E.out_of_memory;
        child.env_map = &env_map.?;
    }

    child.spawn() catch return E.bun_unavailable;

    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);

    // NB: every error path below relies on the `errdefer out.deinit` above —
    // do NOT also deinit manually here, or the errdefer double-frees `out`
    // (deinit sets it to undefined, so the second deinit segfaults).
    if (child.stdout) |stdout| {
        var chunk: [16 * 1024]u8 = undefined;
        while (true) {
            const n = stdout.read(&chunk) catch break;
            if (n == 0) break;
            if (out.items.len + n > self.config.max_stdout_bytes) {
                _ = child.kill() catch {};
                return E.pipeline_failed;
            }
            out.appendSlice(allocator, chunk[0..n]) catch return E.out_of_memory;
        }
    }

    const term = child.wait() catch return E.pipeline_failed;

    switch (term) {
        .Exited => |code| {
            if (code != 0) return E.pipeline_failed;
        },
        else => return E.pipeline_failed,
    }

    return out.toOwnedSlice(allocator) catch E.out_of_memory;
}

fn writeAll(path: []const u8, data: []const u8) !void {
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(data);
}

// ── Inline tests ──────────────────────────────────────────────────────

const testing = std.testing;

test "image_extract_shell: stub command echoes on stdout" {
    var shell = Shell{
        .config = .{
            .bun_path = "/bin/echo",
            .script_path = "ignored",
            .cwd = "/tmp",
        },
    };
    const iface = shell.asInterface();
    const images = [_]image_extract_http.ImageInput{
        .{ .bytes = "IMG", .media_type = "image/jpeg" },
    };
    const out = iface.run(testing.allocator, &images, "{\"day\":\"2026-06-10\"}", null, null) catch |e| {
        std.debug.print("shell.run errored: {s}\n", .{@errorName(e)});
        return e;
    };
    defer testing.allocator.free(out);
    try testing.expect(out.len > 0);
}

test "image_extract_shell: missing bun returns bun_unavailable" {
    var shell = Shell{
        .config = .{
            .bun_path = "/nonexistent/bun",
            .script_path = "/nonexistent/script.ts",
            .cwd = "/tmp",
        },
    };
    const iface = shell.asInterface();
    const images = [_]image_extract_http.ImageInput{
        .{ .bytes = "IMG", .media_type = "image/jpeg" },
    };
    // A nonexistent bun surfaces either as a spawn failure (bun_unavailable)
    // or, on platforms where fork succeeds and exec fails post-fork, as a
    // non-zero child exit (pipeline_failed). Either is an acceptable error;
    // the contract is "does not crash, returns a ShellError, leaks nothing".
    if (iface.run(testing.allocator, &images, null, null, null)) |out| {
        testing.allocator.free(out);
        try testing.expect(false); // a missing bun must not succeed
    } else |err| {
        try testing.expect(err == image_extract_http.ShellError.bun_unavailable or
            err == image_extract_http.ShellError.pipeline_failed);
    }
}

```
