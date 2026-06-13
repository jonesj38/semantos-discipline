---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/wss_operator_auth.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.233040+00:00
---

# runtime/semantos-brain/src/wss_operator_auth.zig

```zig
// W7.4 — Operator-scoped WSS auth: SNI → op_pkh + BRC-52 cert chain validation.
//
// Called by wss_wallet.tryUpgradeFromParsed when the brain runs in hosted-
// operator mode (a DomainMap is configured on the Backend).  Replaces bearer-
// token auth for connections arriving on brain.<domain>.
//
// Auth flow:
//   1. Extract the `Host` header (strip port suffix if present).
//   2. Resolve op_pkh16 via DomainMap.get(host).
//   3. Extract `X-Brain-Pubkey: <66 hex chars>` from the upgrade request.
//   4. Hex-decode to 33 bytes (compressed-SEC1 secp256k1).
//   5. Derive cert_id: certIdFromPubkey(pubkey).
//   6. Load the per-operator CertStore at
//      `$data_dir/operators/<op_pkh16>/identity-certs.log`.
//   7. Fetch the cert record; reject if not found.
//   8. Walk the chain: child → parent must be live → root.
//   9. Return AuthContext on success.
//
// PRD: docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md W7.4

const std = @import("std");
const identity_certs = @import("identity_certs");
const sni_domain_map = @import("sni_domain_map");
const bkds = @import("bkds");

pub const AuthError = error{
    /// Host header not in the domain map — unknown operator.
    sni_not_registered,
    /// X-Brain-Pubkey header absent from the upgrade request.
    missing_pubkey_header,
    /// X-Brain-Pubkey is not 66 lowercase hex chars.
    bad_pubkey_format,
    /// Cert derived from the pubkey does not exist in the operator's store.
    cert_not_found,
    /// Parent cert in the chain is missing from the operator's store.
    cert_chain_broken,
    /// Could not open/replay the operator's cert store.
    store_load_failed,
    out_of_memory,
};

pub const AuthContext = struct {
    /// 16-char lowercase hex op_pkh identifying the operator namespace.
    op_pkh16: [16]u8,
    /// 32-char hex cert id (BRC-52, sha256(pubkey)[0..16] hex-encoded).
    cert_id: [identity_certs.CERT_ID_HEX_LEN]u8,
    /// Root or child — callers may use this to gate root-only operations.
    cert_kind: identity_certs.CertKind,
};

/// Header name the client presents its compressed pubkey under.
/// Value must be 66 lowercase hex chars (33 bytes compressed-SEC1).
pub const PUBKEY_HEADER = "x-brain-pubkey";

/// Real-time clock for CertStore.init.
fn wallClock() i64 {
    return std.time.timestamp();
}

/// Validate an incoming WSS upgrade in hosted-operator mode.
///
/// `host` — raw value of the HTTP Host header (may include `:443` suffix).
/// `pubkey_hex` — value of X-Brain-Pubkey header.
/// `domain_map` — the process-wide SNI map.
/// `data_dir` — brain data directory; per-operator stores live under
///              `<data_dir>/operators/<op_pkh16>/`.
///
/// Returns AuthContext on success; never opens the CertStore twice.
pub fn authenticate(
    host: []const u8,
    pubkey_hex: []const u8,
    domain_map: *const sni_domain_map.DomainMap,
    data_dir: []const u8,
    allocator: std.mem.Allocator,
) AuthError!AuthContext {
    // Step 1: strip port from Host (e.g. "brain.coastal.com.au:443" → ".coastal.com.au")
    const bare_host = if (std.mem.lastIndexOfScalar(u8, host, ':')) |ci|
        host[0..ci]
    else
        host;

    // Step 2: resolve op_pkh16.
    const op_pkh16 = domain_map.get(bare_host) orelse return AuthError.sni_not_registered;

    // Step 3+4: validate and decode the pubkey header.
    if (pubkey_hex.len != 66) return AuthError.bad_pubkey_format;
    var pubkey: [bkds.PUBKEY_LEN]u8 = undefined;
    bkds.hexDecode(pubkey_hex, &pubkey) catch return AuthError.bad_pubkey_format;

    // Step 5: derive cert_id.
    const cert_id = identity_certs.certIdFromPubkey(pubkey);

    // Step 6: open the operator's CertStore.
    const op_dir = std.fs.path.join(
        allocator,
        &.{ data_dir, "operators", &op_pkh16 },
    ) catch return AuthError.out_of_memory;
    defer allocator.free(op_dir);

    var store = identity_certs.CertStore.init(allocator, op_dir, wallClock) catch
        return AuthError.store_load_failed;
    defer store.deinit();

    // Step 7+8: fetch cert and walk chain.
    const record = store.get(&cert_id) catch return AuthError.cert_not_found;
    try walkChain(&store, record);

    return .{
        .op_pkh16 = op_pkh16,
        .cert_id = cert_id,
        .cert_kind = record.kind,
    };
}

/// Walk the cert chain from `record` toward the root, ensuring every
/// ancestor is live (present in the store).  The root cert itself has
/// no parent, so the walk terminates there.
///
/// Max depth: 8 levels — adequate for any realistic BRC-52 chain and
/// prevents runaway iteration on a corrupted store.
fn walkChain(store: *identity_certs.CertStore, start: identity_certs.CertRecord) AuthError!void {
    var current = start;
    var depth: usize = 0;
    while (current.kind == .child) : (depth += 1) {
        if (depth >= 8) return AuthError.cert_chain_broken;
        if (!current.has_parent) return AuthError.cert_chain_broken;
        const parent = store.get(&current.parent_cert_id) catch return AuthError.cert_chain_broken;
        current = parent;
    }
    // current.kind == .root — chain is valid.
}

// ── Inline tests ──────────────────────────────────────────────────────────

test "authenticate: sni_not_registered when host missing" {
    var map = sni_domain_map.DomainMap.init(std.testing.allocator);
    defer map.deinit();
    const err = authenticate(
        "unknown.host.com",
        "a" ** 66,
        &map,
        "/tmp",
        std.testing.allocator,
    );
    try std.testing.expectError(AuthError.sni_not_registered, err);
}

test "authenticate: bad_pubkey_format on wrong length" {
    var map = sni_domain_map.DomainMap.init(std.testing.allocator);
    defer map.deinit();
    const pkh: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    try map.set("brain.coastal.com.au", pkh);
    const err = authenticate(
        "brain.coastal.com.au",
        "tooshort",
        &map,
        "/tmp",
        std.testing.allocator,
    );
    try std.testing.expectError(AuthError.bad_pubkey_format, err);
}

test "authenticate: bad_pubkey_format on non-hex chars" {
    var map = sni_domain_map.DomainMap.init(std.testing.allocator);
    defer map.deinit();
    const pkh: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    try map.set("brain.coastal.com.au", pkh);
    // 66 chars but contains 'z' — invalid hex.
    const err = authenticate(
        "brain.coastal.com.au",
        "z" ** 66,
        &map,
        "/tmp",
        std.testing.allocator,
    );
    try std.testing.expectError(AuthError.bad_pubkey_format, err);
}

test "authenticate: strips port from Host header" {
    var map = sni_domain_map.DomainMap.init(std.testing.allocator);
    defer map.deinit();
    // Not registered → sni_not_registered, but "brain.coastal.com.au"
    // should have been the lookup key after stripping ":443".
    const pkh: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    try map.set("brain.coastal.com.au", pkh);
    // The store load will fail for /tmp path with no operator dir — that's
    // store_load_failed, NOT sni_not_registered.  Port strip worked.
    const err = authenticate(
        "brain.coastal.com.au:443",
        "02" ++ "a3" ** 32, // valid-length 66 hex chars
        &map,
        "/tmp/nonexistent_brain_test_dir",
        std.testing.allocator,
    );
    // Should NOT be sni_not_registered (that would mean port wasn't stripped).
    if (err) |_| {} else |e| {
        try std.testing.expect(e != AuthError.sni_not_registered);
    }
}

```
