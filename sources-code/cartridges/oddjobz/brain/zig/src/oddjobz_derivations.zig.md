---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/oddjobz_derivations.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.546945+00:00
---

# cartridges/oddjobz/brain/zig/src/oddjobz_derivations.zig

```zig
//! D-DOG.1.0c Phase 2B.4 — pure derivation surface for oddjobz cellIDs.
//!
//! Extracted from `oddjobz_ratify_handler.zig` so:
//!   1. The TS↔Zig parity oracle test (`oddjobz_derivations_parity_conformance.zig`)
//!      can drive these functions directly without spinning up the full
//!      WSS handler scaffolding.
//!   2. The functions are guaranteed-pure (no I/O, no allocator state
//!      leaking up except through caller-owned `[]u8` returns) and can
//!      be unit-tested in isolation.
//!
//! The handler continues to call into here — there is exactly ONE
//! implementation of each derivation, byte-for-byte equivalent to its
//! TS mirror in `runtime/legacy-ingest/src/cell-writer/brain-rpc.ts` and
//! `cartridges/oddjobz/brain/src/cell-types/site.v2.ts`.
//!
//! Phase 2B.4 lands the JSON-fixture-driven parity oracle that asserts
//! the byte-equality claim across both implementations.

const std = @import("std");

// ─── Address normalisation + lookup-key derivation ────────────────────

/// Mirror site.v2.ts `normaliseAddress` byte-for-byte: lowercase +
/// collapse internal whitespace + trim. Caller owns the returned
/// string.
pub fn normaliseAddress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    var prev_space = true; // suppress leading whitespace
    for (input) |c| {
        const lower = std.ascii.toLower(c);
        if (lower == ' ' or lower == '\t' or lower == '\n' or lower == '\r') {
            if (!prev_space) {
                try out.append(allocator, ' ');
                prev_space = true;
            }
        } else {
            try out.append(allocator, lower);
            prev_space = false;
        }
    }
    // Trim trailing whitespace.
    while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') {
        _ = out.pop();
    }
    return out.toOwnedSlice(allocator);
}

/// Mirror site.v2.ts `deriveLookupKey`: `<normalised>|<keyNumber-or-empty>`.
pub fn deriveLookupKey(
    allocator: std.mem.Allocator,
    normalised: []const u8,
    key_number: ?[]const u8,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}|{s}", .{
        normalised,
        if (key_number) |k| k else "",
    });
}

// ─── CellID derivation (separator-string SHA-256) ─────────────────────

/// Site cellID. SHA-256("oddjobz.site.v2|" + normalised + "|" +
/// keyNumber + "|" + fullAddress). Lookup-or-mint dedupe is keyed on
/// lookupKey (separate index), so this just needs to be deterministic
/// and collision-resistant per (lookupKey, fullAddress).
pub fn computeSiteCellId(
    normalised_address: []const u8,
    key_number: ?[]const u8,
    full_address: []const u8,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("oddjobz.site.v2|");
    hasher.update(normalised_address);
    hasher.update("|");
    if (key_number) |k| hasher.update(k);
    hasher.update("|");
    hasher.update(full_address);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

/// Customer cellID. Deterministic on (name, role, site, phone, email)
/// so re-ratifies of equivalent SIRs converge.
pub fn computeCustomerCellId(
    name: []const u8,
    role: []const u8,
    site_cell_id: [32]u8,
    phone: []const u8,
    email: []const u8,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("oddjobz.customer.v2|");
    hasher.update(name);
    hasher.update("|");
    hasher.update(role);
    hasher.update("|");
    hasher.update(&site_cell_id);
    hasher.update("|");
    hasher.update(phone);
    hasher.update("|");
    hasher.update(email);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

/// Minimal customer-ref shape for cellID derivation. Decoupled from
/// `jobs_store_fs.CustomerRef` so this module stays a pure leaf with
/// no upward dependencies — the handler converts its store-shaped
/// CustomerRefs into this on the way in.
pub const CustomerRefHash = struct {
    cell_id: [32]u8,
    role: []const u8,
    primary: bool,
};

/// Job cellID. Deterministic on the site + customer refs + WO# + the
/// timestamp the job was minted at (so two ratifies with the same SIR
/// at different wall-clock times produce DIFFERENT job cells —
/// matching the user-facing semantic that re-ratifying the same
/// proposal_id is the per-proposal idempotency cache, NOT a
/// deduplicator-on-content).
pub fn computeJobCellId(
    site_cell_id: [32]u8,
    customer_refs: []const CustomerRefHash,
    work_order_number: []const u8,
    issuance_date: []const u8,
    due_date: []const u8,
    created_at: []const u8,
    display_name: []const u8,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("oddjobz.job.v2|");
    hasher.update(&site_cell_id);
    hasher.update("|");
    for (customer_refs) |cref| {
        hasher.update(&cref.cell_id);
        hasher.update(":");
        hasher.update(cref.role);
        hasher.update(if (cref.primary) "*" else " ");
        hasher.update("|");
    }
    hasher.update(work_order_number);
    hasher.update("|");
    hasher.update(issuance_date);
    hasher.update("|");
    hasher.update(due_date);
    hasher.update("|");
    hasher.update(display_name);
    hasher.update("|");
    hasher.update(created_at);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

/// Attachment cellID. Deterministic on (job, source_path, ts) so two
/// ratifies of the same proposal converge through the per-proposal
/// idempotency cache.
pub fn computeAttachmentCellId(
    job_cell_id: [32]u8,
    source_attachment_path: []const u8,
    created_at: []const u8,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("oddjobz.attachment.v2|");
    hasher.update(&job_cell_id);
    hasher.update("|");
    hasher.update(source_attachment_path);
    hasher.update("|");
    hasher.update(created_at);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

// ─── UUID-shape derivation from cellID ────────────────────────────────

/// Build a UUID v4-shape hex string (32 chars, no dashes) from a
/// 32-byte source. Take the first 16 bytes, force the version (high
/// nibble of byte 6 = 4) and variant (high two bits of byte 8 = 10)
/// bits per RFC 4122 §4.4, emit lowercase hex without dashes.
///
/// The function name is historical: the byte transformation matches
/// the RFC 4122 v4 mask (version=4, variant=10). The TS port in
/// `brain-rpc.ts::uuidV5LikeFromBytes` mirrors this exact byte-level
/// behaviour for parity.
pub fn uuidV5LikeFromBytes(allocator: std.mem.Allocator, source: *const [32]u8) ![]u8 {
    var bytes: [16]u8 = undefined;
    @memcpy(bytes[0..], source[0..16]);
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    const hex = std.fmt.bytesToHex(bytes, .lower);
    return allocator.dupe(u8, hex[0..]);
}

// ─── Inline tests (a sanity-check layer; the cross-language parity
//     oracle lives in `tests/oddjobz_derivations_parity_conformance.zig`).

test "normaliseAddress collapses whitespace and lowercases" {
    const a = std.testing.allocator;
    const out = try normaliseAddress(a, "  29 Foedera   Cres,  Tewantin QLD 4565  ");
    defer a.free(out);
    try std.testing.expectEqualStrings("29 foedera cres, tewantin qld 4565", out);
}

test "deriveLookupKey appends keyNumber after pipe" {
    const a = std.testing.allocator;
    const k = try deriveLookupKey(a, "addr", "key #177");
    defer a.free(k);
    try std.testing.expectEqualStrings("addr|key #177", k);

    const k2 = try deriveLookupKey(a, "addr", null);
    defer a.free(k2);
    try std.testing.expectEqualStrings("addr|", k2);
}

test "uuidV5LikeFromBytes sets version+variant nibbles" {
    const a = std.testing.allocator;
    const src: [32]u8 = .{ 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff } ** 2;
    const u = try uuidV5LikeFromBytes(a, &src);
    defer a.free(u);
    // byte 6 = 0x66 → high nibble 4 → "46" ; byte 8 = 0x88 → high two bits 10 → "88"
    try std.testing.expectEqualStrings("00112233445546778899aabbccddeeff", u);
}

test "computeSiteCellId deterministic on inputs" {
    const a = computeSiteCellId("addr", "k1", "Addr full");
    const b = computeSiteCellId("addr", "k1", "Addr full");
    try std.testing.expectEqualSlices(u8, &a, &b);

    const c = computeSiteCellId("addr", null, "Addr full");
    try std.testing.expect(!std.mem.eql(u8, &a, &c));
}

```
