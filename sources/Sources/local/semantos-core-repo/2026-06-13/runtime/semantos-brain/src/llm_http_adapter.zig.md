---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/llm_http_adapter.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.239621+00:00
---

# runtime/semantos-brain/src/llm_http_adapter.zig

```zig
// Phase Brain 5.1 — HTTP transport for the LLM adapter.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 5).
//
// Wires the existing LlmAdapter vtable to a real HTTP backend so the
// `brain llm enable / set backend / set api_key_env` config (Brain 5 PR #257)
// finally produces parsed commands instead of stubs. Three backends:
//
//   • local    — POSTs to a llama.cpp-style /completion endpoint.  No
//                auth header.  Body is a plain `{"prompt":...,"n_predict":N}`.
//   • openai   — Chat Completions API.  Bearer token from env.
//   • anthropic — Messages API.  x-api-key from env, anthropic-version header.
//
// ─── Trust boundary (carries through from Brain 5 PR #257) ─────────────
//
// • api_key_env stores the env-var NAME, never the secret.  We read it
//   here at request time; it never lands in any persisted config or log.
// • The LLM is a translator, not an actor.  Its output goes back to the
//   REPL as a structured ParseResponse; the wallet engine still requires
//   operator confirmation before signing.  So a hallucinated parse
//   produces a wrong command preview, never a wrong signature.
//
// ─── Request flow ───────────────────────────────────────────────────
//
//   build prompt  ─►  POST endpoint  ─►  parse response
//      │               │                  │
//      │               │                  ├─ extract message text
//      │               │                  ├─ parse text as JSON
//      │               │                  └─ map to ParseResponse
//      │               │
//      │               ├─ headers per backend
//      │               └─ body per backend
//      │
//      └─ system prompt + utterance + available_verbs + context
//
// All three backends use a uniform system prompt that constrains the
// LLM to emit a JSON object matching ParseResponse exactly.  Backend-
// specific code is just the transport-shape adapter.

const std = @import("std");
const llm = @import("llm_adapter");

pub const HttpLlmError = llm.LlmError;

/// Adapter instance — owns its config (a deep-copy from disk) so the
/// caller can free the loaded config without dangling references.
pub const HttpLlmAdapter = struct {
    cfg: llm.LlmConfig,
    /// Borrowed allocator — used for one-shot per-parse allocations
    /// (request body, response buffer, parsed JSON nodes).
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, cfg: llm.LlmConfig) HttpLlmAdapter {
        return .{ .cfg = cfg, .allocator = allocator };
    }

    pub fn adapter(self: *HttpLlmAdapter) llm.LlmAdapter {
        return .{ .ctx = self, .vtable = &http_vtable };
    }

    fn vParse(ctx: *anyopaque, allocator: std.mem.Allocator, req: llm.ParseRequest) llm.LlmError!llm.ParseResponse {
        const self: *HttpLlmAdapter = @ptrCast(@alignCast(ctx));
        return self.parse(allocator, req);
    }

    const http_vtable: llm.LlmAdapter.VTable = .{ .parse = vParse };

    pub fn parse(
        self: *HttpLlmAdapter,
        allocator: std.mem.Allocator,
        req: llm.ParseRequest,
    ) llm.LlmError!llm.ParseResponse {
        if (!self.cfg.enabled) return llm.LlmError.config_error;
        if (self.cfg.endpoint.len == 0) return llm.LlmError.config_error;

        // ── Build the system prompt + body per backend ──
        const body = self.buildRequestBody(allocator, req) catch |err| switch (err) {
            error.config_error => return llm.LlmError.config_error,
            else => return llm.LlmError.transport_error,
        };
        defer allocator.free(body);

        // ── Send the HTTP request ──
        var resp_writer = std.io.Writer.Allocating.init(allocator);
        defer resp_writer.deinit();

        var headers_buf: [4]std.http.Header = undefined;
        const headers = self.buildHeaders(allocator, &headers_buf) catch |err| switch (err) {
            // Missing api_key_env / empty api key → config_error, not transport.
            error.config_error => return llm.LlmError.config_error,
            else => return llm.LlmError.transport_error,
        };
        defer freeAuthHeader(allocator, headers);

        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        const result = client.fetch(.{
            .location = .{ .url = self.cfg.endpoint },
            .method = .POST,
            .payload = body,
            .extra_headers = headers,
            .response_writer = &resp_writer.writer,
        }) catch return llm.LlmError.transport_error;

        switch (result.status) {
            .ok => {},
            .too_many_requests => return llm.LlmError.rate_limited,
            .unauthorized, .forbidden => return llm.LlmError.config_error,
            else => return llm.LlmError.transport_error,
        }

        // ── Decode the response per backend ──
        const message_text = self.extractMessageText(allocator, resp_writer.written()) catch
            return llm.LlmError.schema_violation;
        defer allocator.free(message_text);

        return decodeParseResponse(allocator, message_text);
    }

    fn buildRequestBody(
        self: *HttpLlmAdapter,
        allocator: std.mem.Allocator,
        req: llm.ParseRequest,
    ) ![]u8 {
        const system_prompt = system_prompt_template;
        const user_prompt = try std.fmt.allocPrint(
            allocator,
            "Utterance: {s}\nAvailable verbs: {s}\nContext: {s}\n\nReturn ONLY a JSON object with this exact shape:\n{{\"modal\":\"do|find|talk\",\"who\":\"...\",\"what\":\"...\",\"why\":\"...\",\"confidence\":0.0_to_1.0}}",
            .{ req.utterance, req.available_verbs, req.context_hint },
        );
        defer allocator.free(user_prompt);

        return switch (self.cfg.backend) {
            .none => return llm.LlmError.config_error,
            .local => buildLocalBody(allocator, system_prompt, user_prompt, self.cfg.model),
            .openai => buildOpenaiBody(allocator, system_prompt, user_prompt, self.cfg.model),
            .anthropic => buildAnthropicBody(allocator, system_prompt, user_prompt, self.cfg.model),
        };
    }

    fn buildHeaders(
        self: *HttpLlmAdapter,
        allocator: std.mem.Allocator,
        buf: *[4]std.http.Header,
    ) ![]std.http.Header {
        var n: usize = 0;
        buf[n] = .{ .name = "content-type", .value = "application/json" };
        n += 1;

        switch (self.cfg.backend) {
            .none, .local => {},
            .openai => {
                if (self.cfg.api_key_env.len == 0) return llm.LlmError.config_error;
                const key = std.process.getEnvVarOwned(allocator, self.cfg.api_key_env) catch
                    return llm.LlmError.config_error;
                // Note: leaks `key` — the bearer slice points into it. Caller
                // (parse) calls freeAuthHeader to free it once the fetch is done.
                const bearer = try std.fmt.allocPrint(allocator, "Bearer {s}", .{key});
                allocator.free(key);
                buf[n] = .{ .name = "authorization", .value = bearer };
                n += 1;
            },
            .anthropic => {
                if (self.cfg.api_key_env.len == 0) return llm.LlmError.config_error;
                const key = std.process.getEnvVarOwned(allocator, self.cfg.api_key_env) catch
                    return llm.LlmError.config_error;
                buf[n] = .{ .name = "x-api-key", .value = key };
                n += 1;
                buf[n] = .{ .name = "anthropic-version", .value = "2023-06-01" };
                n += 1;
            },
        }
        return buf[0..n];
    }

    fn extractMessageText(
        self: *HttpLlmAdapter,
        allocator: std.mem.Allocator,
        body: []const u8,
    ) ![]u8 {
        return switch (self.cfg.backend) {
            .none => llm.LlmError.config_error,
            .local => extractLocalMessage(allocator, body),
            .openai => extractOpenaiMessage(allocator, body),
            .anthropic => extractAnthropicMessage(allocator, body),
        };
    }
};

/// Free a bearer / x-api-key header slice that buildHeaders allocated.
/// Walks the header list and frees any header whose name we know we
/// allocated (authorization for openai, x-api-key for anthropic).
fn freeAuthHeader(allocator: std.mem.Allocator, headers: []std.http.Header) void {
    for (headers) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "authorization") or
            std.ascii.eqlIgnoreCase(h.name, "x-api-key"))
        {
            allocator.free(h.value);
        }
    }
}

const system_prompt_template =
    \\You are the parsing layer of a sovereign-node host shell ("brain"). Your only job is to translate the operator's natural-language utterance into a structured command shape. You NEVER take action. You NEVER sign anything. You NEVER access keys. The operator confirms every action before the wallet engine signs.
    \\
    \\Output: a single JSON object. No prose. No markdown. No code fences. Exactly the shape:
    \\
    \\  {"modal":"do|find|talk","who":"...","what":"...","why":"...","confidence":0.0_to_1.0}
    \\
    \\Modal verb rules:
    \\  - "do"   → user wants to perform an action (send a payment, sign a doc, schedule a job)
    \\  - "find" → user wants to retrieve / look up information
    \\  - "talk" → user wants to send a message / start a conversation
    \\
    \\If the utterance doesn't fit any of these, return confidence below 0.3.
    \\If the available_verbs list doesn't contain a verb matching the user's intent, return confidence below 0.3.
;

// ─── Per-backend body builders ──────────────────────────────────────

fn buildLocalBody(
    allocator: std.mem.Allocator,
    system_prompt: []const u8,
    user_prompt: []const u8,
    model: []const u8,
) ![]u8 {
    _ = model;
    // llama.cpp /completion takes a single prompt + n_predict.
    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"prompt\":");
    try jsonString(allocator, &body, system_prompt);
    try body.appendSlice(allocator, " ");
    // Concatenate system + user into one prompt string. Trim and re-encode.
    var combined: std.ArrayList(u8) = .{};
    defer combined.deinit(allocator);
    try combined.appendSlice(allocator, system_prompt);
    try combined.appendSlice(allocator, "\n\n");
    try combined.appendSlice(allocator, user_prompt);
    body.clearRetainingCapacity();
    try body.appendSlice(allocator, "{\"prompt\":");
    try jsonString(allocator, &body, combined.items);
    try body.appendSlice(allocator, ",\"n_predict\":256,\"stop\":[\"}\\n\\n\"]}");
    return body.toOwnedSlice(allocator);
}

fn buildOpenaiBody(
    allocator: std.mem.Allocator,
    system_prompt: []const u8,
    user_prompt: []const u8,
    model: []const u8,
) ![]u8 {
    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"model\":");
    try jsonString(allocator, &body, model);
    try body.appendSlice(allocator, ",\"messages\":[{\"role\":\"system\",\"content\":");
    try jsonString(allocator, &body, system_prompt);
    try body.appendSlice(allocator, "},{\"role\":\"user\",\"content\":");
    try jsonString(allocator, &body, user_prompt);
    try body.appendSlice(allocator, "}],\"temperature\":0.0}");
    return body.toOwnedSlice(allocator);
}

fn buildAnthropicBody(
    allocator: std.mem.Allocator,
    system_prompt: []const u8,
    user_prompt: []const u8,
    model: []const u8,
) ![]u8 {
    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"model\":");
    try jsonString(allocator, &body, model);
    try body.appendSlice(allocator, ",\"max_tokens\":256,\"system\":");
    try jsonString(allocator, &body, system_prompt);
    try body.appendSlice(allocator, ",\"messages\":[{\"role\":\"user\",\"content\":");
    try jsonString(allocator, &body, user_prompt);
    try body.appendSlice(allocator, "}]}");
    return body.toOwnedSlice(allocator);
}

// ─── Per-backend response extractors ────────────────────────────────

/// llama.cpp /completion: `{"content":"<text>", ...}`.
fn extractLocalMessage(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return llm.LlmError.schema_violation;
    defer parsed.deinit();
    if (parsed.value != .object) return llm.LlmError.schema_violation;
    const content = parsed.value.object.get("content") orelse return llm.LlmError.schema_violation;
    if (content != .string) return llm.LlmError.schema_violation;
    return allocator.dupe(u8, content.string);
}

/// OpenAI Chat Completions: `{"choices":[{"message":{"content":"<text>"}}]}`.
fn extractOpenaiMessage(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return llm.LlmError.schema_violation;
    defer parsed.deinit();
    if (parsed.value != .object) return llm.LlmError.schema_violation;
    const choices = parsed.value.object.get("choices") orelse return llm.LlmError.schema_violation;
    if (choices != .array or choices.array.items.len == 0) return llm.LlmError.schema_violation;
    const first = choices.array.items[0];
    if (first != .object) return llm.LlmError.schema_violation;
    const msg = first.object.get("message") orelse return llm.LlmError.schema_violation;
    if (msg != .object) return llm.LlmError.schema_violation;
    const content = msg.object.get("content") orelse return llm.LlmError.schema_violation;
    if (content != .string) return llm.LlmError.schema_violation;
    return allocator.dupe(u8, content.string);
}

/// Anthropic Messages: `{"content":[{"type":"text","text":"<text>"}]}`.
fn extractAnthropicMessage(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return llm.LlmError.schema_violation;
    defer parsed.deinit();
    if (parsed.value != .object) return llm.LlmError.schema_violation;
    const content = parsed.value.object.get("content") orelse return llm.LlmError.schema_violation;
    if (content != .array or content.array.items.len == 0) return llm.LlmError.schema_violation;
    const first = content.array.items[0];
    if (first != .object) return llm.LlmError.schema_violation;
    const text = first.object.get("text") orelse return llm.LlmError.schema_violation;
    if (text != .string) return llm.LlmError.schema_violation;
    return allocator.dupe(u8, text.string);
}

// ─── Decode the LLM's text response into ParseResponse ──────────────

/// Parse the LLM-emitted JSON message into a ParseResponse.  Strips
/// surrounding code fences if present (some models add them despite
/// the system prompt).
pub fn decodeParseResponse(
    allocator: std.mem.Allocator,
    text: []const u8,
) llm.LlmError!llm.ParseResponse {
    const stripped = stripCodeFence(text);
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, stripped, .{}) catch
        return llm.LlmError.schema_violation;
    defer parsed.deinit();
    if (parsed.value != .object) return llm.LlmError.schema_violation;
    const obj = parsed.value.object;

    const modal_str = obj.get("modal") orelse return llm.LlmError.schema_violation;
    if (modal_str != .string) return llm.LlmError.schema_violation;
    const modal = llm.Modal.fromString(modal_str.string) orelse return llm.LlmError.schema_violation;

    const who = (obj.get("who") orelse return llm.LlmError.schema_violation);
    if (who != .string) return llm.LlmError.schema_violation;
    const what = (obj.get("what") orelse return llm.LlmError.schema_violation);
    if (what != .string) return llm.LlmError.schema_violation;
    const why = obj.get("why") orelse std.json.Value{ .string = "" };
    const why_str: []const u8 = if (why == .string) why.string else "";

    const conf_v = obj.get("confidence") orelse return llm.LlmError.schema_violation;
    const confidence: f32 = switch (conf_v) {
        .float => @floatCast(conf_v.float),
        .integer => @floatFromInt(conf_v.integer),
        else => return llm.LlmError.schema_violation,
    };

    const who_dup = allocator.dupe(u8, who.string) catch return llm.LlmError.out_of_memory;
    const what_dup = allocator.dupe(u8, what.string) catch return llm.LlmError.out_of_memory;
    const why_dup = allocator.dupe(u8, why_str) catch return llm.LlmError.out_of_memory;
    return .{
        .modal = modal,
        .who = who_dup,
        .what = what_dup,
        .why = why_dup,
        .confidence = confidence,
    };
}

fn stripCodeFence(text: []const u8) []const u8 {
    var s = std.mem.trim(u8, text, " \t\r\n");
    if (std.mem.startsWith(u8, s, "```json")) s = s[7..];
    if (std.mem.startsWith(u8, s, "```")) s = s[3..];
    if (std.mem.endsWith(u8, s, "```")) s = s[0 .. s.len - 3];
    return std.mem.trim(u8, s, " \t\r\n");
}

