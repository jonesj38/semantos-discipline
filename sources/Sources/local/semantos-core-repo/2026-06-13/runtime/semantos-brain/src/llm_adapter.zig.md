---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/llm_adapter.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.260635+00:00
---

# runtime/semantos-brain/src/llm_adapter.zig

```zig
// Phase Brain 5 — LLM-conversation adapter for natural-language → typed
// shell command translation.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 5);
//            docs/design/WALLET-VOICE-SHELL-GRAMMAR.md §2.
//
// Layered ABOVE the REPL — the LLM is a *translator*, not a privileged
// actor. The wallet engine's signing path is unchanged. The trust
// boundary is explicit: LLM never signs anything, never sees keys,
// never dispatches without operator confirmation. If the LLM
// hallucinates `send 5000 BTC instead of 5000 sats`, the confirmation
// step catches it.
//
// This module ships the contract surface:
//
//   - `LlmConfig` — persistent config (enabled, backend, endpoint, model)
//     stored at `<data-dir>/llm-config.json` (mode 0600)
//   - `ParseRequest` / `ParseResponse` — JSON shapes the adapter
//     consumes and emits. Mirrors the TS `VoiceCommand` surface that
//     stage 6 (Voice Shell) will codify in `runtime/shell/src/voice-grammar.ts`
//   - `LlmAdapter` vtable — pluggable; default off; subprocess + native
//     HTTP transports added in follow-up PRs
//   - `StubLlmAdapter` — deterministic fixture for tests
//
// The actual HTTP transport (POST to local llama.cpp / OpenAI /
// Anthropic) is intentionally NOT in this PR. Brain 5 ships the contract;
// Brain 5.5 ships the subprocess transport (small Bun script the Semantos Brain
// adapter spawns); Brain 5.6 ships the Voice-Shell integration that
// consumes this contract for real-time mic-to-command translation.

const std = @import("std");

pub const LlmError = error{
    not_enabled,
    config_error,
    transport_error,
    schema_violation,
    rate_limited,
    out_of_memory,
};

// ─────────────────────────────────────────────────────────────────────
// Config
// ─────────────────────────────────────────────────────────────────────

pub const Backend = enum {
    none,
    local,    // local llama.cpp / similar HTTP completion endpoint
    openai,   // OpenAI-compatible API
    anthropic, // Anthropic Messages API

    pub fn fromString(s: []const u8) ?Backend {
        if (std.mem.eql(u8, s, "none")) return .none;
        if (std.mem.eql(u8, s, "local")) return .local;
        if (std.mem.eql(u8, s, "openai")) return .openai;
        if (std.mem.eql(u8, s, "anthropic")) return .anthropic;
        return null;
    }

    pub fn toString(self: Backend) []const u8 {
        return switch (self) {
            .none => "none",
            .local => "local",
            .openai => "openai",
            .anthropic => "anthropic",
        };
    }
};

pub const LlmConfig = struct {
    /// Master switch — `brain llm disable` sets to false; default false.
    /// When false the adapter never makes outbound calls regardless of
    /// other fields.
    enabled: bool = false,
    /// Which backend to use when enabled.
    backend: Backend = .none,
    /// HTTP endpoint URL. For local llama.cpp typically
    /// `http://localhost:8080/completion`. For Anthropic
    /// `https://api.anthropic.com/v1/messages`.
    endpoint: []const u8 = "",
    /// Model identifier passed to the backend.
    /// e.g. `llama-3.1-8b-instruct`, `gpt-4o`, `claude-sonnet-4-5`.
    model: []const u8 = "",
    /// Name of the env var holding the API key for openai / anthropic
    /// backends. The KEY ITSELF NEVER LIVES IN CONFIG. Operator sets
    /// e.g. `ANTHROPIC_API_KEY=sk-ant-...` in their shell env; brain
    /// reads it at request time. Local backends don't need this.
    api_key_env: []const u8 = "",

    pub fn toJson(self: LlmConfig, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);
        try buf.print(
            allocator,
            "{{\"enabled\":{s},\"backend\":\"{s}\",\"endpoint\":\"{s}\",\"model\":\"{s}\",\"api_key_env\":\"{s}\"}}",
            .{
                if (self.enabled) "true" else "false",
                self.backend.toString(),
                self.endpoint,
                self.model,
                self.api_key_env,
            },
        );
        return buf.toOwnedSlice(allocator);
    }

    /// Free allocator-owned strings (endpoint, model, api_key_env). No-op
    /// when the LlmConfig was returned by `loadConfig` with no file
    /// present (defaults are static empty slices, not heap).
    pub fn deinit(self: *LlmConfig, allocator: std.mem.Allocator) void {
        // Heuristic: heap-allocated strings have non-zero length OR
        // came from `fromJson`. Zero-length defaults from the struct's
        // default values are static — calling free on them is UB.
        // The simplest invariant: only free non-empty strings.
        if (self.endpoint.len > 0) allocator.free(self.endpoint);
        if (self.model.len > 0) allocator.free(self.model);
        if (self.api_key_env.len > 0) allocator.free(self.api_key_env);
        self.endpoint = "";
        self.model = "";
        self.api_key_env = "";
    }

    pub fn fromJson(allocator: std.mem.Allocator, text: []const u8) !LlmConfig {
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return LlmError.config_error;
        defer parsed.deinit();
        if (parsed.value != .object) return LlmError.config_error;
        const obj = parsed.value.object;

        const enabled = blk: {
            if (obj.get("enabled")) |v| {
                if (v == .bool) break :blk v.bool;
            }
            break :blk false;
        };
        const backend = blk: {
            if (obj.get("backend")) |v| {
                if (v == .string) {
                    if (Backend.fromString(v.string)) |b| break :blk b;
                }
            }
            break :blk Backend.none;
        };
        const endpoint = if (obj.get("endpoint")) |v| (if (v == .string) try allocator.dupe(u8, v.string) else try allocator.dupe(u8, "")) else try allocator.dupe(u8, "");
        const model = if (obj.get("model")) |v| (if (v == .string) try allocator.dupe(u8, v.string) else try allocator.dupe(u8, "")) else try allocator.dupe(u8, "");
        const api_key_env = if (obj.get("api_key_env")) |v| (if (v == .string) try allocator.dupe(u8, v.string) else try allocator.dupe(u8, "")) else try allocator.dupe(u8, "");

        return .{
            .enabled = enabled,
            .backend = backend,
            .endpoint = endpoint,
            .model = model,
            .api_key_env = api_key_env,
        };
    }
};

