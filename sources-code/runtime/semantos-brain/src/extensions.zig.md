---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/extensions.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.237016+00:00
---

# runtime/semantos-brain/src/extensions.zig

```zig
// D-O3 — brain extension manifest registry + first-boot capability mint pass.
//
// Reference:
//   - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O3 (capability mint table)
//   - docs/design/ODDJOBZ-EXTENSION-PLAN.md §7 (boot-sequence integration:
//     "no new top-level boot step")
//   - docs/design/ODDJOBZ-EXTENSION-PLAN.md §9 (acceptance gates;
//     specifically gate 8: "no new top-level boot step")
//   - docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3 (capabilities row),
//     §2.5 (carpenter+musician hat isolation invariant)
//   - cartridges/oddjobz/brain/src/capabilities.ts  (the canonical TS source
//     this module mirrors)
//   - cartridges/oddjobz/brain/src/manifest.ts      (the canonical manifest;
//     the Zig side of which this module is)
//
// What this module is, and isn't:
//
//   IS: a static registry of bundled-with-the-daemon extension
//   manifests + a `mintFirstBootCapabilities` pass cmdServe calls in
//   its existing post-cert-init boot phase to grant the declared cap
//   names to the operator-root cert.
//
//   IS NOT: an extension loader for arbitrary user-installed
//   extensions. Per ODDJOBZ-EXTENSION-PLAN.md §3 D-O3 brief, the
//   provisioning CLI (D-O10) is what eventually drops extension
//   bundles into a tenant's data dir, and a future D-W1 Phase
//   extends this module to read manifests from
//   `<data_dir>/extensions/<id>/manifest.json`. Today the registry
//   is hard-coded — only oddjobz lives here — and that satisfies the
//   §O3 acceptance gate.
//
// Acceptance-gate citation (§9.8 — "no new top-level boot step"):
//
//   The first-boot capability mint runs INSIDE cmdServe's existing
//   "stand up the dispatcher + Unix socket transport" phase, AFTER
//   identity_certs.issue_root has been registered to the dispatcher.
//   No new step in `brain serve`'s boot sequence; the capability mint
//   is an additive pass on the existing identity-certs resource. The
//   §O3 plan says "step 6 — capability mint" and that's exactly where
//   this lives — within the same post-cert-store-init block.
//
// Mirror-list invariant (the §9 gate's "Canon discipline"):
//
//   The cap-name strings + domain-flag values below MUST exactly
//   match `cartridges/oddjobz/brain/src/capabilities.ts`'s
//   `ODDJOBZ_CAPABILITIES`. The conformance test in
//   tests/extensions_test.zig iterates this Zig list against the TS
//   manifest's serialised wire form (which the
//   `bun run gen:cap-vectors` flow emits); a mismatch fails CI.

const std = @import("std");
const identity_certs = @import("identity_certs");
// DLO.1b — additive: the generic loader for user-installed extensions
// living on disk at <data_dir>/extensions/<id>/manifest.json. Imported
// here so this module exposes enumerateUserInstalled() alongside the
// hardcoded BUILTIN_MANIFESTS path; V1 production capability minting
// continues to flow through the hardcoded path until DLO.1c lands.
const extension_manifest_loader = @import("extension_manifest_loader");

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const ExtensionError = error{
    /// `mintFirstBootCapabilities` was called before `issue_root` had
    /// minted the operator's root cert — there's no place to attach
    /// the cap names yet.
    no_root_cert,
    /// Underlying CertStore error during cap-list update.
    store_error,
    /// Unknown extension id passed to `manifestById`.
    unknown_extension,
    /// Allocator OOM while building the merged cap list.
    out_of_memory,
};

// ─────────────────────────────────────────────────────────────────────
// Manifest types — Zig mirror of cartridges/oddjobz/brain/src/manifest.ts
// ─────────────────────────────────────────────────────────────────────

pub const CapHolder = enum {
    operator_root,
    node_service,
};

pub const ExtensionCapability = struct {
    name: []const u8,
    /// Mint-time-deterministic uint32 — the value the kernel-gate
    /// `OP_CHECKDOMAINFLAG` enforces on the cap UTXO at FSM transition
    /// time (D-O4 territory).
    domain_flag: u32,
    /// Operator-readable role for audit logs.
    description: []const u8,
    /// Who carries the cap in steady state.
    holder: CapHolder,
};

pub const ExtensionManifest = struct {
    id: []const u8,
    version: []const u8,
    description: []const u8,
    capabilities: []const ExtensionCapability,
    /// Cited in audit-log lines on first-boot mint to make the §9
    /// gate trivially auditable.
    plan_ref: []const u8,
};

// ─────────────────────────────────────────────────────────────────────
// The bundled oddjobz manifest — verbatim mirror of
// cartridges/oddjobz/brain/src/capabilities.ts ODDJOBZ_CAPABILITIES.
// Declaration order matches the §O3 plan table.
// ─────────────────────────────────────────────────────────────────────

const ODDJOBZ_CAPS = [_]ExtensionCapability{
    .{
        .name = "cap.oddjobz.write_customer",
        .domain_flag = 0x0001_0105,
        .description = "Authorises customer create / merge writes against the oddjobz substrate.",
        .holder = .operator_root,
    },
    .{
        .name = "cap.oddjobz.quote",
        .domain_flag = 0x0001_0101,
        .description = "Authorises issuing a price for a Job — the operator's jural power to offer.",
        .holder = .operator_root,
    },
    .{
        .name = "cap.oddjobz.dispatch",
        .domain_flag = 0x0001_0102,
        .description = "Authorises committing to a visit slot — jural obligation acceptance.",
        .holder = .operator_root,
    },
    .{
        .name = "cap.oddjobz.invoice",
        .domain_flag = 0x0001_0103,
        .description = "Authorises issuing an invoice on a completed Job.",
        .holder = .operator_root,
    },
    .{
        .name = "cap.oddjobz.close",
        .domain_flag = 0x0001_0104,
        .description = "Authorises the terminal close transition on a Job — jural satisfaction.",
        .holder = .operator_root,
    },
    .{
        .name = "cap.oddjobz.public_chat_serve",
        .domain_flag = 0x0001_0106,
        .description = "Authorises the node daemon to serve anonymous public-chat messages (rate-limited service cap).",
        .holder = .node_service,
    },
};

const ODDJOBZ_MANIFEST = ExtensionManifest{
    .id = "oddjobz",
    .version = "0.1.0",
    .description = "Trades / services vertical extension — cells (D-O2) + capabilities (D-O3).",
    .capabilities = &ODDJOBZ_CAPS,
    .plan_ref = "docs/design/ODDJOBZ-EXTENSION-PLAN.md §O3",
};

// ─────────────────────────────────────────────────────────────────────
// Chess doubling-cube cartridge — single play capability gates every
// chess verb (create_game, join_game, submit_move, offer_double,
// accept_double, decline_double, resolve, get_game, list_legal_moves,
// cancel_game, resign_game). Page 0x000103xx is the chess page
// (oddjobz claims 0x000101xx; loom-shell 0x000100xx).
// See docs/design/CHESS-DOUBLING-CUBE.md §8 (capability_required).
// ─────────────────────────────────────────────────────────────────────

const CHESS_CAPS = [_]ExtensionCapability{
    .{
        .name = "cap.chess.play",
        .domain_flag = 0x0001_0301,
        .description = "Authorises chess verb calls (create_game / join_game / submit_move / offer_double / accept_double / decline_double / resolve / get_game / list_legal_moves / cancel_game / resign_game). Per-identity; the operator root holds it for the game's two players.",
        .holder = .operator_root,
    },
};

const CHESS_MANIFEST = ExtensionManifest{
    .id = "chess",
    .version = "0.1.0",
    .description = "Chess doubling-cube vertical — LINEAR cube/stake state machine + Path A pre-signed-settlement escrow.",
    .capabilities = &CHESS_CAPS,
    .plan_ref = "docs/design/CHESS-DOUBLING-CUBE.md §8",
};

/// Static registry of extensions bundled with the Semantos Brain daemon.
/// Future: read manifests from `<data_dir>/extensions/` post-D-O10.
pub const BUILTIN_MANIFESTS = [_]ExtensionManifest{
    ODDJOBZ_MANIFEST,
    CHESS_MANIFEST,
};

// ─────────────────────────────────────────────────────────────────────
// Lookup
// ─────────────────────────────────────────────────────────────────────

pub fn manifestById(id: []const u8) ?ExtensionManifest {
    for (BUILTIN_MANIFESTS) |m| {
        if (std.mem.eql(u8, m.id, id)) return m;
    }
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// First-boot pass — §9.8 acceptance-gate citation lives here
// ─────────────────────────────────────────────────────────────────────

/// Mint the declared capabilities of every bundled extension onto the
/// operator-root cert held by `cert_store`. Called from cmdServe's
/// existing post-cert-init boot phase — NO NEW TOP-LEVEL BOOT STEP.
///
/// Behaviour:
///   - Idempotent: cap names are added to the root cert's allowlist
///     iff they aren't already present. Re-running the daemon is a
///     no-op past the first call.
///   - Service caps (CapHolder.node_service) are tracked in the same
///     allowlist for v0.1; the dispatcher's CapabilitySet built from
///     the cert's caps is what gates the public-chat handler.
///     Future revisions may split node-service caps onto a separate
///     non-cert-attached principal once the dispatcher learns to
///     surface a "node service" auth context.
///   - Failure to update the store is non-fatal: the audit log
///     records the failure (caller wires `audit` separately) and
///     the daemon serves on with whatever caps survived. This
///     matches the bearer_tokens / identity_certs failure posture.
///
/// Arguments:
///   - allocator   — for the merged cap-list buffers
///   - cert_store  — the live identity-certs store, must already
///     hold a root cert
///   - out_writer  — sink for human-readable progress lines
///     ("[boot] D-O3 — minted N capabilities for extension X");
///     pass `null` to suppress.
/// Mint one manifest's caps onto the operator-root cert (idempotent,
/// set semantics on cap names). Re-reads the root each call so a
/// multi-manifest pass observes prior additions (correctness for the
/// disk-discovered set, not just the single builtin).
fn mintManifestCaps(
    allocator: std.mem.Allocator,
    cert_store: *identity_certs.CertStore,
    manifest: ExtensionManifest,
    out_writer: ?*const fn ([]const u8) void,
) ExtensionError!void {
    const root_id_arr = cert_store.root_id orelse return ExtensionError.no_root_cert;
    const root_id_slice: []const u8 = root_id_arr[0..];
    const root = cert_store.get(root_id_slice) catch return ExtensionError.no_root_cert;

    var merged: std.ArrayList([]u8) = .{};
    defer {
        for (merged.items) |c| allocator.free(c);
        merged.deinit(allocator);
    }
    for (root.capabilities) |c| {
        const dup = allocator.dupe(u8, c) catch return ExtensionError.out_of_memory;
        merged.append(allocator, dup) catch return ExtensionError.out_of_memory;
    }
    var added: usize = 0;
    for (manifest.capabilities) |new_cap| {
        if (containsName(root.capabilities, new_cap.name)) continue;
        const dup = allocator.dupe(u8, new_cap.name) catch return ExtensionError.out_of_memory;
        merged.append(allocator, dup) catch return ExtensionError.out_of_memory;
        added += 1;
    }
    cert_store.setRootCapabilities(merged.items) catch return ExtensionError.store_error;

    if (out_writer) |w| {
        var buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "[boot] D-O3 — extension '{s}' v{s}: minted {d} capabilities ({s})\n", .{
            manifest.id,
            manifest.version,
            added,
            manifest.plan_ref,
        }) catch return;
        w(line);
    }
}

/// First-boot capability mint.
///
/// SCOPE (Wave node-license NL-2, Todd 2026-05-17 — premise correction):
/// this mint is **NOT dispatch-load-bearing**. The dispatcher's
/// `CapabilitySet` is transport-supplied; the `cert:` AuthContext that
/// would derive a capset from a BRC-52 cert is an *unimplemented
/// placeholder* (`dispatcher.CertRef{placeholder}` — D-O5p). The only
/// live consumer of the operator-root cap allowlist this writes is the
/// **device-pairing flow** (`device_pair.zig` embeds it in the signed
/// `PairPayload`; `signed_bundle.zig` carries a leaf cap list). So this
/// is **device-pair / signed-bundle capability provisioning**, not
/// dispatch authorization.
///
/// The N3/N4 cap-UTXO kill-switch authorization is delivered at the
/// NL-1 federation-gate layer (`runtime/node/src/license-policy.ts`
/// `evaluateNodeCapAuthorizationFromConfig`). Retiring this mint is
/// deferred to **D-O5p** (the future dispatcher cert→`CapabilitySet`
/// wiring) — there is no dispatch path to reroute until then, and a
/// blind delete would empty paired-device cap lists. See
/// `docs/design/SELLABLE-NODE-LICENSE.md` N4 (amended).
///
/// DLO.1c (partial — Todd 2026-05-17, "Option C"): the *registry* of
/// which cartridges exist is **disk-driven** via
/// `enumerateUserInstalled` (`<data_dir>/extensions/<id>/manifest.json`)
/// — the hardcoded `BUILTIN_MANIFESTS` array is NO LONGER the registry.
/// Capability *triples* still come from the §9-mirror-gated Zig table
/// keyed by id (`manifestById`); a disk-discovered id with no §9 cap
/// mirror mints zero caps (operator cartridge — brain-core has no cap
/// table for it). First-party oddjobz is ALWAYS minted regardless of
/// on-disk state (manifest.json._notes.boot_loading V1-safety
/// contract). `data_dir == null` ⇒ builtin-only (provisioning uses
/// this; the subsequent `brain serve` boot does disk discovery).
///
/// Called from cmdServe's existing post-cert-init boot phase — NO NEW
/// TOP-LEVEL BOOT STEP (§9.8). Idempotent; `no_root_cert` before
/// `issue_root` is the expected first-run shape (callers swallow it).
pub fn mintFirstBootCapabilities(
    allocator: std.mem.Allocator,
    cert_store: *identity_certs.CertStore,
    out_writer: ?*const fn ([]const u8) void,
    data_dir: ?[]const u8,
) ExtensionError!void {
    // First-party builtin — always minted (V1-safety contract).
    try mintManifestCaps(allocator, cert_store, ODDJOBZ_MANIFEST, out_writer);

    // Disk-driven registry for everything else.
    if (data_dir) |dd| {
        const discovered = enumerateUserInstalled(allocator, dd) catch return;
        defer extension_manifest_loader.deinitManifests(allocator, discovered);
        for (discovered) |disc| {
            if (std.mem.eql(u8, disc.id, ODDJOBZ_MANIFEST.id)) continue; // already minted
            if (manifestById(disc.id)) |m| {
                try mintManifestCaps(allocator, cert_store, m, out_writer);
            }
            // discovered id with no §9 cap mirror ⇒ no caps minted.
        }
    }
}

fn containsName(existing: [][]u8, name: []const u8) bool {
    for (existing) |e| {
        if (std.mem.eql(u8, e, name)) return true;
    }
    return false;
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

test "manifest registry: oddjobz lookup hits" {
    const manifest = manifestById("oddjobz") orelse {
        try std.testing.expect(false);
        return;
    };
    try std.testing.expectEqualStrings("oddjobz", manifest.id);
    try std.testing.expectEqual(@as(usize, 6), manifest.capabilities.len);
}

test "manifest registry: unknown id misses" {
    try std.testing.expect(manifestById("nonexistent") == null);
}

test "manifest registry: chess lookup hits with single play cap" {
    const m = manifestById("chess") orelse {
        try std.testing.expect(false);
        return;
    };
    try std.testing.expectEqualStrings("chess", m.id);
    try std.testing.expectEqual(@as(usize, 1), m.capabilities.len);
    try std.testing.expectEqualStrings("cap.chess.play", m.capabilities[0].name);
    try std.testing.expectEqual(@as(u32, 0x0001_0301), m.capabilities[0].domain_flag);
    // Page 0x000103xx — distinct from oddjobz (0x000101xx) and loom-shell (0x000100xx).
    try std.testing.expect((m.capabilities[0].domain_flag & 0xFFFF_FF00) == 0x0001_0300);
}

test "oddjobz manifest: cap names mirror the TS canonical list" {
    const manifest = manifestById("oddjobz").?;
    const expected = [_][]const u8{
        "cap.oddjobz.write_customer",
        "cap.oddjobz.quote",
        "cap.oddjobz.dispatch",
        "cap.oddjobz.invoice",
        "cap.oddjobz.close",
        "cap.oddjobz.public_chat_serve",
    };
    try std.testing.expectEqual(expected.len, manifest.capabilities.len);
    for (expected, manifest.capabilities) |want, got| {
        try std.testing.expectEqualStrings(want, got.name);
    }
}

test "oddjobz manifest: domain flags sit on the canonical page 0x000101xx" {
    // Page-aligned canonical low-bits assignment per Plexus client-spec
    // requirement 2.2.2 + tech-spec §30. Oddjobz claims the 0x000101xx
    // page; loom-shell verbs (runtime/shell/src/capabilities.ts) sit one
    // page over at 0x000100xx. See cartridges/oddjobz/brain/src/capabilities.ts
    // module head for the page table.
    const manifest = manifestById("oddjobz").?;
    var seen = [_]u32{0} ** 6;
    for (manifest.capabilities, 0..) |c, i| {
        // High 24 bits = canonical oddjobz page marker.
        try std.testing.expectEqual(@as(u32, 0x000101), c.domain_flag >> 8);
        seen[i] = c.domain_flag;
    }
    // Uniqueness check.
    for (seen, 0..) |a, i| {
        for (seen, 0..) |b, j| {
            if (i != j) try std.testing.expect(a != b);
        }
    }
    // Verbatim assignments per the §O3 plan + capabilities.ts module head.
    try std.testing.expectEqual(@as(u32, 0x0001_0105), manifest.capabilities[0].domain_flag); // write_customer
    try std.testing.expectEqual(@as(u32, 0x0001_0101), manifest.capabilities[1].domain_flag); // quote
    try std.testing.expectEqual(@as(u32, 0x0001_0102), manifest.capabilities[2].domain_flag); // dispatch
    try std.testing.expectEqual(@as(u32, 0x0001_0103), manifest.capabilities[3].domain_flag); // invoice
    try std.testing.expectEqual(@as(u32, 0x0001_0104), manifest.capabilities[4].domain_flag); // close
    try std.testing.expectEqual(@as(u32, 0x0001_0106), manifest.capabilities[5].domain_flag); // public_chat_serve
}

test "oddjobz manifest: holder split — 5 operator-root, 1 node-service" {
    const manifest = manifestById("oddjobz").?;
    var operator_count: usize = 0;
    var service_count: usize = 0;
    for (manifest.capabilities) |c| {
        switch (c.holder) {
            .operator_root => operator_count += 1,
            .node_service => service_count += 1,
        }
    }
    try std.testing.expectEqual(@as(usize, 5), operator_count);
    try std.testing.expectEqual(@as(usize, 1), service_count);
}

// ─────────────────────────────────────────────────────────────────────
// DLO.1b — User-installed extension enumeration (additive)
// ─────────────────────────────────────────────────────────────────────

/// Enumerate user-installed cartridges from `<data_dir>/extensions/<id>/
/// manifest.json`. This is the ADDITIVE wiring of DLO.1a's generic
/// loader; it does NOT replace BUILTIN_MANIFESTS or change V1 capability
/// minting. Callers (cmdServe) can compose results from
/// `BUILTIN_MANIFESTS` + this list to enumerate every cartridge the
/// brain knows about — but capability minting still flows through the
/// hardcoded `mintFirstBootCapabilities` until DLO.1c migrates it.
///
/// Caller owns the returned slice; call
/// `extension_manifest_loader.deinitManifests(allocator, slice)` to free.
pub fn enumerateUserInstalled(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
) extension_manifest_loader.LoaderError![]extension_manifest_loader.ExtensionManifest {
    return extension_manifest_loader.loadAll(allocator, data_dir);
}

