---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/audio_extract_shell.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.261209+00:00
---

# runtime/semantos-brain/src/audio_extract_shell.zig

```zig
// Betterment voice — audio-extract shell impl.
//
// Spawns `bun cartridges/betterment/brain/tools/audio-extract.ts` per request,
// handing it the uploaded voice note as a temp .wav and the optional metadata,
// and reads the ExtractResult JSON (turns + rawText) from stdout. The bun tool
// shells to whisper.cpp on the brain host.
//
// Sibling of image_extract_shell.zig. The subprocess inherits the brain's env
// (so WHISPER_BIN / WHISPER_MODEL set there reach audio-extract.ts; otherwise it
// uses its /opt/whisper.cpp defaults). No API key (whisper is local).

const std = @import("std");
const audio_extract_http = @import("audio_extract_http");

pub const Config = struct {
    bun_path: []const u8 = "bun",
    /// Absolute path to cartridges/betterment/brain/tools/audio-extract.ts.
    script_path: []const u8,
    cwd: []const u8,
    max_stdout_bytes: usize = 4 * 1024 * 1024,
    tmp_dir: []const u8 = "/tmp/brain-audio-extract",
};

pub const Shell = struct {
    config: Config,

    pub fn asInterface(self: *const Shell) audio_extract_http.AudioExtractShell {
        return .{
            .ctx = @ptrCast(@constCast(self)),
            .runFn = runImpl,
        };
    }
};

fn runImpl(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    audio_bytes: []const u8,
    metadata_json: ?[]const u8,
) audio_extract_http.ShellError![]u8 {
    const self: *const Shell = @ptrCast(@alignCast(ctx));
    const E = audio_extract_http.ShellError;

    if (audio_bytes.len == 0) return E.pipeline_failed;

    var random_bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    var suffix_hex: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&suffix_hex, "{x:0>16}", .{std.mem.readInt(u64, &random_bytes, .little)}) catch {
        return E.out_of_memory;
    };

    std.fs.cwd().makePath(self.config.tmp_dir) catch return E.bun_unavailable;

    const wav_path = std.fmt.allocPrint(allocator, "{s}/voice-{s}.wav", .{ self.config.tmp_dir, &suffix_hex }) catch
        return E.out_of_memory;
    defer {
        std.fs.cwd().deleteFile(wav_path) catch {};
        allocator.free(wav_path);
    }
    writeAll(wav_path, audio_bytes) catch return E.bun_unavailable;

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

    var argv: std.ArrayList([]const u8) = .{};
    defer argv.deinit(allocator);
    argv.append(allocator, self.config.bun_path) catch return E.out_of_memory;
    argv.append(allocator, self.config.script_path) catch return E.out_of_memory;
    argv.append(allocator, "--audio") catch return E.out_of_memory;
    argv.append(allocator, wav_path) catch return E.out_of_memory;
    if (meta_path_opt) |p| {
        argv.append(allocator, "--metadata") catch return E.out_of_memory;
        argv.append(allocator, p) catch return E.out_of_memory;
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.cwd = self.config.cwd;
    child.stdin_behavior = .Close;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return E.bun_unavailable;

    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);

    // Error paths below rely on the errdefer above — do NOT also deinit manually
    // (double-free on an undefined ArrayList → segfault).
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

test "audio_extract_shell: stub command echoes on stdout" {
    var shell = Shell{
        .config = .{ .bun_path = "/bin/echo", .script_path = "ignored", .cwd = "/tmp" },
    };
    const iface = shell.asInterface();
    const out = iface.run(testing.allocator, "RIFFDATA", null) catch |e| {
        std.debug.print("shell.run errored: {s}\n", .{@errorName(e)});
        return e;
    };
    defer testing.allocator.free(out);
    try testing.expect(out.len > 0);
}

test "audio_extract_shell: missing bun returns an error (no crash/leak)" {
    var shell = Shell{
        .config = .{ .bun_path = "/nonexistent/bun", .script_path = "/nope.ts", .cwd = "/tmp" },
    };
    const iface = shell.asInterface();
    if (iface.run(testing.allocator, "RIFFDATA", null)) |out| {
        testing.allocator.free(out);
        try testing.expect(false);
    } else |err| {
        try testing.expect(err == audio_extract_http.ShellError.bun_unavailable or
            err == audio_extract_http.ShellError.pipeline_failed);
    }
}

```
