---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/zig/sweep_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.565005+00:00
---

# cartridges/betterment/brain/zig/sweep_http.zig

```zig
// Betterment-practice pask sweep — GET /api/v1/betterment/sweep acceptor.
//
// Pure types + canonical constants module. The live handler lives in
// site_server/reactor.zig::reactorHandleBettermentSweep, which:
//
//   1. resolves the acceptor (or 503),
//   2. enforces GET + bearer auth via `bearer_tokens.verifyHex`,
//   3. fans `cell_store.cellsByOwner(zero_owner)` into the namespace
//      filter (cell[TYPEHASH_OFFSET..+8] == BETTERMENT_NAMESPACE_PREFIX),
//   4. emits a `{"cells":[...]}` JSON envelope and pipes it to
//      `bun run <sweep_script>` (sweep_runner.ts), returning the
//      Bun stdout as the response body.
//
// This module owns only:
//   - the route prefix constant,
//   - the canonical 1024-byte cell-header offsets the reactor walks
//     (mirrors `substrate_entity.zig`'s OFFSET_* — kept here as
//     reactor-facing names so the call sites read locally),
//   - the 8-byte BETTERMENT_NAMESPACE_PREFIX = sha256("betterment")[0:8],
//     shared by every betterment.* type hash (parity test in
//     cartridges/betterment/brain/zig/betterment_cell_specs.zig
//     line 169-174),
//   - the Acceptor struct (borrowed cell_store + bearer + script path).
//
// RENAME (2026-05-29): previously self-practice pask sweep with route
// /api/v1/self/sweep and constant SELF_NAMESPACE_PREFIX
// (06c604b332b386b6 = sha256("self")[0:8]). The cartridge was renamed
// self → betterment to free "self" for the shell identity primitive;
// new prefix is sha256("betterment")[0:8] = 06d0a049e88a982b.

const std = @import("std");

const cell_store_mod = @import("cell_store");
const bearer_tokens = @import("bearer_tokens");

pub const ROUTE: []const u8 = "/api/v1/betterment/sweep";

// Canonical 1024-byte cell layout (mirrors substrate_entity.zig).
pub const CELL_BYTES: usize = 1024;
pub const HEADER_BYTES: usize = 256;
pub const TYPEHASH_OFFSET: usize = 30;
pub const TIMESTAMP_OFFSET: usize = 78;

/// sha256("betterment")[0:8] — shared by every betterment.* type hash.
/// The reactor uses this as an 8-byte memcmp prefix at
/// cell[TYPEHASH_OFFSET..+8] to filter the zero-owner sweep down to
/// the betterment cartridge's cells.
///
/// Parity contract: must match
/// `cartridges/betterment/brain/zig/betterment_cell_specs.zig`
/// EXPECTED[*].hex[0..16] (see the "namespace prefix" test in that
/// file). If you regenerate the betterment cellType hashes, regenerate
/// this constant too.
pub const BETTERMENT_NAMESPACE_PREFIX: [8]u8 = .{
    0x06, 0xd0, 0xa0, 0x49, 0xe8, 0x8a, 0x98, 0x2b,
};

/// Borrowed wrappers + script path. The reactor holds one of these
/// for the lifetime of the server; none of the pointed-to objects
/// are owned here. cmdServe outlives the acceptor.
///
/// `cell_store` is the read seam (cellsByOwner + getCell).
/// `bearer_tokens` gates pre-flight auth.
/// `sweep_script` is the path passed to `bun run <script>`; the
/// reactor never copies it, so the slice must outlive the acceptor
/// (cmdServe holds the args buffer for the process lifetime).
pub const Acceptor = struct {
    cell_store: *const cell_store_mod.CellStore,
    bearer_tokens: *bearer_tokens.TokenStore,
    sweep_script: []const u8,
};

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure constants. The live handler conformance
// (acceptor gate, bearer rejection, namespace filter) is exercised by
// the reactor suite which can wire a real CellStore + TokenStore.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "ROUTE — canonical path" {
    try testing.expectEqualStrings("/api/v1/betterment/sweep", ROUTE);
}

test "cell layout — 256-byte header in a 1024-byte cell" {
    try testing.expectEqual(@as(usize, 1024), CELL_BYTES);
    try testing.expectEqual(@as(usize, 256), HEADER_BYTES);
    try testing.expect(TYPEHASH_OFFSET + 32 <= HEADER_BYTES);
    try testing.expect(TIMESTAMP_OFFSET + 8 <= HEADER_BYTES);
}

test "BETTERMENT_NAMESPACE_PREFIX — first 8 bytes of sha256(\"betterment\")" {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("betterment", &digest, .{});
    try testing.expectEqualSlices(u8, digest[0..8], &BETTERMENT_NAMESPACE_PREFIX);
}

```