// ─── JSON helpers ────────────────────────────────────────────────────

/// Append a JSON-encoded string to `out`. Uses std.json to handle
/// escaping correctly (including non-ASCII).
fn jsonString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    s: []const u8,
) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

// ─── Tests ───────────────────────────────────────────────────────────

test "decodeParseResponse handles plain JSON" {
    const allocator = std.testing.allocator;
    const r = try decodeParseResponse(allocator,
        \\{"modal":"do","who":"alice","what":"send-payment","why":"for pizza","confidence":0.85}
    );
    defer {
        allocator.free(r.who);
        allocator.free(r.what);
        allocator.free(r.why);
    }
    try std.testing.expectEqual(llm.Modal.do_, r.modal);
    try std.testing.expectEqualSlices(u8, "alice", r.who);
    try std.testing.expectEqualSlices(u8, "send-payment", r.what);
    try std.testing.expectEqualSlices(u8, "for pizza", r.why);
    try std.testing.expect(r.confidence > 0.84 and r.confidence < 0.86);
}

test "decodeParseResponse strips ```json code fences" {
    const allocator = std.testing.allocator;
    const r = try decodeParseResponse(allocator,
        \\```json
        \\{"modal":"find","who":"self","what":"recent-emails","why":"","confidence":0.9}
        \\```
    );
    defer {
        allocator.free(r.who);
        allocator.free(r.what);
        allocator.free(r.why);
    }
    try std.testing.expectEqual(llm.Modal.find, r.modal);
    try std.testing.expectEqualSlices(u8, "recent-emails", r.what);
}