/// Read-from-disk; on first read with no file present, return defaults.
pub fn loadConfig(allocator: std.mem.Allocator, data_dir: []const u8) !LlmConfig {
    const path = try std.fs.path.join(allocator, &.{ data_dir, "llm-config.json" });
    defer allocator.free(path);
    const f = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer f.close();
    var buf: [4096]u8 = undefined;
    const n = try f.readAll(&buf);
    return LlmConfig.fromJson(allocator, buf[0..n]);
}

/// Persist the config; writes mode 0600 because while api_key_env is
/// only an env-var name (not a secret), the file is operator-only.
pub fn saveConfig(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    cfg: LlmConfig,
) !void {
    std.fs.cwd().makePath(data_dir) catch {};
    const path = try std.fs.path.join(allocator, &.{ data_dir, "llm-config.json" });
    defer allocator.free(path);
    const json = try cfg.toJson(allocator);
    defer allocator.free(json);
    const f = try std.fs.cwd().createFile(path, .{ .mode = 0o600 });
    defer f.close();
    try f.writeAll(json);
}

// ─────────────────────────────────────────────────────────────────────
// Adapter contract
// ─────────────────────────────────────────────────────────────────────

/// Modal verb of a parsed voice / NL command. Mirrors the TS
/// VoiceCommand interface in docs/design/WALLET-VOICE-SHELL-GRAMMAR.md §2.3.
pub const Modal = enum {
    do_, // Zig keyword `do` requires trailing underscore
    find,
    talk,

    pub fn fromString(s: []const u8) ?Modal {
        if (std.mem.eql(u8, s, "do")) return .do_;
        if (std.mem.eql(u8, s, "find")) return .find;
        if (std.mem.eql(u8, s, "talk")) return .talk;
        return null;
    }

    pub fn toString(self: Modal) []const u8 {
        return switch (self) {
            .do_ => "do",
            .find => "find",
            .talk => "talk",
        };
    }
};