test "enumerateUserInstalled: empty data_dir returns empty list" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const list = try enumerateUserInstalled(std.testing.allocator, tmp_path);
    defer extension_manifest_loader.deinitManifests(std.testing.allocator, list);
    try std.testing.expectEqual(@as(usize, 0), list.len);
}

test "enumerateUserInstalled: catalogs on-disk oddjobz manifest" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("extensions/oddjobz");

    // Synthesize a minimal Phase 36A config.json that loadAll() can read.
    // This exercises the RUNTIME install convention `<data_dir>/extensions/<id>/`
    // (a separate filesystem contract from the repo source home — CC4 is
    // source-tree-only); the synthesized fields mirror cartridge.json.
    var sub = try tmp.dir.openDir("extensions/oddjobz", .{});
    defer sub.close();
    var file = try sub.createFile("manifest.json", .{});
    defer file.close();
    try file.writeAll(
        \\{"id":"oddjobz","name":"Oddjobz","version":"0.1.0","description":"trades vertical"}
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const list = try enumerateUserInstalled(std.testing.allocator, tmp_path);
    defer extension_manifest_loader.deinitManifests(std.testing.allocator, list);
    try std.testing.expectEqual(@as(usize, 1), list.len);
    try std.testing.expectEqualStrings("oddjobz", list[0].id);
    try std.testing.expectEqualStrings("Oddjobz", list[0].name);
}