test "decodeParseResponse rejects missing fields" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        llm.LlmError.schema_violation,
        decodeParseResponse(allocator, "{\"modal\":\"do\"}"),
    );
}

test "decodeParseResponse rejects unknown modal" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        llm.LlmError.schema_violation,
        decodeParseResponse(allocator,
            \\{"modal":"explode","who":"x","what":"y","why":"","confidence":0.5}
        ),
    );
}

test "decodeParseResponse accepts integer confidence" {
    const allocator = std.testing.allocator;
    const r = try decodeParseResponse(allocator,
        \\{"modal":"talk","who":"alice","what":"hi","why":"","confidence":1}
    );
    defer {
        allocator.free(r.who);
        allocator.free(r.what);
        allocator.free(r.why);
    }
    try std.testing.expectEqual(@as(f32, 1.0), r.confidence);
}

test "buildOpenaiBody emits correct shape" {
    const allocator = std.testing.allocator;
    const body = try buildOpenaiBody(allocator, "system", "user", "gpt-4o");
    defer allocator.free(body);
    // Sanity: model + system + user roles all present, JSON parseable.
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    const model = parsed.value.object.get("model").?;
    try std.testing.expectEqualSlices(u8, "gpt-4o", model.string);
    const messages = parsed.value.object.get("messages").?;
    try std.testing.expect(messages == .array and messages.array.items.len == 2);
}

