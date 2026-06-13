---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/voice_extract_shell.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.220835+00:00
---

# runtime/semantos-brain/src/voice_extract_shell.zig

```zig
// T8b — voice-extract shell impl.
//
// Spawns `bun cartridges/oddjobz/brain/tools/voice-extract.ts` as a subprocess
// per request, hands it the signed Transcript + metadata + optional
// sir_candidate via temp files (matching the CLI's documented argv
// contract), and reads the IntentResult JSON back from stdout.
//
// Contract reference: `cartridges/oddjobz/brain/tools/voice-extract.ts` —
//   stdout: IntentResult JSON (success or rejection — both shapes
//           returned with exit 0 when the pipeline ran end-to-end)
//   non-zero exit → fatal infra failure before pipeline could observe
//
// Mapping to ShellError:
//   spawn fails (bun missing, script missing, etc) → bun_unavailable
//   wait fails / non-zero exit                     → pipeline_failed
//   exit 0                                          → return stdout
//
// V1 limitations (documented; revisit when reactor's request handlers
// become non-blocking):
//   • No timeout.  A hung bun subprocess wedges the reactor's single
//     thread until it terminates.  In practice bun startup is <1s and
//     the pipeline is sub-second for short voice notes; an operator
//     observing a hang restarts the brain.
//   • stderr is discarded.  The CLI documents that structured rejection
//     details get mirrored to the IntentResult on stdout, so dropping
//     stderr is the documented behaviour for non-debug operation.
//
// Future: extending the bun CLI to accept the three JSON blobs on
// stdin (instead of three temp files) would eliminate temp-file
// overhead + cleanup paths.  Not in T8b scope — preserves the
// existing CLI argv contract verbatim.

const std = @import("std");
const voice_extract_http = @import("voice_extract_http");

/// Configuration for the bun-based shell.  cmdServe constructs this
/// when both `--voice-extract-script` and `--voice-extract-cwd` are
/// passed.  Absence of either → voice-extract acceptor is not wired
/// and the endpoint returns 404.
pub const Config = struct {
    /// Path to the `bun` executable.  Defaults to "bun" (PATH lookup).
    bun_path: []const u8 = "bun",
    /// Absolute path to cartridges/oddjobz/brain/tools/voice-extract.ts.
    script_path: []const u8,
    /// Working directory for the subprocess (the workspace root, so
    /// the CLI's @semantos/* imports resolve via the monorepo's
    /// workspace map).  On rbs production: `/opt/semantos-core`.
    cwd: []const u8,
    /// Cap on stdout bytes read from the subprocess.  IntentResult
    /// JSON is typically <8 KB; 1 MiB is comfortable headroom.
    max_stdout_bytes: usize = 1 * 1024 * 1024,
    /// Directory for the per-request temp files.  Created if missing.
    tmp_dir: []const u8 = "/tmp/brain-voice-extract",
};

pub const Shell = struct {
    config: Config,

    /// Cast to the typed function-pointer interface that
    /// `voice_extract_http.Acceptor.shell` expects.
    pub fn asInterface(self: *const Shell) voice_extract_http.VoiceExtractShell {
        return .{
            .ctx = @ptrCast(@constCast(self)),
            .runFn = runImpl,
        };
    }
};

fn runImpl(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    transcript_json: []const u8,
    metadata_json: []const u8,
    sir_candidate_json: ?[]const u8,
) voice_extract_http.ShellError![]u8 {
    const self: *const Shell = @ptrCast(@alignCast(ctx));

    // Per-request directory under tmp_dir.  Random-suffix to keep
    // concurrent requests from stomping each other's files.
    var random_bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    var suffix_hex: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&suffix_hex, "{x:0>16}", .{std.mem.readInt(u64, &random_bytes, .little)}) catch {
        return voice_extract_http.ShellError.out_of_memory;
    };

    // Ensure the parent tmp dir exists.  makePath is idempotent.
    std.fs.cwd().makePath(self.config.tmp_dir) catch {
        return voice_extract_http.ShellError.bun_unavailable;
    };

    const t_path = std.fmt.allocPrint(allocator, "{s}/t-{s}.json", .{ self.config.tmp_dir, &suffix_hex }) catch {
        return voice_extract_http.ShellError.out_of_memory;
    };
    defer allocator.free(t_path);
    const m_path = std.fmt.allocPrint(allocator, "{s}/m-{s}.json", .{ self.config.tmp_dir, &suffix_hex }) catch {
        return voice_extract_http.ShellError.out_of_memory;
    };
    defer allocator.free(m_path);

    var sir_path_opt: ?[]u8 = null;
    if (sir_candidate_json != null) {
        sir_path_opt = std.fmt.allocPrint(allocator, "{s}/sir-{s}.json", .{ self.config.tmp_dir, &suffix_hex }) catch {
            return voice_extract_http.ShellError.out_of_memory;
        };
    }
    defer if (sir_path_opt) |p| {
        std.fs.cwd().deleteFile(p) catch {};
        allocator.free(p);
    };

    // Write the temp files.  We defer-delete unconditionally so even
    // on error paths the file system stays clean.
    writeAll(t_path, transcript_json) catch return voice_extract_http.ShellError.bun_unavailable;
    defer std.fs.cwd().deleteFile(t_path) catch {};
    writeAll(m_path, metadata_json) catch return voice_extract_http.ShellError.bun_unavailable;
    defer std.fs.cwd().deleteFile(m_path) catch {};
    if (sir_candidate_json) |sir_json| {
        writeAll(sir_path_opt.?, sir_json) catch return voice_extract_http.ShellError.bun_unavailable;
    }

    // Build argv.
    var argv: std.ArrayList([]const u8) = .{};
    defer argv.deinit(allocator);
    argv.append(allocator, self.config.bun_path) catch return voice_extract_http.ShellError.out_of_memory;
    argv.append(allocator, self.config.script_path) catch return voice_extract_http.ShellError.out_of_memory;
    argv.append(allocator, "--transcript") catch return voice_extract_http.ShellError.out_of_memory;
    argv.append(allocator, t_path) catch return voice_extract_http.ShellError.out_of_memory;
    argv.append(allocator, "--metadata") catch return voice_extract_http.ShellError.out_of_memory;
    argv.append(allocator, m_path) catch return voice_extract_http.ShellError.out_of_memory;
    if (sir_path_opt) |p| {
        argv.append(allocator, "--sir-candidate") catch return voice_extract_http.ShellError.out_of_memory;
        argv.append(allocator, p) catch return voice_extract_http.ShellError.out_of_memory;
    }

    // Spawn.
    var child = std.process.Child.init(argv.items, allocator);
    child.cwd = self.config.cwd;
    child.stdin_behavior = .Close;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return voice_extract_http.ShellError.bun_unavailable;

    // Read stdout with the cap.  We use a heap buffer + accumulator
    // pattern mirroring intake_http.callScript so a large reply
    // doesn't blow the stack.
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);

    if (child.stdout) |stdout| {
        var chunk: [16 * 1024]u8 = undefined;
        while (true) {
            const n = stdout.read(&chunk) catch break;
            if (n == 0) break;
            if (out.items.len + n > self.config.max_stdout_bytes) {
                // Truncate at the cap; treat as a pipeline failure since
                // a real IntentResult should fit comfortably.
                _ = child.kill() catch {};
                out.deinit(allocator);
                return voice_extract_http.ShellError.pipeline_failed;
            }
            out.appendSlice(allocator, chunk[0..n]) catch {
                out.deinit(allocator);
                return voice_extract_http.ShellError.out_of_memory;
            };
        }
    }

    const term = child.wait() catch {
        out.deinit(allocator);
        return voice_extract_http.ShellError.pipeline_failed;
    };

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                out.deinit(allocator);
                return voice_extract_http.ShellError.pipeline_failed;
            }
        },
        else => {
            // Signaled / Stopped / Unknown — treat as a failure.
            out.deinit(allocator);
            return voice_extract_http.ShellError.pipeline_failed;
        },
    }

    return out.toOwnedSlice(allocator) catch voice_extract_http.ShellError.out_of_memory;
}

fn writeAll(path: []const u8, data: []const u8) !void {
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(data);
}

// ── Inline tests ──────────────────────────────────────────────────────
//
// These exercise the spawn + temp-file + arg-build path against a
// trivial shell-script "bun" (a stub that just echoes a known
// IntentResult).  No real bun required.

const testing = std.testing;

test "voice_extract_shell: stub command echoes IntentResult on stdout" {
    // Use /bin/cat as a stub "bun": it reads no input and prints
    // nothing.  We test only that spawn + wait + empty-stdout works
    // end-to-end without crashing.  Real bun-CLI integration is
    // tested via the conformance suite when ssh rbs is available.
    var shell = Shell{
        .config = .{
            .bun_path = "/bin/echo",
            .script_path = "{\"ok\":true,\"correlationId\":\"test\"}",
            .cwd = "/tmp",
        },
    };
    const iface = shell.asInterface();
    const out = iface.run(
        testing.allocator,
        "{\"id\":\"t\"}",
        "{\"visit_id\":\"v\"}",
        null,
    ) catch |e| {
        std.debug.print("shell.run errored: {s}\n", .{@errorName(e)});
        return e;
    };
    defer testing.allocator.free(out);
    // /bin/echo prints all its args + newline.  We just confirm the
    // stdout is captured non-empty.
    try testing.expect(out.len > 0);
}

test "voice_extract_shell: missing bun returns bun_unavailable" {
    var shell = Shell{
        .config = .{
            .bun_path = "/nonexistent/bun/path",
            .script_path = "/nonexistent/script.ts",
            .cwd = "/tmp",
        },
    };
    const iface = shell.asInterface();
    const r = iface.run(
        testing.allocator,
        "{\"id\":\"t\"}",
        "{\"visit_id\":\"v\"}",
        null,
    );
    try testing.expectError(voice_extract_http.ShellError.bun_unavailable, r);
}

```
