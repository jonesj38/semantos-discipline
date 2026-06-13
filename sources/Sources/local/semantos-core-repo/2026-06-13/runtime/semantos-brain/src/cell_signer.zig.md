---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cell_signer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.247937+00:00
---

# runtime/semantos-brain/src/cell_signer.zig

```zig
// Zig CellSigner — brain-side seam for generic, hat-scoped cell signing.
//
// Reference: docs/prd/UNIFICATION-ROADMAP.md §11.10 order 4a (this PR);
//            runtime/semantos-brain/src/hat_bkds.zig (the BRC-42 BKDS
//              primitive this seam wraps);
//            runtime/semantos-brain/src/anchor_emitter.zig (sister seam
//              — same staged-backend + structured-result pattern);
//            runtime/semantos-brain/src/policy_runtime.zig (sister seam
//              — same init / initWith* mode-selection pattern);
//            cartridges/oddjobz/brain/zig/src/oddjobz_ratify_handler.zig
//              (today's direct *HatBkds caller — flips to *CellSigner
//              in PR-4b after this seam soaks).
//
// What this is: the single entry point cartridge handlers call to sign
// a canonical cell payload.  Wraps the brain's hat (BRC-42 BKDS root
// scalar) with a cartridge-specific derivation scope so that two
// cartridges signing the same canonical bytes under the same root hat
// produce different derived keys.  This is what Todd 2026-05-25 meant
// by "cell signing should be generic but under hats relevant to the
// cartridge" — one shared hat primitive, per-cartridge scope.
//
// What this IS NOT (today): a hat-resolution registry.  The brain holds
// one operator hat; the cartridge supplies its own scope at construct
// time (initWithHat).  When the brain grows multiple hats (e.g.
// per-cartridge hats or per-user hats), a CellSignerRegistry on top of
// this seam will resolve hat_id → *HatBkds; CellSigner itself stays
// the per-call surface.
//
// Mirror shape:
//   PolicyRuntime.evaluate(policy_bytes, context) → PolicyResult
//   AnchorEmitter.emit(context)                    → AnchorResult
//   CellSigner.sign(context)                       → CellSignResult
//
// All three are: pluggable backend, structured return, no exceptions for
// business-rule outcomes (not_configured / failed are encoded in
// status, not thrown).
//
// Why a seam at all (vs. cartridges calling hat_bkds.signCell directly,
// the pre-PR-4a pattern)?
//
//   1. Scope leak: hat_bkds.signCell signs under the substrate DEFAULT
//      scope (PROTOCOL_ID + CONTEXT_TAG_CELL_SIGN).  A cartridge calling
//      it directly would silently sign under that shared default,
//      producing keys indistinguishable from any other cartridge's
//      default-scope cells to the verifier — wrong tenancy.  The seam
//      forces an explicit per-cartridge scope via signCellScoped.
//   2. Hat lifetime: cartridges holding `?*HatBkds` directly need to
//      know about hat boot order, kek-decryption state, scope rules.
//      The seam encapsulates that.
//   3. Future hat resolution: when there are N hats, the seam grows a
//      hat-id parameter on init; consumers don't change.
//   4. Stub mode for tests: cartridge tests get a deterministic
//      stub-signed result without standing up a HatBkds.

const std = @import("std");
const hat_bkds = @import("hat_bkds");

// ─────────────────────────────────────────────────────────────────────
// Public types
// ─────────────────────────────────────────────────────────────────────

/// Which backend the CellSigner dispatches to.
pub const CellSignerMode = enum {
    /// Synthesises a deterministic fake signature derived from the
    /// payload hash.  No keys touched.  Used in tests + dev paths
    /// where on-chain identity isn't wanted.  This is the default for
    /// `init(allocator)` — matches the safe-default pattern of
    /// PolicyRuntime + AnchorEmitter.
    stub,
    /// Real BRC-42 BKDS signing via a *HatBkds reference held in
    /// `hat`.  Constructed via `initWithHat(allocator, hat,
    /// scope_protocol_id, scope_context_tag)`.  The seam never owns
    /// the hat — caller is responsible for the hat's lifetime (init +
    /// deinit).
    hat_bkds,
};