test "buildAnthropicBody emits correct shape" {
    const allocator = std.testing.allocator;
    const body = try buildAnthropicBody(allocator, "system", "user", "claude-sonnet-4-5");
    defer allocator.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    const sys = parsed.value.object.get("system").?;
    try std.testing.expectEqualSlices(u8, "system", sys.string);
    const messages = parsed.value.object.get("messages").?;
    try std.testing.expect(messages == .array and messages.array.items.len == 1);
}

// ─────────────────────────────────────────────────────────────────────
// D-W1 Phase 1 follow-up — generic completion API
//
// Adds the prompt-in / text-out path the dispatcher's `llm.complete`
// resource handler delegates to.  Same per-backend HTTP shape as
// `parse()` above (config-driven endpoint + headers + body builders),
// but the system prompt is operator-supplied (per call) instead of the
// modal-verb parsing system prompt baked into `system_prompt_template`.
//
// The handler in `resources/llm_complete_handler.zig` wraps this with
// per-scope token-bucket + day-budget tracking (a layer this transport
// is intentionally unaware of — keeps all business logic out of the
// rate limiter, all HTTP/auth/body construction out of the handler).
// ─────────────────────────────────────────────────────────────────────

pub const CompletionRequest = struct {
    prompt: []const u8,
    /// Optional operator-supplied system prompt; empty string = none.
    system_prompt: []const u8 = "",
    /// 0 = backend default.
    max_tokens: u32 = 0,
    /// Negative or NaN = backend default.
    temperature: f32 = -1.0,
};

pub const CompletionResponse = struct {
    /// Decoded text.  Allocator-owned by the caller.
    text: []u8,
    /// Backend's reported model id.  Allocator-owned by the caller.
    model: []u8,
    /// Best-effort total token count (input + output) reported by the
    /// backend.  0 if the backend doesn't surface it.
    tokens_used: u32 = 0,
};

/// Free both owned slices in a CompletionResponse.
pub fn completionResponseDeinit(
    self: *CompletionResponse,
    allocator: std.mem.Allocator,
) void {
    if (self.text.len > 0) allocator.free(self.text);
    if (self.model.len > 0) allocator.free(self.model);
    self.text = &.{};
    self.model = &.{};
}