/// A free-text utterance + the operator's available verb vocabulary.
/// The LLM is given this and asked to produce a typed command.
pub const ParseRequest = struct {
    utterance: []const u8,
    /// Comma-separated list of available shell verbs the operator's
    /// node supports. The LLM constrains its output to this set so it
    /// can't hallucinate verbs that don't exist.
    available_verbs: []const u8,
    /// Optional context — recent commands, current pinned object, etc.
    /// Free-form string the operator's host may inject.
    context_hint: []const u8 = "",
};

/// Parsed command. The shell router maps `(modal, who, what, why)` to
/// a concrete shell verb + flags. The TS-side parser in stage 6 wraps
/// this with `alternatives` (ambiguous parses) and `raw` (transcript).
pub const ParseResponse = struct {
    modal: Modal,
    /// Free-text, e.g. "Mrs Henderson", "self", "@team".
    who: []const u8,
    /// Free-text, e.g. "job", "quote", "fence-job-12".
    what: []const u8,
    /// Optional qualifier, e.g. "the urgent one", "from Tuesday".
    why: []const u8,
    /// 0..1, parser's self-reported confidence.
    confidence: f32,

    pub fn isValid(self: ParseResponse) bool {
        return self.confidence >= 0 and self.confidence <= 1;
    }
};

/// Pluggable adapter — config + transport + caller (typically the REPL
/// or the voice parser) calls `parse(req)` and gets a typed
/// `ParseResponse`.
pub const LlmAdapter = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        parse: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, req: ParseRequest) LlmError!ParseResponse,
    };

    pub fn parse(self: LlmAdapter, allocator: std.mem.Allocator, req: ParseRequest) LlmError!ParseResponse {
        return self.vtable.parse(self.ctx, allocator, req);
    }
};

// ─────────────────────────────────────────────────────────────────────
// Stub adapter (for tests + dev mode)
// ─────────────────────────────────────────────────────────────────────

/// Deterministic stub. Maps exact-match utterances to fixed responses;
/// returns a default `LlmError.transport_error` for unmatched ones so
/// tests can assert the error path.
pub const StubLlmAdapter = struct {
    fixtures: std.StringHashMap(ParseResponse),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StubLlmAdapter {
        return .{
            .fixtures = std.StringHashMap(ParseResponse).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StubLlmAdapter) void {
        var it = self.fixtures.iterator();
        while (it.next()) |entry| self.allocator.free(entry.key_ptr.*);
        self.fixtures.deinit();
    }

    /// Register a fixture: when the adapter sees `utterance`, it returns
    /// `response`.
    pub fn add(self: *StubLlmAdapter, utterance: []const u8, response: ParseResponse) !void {
        const key = try self.allocator.dupe(u8, utterance);
        try self.fixtures.put(key, response);
    }

    pub fn adapter(self: *StubLlmAdapter) LlmAdapter {
        return .{ .ctx = @ptrCast(self), .vtable = &stub_vtable };
    }

    fn vParse(ctx: *anyopaque, _: std.mem.Allocator, req: ParseRequest) LlmError!ParseResponse {
        const self: *StubLlmAdapter = @ptrCast(@alignCast(ctx));
        if (self.fixtures.get(req.utterance)) |r| return r;
        return LlmError.transport_error;
    }

    const stub_vtable: LlmAdapter.VTable = .{
        .parse = vParse,
    };
};

```