/// What's being signed + how to route the signing call.  All slices are
/// borrowed for the duration of `sign`; callers own the underlying
/// memory.
pub const CellSignContext = struct {
    /// Canonical bytes hashed + signed.  IS the signing input: the
    /// verifier reaches the same digest by hashing these same bytes.
    canonical_payload: []const u8,
    /// Reserved for a future tier where the header (typeHash + cellId)
    /// is signed separately from the payload.  Today's backends
    /// accept-but-ignore — same shape as hat_bkds.signCell.
    cell_header: []const u8 = &.{},
    /// Optional cartridge id (e.g., "oddjobz", "jambox").  Hint for
    /// future per-cartridge audit-log tagging + observability.  Today
    /// informational; tomorrow used by the planned hat-resolution
    /// registry to pick the cartridge's hat.
    cartridge_id: ?[]const u8 = null,
    /// Optional correlation id for trace threading.  Cartridges that
    /// already carry correlation_id (e.g. intent_cells) pass it through
    /// for join-on-audit-log queries.
    correlation_id: ?[]const u8 = null,
};

/// Lifecycle status of a `sign()` call.  Distinguishes "no hat
/// available" (configuration gap) from "tried and failed" (key
/// derivation / signing error) so call sites can route distinctly.
pub const CellSignStatus = enum {
    /// Backend signed; derived_pubkey + signature are populated and
    /// safe to write into a cell's signedBy + signature fields.
    signed,
    /// Mode is .hat_bkds but no hat was configured — `initWithHat` was
    /// never called, or the hat pointer is null.  Distinct from
    /// .failed because this is a wiring gap, not a key-derivation
    /// error.
    not_configured,
    /// Hat present + scope valid, but the BKDS primitive surfaced an
    /// error.  `error_kind` carries the short token.
    failed,
};

/// Structured outcome of a `sign()` call.  Never thrown; all outcomes
/// encoded in status.  derived_pubkey + signature are zero-filled when
/// status != .signed so callers don't accidentally write junk into
/// cell fields on a non-signed result.
pub const CellSignResult = struct {
    status: CellSignStatus,
    /// 33-byte compressed-SEC1 derived pubkey — goes in the cell's
    /// `signedBy` field.  Zeroed when status != .signed.
    derived_pubkey: [hat_bkds.PUBKEY_LEN]u8 = [_]u8{0} ** hat_bkds.PUBKEY_LEN,
    /// 64-byte compact (r || s) signature — goes in the cell's
    /// `signature` field.  Zeroed when status != .signed.
    signature: [hat_bkds.SIGNATURE_LEN]u8 = [_]u8{0} ** hat_bkds.SIGNATURE_LEN,
    /// Short error token when status == .failed.  Borrowed from a
    /// static table; lifetime is the program.  Null otherwise.
    error_kind: ?[]const u8 = null,
};

// ─────────────────────────────────────────────────────────────────────
// CellSigner
// ─────────────────────────────────────────────────────────────────────