/// Run a single prompt-in / text-out completion against the configured
/// backend.  Same trust boundary as `parse()` — the operator's
/// `api_key_env` env-var name is read at request time, never persisted,
/// never logged.
///
/// The dispatcher's `llm.complete` handler calls this only after its
/// rate-limit + day-budget gate has cleared.  Errors flow through
/// unchanged so the handler can map them to typed dispatcher errors.
pub fn complete(
    self: *HttpLlmAdapter,
    allocator: std.mem.Allocator,
    req: CompletionRequest,
) llm.LlmError!CompletionResponse {
    if (!self.cfg.enabled) return llm.LlmError.config_error;
    if (self.cfg.endpoint.len == 0) return llm.LlmError.config_error;
    if (self.cfg.backend == .none) return llm.LlmError.config_error;

    const body = buildCompletionBody(allocator, self.cfg.backend, self.cfg.model, req) catch |err| switch (err) {
        error.OutOfMemory => return llm.LlmError.out_of_memory,
        else => return llm.LlmError.transport_error,
    };
    defer allocator.free(body);

    var resp_writer = std.io.Writer.Allocating.init(allocator);
    defer resp_writer.deinit();

    var headers_buf: [4]std.http.Header = undefined;
    const headers = self.buildHeaders(allocator, &headers_buf) catch |err| switch (err) {
        error.config_error => return llm.LlmError.config_error,
        else => return llm.LlmError.transport_error,
    };
    defer freeAuthHeader(allocator, headers);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const result = client.fetch(.{
        .location = .{ .url = self.cfg.endpoint },
        .method = .POST,
        .payload = body,
        .extra_headers = headers,
        .response_writer = &resp_writer.writer,
    }) catch return llm.LlmError.transport_error;

    switch (result.status) {
        .ok => {},
        .too_many_requests => return llm.LlmError.rate_limited,
        .unauthorized, .forbidden => return llm.LlmError.config_error,
        else => return llm.LlmError.transport_error,
    }

    return decodeCompletionResponse(allocator, self.cfg.backend, resp_writer.written());
}

/// Per-backend body for the generic completion path.  Mirrors the
/// `buildLocalBody` / `buildOpenaiBody` / `buildAnthropicBody` shape
/// used by `parse()`, but the system prompt is caller-supplied (or
/// omitted) and `max_tokens` / `temperature` flow through.
pub fn buildCompletionBody(
    allocator: std.mem.Allocator,
    backend: llm.Backend,
    model: []const u8,
    req: CompletionRequest,
) ![]u8 {
    return switch (backend) {
        .none => llm.LlmError.config_error,
        .local => buildCompletionLocalBody(allocator, model, req),
        .openai => buildCompletionOpenaiBody(allocator, model, req),
        .anthropic => buildCompletionAnthropicBody(allocator, model, req),
    };
}

fn buildCompletionLocalBody(
    allocator: std.mem.Allocator,
    model: []const u8,
    req: CompletionRequest,
) ![]u8 {
    _ = model;
    var combined: std.ArrayList(u8) = .{};
    defer combined.deinit(allocator);
    if (req.system_prompt.len > 0) {
        try combined.appendSlice(allocator, req.system_prompt);
        try combined.appendSlice(allocator, "\n\n");
    }
    try combined.appendSlice(allocator, req.prompt);

    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"prompt\":");
    try jsonString(allocator, &body, combined.items);
    const n_predict: u32 = if (req.max_tokens == 0) 256 else req.max_tokens;
    try body.print(allocator, ",\"n_predict\":{d}", .{n_predict});
    if (req.temperature >= 0) {
        try body.print(allocator, ",\"temperature\":{d}", .{req.temperature});
    }
    try body.appendSlice(allocator, "}");
    return body.toOwnedSlice(allocator);
}

fn buildCompletionOpenaiBody(
    allocator: std.mem.Allocator,
    model: []const u8,
    req: CompletionRequest,
) ![]u8 {
    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"model\":");
    try jsonString(allocator, &body, model);
    try body.appendSlice(allocator, ",\"messages\":[");
    var emitted_any = false;
    if (req.system_prompt.len > 0) {
        try body.appendSlice(allocator, "{\"role\":\"system\",\"content\":");
        try jsonString(allocator, &body, req.system_prompt);
        try body.appendSlice(allocator, "}");
        emitted_any = true;
    }
    if (emitted_any) try body.append(allocator, ',');
    try body.appendSlice(allocator, "{\"role\":\"user\",\"content\":");
    try jsonString(allocator, &body, req.prompt);
    try body.appendSlice(allocator, "}]");
    if (req.max_tokens != 0) {
        try body.print(allocator, ",\"max_tokens\":{d}", .{req.max_tokens});
    }
    if (req.temperature >= 0) {
        try body.print(allocator, ",\"temperature\":{d}", .{req.temperature});
    }
    try body.append(allocator, '}');
    return body.toOwnedSlice(allocator);
}

