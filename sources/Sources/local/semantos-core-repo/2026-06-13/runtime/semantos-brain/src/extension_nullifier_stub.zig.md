---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/extension_nullifier_stub.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.237596+00:00
---

# runtime/semantos-brain/src/extension_nullifier_stub.zig

```zig
// Phase D-W2 Phase 3 — extension_nullifier stub (built when bsvz is
// unavailable, mirroring extension_publish_stub.zig).
//
// Pure-Zig functions that don't touch bsvz (encode/decode, digest
// construction, manifest text rewrite, revoked-keys index) are
// implemented identically to the canonical module.  The signing +
// signature-verification primitives that need bsvz return
// `error.bsvz_unavailable` / `error.bad_rotation_authority_signature`.
//
// Source-of-truth comments live in `extension_nullifier.zig` (the
// canonical module).  This stub mirrors the public surface only.

const std = @import("std");
const tenant_manifest = @import("tenant_manifest");
const audit_log = @import("audit_log");
const ext_pub = @import("extension_publish");
// D-W2 Phase 4 — same wiring as the canonical module so callers
// have a stable surface in either build mode.
const quarantine_mod = @import("extension_quarantine");
const dispatcher_mod = @import("dispatcher");

pub const PAYLOAD_VERSION_TAG: []const u8 = "extension-nullifier-v1";
pub const SHARD_GROUP_PREFIX: []const u8 = "extension-nullifier:";
pub const PUBKEY_LEN: usize = 33;
pub const SIG_LEN: usize = 64;
pub const TXID_LEN: usize = 32;
pub const MAX_PAYLOAD_LEN: usize = PAYLOAD_VERSION_TAG.len + PUBKEY_LEN + 1 + 8 + 1 + PUBKEY_LEN + SIG_LEN;
pub const MIN_PAYLOAD_LEN: usize = PAYLOAD_VERSION_TAG.len + PUBKEY_LEN + 1 + 8 + 1;

pub const CodecError = error{
    payload_too_small,
    payload_too_large,
    payload_bad_tag,
    payload_truncated,
    payload_bad_reason_code,
    payload_bad_replacement_flag,
    out_of_memory,
};

pub const VerifyError = error{
    unknown_target_signer,
    bad_rotation_authority_signature,
    missing_replacement_for_rotation,
    missing_rotation_authority,
    out_of_memory,
};

pub const ApplyError = error{
    manifest_open_failed,
    manifest_read_failed,
    manifest_write_failed,
    manifest_signer_not_found,
    revoked_index_io_failed,
    bad_manifest_text,
    out_of_memory,
};

pub const ReasonCode = enum(u8) {
    compromised = 0,
    superseded = 1,
    voluntary = 2,
    breach = 3,

    pub fn fromByte(b: u8) ?ReasonCode {
        return switch (b) {
            0 => .compromised,
            1 => .superseded,
            2 => .voluntary,
            3 => .breach,
            else => null,
        };
    }

    pub fn name(self: ReasonCode) []const u8 {
        return switch (self) {
            .compromised => "compromised",
            .superseded => "superseded",
            .voluntary => "voluntary",
            .breach => "breach",
        };
    }
};

pub fn parseReasonCode(s: []const u8) ?ReasonCode {
    if (std.mem.eql(u8, s, "compromised")) return .compromised;
    if (std.mem.eql(u8, s, "superseded")) return .superseded;
    if (std.mem.eql(u8, s, "voluntary")) return .voluntary;
    if (std.mem.eql(u8, s, "breach")) return .breach;
    return null;
}

pub const NullifierPayload = struct {
    revoked_pubkey: [PUBKEY_LEN]u8,
    reason_code: ReasonCode,
    timestamp: u64,
    replacement_pubkey: ?[PUBKEY_LEN]u8 = null,
    rotation_authority_signature: ?[SIG_LEN]u8 = null,

    pub fn isRotation(self: NullifierPayload) bool {
        return self.replacement_pubkey != null;
    }
};

pub const VerifiedNullifier = struct {
    payload: NullifierPayload,
    target_signer_name: []const u8,
    rotation_authority_label: []const u8 = "",
};

pub const RecoveryAuthorityLookup = struct {
    state: ?*anyopaque,
    lookup_fn: *const fn (state: ?*anyopaque, recovery_enrolment_id: []const u8) ?[PUBKEY_LEN]u8,

    pub fn lookup(self: RecoveryAuthorityLookup, recovery_enrolment_id: []const u8) ?[PUBKEY_LEN]u8 {
        return self.lookup_fn(self.state, recovery_enrolment_id);
    }
};

fn writeU64Be(buf: *[8]u8, v: u64) void {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        buf[i] = @intCast((v >> @intCast(8 * (7 - i))) & 0xff);
    }
}

fn readU64Be(bytes: *const [8]u8) u64 {
    var v: u64 = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        v = (v << 8) | @as(u64, bytes[i]);
    }
    return v;
}

pub fn encodeNullifierPayload(
    allocator: std.mem.Allocator,
    p: NullifierPayload,
) CodecError![]u8 {
    const has_replacement = p.replacement_pubkey != null;
    if (has_replacement and p.rotation_authority_signature == null) {
        return error.payload_bad_replacement_flag;
    }
    const total: usize = if (has_replacement) MAX_PAYLOAD_LEN else MIN_PAYLOAD_LEN;
    const buf = allocator.alloc(u8, total) catch return error.out_of_memory;
    var i: usize = 0;
    @memcpy(buf[i .. i + PAYLOAD_VERSION_TAG.len], PAYLOAD_VERSION_TAG);
    i += PAYLOAD_VERSION_TAG.len;
    @memcpy(buf[i .. i + PUBKEY_LEN], &p.revoked_pubkey);
    i += PUBKEY_LEN;
    buf[i] = @intFromEnum(p.reason_code);
    i += 1;
    var ts_buf: [8]u8 = undefined;
    writeU64Be(&ts_buf, p.timestamp);
    @memcpy(buf[i .. i + 8], &ts_buf);
    i += 8;
    buf[i] = if (has_replacement) 1 else 0;
    i += 1;
    if (has_replacement) {
        @memcpy(buf[i .. i + PUBKEY_LEN], &p.replacement_pubkey.?);
        i += PUBKEY_LEN;
        @memcpy(buf[i .. i + SIG_LEN], &p.rotation_authority_signature.?);
        i += SIG_LEN;
    }
    std.debug.assert(i == total);
    return buf;
}

pub fn decodeNullifierPayload(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) CodecError!NullifierPayload {
    _ = allocator;
    if (bytes.len < MIN_PAYLOAD_LEN) return error.payload_too_small;
    if (bytes.len > MAX_PAYLOAD_LEN) return error.payload_too_large;

    var off: usize = 0;
    if (!std.mem.eql(u8, bytes[off .. off + PAYLOAD_VERSION_TAG.len], PAYLOAD_VERSION_TAG)) {
        return error.payload_bad_tag;
    }
    off += PAYLOAD_VERSION_TAG.len;

    var revoked: [PUBKEY_LEN]u8 = undefined;
    @memcpy(&revoked, bytes[off .. off + PUBKEY_LEN]);
    off += PUBKEY_LEN;

    const reason = ReasonCode.fromByte(bytes[off]) orelse return error.payload_bad_reason_code;
    off += 1;

    var ts_buf: [8]u8 = undefined;
    @memcpy(&ts_buf, bytes[off .. off + 8]);
    const ts = readU64Be(&ts_buf);
    off += 8;

    const has = bytes[off];
    if (has != 0 and has != 1) return error.payload_bad_replacement_flag;
    off += 1;

    if (has == 0) {
        if (bytes.len != MIN_PAYLOAD_LEN) return error.payload_truncated;
        return .{
            .revoked_pubkey = revoked,
            .reason_code = reason,
            .timestamp = ts,
        };
    }

    if (bytes.len != MAX_PAYLOAD_LEN) return error.payload_truncated;
    var replacement: [PUBKEY_LEN]u8 = undefined;
    @memcpy(&replacement, bytes[off .. off + PUBKEY_LEN]);
    off += PUBKEY_LEN;
    var sig: [SIG_LEN]u8 = undefined;
    @memcpy(&sig, bytes[off .. off + SIG_LEN]);
    off += SIG_LEN;

    return .{
        .revoked_pubkey = revoked,
        .reason_code = reason,
        .timestamp = ts,
        .replacement_pubkey = replacement,
        .rotation_authority_signature = sig,
    };
}

pub fn rotationAuthoritySignDigest(
    revoked: [PUBKEY_LEN]u8,
    replacement: [PUBKEY_LEN]u8,
    timestamp: u64,
) [32]u8 {
    var ts_buf: [8]u8 = undefined;
    writeU64Be(&ts_buf, timestamp);
    var first: [32]u8 = undefined;
    {
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        h.update(&revoked);
        h.update(&replacement);
        h.update(&ts_buf);
        h.final(&first);
    }
    var second: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&first, &second, .{});
    return second;
}

// ── Tx construction + broadcast — re-exported from ext_pub stub ──

pub const FundingUtxo = ext_pub.FundingUtxo;
pub const BuiltTx = ext_pub.BuiltTx;
pub const freeBuiltTx = ext_pub.freeBuiltTx;
pub const BroadcastOutcome = ext_pub.BroadcastOutcome;
pub const freeBroadcastOutcome = ext_pub.freeBroadcastOutcome;
pub const broadcastViaArc = ext_pub.broadcastViaArc;
pub const DEFAULT_ARC_URL = ext_pub.DEFAULT_ARC_URL;

pub fn buildNullifierTx(
    allocator: std.mem.Allocator,
    payload: NullifierPayload,
    signer_priv: [32]u8,
    utxo: FundingUtxo,
    change_address_text: []const u8,
    fee_sats_per_kb_opt: u64,
) ext_pub.PublishError!BuiltTx {
    _ = allocator;
    _ = payload;
    _ = signer_priv;
    _ = utxo;
    _ = change_address_text;
    _ = fee_sats_per_kb_opt;
    return error.bsvz_unavailable;
}

// ── Stub-only signing/verification primitives ──

pub fn signRotationAuthority(
    authority_priv: [32]u8,
    revoked: [PUBKEY_LEN]u8,
    replacement: [PUBKEY_LEN]u8,
    timestamp: u64,
) ext_pub.PublishError![SIG_LEN]u8 {
    _ = authority_priv;
    _ = revoked;
    _ = replacement;
    _ = timestamp;
    return error.bsvz_unavailable;
}

pub fn verifyRotationAuthoritySignature(
    authority_pubkey: [PUBKEY_LEN]u8,
    revoked: [PUBKEY_LEN]u8,
    replacement: [PUBKEY_LEN]u8,
    timestamp: u64,
    signature: [SIG_LEN]u8,
) VerifyError!void {
    _ = authority_pubkey;
    _ = revoked;
    _ = replacement;
    _ = timestamp;
    _ = signature;
    return error.bad_rotation_authority_signature;
}

pub fn verifyNullifier(
    payload: NullifierPayload,
    manifest_signers: []const tenant_manifest.TrustedSigner,
    recovery_authority: RecoveryAuthorityLookup,
) VerifyError!VerifiedNullifier {
    _ = recovery_authority;
    const target_signer = findSignerByPubkey(manifest_signers, payload.revoked_pubkey) orelse
        return error.unknown_target_signer;

    if (payload.replacement_pubkey == null) {
        if (payload.rotation_authority_signature != null) {
            return error.missing_replacement_for_rotation;
        }
        return .{
            .payload = payload,
            .target_signer_name = target_signer.name,
        };
    }

    return error.bad_rotation_authority_signature;
}

fn findSignerByPubkey(
    signers: []const tenant_manifest.TrustedSigner,
    pubkey: [PUBKEY_LEN]u8,
) ?tenant_manifest.TrustedSigner {
    for (signers) |s| {
        const sp = parseHexPubkey(s.pubkey_hex) catch continue;
        if (std.mem.eql(u8, &sp, &pubkey)) return s;
    }
    return null;
}

fn parseHexPubkey(hex: []const u8) !([PUBKEY_LEN]u8) {
    if (hex.len != PUBKEY_LEN * 2) return error.bad_pubkey_hex;
    var out: [PUBKEY_LEN]u8 = undefined;
    var i: usize = 0;
    while (i < PUBKEY_LEN) : (i += 1) {
        const hi = hexNibble(hex[i * 2]) orelse return error.bad_pubkey_hex;
        const lo = hexNibble(hex[i * 2 + 1]) orelse return error.bad_pubkey_hex;
        out[i] = (hi << 4) | lo;
    }
    return out;
}

fn hexNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn hexEncode(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

// ── applyNullifier — pure text + filesystem; no bsvz needed ──

pub const ApplyMode = enum { applied, already_applied };

pub const ApplyOutcome = struct {
    mode: ApplyMode,
    promoted_replacement: bool,
    signer_name: []const u8,
    new_manifest_text: []u8 = &.{},
    /// D-W2 Phase 4 — count of extensions transitioned to quarantine
    /// (or hard-removed when `quarantine_on_revoke = false`).
    quarantined: u32 = 0,

    pub fn deinit(self: *ApplyOutcome, allocator: std.mem.Allocator) void {
        if (self.new_manifest_text.len > 0) {
            allocator.free(self.new_manifest_text);
            self.new_manifest_text = &.{};
        }
    }
};

pub fn applyNullifier(
    allocator: std.mem.Allocator,
    vn: VerifiedNullifier,
    manifest_path: []const u8,
    revoked_keys_index_path: []const u8,
    audit: ?*audit_log.AuditLog,
) ApplyError!ApplyOutcome {
    const already = try revokedKeysIndexContains(allocator, revoked_keys_index_path, vn.payload.revoked_pubkey);
    if (already) {
        if (audit) |a| {
            var detail_buf: [256]u8 = undefined;
            const detail = std.fmt.bufPrint(
                &detail_buf,
                "phase=apply_skip kind=idempotent signer={s} reason={s}",
                .{ vn.target_signer_name, vn.payload.reason_code.name() },
            ) catch detail_buf[0..0];
            a.record(allocator, .{
                .module = "extension_nullifier",
                .op = "extension.nullifier_apply",
                .result = .ok,
                .detail = detail,
            }) catch {};
        }
        return .{
            .mode = .already_applied,
            .promoted_replacement = false,
            .signer_name = vn.target_signer_name,
        };
    }

    const manifest_text = readFileAlloc(allocator, manifest_path, 256 * 1024) catch
        return error.manifest_open_failed;
    defer allocator.free(manifest_text);

    const rewrite = if (vn.payload.replacement_pubkey) |rp|
        rewriteForRotation(allocator, manifest_text, vn.target_signer_name, rp) catch |e| return mapRewriteErr(e)
    else
        rewriteForRevocation(allocator, manifest_text, vn.target_signer_name) catch |e| return mapRewriteErr(e);
    errdefer allocator.free(rewrite);

    try writeFileAtomic(allocator, manifest_path, rewrite);
    try appendRevokedKey(allocator, revoked_keys_index_path, vn);

    if (audit) |a| {
        var detail_buf: [256]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "phase=apply mode={s} signer={s} reason={s} ts={d}",
            .{
                if (vn.payload.replacement_pubkey != null) "rotation" else "revocation",
                vn.target_signer_name,
                vn.payload.reason_code.name(),
                vn.payload.timestamp,
            },
        ) catch detail_buf[0..0];
        a.record(allocator, .{
            .module = "extension_nullifier",
            .op = "extension.nullifier_apply",
            .result = .ok,
            .detail = detail,
        }) catch {};
        if (std.mem.eql(u8, vn.target_signer_name, "platform")) {
            var crit_buf: [256]u8 = undefined;
            const crit = std.fmt.bufPrint(
                &crit_buf,
                "phase=critical kind=platform_tier_revocation signer=platform reason={s} replacement_present={s}",
                .{
                    vn.payload.reason_code.name(),
                    if (vn.payload.replacement_pubkey != null) "true" else "false",
                },
            ) catch crit_buf[0..0];
            a.record(allocator, .{
                .module = "extension_nullifier",
                .op = "extension.platform_tier_revoked",
                .result = .denied,
                .detail = crit,
            }) catch {};
        }
    }

    return .{
        .mode = .applied,
        .promoted_replacement = vn.payload.replacement_pubkey != null,
        .signer_name = vn.target_signer_name,
        .new_manifest_text = rewrite,
    };
}

/// D-W2 Phase 4 — apply with the post-mutation quarantine hook.
/// Mirror of the canonical module's wrapper.
pub fn applyNullifierWithQuarantine(
    allocator: std.mem.Allocator,
    vn: VerifiedNullifier,
    manifest_path: []const u8,
    revoked_keys_index_path: []const u8,
    data_dir: []const u8,
    dispatcher: ?*dispatcher_mod.Dispatcher,
    quarantine_on_revoke: bool,
    audit: ?*audit_log.AuditLog,
) ApplyError!ApplyOutcome {
    var outcome = try applyNullifier(allocator, vn, manifest_path, revoked_keys_index_path, audit);
    if (outcome.mode == .already_applied) return outcome;

    var revoked_hex: [PUBKEY_LEN * 2]u8 = undefined;
    hexEncode(&vn.payload.revoked_pubkey, &revoked_hex);

    const affected = quarantine_mod.quarantineExtensionsBySigner(
        allocator,
        data_dir,
        &revoked_hex,
        vn.target_signer_name,
        quarantine_on_revoke,
        dispatcher,
        audit,
    ) catch |err| switch (err) {
        else => {
            if (audit) |a| {
                var detail_buf: [256]u8 = undefined;
                const detail = std.fmt.bufPrint(
                    &detail_buf,
                    "phase=apply_quarantine_warn signer={s} err={s}",
                    .{ vn.target_signer_name, @errorName(err) },
                ) catch detail_buf[0..0];
                a.record(allocator, .{
                    .module = "extension_nullifier",
                    .op = "extension.quarantine_walk",
                    .result = .err,
                    .detail = detail,
                }) catch {};
            }
            return outcome;
        },
    };

    outcome.quarantined = affected;

    if (audit) |a| {
        var detail_buf: [256]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "phase=apply_quarantine signer={s} affected={d} mode={s}",
            .{
                vn.target_signer_name,
                affected,
                if (quarantine_on_revoke) "quarantine" else "hard_remove",
            },
        ) catch detail_buf[0..0];
        a.record(allocator, .{
            .module = "extension_nullifier",
            .op = "extension.quarantine_walk",
            .result = .ok,
            .detail = detail,
        }) catch {};
    }

    return outcome;
}

fn mapRewriteErr(e: anyerror) ApplyError {
    return switch (e) {
        error.signer_not_found => error.manifest_signer_not_found,
        error.bad_manifest_text => error.bad_manifest_text,
        error.OutOfMemory => error.out_of_memory,
        else => error.bad_manifest_text,
    };
}

const RewriteError = error{
    signer_not_found,
    bad_manifest_text,
    OutOfMemory,
};

fn rewriteForRevocation(
    allocator: std.mem.Allocator,
    text: []const u8,
    signer_name: []const u8,
) RewriteError![]u8 {
    const section = try findSignerSection(text, signer_name);
    if (section == null) return error.signer_not_found;
    const range = section.?;

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, text[0..range.start]);
    try buf.appendSlice(allocator, text[range.end..]);

    while (buf.items.len > 0 and (buf.items[buf.items.len - 1] == '\n' or buf.items[buf.items.len - 1] == ' ')) {
        _ = buf.pop();
    }
    try buf.appendSlice(allocator, "\n\n# nullifier-applied: revoked trusted_signers.");
    try buf.appendSlice(allocator, signer_name);
    try buf.appendSlice(allocator, " (pure revocation)\n");

    return buf.toOwnedSlice(allocator);
}

fn rewriteForRotation(
    allocator: std.mem.Allocator,
    text: []const u8,
    signer_name: []const u8,
    replacement_pubkey: [PUBKEY_LEN]u8,
) RewriteError![]u8 {
    const section = try findSignerSection(text, signer_name);
    if (section == null) return error.signer_not_found;
    const range = section.?;

    const section_text = text[range.start..range.end];
    const pubkey_line = findPubkeyLine(section_text) orelse return error.bad_manifest_text;
    const old_pubkey_hex = pubkey_line.value;

    var new_pubkey_hex_buf: [PUBKEY_LEN * 2]u8 = undefined;
    hexEncode(&replacement_pubkey, &new_pubkey_hex_buf);

    const chain_line = findChainLine(section_text);

    var new_section: std.ArrayList(u8) = .empty;
    errdefer new_section.deinit(allocator);

    try new_section.appendSlice(allocator, section_text[0..pubkey_line.start]);
    try new_section.appendSlice(allocator, "pubkey = \"");
    try new_section.appendSlice(allocator, &new_pubkey_hex_buf);
    try new_section.appendSlice(allocator, "\"\n");

    if (chain_line) |cl| {
        try new_section.appendSlice(allocator, section_text[pubkey_line.end..cl.start]);
        try new_section.appendSlice(allocator, "previous_pubkey_chain = [\"");
        try new_section.appendSlice(allocator, old_pubkey_hex);
        try new_section.appendSlice(allocator, "\"");
        for (cl.entries) |entry| {
            try new_section.appendSlice(allocator, ", \"");
            try new_section.appendSlice(allocator, entry);
            try new_section.appendSlice(allocator, "\"");
        }
        try new_section.appendSlice(allocator, "]\n");
        try new_section.appendSlice(allocator, section_text[cl.end..]);
    } else {
        try new_section.appendSlice(allocator, section_text[pubkey_line.end..]);
        while (new_section.items.len > 0 and new_section.items[new_section.items.len - 1] == '\n') {
            _ = new_section.pop();
        }
        try new_section.appendSlice(allocator, "\nprevious_pubkey_chain = [\"");
        try new_section.appendSlice(allocator, old_pubkey_hex);
        try new_section.appendSlice(allocator, "\"]\n");
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, text[0..range.start]);
    try out.appendSlice(allocator, new_section.items);
    try out.appendSlice(allocator, text[range.end..]);

    new_section.deinit(allocator);
    return out.toOwnedSlice(allocator);
}

const SectionRange = struct {
    start: usize,
    end: usize,
};

fn findSignerSection(text: []const u8, signer_name: []const u8) RewriteError!?SectionRange {
    var header_buf: [256]u8 = undefined;
    if (signer_name.len + 22 > header_buf.len) return error.bad_manifest_text;
    const header = std.fmt.bufPrint(&header_buf, "[trusted_signers.{s}]", .{signer_name}) catch return error.bad_manifest_text;

    var search_from: usize = 0;
    while (search_from < text.len) {
        const idx_opt = std.mem.indexOf(u8, text[search_from..], header);
        if (idx_opt == null) return null;
        const idx = search_from + idx_opt.?;
        const at_sol = idx == 0 or text[idx - 1] == '\n';
        if (at_sol) {
            var scan: usize = idx + header.len;
            while (scan < text.len) {
                const next_opt = std.mem.indexOfScalarPos(u8, text, scan, '\n');
                if (next_opt == null) break;
                const next = next_opt.?;
                if (next + 1 < text.len and text[next + 1] == '[') {
                    return .{ .start = idx, .end = next + 1 };
                }
                scan = next + 1;
            }
            return .{ .start = idx, .end = text.len };
        }
        search_from = idx + 1;
    }
    return null;
}

const KvLineMatch = struct {
    start: usize,
    end: usize,
    value: []const u8,
};

fn findPubkeyLine(section_text: []const u8) ?KvLineMatch {
    return findKeyValueLine(section_text, "pubkey");
}

const ChainLineMatch = struct {
    start: usize,
    end: usize,
    entries: [][]const u8,
};

var chain_entries_buf: [32][]const u8 = undefined;

fn findChainLine(section_text: []const u8) ?ChainLineMatch {
    const m = findKeyValueLine(section_text, "previous_pubkey_chain") orelse return null;
    var entries_count: usize = 0;
    var i: usize = 0;
    while (i < m.value.len and entries_count < chain_entries_buf.len) {
        while (i < m.value.len and (m.value[i] == ' ' or m.value[i] == ',' or m.value[i] == '[' or m.value[i] == ']')) {
            i += 1;
        }
        if (i >= m.value.len) break;
        if (m.value[i] != '"') break;
        i += 1;
        const start = i;
        while (i < m.value.len and m.value[i] != '"') i += 1;
        if (i >= m.value.len) break;
        chain_entries_buf[entries_count] = m.value[start..i];
        entries_count += 1;
        i += 1;
    }
    return .{
        .start = m.start,
        .end = m.end,
        .entries = chain_entries_buf[0..entries_count],
    };
}

fn findKeyValueLine(section_text: []const u8, key: []const u8) ?KvLineMatch {
    var line_start: usize = 0;
    while (line_start < section_text.len) {
        const nl = std.mem.indexOfScalarPos(u8, section_text, line_start, '\n') orelse section_text.len;
        const line = section_text[line_start..nl];
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, key)) {
            const after_key = trimmed[key.len..];
            const after_trim = std.mem.trimLeft(u8, after_key, " \t");
            if (std.mem.startsWith(u8, after_trim, "=")) {
                const value_start = std.mem.indexOfScalar(u8, line, '=').? + 1;
                const value_raw = std.mem.trim(u8, line[value_start..], " \t");
                if (value_raw.len >= 2 and value_raw[0] == '"' and value_raw[value_raw.len - 1] == '"') {
                    return .{
                        .start = line_start,
                        .end = if (nl == section_text.len) nl else nl + 1,
                        .value = value_raw[1 .. value_raw.len - 1],
                    };
                }
                if (value_raw.len >= 2 and value_raw[0] == '[' and value_raw[value_raw.len - 1] == ']') {
                    return .{
                        .start = line_start,
                        .end = if (nl == section_text.len) nl else nl + 1,
                        .value = value_raw,
                    };
                }
            }
        }
        if (nl == section_text.len) break;
        line_start = nl + 1;
    }
    return null;
}

fn revokedKeysIndexContains(
    allocator: std.mem.Allocator,
    path: []const u8,
    pubkey: [PUBKEY_LEN]u8,
) ApplyError!bool {
    const f = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return error.revoked_index_io_failed,
    };
    defer f.close();
    const stat = f.stat() catch return error.revoked_index_io_failed;
    if (stat.size > 4 * 1024 * 1024) return error.revoked_index_io_failed;
    const buf = allocator.alloc(u8, stat.size) catch return error.out_of_memory;
    defer allocator.free(buf);
    _ = f.readAll(buf) catch return error.revoked_index_io_failed;

    var hex_buf: [PUBKEY_LEN * 2]u8 = undefined;
    hexEncode(&pubkey, &hex_buf);
    return std.mem.indexOf(u8, buf, &hex_buf) != null;
}

fn appendRevokedKey(
    allocator: std.mem.Allocator,
    path: []const u8,
    vn: VerifiedNullifier,
) ApplyError!void {
    if (std.fs.path.dirname(path)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }
    var hex_buf: [PUBKEY_LEN * 2]u8 = undefined;
    hexEncode(&vn.payload.revoked_pubkey, &hex_buf);
    const replacement_hex_owned = if (vn.payload.replacement_pubkey) |rp| blk: {
        const buf = allocator.alloc(u8, PUBKEY_LEN * 2) catch return error.out_of_memory;
        hexEncode(&rp, buf);
        break :blk buf;
    } else "";
    defer if (replacement_hex_owned.len > 0) allocator.free(replacement_hex_owned);

    const line = std.fmt.allocPrint(
        allocator,
        "{{\"pubkey\":\"{s}\",\"reason\":\"{s}\",\"timestamp\":{d},\"signer\":\"{s}\",\"replacement\":\"{s}\"}}\n",
        .{
            hex_buf,
            vn.payload.reason_code.name(),
            vn.payload.timestamp,
            vn.target_signer_name,
            replacement_hex_owned,
        },
    ) catch return error.out_of_memory;
    defer allocator.free(line);

    const f = std.fs.cwd().createFile(path, .{ .read = false, .truncate = false }) catch
        return error.revoked_index_io_failed;
    defer f.close();
    f.seekFromEnd(0) catch return error.revoked_index_io_failed;
    f.writeAll(line) catch return error.revoked_index_io_failed;
}

fn readFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
    max_bytes: usize,
) ![]u8 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const stat = try f.stat();
    if (stat.size > max_bytes) return error.FileTooBig;
    const buf = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(buf);
    _ = try f.readAll(buf);
    return buf;
}

fn writeFileAtomic(
    allocator: std.mem.Allocator,
    path: []const u8,
    contents: []const u8,
) ApplyError!void {
    const tmp_path = std.fmt.allocPrint(allocator, "{s}.tmp", .{path}) catch return error.out_of_memory;
    defer allocator.free(tmp_path);

    const f = std.fs.cwd().createFile(tmp_path, .{ .truncate = true }) catch
        return error.manifest_write_failed;
    {
        defer f.close();
        f.writeAll(contents) catch return error.manifest_write_failed;
    }
    std.fs.cwd().rename(tmp_path, path) catch return error.manifest_write_failed;
}

```
