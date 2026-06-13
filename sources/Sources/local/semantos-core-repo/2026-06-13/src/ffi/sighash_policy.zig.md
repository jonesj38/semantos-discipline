---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/sighash_policy.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.401984+00:00
---

# src/ffi/sighash_policy.zig

```zig
// Semantos FFI — SIGHASH Policy Engine
// Maps FSM transitions to SIGHASH flags + algorithm via vertical config JSON.
// Pure lookup, no I/O. Loaded at kernel init from the config's sighashPolicy block.

const std = @import("std");
const sighash = @import("sighash");

pub const SighashResult = struct {
    flags: u8,
    algorithm: sighash.SighashAlgorithm,
};

pub const MAX_RULES = 64;
const MAX_NAME_LEN = 64;

pub const PolicyRule = struct {
    from_state: [MAX_NAME_LEN]u8,
    from_state_len: u8,
    to_state: [MAX_NAME_LEN]u8,
    to_state_len: u8,
    role: [MAX_NAME_LEN]u8,
    role_len: u8,
    flags: u8,
    algorithm: sighash.SighashAlgorithm,
    linear: bool,

    fn fromSlice(self: *const PolicyRule) []const u8 {
        return self.from_state[0..self.from_state_len];
    }
    fn toSlice(self: *const PolicyRule) []const u8 {
        return self.to_state[0..self.to_state_len];
    }
    fn roleSlice(self: *const PolicyRule) []const u8 {
        return self.role[0..self.role_len];
    }
};

pub const PolicyError = error{
    invalid_json,
    missing_field,
    too_many_rules,
    invalid_sighash_string,
    forkid_original_conflict,
    name_too_long,
};

pub const SighashPolicy = struct {
    rules: [MAX_RULES]PolicyRule,
    rule_count: u32,
    genesis_sighash: SighashResult,

    pub fn init() SighashPolicy {
        return .{
            .rules = undefined,
            .rule_count = 0,
            .genesis_sighash = .{
                .flags = sighash.SIGHASH_ALL | sighash.SIGHASH_FORKID,
                .algorithm = .bip143,
            },
        };
    }

    /// Load policy from vertical config JSON.
    /// Expected shape:
    /// {
    ///   "sighashPolicy": {
    ///     "genesis": "ALL|FORKID",
    ///     "transitions": [
    ///       { "from": "new", "to": "dispatched", "role": "pm",
    ///         "sighash": "SINGLE|ACP|FORKID", "algorithm": "bip143", "linear": false }
    ///     ]
    ///   }
    /// }
    pub fn loadFromJson(json: []const u8) PolicyError!SighashPolicy {
        var policy = SighashPolicy.init();

        const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, json, .{}) catch {
            return error.invalid_json;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.invalid_json;

        const sp_val = root.object.get("sighashPolicy") orelse return error.missing_field;
        if (sp_val != .object) return error.invalid_json;
        const sp = sp_val.object;

        // Parse genesis sighash
        if (sp.get("genesis")) |genesis_val| {
            if (genesis_val != .string) return error.invalid_json;
            const genesis_flags = try parseSighashFlags(genesis_val.string);
            const genesis_algo = parseAlgorithm(sp.get("genesisAlgorithm"));
            // Validate FORKID/algorithm consistency
            if (genesis_algo == .original and (genesis_flags & sighash.SIGHASH_FORKID != 0)) {
                return error.forkid_original_conflict;
            }
            policy.genesis_sighash = .{ .flags = genesis_flags, .algorithm = genesis_algo };
        }

        // Parse transitions
        const transitions_val = sp.get("transitions") orelse return error.missing_field;
        if (transitions_val != .array) return error.invalid_json;

        for (transitions_val.array.items) |item| {
            if (item != .object) return error.invalid_json;
            if (policy.rule_count >= MAX_RULES) return error.too_many_rules;

            const from = getStr(item.object.get("from")) orelse return error.missing_field;
            const to = getStr(item.object.get("to")) orelse return error.missing_field;
            const role = getStr(item.object.get("role")) orelse return error.missing_field;
            const sighash_str = getStr(item.object.get("sighash")) orelse return error.missing_field;

            if (from.len > MAX_NAME_LEN or to.len > MAX_NAME_LEN or role.len > MAX_NAME_LEN) {
                return error.name_too_long;
            }

            const flags = try parseSighashFlags(sighash_str);
            const algo = parseAlgorithm(item.object.get("algorithm"));

            // Validate: original algorithm must NOT have FORKID
            if (algo == .original and (flags & sighash.SIGHASH_FORKID != 0)) {
                return error.forkid_original_conflict;
            }

            const linear = if (item.object.get("linear")) |l| (l == .bool and l.bool) else false;

            var rule: PolicyRule = undefined;
            @memset(&rule.from_state, 0);
            @memset(&rule.to_state, 0);
            @memset(&rule.role, 0);
            @memcpy(rule.from_state[0..from.len], from);
            rule.from_state_len = @intCast(from.len);
            @memcpy(rule.to_state[0..to.len], to);
            rule.to_state_len = @intCast(to.len);
            @memcpy(rule.role[0..role.len], role);
            rule.role_len = @intCast(role.len);
            rule.flags = flags;
            rule.algorithm = algo;
            rule.linear = linear;

            policy.rules[policy.rule_count] = rule;
            policy.rule_count += 1;
        }

        return policy;
    }

    /// Look up SIGHASH result for a state transition.
    /// Returns null if the transition is not permitted (caller treats as FSM violation).
    pub fn lookupSighash(self: *const SighashPolicy, from: []const u8, to: []const u8, role: []const u8) ?SighashResult {
        var i: u32 = 0;
        while (i < self.rule_count) : (i += 1) {
            const rule = &self.rules[i];
            if (std.mem.eql(u8, rule.fromSlice(), from) and
                std.mem.eql(u8, rule.toSlice(), to) and
                std.mem.eql(u8, rule.roleSlice(), role))
            {
                return .{ .flags = rule.flags, .algorithm = rule.algorithm };
            }
        }
        return null;
    }

    /// Check if a transition consumes a LINEAR capability.
    pub fn isLinear(self: *const SighashPolicy, from: []const u8, to: []const u8) bool {
        var i: u32 = 0;
        while (i < self.rule_count) : (i += 1) {
            const rule = &self.rules[i];
            if (std.mem.eql(u8, rule.fromSlice(), from) and
                std.mem.eql(u8, rule.toSlice(), to))
            {
                return rule.linear;
            }
        }
        return false;
    }
};

// ── SIGHASH flag string parser ──

/// Parse pipe-separated SIGHASH flag names into a byte.
/// "SINGLE|ACP|FORKID" → 0x03 | 0x80 | 0x40 = 0xC3
fn parseSighashFlags(s: []const u8) PolicyError!u8 {
    var flags: u8 = 0;
    var start: usize = 0;
    var i: usize = 0;

    while (i <= s.len) : (i += 1) {
        if (i == s.len or s[i] == '|') {
            const token = s[start..i];
            if (std.mem.eql(u8, token, "ALL")) {
                flags |= sighash.SIGHASH_ALL;
            } else if (std.mem.eql(u8, token, "NONE")) {
                flags |= sighash.SIGHASH_NONE;
            } else if (std.mem.eql(u8, token, "SINGLE")) {
                flags |= sighash.SIGHASH_SINGLE;
            } else if (std.mem.eql(u8, token, "ACP") or std.mem.eql(u8, token, "ANYONECANPAY")) {
                flags |= sighash.SIGHASH_ANYONECANPAY;
            } else if (std.mem.eql(u8, token, "FORKID")) {
                flags |= sighash.SIGHASH_FORKID;
            } else {
                return error.invalid_sighash_string;
            }
            start = i + 1;
        }
    }
    return flags;
}

fn parseAlgorithm(val: ?std.json.Value) sighash.SighashAlgorithm {
    if (val) |v| {
        if (v == .string) {
            if (std.mem.eql(u8, v.string, "original")) return .original;
        }
    }
    return .bip143; // default
}

fn getStr(val: ?std.json.Value) ?[]const u8 {
    if (val) |v| {
        if (v == .string) return v.string;
    }
    return null;
}

// ── Tests ──

const test_config =
    \\{
    \\  "sighashPolicy": {
    \\    "genesis": "ALL|FORKID",
    \\    "transitions": [
    \\      {"from": "new", "to": "dispatched", "role": "pm", "sighash": "SINGLE|ACP|FORKID"},
    \\      {"from": "dispatched", "to": "in_progress", "role": "executor", "sighash": "SINGLE|ACP|FORKID"},
    \\      {"from": "in_progress", "to": "completed", "role": "executor", "sighash": "ALL|FORKID"},
    \\      {"from": "completed", "to": "approved", "role": "approver", "sighash": "ALL|FORKID", "linear": true}
    \\    ]
    \\  }
    \\}
;

test "T5: PM dispatch → SINGLE|ACP|FORKID bip143" {
    const policy = try SighashPolicy.loadFromJson(test_config);
    const result = policy.lookupSighash("new", "dispatched", "pm");
    try std.testing.expect(result != null);
    // SINGLE=0x03, ACP=0x80, FORKID=0x40 → 0xC3
    try std.testing.expectEqual(@as(u8, 0xC3), result.?.flags);
    try std.testing.expectEqual(sighash.SighashAlgorithm.bip143, result.?.algorithm);
}

test "T6: approval → ALL|FORKID bip143" {
    const policy = try SighashPolicy.loadFromJson(test_config);
    const result = policy.lookupSighash("completed", "approved", "approver");
    try std.testing.expect(result != null);
    // ALL=0x01, FORKID=0x40 → 0x41
    try std.testing.expectEqual(@as(u8, 0x41), result.?.flags);
    try std.testing.expectEqual(sighash.SighashAlgorithm.bip143, result.?.algorithm);
}

test "T7: unknown transition → null" {
    const policy = try SighashPolicy.loadFromJson(test_config);
    const result = policy.lookupSighash("new", "completed", "pm");
    try std.testing.expect(result == null);
}

test "T8: different vertical, different SIGHASH" {
    const alt_config =
        \\{
        \\  "sighashPolicy": {
        \\    "genesis": "ALL|FORKID",
        \\    "transitions": [
        \\      {"from": "new", "to": "dispatched", "role": "pm", "sighash": "ALL|FORKID"}
        \\    ]
        \\  }
        \\}
    ;
    const policy1 = try SighashPolicy.loadFromJson(test_config);
    const policy2 = try SighashPolicy.loadFromJson(alt_config);

    const r1 = policy1.lookupSighash("new", "dispatched", "pm").?;
    const r2 = policy2.lookupSighash("new", "dispatched", "pm").?;

    // Same transition name, different SIGHASH in each vertical
    try std.testing.expectEqual(@as(u8, 0xC3), r1.flags); // SINGLE|ACP|FORKID
    try std.testing.expectEqual(@as(u8, 0x41), r2.flags); // ALL|FORKID
}

test "T35: original algorithm rule returns algorithm=original" {
    const chronicle_config =
        \\{
        \\  "sighashPolicy": {
        \\    "genesis": "ALL|FORKID",
        \\    "transitions": [
        \\      {"from": "new", "to": "dispatched", "role": "pm", "sighash": "ALL", "algorithm": "original"},
        \\      {"from": "dispatched", "to": "done", "role": "pm", "sighash": "ALL|FORKID"}
        \\    ]
        \\  }
        \\}
    ;
    const policy = try SighashPolicy.loadFromJson(chronicle_config);

    // Rule with algorithm=original
    const r1 = policy.lookupSighash("new", "dispatched", "pm").?;
    try std.testing.expectEqual(sighash.SighashAlgorithm.original, r1.algorithm);
    try std.testing.expectEqual(@as(u8, 0x01), r1.flags); // ALL without FORKID

    // Rule without algorithm field → defaults to bip143
    const r2 = policy.lookupSighash("dispatched", "done", "pm").?;
    try std.testing.expectEqual(sighash.SighashAlgorithm.bip143, r2.algorithm);
}

test "FORKID + original algorithm rejected at load time" {
    const bad_config =
        \\{
        \\  "sighashPolicy": {
        \\    "genesis": "ALL|FORKID",
        \\    "transitions": [
        \\      {"from": "a", "to": "b", "role": "r", "sighash": "ALL|FORKID", "algorithm": "original"}
        \\    ]
        \\  }
        \\}
    ;
    const result = SighashPolicy.loadFromJson(bad_config);
    try std.testing.expectError(error.forkid_original_conflict, result);
}

test "isLinear returns true for linear transitions" {
    const policy = try SighashPolicy.loadFromJson(test_config);
    try std.testing.expect(policy.isLinear("completed", "approved"));
    try std.testing.expect(!policy.isLinear("new", "dispatched"));
}

test "genesis sighash parsed from config" {
    const policy = try SighashPolicy.loadFromJson(test_config);
    try std.testing.expectEqual(@as(u8, 0x41), policy.genesis_sighash.flags);
    try std.testing.expectEqual(sighash.SighashAlgorithm.bip143, policy.genesis_sighash.algorithm);
}

```