fn buildCompletionAnthropicBody(
    allocator: std.mem.Allocator,
    model: []const u8,
    req: CompletionRequest,
) ![]u8 {
    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"model\":");
    try jsonString(allocator, &body, model);
    const max_tokens: u32 = if (req.max_tokens == 0) 256 else req.max_tokens;
    try body.print(allocator, ",\"max_tokens\":{d}", .{max_tokens});
    if (req.system_prompt.len > 0) {
        try body.appendSlice(allocator, ",\"system\":");
        try jsonString(allocator, &body, req.system_prompt);
    }
    if (req.temperature >= 0) {
        try body.print(allocator, ",\"temperature\":{d}", .{req.temperature});
    }
    try body.appendSlice(allocator, ",\"messages\":[{\"role\":\"user\",\"content\":");
    try jsonString(allocator, &body, req.prompt);
    try body.appendSlice(allocator, "}]}");
    return body.toOwnedSlice(allocator);
}

/// Decode a per-backend completion response into a CompletionResponse.
/// Caller owns `text` and `model` strings.  Allocator-OOM converts to
/// `llm.LlmError.out_of_memory`.
pub fn decodeCompletionResponse(
    allocator: std.mem.Allocator,
    backend: llm.Backend,
    body: []const u8,
) llm.LlmError!CompletionResponse {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return llm.LlmError.schema_violation;
    defer parsed.deinit();
    if (parsed.value != .object) return llm.LlmError.schema_violation;
    const obj = parsed.value.object;

    return switch (backend) {
        .none => llm.LlmError.config_error,
        .local => decodeLocalCompletion(allocator, obj),
        .openai => decodeOpenaiCompletion(allocator, obj),
        .anthropic => decodeAnthropicCompletion(allocator, obj),
    };
}

fn decodeLocalCompletion(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
) llm.LlmError!CompletionResponse {
    const content = obj.get("content") orelse return llm.LlmError.schema_violation;
    if (content != .string) return llm.LlmError.schema_violation;
    const text = allocator.dupe(u8, content.string) catch return llm.LlmError.out_of_memory;
    errdefer allocator.free(text);
    const model_v = obj.get("model");
    const model_str: []const u8 = if (model_v) |v| (if (v == .string) v.string else "") else "";
    const model = allocator.dupe(u8, model_str) catch return llm.LlmError.out_of_memory;
    var tokens: u32 = 0;
    if (obj.get("tokens_predicted")) |v| {
        if (v == .integer and v.integer >= 0 and v.integer <= std.math.maxInt(u32)) {
            tokens = @intCast(v.integer);
        }
    }
    return .{ .text = text, .model = model, .tokens_used = tokens };
}

fn decodeOpenaiCompletion(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
) llm.LlmError!CompletionResponse {
    const choices = obj.get("choices") orelse return llm.LlmError.schema_violation;
    if (choices != .array or choices.array.items.len == 0) return llm.LlmError.schema_violation;
    const first = choices.array.items[0];
    if (first != .object) return llm.LlmError.schema_violation;
    const msg = first.object.get("message") orelse return llm.LlmError.schema_violation;
    if (msg != .object) return llm.LlmError.schema_violation;
    const content = msg.object.get("content") orelse return llm.LlmError.schema_violation;
    if (content != .string) return llm.LlmError.schema_violation;
    const text = allocator.dupe(u8, content.string) catch return llm.LlmError.out_of_memory;
    errdefer allocator.free(text);

    const model_v = obj.get("model");
    const model_str: []const u8 = if (model_v) |v| (if (v == .string) v.string else "") else "";
    const model = allocator.dupe(u8, model_str) catch return llm.LlmError.out_of_memory;

    var tokens: u32 = 0;
    if (obj.get("usage")) |usage| {
        if (usage == .object) {
            if (usage.object.get("total_tokens")) |t| {
                if (t == .integer and t.integer >= 0 and t.integer <= std.math.maxInt(u32)) {
                    tokens = @intCast(t.integer);
                }
            }
        }
    }
    return .{ .text = text, .model = model, .tokens_used = tokens };
}

fn decodeAnthropicCompletion(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
) llm.LlmError!CompletionResponse {
    const content = obj.get("content") orelse return llm.LlmError.schema_violation;
    if (content != .array or content.array.items.len == 0) return llm.LlmError.schema_violation;
    const first = content.array.items[0];
    if (first != .object) return llm.LlmError.schema_violation;
    const text_v = first.object.get("text") orelse return llm.LlmError.schema_violation;
    if (text_v != .string) return llm.LlmError.schema_violation;
    const text = allocator.dupe(u8, text_v.string) catch return llm.LlmError.out_of_memory;
    errdefer allocator.free(text);

    const model_v = obj.get("model");
    const model_str: []const u8 = if (model_v) |v| (if (v == .string) v.string else "") else "";
    const model = allocator.dupe(u8, model_str) catch return llm.LlmError.out_of_memory;

    var tokens: u32 = 0;
    if (obj.get("usage")) |usage| {
        if (usage == .object) {
            // Anthropic surfaces input_tokens + output_tokens separately.
            var sum: i64 = 0;
            if (usage.object.get("input_tokens")) |t| {
                if (t == .integer) sum += t.integer;
            }
            if (usage.object.get("output_tokens")) |t| {
                if (t == .integer) sum += t.integer;
            }
            if (sum >= 0 and sum <= std.math.maxInt(u32)) tokens = @intCast(sum);
        }
    }
    return .{ .text = text, .model = model, .tokens_used = tokens };
}