test "DLO.1c Option C: BUILTIN_MANIFESTS is now the §9 cap table keyed by id (not the registry)" {
    // Post-DLO.1c (Option C): the *registry* of which cartridges exist
    // is disk-driven (enumerateUserInstalled); BUILTIN_MANIFESTS / the
    // ODDJOBZ_MANIFEST data persists ONLY as the §9-mirror-gated cap
    // table that `manifestById` looks up by id. First-party oddjobz is
    // always minted (V1-safety); disk-discovered ids mint caps iff
    // they have a §9 entry here.
    try std.testing.expectEqual(@as(usize, 2), BUILTIN_MANIFESTS.len);
    try std.testing.expectEqualStrings("oddjobz", BUILTIN_MANIFESTS[0].id);
    try std.testing.expectEqual(@as(usize, 6), BUILTIN_MANIFESTS[0].capabilities.len);
    try std.testing.expectEqualStrings("chess", BUILTIN_MANIFESTS[1].id);
    try std.testing.expectEqual(@as(usize, 1), BUILTIN_MANIFESTS[1].capabilities.len);
    // manifestById remains the §9-gated cap lookup keyed by id.
    try std.testing.expect(manifestById("oddjobz") != null);
    try std.testing.expect(manifestById("chess") != null);
    try std.testing.expect(manifestById("no-such-cartridge") == null);
}

```
