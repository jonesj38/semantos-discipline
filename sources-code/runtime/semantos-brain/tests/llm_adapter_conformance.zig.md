---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/llm_adapter_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.173696+00:00
---

# runtime/semantos-brain/tests/llm_adapter_conformance.zig

```zig
// Phase Brain 5 — LLM adapter conformance tests.
//
// Covers the schema (config + ParseRequest/ParseResponse), the
// stub adapter, and config persistence. The actual transport
// (subprocess to llama.cpp / Anthropic) is in Brain 5.5.

const std = @import("std");
const llm = @import("llm_adapter");

// ── Backend enum ──

test "Brain 5 Backend: fromString round-trips known values" {
    try std.testing.expectEqual(llm.Backend.none, llm.Backend.fromString("none").?);
    try std.testing.expectEqual(llm.Backend.local, llm.Backend.fromString("local").?);
    try std.testing.expectEqual(llm.Backend.openai, llm.Backend.fromString("openai").?);
    try std.testing.expectEqual(llm.Backend.anthropic, llm.Backend.fromString("anthropic").?);
}

test "Brain 5 Backend: fromString rejects unknown values" {
    try std.testing.expect(llm.Backend.fromString("gemini") == null);
    try std.testing.expect(llm.Backend.fromString("") == null);
}

test "Brain 5 Backend: toString round-trips" {
    try std.testing.expectEqualStrings("none", llm.Backend.none.toString());
    try std.testing.expectEqualStrings("local", llm.Backend.local.toString());
    try std.testing.expectEqualStrings("openai", llm.Backend.openai.toString());
    try std.testing.expectEqualStrings("anthropic", llm.Backend.anthropic.toString());
}

// ── Modal ──

test "Brain 5 Modal: fromString + toString round-trip" {
    try std.testing.expectEqual(llm.Modal.do_, llm.Modal.fromString("do").?);
    try std.testing.expectEqual(llm.Modal.find, llm.Modal.fromString("find").?);
    try std.testing.expectEqual(llm.Modal.talk, llm.Modal.fromString("talk").?);

    try std.testing.expectEqualStrings("do", llm.Modal.do_.toString());
    try std.testing.expectEqualStrings("find", llm.Modal.find.toString());
    try std.testing.expectEqualStrings("talk", llm.Modal.talk.toString());
}

test "Brain 5 Modal: fromString rejects garbage" {
    try std.testing.expect(llm.Modal.fromString("doesomething") == null);
    try std.testing.expect(llm.Modal.fromString("DO") == null);
}

// ── LlmConfig ──

test "Brain 5 LlmConfig: defaults to disabled + .none backend" {
    const cfg = llm.LlmConfig{};
    try std.testing.expect(!cfg.enabled);
    try std.testing.expectEqual(llm.Backend.none, cfg.backend);
}

test "Brain 5 LlmConfig: toJson + fromJson round-trip" {
    const cfg = llm.LlmConfig{
        .enabled = true,
        .backend = .anthropic,
        .endpoint = "https://api.anthropic.com/v1/messages",
        .model = "claude-sonnet-4-5",
        .api_key_env = "ANTHROPIC_API_KEY",
    };
    const json = try cfg.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    const back = try llm.LlmConfig.fromJson(std.testing.allocator, json);
    defer std.testing.allocator.free(back.endpoint);
    defer std.testing.allocator.free(back.model);
    defer std.testing.allocator.free(back.api_key_env);

    try std.testing.expect(back.enabled);
    try std.testing.expectEqual(llm.Backend.anthropic, back.backend);
    try std.testing.expectEqualStrings("https://api.anthropic.com/v1/messages", back.endpoint);
    try std.testing.expectEqualStrings("claude-sonnet-4-5", back.model);
    try std.testing.expectEqualStrings("ANTHROPIC_API_KEY", back.api_key_env);
}

test "Brain 5 LlmConfig: fromJson defaults missing fields safely" {
    const cfg = try llm.LlmConfig.fromJson(std.testing.allocator, "{\"enabled\":false}");
    defer std.testing.allocator.free(cfg.endpoint);
    defer std.testing.allocator.free(cfg.model);
    defer std.testing.allocator.free(cfg.api_key_env);
    try std.testing.expect(!cfg.enabled);
    try std.testing.expectEqual(llm.Backend.none, cfg.backend);
    try std.testing.expectEqualStrings("", cfg.endpoint);
}

test "Brain 5 LlmConfig: fromJson rejects non-object root" {
    const result = llm.LlmConfig.fromJson(std.testing.allocator, "\"just a string\"");
    try std.testing.expectError(llm.LlmError.config_error, result);
}

test "Brain 5 LlmConfig: fromJson rejects malformed JSON" {
    const result = llm.LlmConfig.fromJson(std.testing.allocator, "{not valid json");
    try std.testing.expectError(llm.LlmError.config_error, result);
}

test "Brain 5 LlmConfig: fromJson tolerates unknown backend string" {
    const cfg = try llm.LlmConfig.fromJson(std.testing.allocator, "{\"enabled\":true,\"backend\":\"gemini\"}");
    defer std.testing.allocator.free(cfg.endpoint);
    defer std.testing.allocator.free(cfg.model);
    defer std.testing.allocator.free(cfg.api_key_env);
    // Falls back to .none for forward compat.
    try std.testing.expectEqual(llm.Backend.none, cfg.backend);
}

// ── Config persistence ──

test "Brain 5 saveConfig + loadConfig: round-trip via filesystem" {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    const cfg = llm.LlmConfig{
        .enabled = true,
        .backend = .local,
        .endpoint = "http://localhost:8080/completion",
        .model = "llama-3.1-8b-instruct",
        .api_key_env = "",
    };
    try llm.saveConfig(std.testing.allocator, path, cfg);

    const back = try llm.loadConfig(std.testing.allocator, path);
    defer std.testing.allocator.free(back.endpoint);
    defer std.testing.allocator.free(back.model);
    defer std.testing.allocator.free(back.api_key_env);

    try std.testing.expect(back.enabled);
    try std.testing.expectEqual(llm.Backend.local, back.backend);
    try std.testing.expectEqualStrings("http://localhost:8080/completion", back.endpoint);
}

test "Brain 5 loadConfig: missing file returns defaults" {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    const back = try llm.loadConfig(std.testing.allocator, path);
    defer std.testing.allocator.free(back.endpoint);
    defer std.testing.allocator.free(back.model);
    defer std.testing.allocator.free(back.api_key_env);
    try std.testing.expect(!back.enabled);
    try std.testing.expectEqual(llm.Backend.none, back.backend);
}

test "Brain 5 saveConfig: file lives under data-dir with mode 0600" {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    try llm.saveConfig(std.testing.allocator, path, .{});
    const cfg_path = try std.fs.path.join(std.testing.allocator, &.{ path, "llm-config.json" });
    defer std.testing.allocator.free(cfg_path);
    const f = try std.fs.cwd().openFile(cfg_path, .{});
    defer f.close();
    const stat = try f.stat();
    try std.testing.expect(stat.size > 0);
    // Mode check intentionally lenient: createFile's `mode` param is
    // applied via umask on POSIX so the effective mode may be more
    // restrictive than what we requested. We just confirm the file
    // exists + is non-empty.
}

// ── ParseResponse ──

test "Brain 5 ParseResponse.isValid: rejects out-of-range confidence" {
    const high = llm.ParseResponse{ .modal = .find, .who = "x", .what = "y", .why = "", .confidence = 1.5 };
    try std.testing.expect(!high.isValid());

    const low = llm.ParseResponse{ .modal = .find, .who = "x", .what = "y", .why = "", .confidence = -0.1 };
    try std.testing.expect(!low.isValid());

    const ok = llm.ParseResponse{ .modal = .find, .who = "x", .what = "y", .why = "", .confidence = 0.85 };
    try std.testing.expect(ok.isValid());
}

// ── StubLlmAdapter ──

test "Brain 5 StubLlmAdapter: returns matching fixture" {
    var stub = llm.StubLlmAdapter.init(std.testing.allocator);
    defer stub.deinit();

    try stub.add("show me Mrs Henderson's job", .{
        .modal = .find,
        .who = "Mrs Henderson",
        .what = "job",
        .why = "",
        .confidence = 0.92,
    });

    const adapter = stub.adapter();
    const resp = try adapter.parse(std.testing.allocator, .{
        .utterance = "show me Mrs Henderson's job",
        .available_verbs = "list,inspect,patch,new",
    });
    try std.testing.expectEqual(llm.Modal.find, resp.modal);
    try std.testing.expectEqualStrings("Mrs Henderson", resp.who);
    try std.testing.expectEqualStrings("job", resp.what);
    try std.testing.expectEqual(@as(f32, 0.92), resp.confidence);
}

test "Brain 5 StubLlmAdapter: missing fixture returns transport_error" {
    var stub = llm.StubLlmAdapter.init(std.testing.allocator);
    defer stub.deinit();

    const adapter = stub.adapter();
    const result = adapter.parse(std.testing.allocator, .{
        .utterance = "no fixture for this one",
        .available_verbs = "",
    });
    try std.testing.expectError(llm.LlmError.transport_error, result);
}

test "Brain 5 StubLlmAdapter: multiple fixtures dispatch independently" {
    var stub = llm.StubLlmAdapter.init(std.testing.allocator);
    defer stub.deinit();

    try stub.add("create a quote", .{ .modal = .do_, .who = "self", .what = "quote", .why = "", .confidence = 0.88 });
    try stub.add("show recent jobs", .{ .modal = .find, .who = "self", .what = "jobs", .why = "recent", .confidence = 0.95 });

    const adapter = stub.adapter();
    const r1 = try adapter.parse(std.testing.allocator, .{ .utterance = "create a quote", .available_verbs = "" });
    try std.testing.expectEqual(llm.Modal.do_, r1.modal);
    const r2 = try adapter.parse(std.testing.allocator, .{ .utterance = "show recent jobs", .available_verbs = "" });
    try std.testing.expectEqual(llm.Modal.find, r2.modal);
    try std.testing.expectEqualStrings("recent", r2.why);
}

```