/// The single entry point cartridge handlers call to sign a canonical
/// cell payload.  Holds the backend mode + (for .hat_bkds mode) a
/// borrowed hat pointer and the cartridge-specific derivation scope.
///
/// Lifetime: the seam does NOT own the hat — caller is responsible for
/// the hat's `init` and `deinit`.  The seam itself has no per-instance
/// resources to release; cartridges can construct + drop CellSigner
/// freely.
pub const CellSigner = struct {
    allocator: std.mem.Allocator,
    mode: CellSignerMode,
    /// Borrowed *HatBkds reference for .hat_bkds mode.  Null in .stub
    /// mode; non-null in .hat_bkds mode (enforced at construction —
    /// see initWithHat).
    hat: ?*hat_bkds.HatBkds,
    /// Cartridge-specific derivation scope.  Combined with the
    /// canonical_payload's content hash to form the BRC-42 invoice
    /// label.  Empty in .stub mode.
    scope_protocol_id: []const u8,
    /// Cartridge-specific BRC-42 invoice context tag.  Distinguishes
    /// derivations across cartridges that share the same protocol_id
    /// prefix.  0 in .stub mode.
    scope_context_tag: u8,

    /// Construct a stub-mode signer — no hat, no real key material.
    /// Tests + dev paths.
    pub fn init(allocator: std.mem.Allocator) CellSigner {
        return .{
            .allocator = allocator,
            .mode = .stub,
            .hat = null,
            .scope_protocol_id = &.{},
            .scope_context_tag = 0,
        };
    }

    /// Construct a real-signing signer bound to a hat + cartridge
    /// scope.  The hat reference is borrowed; the caller owns its
    /// lifetime.
    ///
    /// `scope_protocol_id` example: "oddjobz.cell-sign/v1" for the
    /// oddjobz cartridge.  `scope_context_tag` example: 0x20 for
    /// oddjobz.  Each cartridge picks its own.
    pub fn initWithHat(
        allocator: std.mem.Allocator,
        hat: *hat_bkds.HatBkds,
        scope_protocol_id: []const u8,
        scope_context_tag: u8,
    ) CellSigner {
        return .{
            .allocator = allocator,
            .mode = .hat_bkds,
            .hat = hat,
            .scope_protocol_id = scope_protocol_id,
            .scope_context_tag = scope_context_tag,
        };
    }

    /// Sign a canonical cell payload.  Dispatches to the per-mode
    /// helper; pure dispatch, no shared work.
    pub fn sign(self: *CellSigner, context: CellSignContext) CellSignResult {
        return switch (self.mode) {
            .stub => signStub(context),
            .hat_bkds => self.signHatBkds(context),
        };
    }

    // ─────────────────────────────────────────────────────────────────
    // Backends
    // ─────────────────────────────────────────────────────────────────

    /// Real backend.  Delegates to hat_bkds.signCellScoped using the
    /// seam's stored cartridge scope.  Maps hat_bkds.Error into
    /// structured CellSignResult — no thrown errors for the caller.
    fn signHatBkds(self: *CellSigner, context: CellSignContext) CellSignResult {
        const hat = self.hat orelse return .{
            .status = .not_configured,
            .error_kind = "hat_not_configured",
        };
        const signed = hat.signCellScoped(
            context.canonical_payload,
            context.cell_header,
            self.scope_protocol_id,
            self.scope_context_tag,
        ) catch |err| {
            return .{
                .status = .failed,
                .error_kind = @errorName(err),
            };
        };
        return .{
            .status = .signed,
            .derived_pubkey = signed.derived_pubkey,
            .signature = signed.signature,
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// Backends — free functions for mode dispatch (stub is stateless so it
// lives outside the struct)
// ─────────────────────────────────────────────────────────────────────

/// Stub backend.  Synthesises a deterministic fake derived_pubkey +
/// signature by hashing the canonical_payload with two distinct domain
/// separators.  No on-chain meaning, no key material — but stable
/// per-payload so test fixtures can pin assertions against the bytes
/// and audit logs can join across runs.
///
/// Domain separators (avoid accidental collision with any real pubkey
/// / signature byte pattern):
///   "cell_signer.stub.derived_pubkey.v1\n" — 33 bytes from SHA-256
///     prefix
///   "cell_signer.stub.signature.v1\n"      — 64 bytes from two
///     SHA-256 invocations, truncate-and-concat
fn signStub(context: CellSignContext) CellSignResult {
    var result: CellSignResult = .{ .status = .signed };

    // Derived pubkey = first 33 bytes of SHA-256(sep1 || payload).  The
    // 33rd byte position is what compressed-SEC1 calls the prefix
    // byte; for a fake we don't care that it's a valid 02/03 — the
    // stub mode is for tests, not for downstream pubkey validation.
    var hasher_pk = std.crypto.hash.sha2.Sha256.init(.{});
    hasher_pk.update("cell_signer.stub.derived_pubkey.v1\n");
    hasher_pk.update(context.canonical_payload);
    var hash_pk: [32]u8 = undefined;
    hasher_pk.final(&hash_pk);
    @memcpy(result.derived_pubkey[0..32], &hash_pk);
    result.derived_pubkey[32] = 0x02; // leading-byte placeholder

    // Signature = 64 bytes via two SHA-256 invocations with distinct
    // sub-separators (".r" / ".s" — mirrors the r||s shape of a real
    // ECDSA signature, just with deterministic hash bytes instead of
    // curve-arithmetic outputs).
    var hasher_r = std.crypto.hash.sha2.Sha256.init(.{});
    hasher_r.update("cell_signer.stub.signature.v1.r\n");
    hasher_r.update(context.canonical_payload);
    var hash_r: [32]u8 = undefined;
    hasher_r.final(&hash_r);
    @memcpy(result.signature[0..32], &hash_r);

    var hasher_s = std.crypto.hash.sha2.Sha256.init(.{});
    hasher_s.update("cell_signer.stub.signature.v1.s\n");
    hasher_s.update(context.canonical_payload);
    var hash_s: [32]u8 = undefined;
    hasher_s.final(&hash_s);
    @memcpy(result.signature[32..64], &hash_s);

    return result;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure-function behaviour + dispatch + stub determinism.
// Cross-module conformance (real-hat round-trip through CellSigner +
// hat_bkds_verifier) lives in tests/cell_signer_conformance.zig under
// PR-4b once the seam soaks.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "CellSigner.init defaults to .stub mode (no hat needed)" {
    const signer = CellSigner.init(testing.allocator);
    try testing.expectEqual(CellSignerMode.stub, signer.mode);
    try testing.expect(signer.hat == null);
}

test "CellSigner stub: same payload → byte-identical result (determinism)" {
    var signer = CellSigner.init(testing.allocator);
    const r1 = signer.sign(.{ .canonical_payload = "hello world" });
    const r2 = signer.sign(.{ .canonical_payload = "hello world" });
    try testing.expectEqual(CellSignStatus.signed, r1.status);
    try testing.expectEqual(CellSignStatus.signed, r2.status);
    try testing.expectEqualSlices(u8, &r1.derived_pubkey, &r2.derived_pubkey);
    try testing.expectEqualSlices(u8, &r1.signature, &r2.signature);
}

test "CellSigner stub: different payload → different bytes" {
    var signer = CellSigner.init(testing.allocator);
    const r1 = signer.sign(.{ .canonical_payload = "payload-a" });
    const r2 = signer.sign(.{ .canonical_payload = "payload-b" });
    try testing.expect(!std.mem.eql(u8, &r1.derived_pubkey, &r2.derived_pubkey));
    try testing.expect(!std.mem.eql(u8, &r1.signature, &r2.signature));
}

test "CellSigner stub: empty payload still produces signed result" {
    var signer = CellSigner.init(testing.allocator);
    const r = signer.sign(.{ .canonical_payload = "" });
    try testing.expectEqual(CellSignStatus.signed, r.status);
}

test "CellSigner stub: ignores cartridge_id + correlation_id (informational)" {
    var signer = CellSigner.init(testing.allocator);
    const r1 = signer.sign(.{
        .canonical_payload = "x",
        .cartridge_id = "oddjobz",
        .correlation_id = "trace-1",
    });
    const r2 = signer.sign(.{
        .canonical_payload = "x",
        .cartridge_id = "jambox",
        .correlation_id = "trace-2",
    });
    // Same payload → identical stub output regardless of cartridge_id /
    // correlation_id.  Those fields are observability hints in stub
    // mode (they flow to audit logs / hat-resolution routing in real
    // mode + future PRs but don't enter the deterministic-hash chain).
    try testing.expectEqualSlices(u8, &r1.derived_pubkey, &r2.derived_pubkey);
    try testing.expectEqualSlices(u8, &r1.signature, &r2.signature);
}

test "CellSigner hat_bkds with null hat → not_configured (defensive)" {
    // Direct struct construction (vs. initWithHat which requires a
    // non-null hat) so we can simulate the wiring-gap case — the
    // brain's hat boot didn't run, or the cartridge constructed
    // CellSigner before the hat was available.
    var signer: CellSigner = .{
        .allocator = testing.allocator,
        .mode = .hat_bkds,
        .hat = null,
        .scope_protocol_id = "test.scope/v1",
        .scope_context_tag = 0x21,
    };
    const r = signer.sign(.{ .canonical_payload = "anything" });
    try testing.expectEqual(CellSignStatus.not_configured, r.status);
    try testing.expectEqualStrings("hat_not_configured", r.error_kind.?);
    // Defensive: when status != .signed, key bytes are zero-filled so a
    // caller that writes them blindly into a cell field at least
    // produces all-zeros instead of stack garbage.
    for (r.derived_pubkey) |b| try testing.expectEqual(@as(u8, 0), b);
    for (r.signature) |b| try testing.expectEqual(@as(u8, 0), b);
}

test "CellSigner hat_bkds with real hat: signed under cartridge scope" {
    var hat = try hat_bkds.HatBkds.initFromSeed("test-operator-root");
    defer hat.deinit();

    var signer = CellSigner.initWithHat(
        testing.allocator,
        &hat,
        "test-cartridge.cell-sign/v1",
        0x21, // distinct from the substrate default CONTEXT_TAG_CELL_SIGN = 0x20
    );
    const r = signer.sign(.{ .canonical_payload = "scoped payload" });
    try testing.expectEqual(CellSignStatus.signed, r.status);
    // Derived pubkey must be a valid compressed-SEC1 leading byte
    // (0x02 or 0x03) — sanity check that we're getting real key
    // material, not stub bytes.
    try testing.expect(r.derived_pubkey[0] == 0x02 or r.derived_pubkey[0] == 0x03);
}

test "CellSigner hat_bkds: same payload, different scope → different keys" {
    // The "generic but under hats relevant to the cartridge" property
    // — two cartridges signing the same canonical bytes under the
    // same hat produce different derived keys.  This is what stops
    // cross-cartridge cell-trace linkability.
    var hat = try hat_bkds.HatBkds.initFromSeed("test-operator-root");
    defer hat.deinit();

    var signer_a = CellSigner.initWithHat(
        testing.allocator,
        &hat,
        "cartridge-a.cell-sign/v1",
        0x21,
    );
    var signer_b = CellSigner.initWithHat(
        testing.allocator,
        &hat,
        "cartridge-b.cell-sign/v1",
        0x22,
    );
    const payload = "shared canonical payload";
    const r_a = signer_a.sign(.{ .canonical_payload = payload });
    const r_b = signer_b.sign(.{ .canonical_payload = payload });
    try testing.expectEqual(CellSignStatus.signed, r_a.status);
    try testing.expectEqual(CellSignStatus.signed, r_b.status);
    try testing.expect(!std.mem.eql(u8, &r_a.derived_pubkey, &r_b.derived_pubkey));
    try testing.expect(!std.mem.eql(u8, &r_a.signature, &r_b.signature));
}

test "CellSigner hat_bkds: same payload, same scope → byte-identical (idempotent)" {
    // The idempotent re-sign property — re-signing an already-signed
    // cell with the same scope reaches the same (pubkey, signature)
    // pair.  This is what backs the safety of ratify/resign admin
    // verbs.
    var hat = try hat_bkds.HatBkds.initFromSeed("test-operator-root");
    defer hat.deinit();

    var signer = CellSigner.initWithHat(
        testing.allocator,
        &hat,
        "idem.cell-sign/v1",
        0x21,
    );
    const r1 = signer.sign(.{ .canonical_payload = "idempotent test" });
    const r2 = signer.sign(.{ .canonical_payload = "idempotent test" });
    try testing.expectEqualSlices(u8, &r1.derived_pubkey, &r2.derived_pubkey);
    try testing.expectEqualSlices(u8, &r1.signature, &r2.signature);
}

```