test "buildCompletionOpenaiBody embeds system + user + max_tokens" {
    const allocator = std.testing.allocator;
    const body = try buildCompletionOpenaiBody(allocator, "gpt-4o", .{
        .prompt = "say hi",
        .system_prompt = "you are terse",
        .max_tokens = 32,
    });
    defer allocator.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    const messages = parsed.value.object.get("messages").?;
    try std.testing.expect(messages == .array and messages.array.items.len == 2);
    try std.testing.expect(parsed.value.object.get("max_tokens").?.integer == 32);
}

test "buildCompletionAnthropicBody omits system when empty" {
    const allocator = std.testing.allocator;
    const body = try buildCompletionAnthropicBody(allocator, "claude-sonnet-4-5", .{
        .prompt = "say hi",
    });
    defer allocator.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expect(parsed.value.object.get("system") == null);
    const messages = parsed.value.object.get("messages").?;
    try std.testing.expect(messages == .array and messages.array.items.len == 1);
}

test "decodeOpenaiCompletion picks first choice content + total_tokens" {
    const allocator = std.testing.allocator;
    var resp = try decodeCompletionResponse(allocator, .openai,
        \\{"model":"gpt-4o","choices":[{"message":{"content":"hello there"}}],"usage":{"total_tokens":17}}
    );
    defer completionResponseDeinit(&resp, allocator);
    try std.testing.expectEqualSlices(u8, "hello there", resp.text);
    try std.testing.expectEqualSlices(u8, "gpt-4o", resp.model);
    try std.testing.expectEqual(@as(u32, 17), resp.tokens_used);
}

test "decodeAnthropicCompletion sums input + output tokens" {
    const allocator = std.testing.allocator;
    var resp = try decodeCompletionResponse(allocator, .anthropic,
        \\{"model":"claude-sonnet-4-5","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":10,"output_tokens":5}}
    );
    defer completionResponseDeinit(&resp, allocator);
    try std.testing.expectEqualSlices(u8, "hi", resp.text);
    try std.testing.expectEqual(@as(u32, 15), resp.tokens_used);
}

test "decodeLocalCompletion handles content + tokens_predicted" {
    const allocator = std.testing.allocator;
    var resp = try decodeCompletionResponse(allocator, .local,
        \\{"content":"local response","tokens_predicted":42}
    );
    defer completionResponseDeinit(&resp, allocator);
    try std.testing.expectEqualSlices(u8, "local response", resp.text);
    try std.testing.expectEqual(@as(u32, 42), resp.tokens_used);
}

// ─────────────────────────────────────────────────────────────────────
// Vision API — image + optional text → text response.
//
// Only the Anthropic backend supports vision.  The local / OpenAI
// backends return config_error until multi-modal support lands there.
//
// The response is decoded exactly like a CompletionResponse (same
// Anthropic Messages shape; the content array still has one text block
// in the reply).  The caller (llm_complete_handler.handleVision) reuses
// `completionResponseDeinit` for cleanup.
// ─────────────────────────────────────────────────────────────────────

pub const VisionRequest = struct {
    /// Base64-encoded image bytes (raw base64, no `data:` URI prefix).
    image_b64: []const u8,
    /// MIME type, e.g. "image/jpeg", "image/png", "image/webp",
    /// "image/gif".  Defaults to "image/jpeg" if empty.
    media_type: []const u8 = "image/jpeg",
    /// Text prompt that accompanies the image.  May be empty.
    prompt: []const u8 = "",
    /// Optional system prompt.  Empty = omit from request body.
    system_prompt: []const u8 = "",
    /// 0 = backend default (1024 for vision).
    max_tokens: u32 = 0,
    /// Negative or NaN = backend default.
    temperature: f32 = -1.0,
};

/// Send an image (and optional text prompt) to the Anthropic Vision
/// API and return the text response as a CompletionResponse.
///
/// Only `.anthropic` backend is supported; other backends return
/// `llm.LlmError.config_error`.  Same trust boundary as `complete()`.
pub fn vision(
    self: *HttpLlmAdapter,
    allocator: std.mem.Allocator,
    req: VisionRequest,
) llm.LlmError!CompletionResponse {
    if (!self.cfg.enabled) return llm.LlmError.config_error;
    if (self.cfg.endpoint.len == 0) return llm.LlmError.config_error;
    // Vision is Anthropic-only for now.
    if (self.cfg.backend != .anthropic) return llm.LlmError.config_error;

    // buildVisionAnthropicBody can only fail with OutOfMemory (all
    // its operations are ArrayList appends / jsonString calls).
    const body = buildVisionAnthropicBody(allocator, self.cfg.model, req) catch
        return llm.LlmError.out_of_memory;
    defer allocator.free(body);

    var resp_writer = std.io.Writer.Allocating.init(allocator);
    defer resp_writer.deinit();

    var headers_buf: [4]std.http.Header = undefined;
    const headers = self.buildHeaders(allocator, &headers_buf) catch |err| switch (err) {
        error.config_error => return llm.LlmError.config_error,
        else => return llm.LlmError.transport_error,
    };
    defer freeAuthHeader(allocator, headers);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const result = client.fetch(.{
        .location = .{ .url = self.cfg.endpoint },
        .method = .POST,
        .payload = body,
        .extra_headers = headers,
        .response_writer = &resp_writer.writer,
    }) catch return llm.LlmError.transport_error;

    switch (result.status) {
        .ok => {},
        .too_many_requests => return llm.LlmError.rate_limited,
        .unauthorized, .forbidden => return llm.LlmError.config_error,
        else => return llm.LlmError.transport_error,
    }

    // Response shape is identical to a text completion — Anthropic
    // returns `{"content":[{"type":"text","text":"..."}],"model":"...",
    // "usage":{"input_tokens":N,"output_tokens":M}}`.
    return decodeCompletionResponse(allocator, .anthropic, resp_writer.written());
}

/// Build the Anthropic Messages API body for a vision request.
/// Content is a multipart array: one image block + an optional text block.
pub fn buildVisionAnthropicBody(
    allocator: std.mem.Allocator,
    model: []const u8,
    req: VisionRequest,
) ![]u8 {
    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"model\":");
    try jsonString(allocator, &body, model);
    const max_tokens: u32 = if (req.max_tokens == 0) 1024 else req.max_tokens;
    try body.print(allocator, ",\"max_tokens\":{d}", .{max_tokens});
    if (req.system_prompt.len > 0) {
        try body.appendSlice(allocator, ",\"system\":");
        try jsonString(allocator, &body, req.system_prompt);
    }
    if (req.temperature >= 0) {
        try body.print(allocator, ",\"temperature\":{d}", .{req.temperature});
    }
    // messages[0].content = array of image block + optional text block.
    try body.appendSlice(allocator, ",\"messages\":[{\"role\":\"user\",\"content\":[");
    // Image block.
    const media_type = if (req.media_type.len > 0) req.media_type else "image/jpeg";
    try body.appendSlice(allocator, "{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":");
    try jsonString(allocator, &body, media_type);
    try body.appendSlice(allocator, ",\"data\":");
    try jsonString(allocator, &body, req.image_b64);
    try body.appendSlice(allocator, "}}");
    // Optional text block.
    if (req.prompt.len > 0) {
        try body.appendSlice(allocator, ",{\"type\":\"text\",\"text\":");
        try jsonString(allocator, &body, req.prompt);
        try body.append(allocator, '}');
    }
    try body.appendSlice(allocator, "]}]}");
    return body.toOwnedSlice(allocator);
}

test "buildVisionAnthropicBody emits image + text blocks" {
    const allocator = std.testing.allocator;
    const body = try buildVisionAnthropicBody(allocator, "claude-haiku-4-5", .{
        .image_b64 = "aGVsbG8=",
        .media_type = "image/jpeg",
        .prompt = "What is in this image?",
        .system_prompt = "You are a receipt analyser.",
        .max_tokens = 512,
    });
    defer allocator.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    // model
    const m = parsed.value.object.get("model").?;
    try std.testing.expectEqualSlices(u8, "claude-haiku-4-5", m.string);
    // max_tokens
    try std.testing.expectEqual(@as(i64, 512), parsed.value.object.get("max_tokens").?.integer);
    // system
    const sys = parsed.value.object.get("system").?;
    try std.testing.expectEqualSlices(u8, "You are a receipt analyser.", sys.string);
    // messages[0].content array
    const msgs = parsed.value.object.get("messages").?;
    try std.testing.expect(msgs == .array and msgs.array.items.len == 1);
    const content = msgs.array.items[0].object.get("content").?;
    try std.testing.expect(content == .array and content.array.items.len == 2);
    // First block = image
    const img_block = content.array.items[0];
    try std.testing.expectEqualSlices(u8, "image", img_block.object.get("type").?.string);
    const src = img_block.object.get("source").?;
    try std.testing.expectEqualSlices(u8, "base64", src.object.get("type").?.string);
    try std.testing.expectEqualSlices(u8, "image/jpeg", src.object.get("media_type").?.string);
    try std.testing.expectEqualSlices(u8, "aGVsbG8=", src.object.get("data").?.string);
    // Second block = text
    const txt_block = content.array.items[1];
    try std.testing.expectEqualSlices(u8, "text", txt_block.object.get("type").?.string);
    try std.testing.expectEqualSlices(u8, "What is in this image?", txt_block.object.get("text").?.string);
}

test "buildVisionAnthropicBody omits text block when prompt is empty" {
    const allocator = std.testing.allocator;
    const body = try buildVisionAnthropicBody(allocator, "claude-haiku-4-5", .{
        .image_b64 = "aGVsbG8=",
        .media_type = "image/png",
    });
    defer allocator.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const msgs = parsed.value.object.get("messages").?;
    const content = msgs.array.items[0].object.get("content").?;
    // Only one block (image), no text
    try std.testing.expect(content.array.items.len == 1);
    try std.testing.expectEqualSlices(u8, "image", content.array.items[0].object.get("type").?.string);
}

test "buildVisionAnthropicBody defaults media_type to image/jpeg when empty" {
    const allocator = std.testing.allocator;
    const body = try buildVisionAnthropicBody(allocator, "claude-haiku-4-5", .{
        .image_b64 = "aGVsbG8=",
        .media_type = "",
    });
    defer allocator.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const msgs = parsed.value.object.get("messages").?;
    const content = msgs.array.items[0].object.get("content").?;
    const src = content.array.items[0].object.get("source").?;
    try std.testing.expectEqualSlices(u8, "image/jpeg", src.object.get("media_type").?.string);
}

```
