---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/swarm/brain/access_grant_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.678322+00:00
---

# cartridges/swarm/brain/access_grant_handler.zig

```zig
// DAM-2 — the access-grant VERIFY `.handler` (engine-checked, runs on the real 2-PDA).
//
// Companion to DAM-1 (access_grant_context.zig). The brain's mint/dispatch
// pipeline (cells_mint_handler.dispatchCellScriptHandler) runs this bytecode
// AFTER the ScriptContextBuilder has:
//   - gated on the `access.grant.verify.intent` typeHash,
//   - loaded the LINEAR `access.grant` cell + checked DATA_ACCESS + expiry,
//   - computed the canonical BIP-143 challenge digest (accessChallengeDigest),
//   - set a host_verify_partial_sig.Context {pubkey=grantee, digest, signature},
//   - pushed the grant cell onto the PDA stack at slot 1 (extra_cells_fn).
//
// Stack at handler entry (per the dispatcher's push order):
//   slot 0 (bottom) = the input `access.grant.verify.intent` cell
//   slot 1 (TOP)    = the `access.grant` cell (pushed by extra_cells_fn)
//
// So the grant is already on top — no OP_PICK needed (the DAM handoff's
// pseudocode assumed the opposite order; the real PR4b push order is
// input-first/extra-second, verified against cells_mint_handler.zig).
//
// ── The handler (cell-engine assembly) ────────────────────────────────────
//
//   OP_2                          # push expected capability = DATA_ACCESS(2)
//   OP_CHECKCAPABILITY            # [grant, 2] -> [grant, TRUE]; trap (capability_type_mismatch)
//                                 #   if grant !LINEAR or cap != 2. Defence-in-depth:
//                                 #   the builder already checked, but the engine re-asserts.
//   OP_DROP                       # drop the TRUE marker -> [intent, grant]
//   PUSH "host_verify_partial_sig"
//   OP_CALLHOST                   # rc=0 (valid) pushes EMPTY/falsy; rc!=0 pushes truthy.
//                                 #   (OP_CALLHOST convention: i64ToCell(0) == empty.)
//   OP_0                          # push empty
//   OP_EQUAL                      # rc == empty?  valid -> TRUE, invalid -> FALSE
//   OP_VERIFY                     # trap (verify_failed) unless the sig verified
//   OP_DROP                       # drop the grant cell -> [intent]. The dispatcher's
//                                 #   emit-walker treats ANY full-1024B non-input stack
//                                 #   slot as an emitted cell (gated by emits[]); leaving
//                                 #   the grant on the stack trips emit_outside_allowlist.
//   # ── grant path: emit the access.grant.verify.result{ok} cell ──
//   OP_3                          # linearity field = RELEVANT(3) (OP_CELLCREATE needs 1..3;
//                                 #   the result is substrate-EPHEMERAL, refined in DAM-4)
//   OP_0                          # domainFlag = 0
//   PUSH <RESULT_TYPE_HASH:32>    # access.grant.verify.result typeHash
//   PUSH <ownerId:16>             # owner placeholder (DAM-4 stamps the real owner)
//   OP_CELLCREATE                 # [lin, flag, typeHash, owner] -> [result_cell]
//   OP_1                          # payload byte value = 1 (ok)
//   OP_0                          # payload offset = 0
//   OP_WRITEPAYLOAD               # result.payload[0] = 1  -> [intent, result']
//   # final stack = [intent, result] — only the input + the emitted result are
//   # full cells; top = result cell (1024B, non-zero magic) -> truthy
//
// DAM-2 proves the two REJECT paths on the real 2-PDA (they trap BEFORE
// OP_CELLCREATE, so no valid ECDSA signature is needed — see the inline
// tests). The GRANT (valid-sig) path is exercised end-to-end from TS in
// DAM-3, where signing the challenge digest with the edge key is trivial.

const std = @import("std");

// ── Opcodes (mirrors core/cell-engine/src/opcodes/{standard,plexus}.zig
//    + constants.zig; duplicated as named literals so the bytecode below
//    reads as assembly without importing the whole engine into this leaf). ──
const OP_0: u8 = 0x00;
const OP_1: u8 = 0x51;
const OP_2: u8 = 0x52;
const OP_3: u8 = 0x53;
const OP_DROP: u8 = 0x75;
const OP_VERIFY: u8 = 0x69;
const OP_EQUAL: u8 = 0x87;
const OP_CHECKCAPABILITY: u8 = 0xC3;
const OP_CELLCREATE: u8 = 0xCA;
const OP_CALLHOST: u8 = 0xD0;
const OP_WRITEPAYLOAD: u8 = 0xD1;

/// The capability byte an `access.grant` must carry (linearity.zig:
/// 2 = DATA_ACCESS).
pub const CAP_DATA_ACCESS: u8 = 2;

/// The hostcall the handler invokes to verify the grantee's challenge
/// signature against the builder-supplied Context.
pub const HVPS_NAME = "host_verify_partial_sig";

fn sha256OfStr(comptime s: []const u8) [32]u8 {
    @setEvalBranchQuota(10000);
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(s, &out, .{});
    return out;
}

/// sha256("access.grant.verify.result") — the EPHEMERAL result cell the
/// handler emits on the grant path. Registered into the verify-intent
/// handler's `emits[]` allowlist in DAM-4.
pub const RESULT_TYPE_HASH: [32]u8 = sha256OfStr("access.grant.verify.result");

/// Owner placeholder for the emitted result. DAM-4 stamps the real owner
/// (the grant owner / brain identity); reject-path tests never reach
/// OP_CELLCREATE so the value is immaterial for DAM-2.
const RESULT_OWNER_PLACEHOLDER = [_]u8{0} ** 16;

const HANDLER_BYTES =
    // capability gate
    [_]u8{ OP_2, OP_CHECKCAPABILITY, OP_DROP } ++
    // signature gate: push the hostcall name, call it, assert rc == 0
    [_]u8{HVPS_NAME.len} ++ HVPS_NAME[0..HVPS_NAME.len].* ++
    [_]u8{ OP_CALLHOST, OP_0, OP_EQUAL, OP_VERIFY } ++
    // drop the grant cell so the dispatcher's emit-walker doesn't treat it as an
    // emitted cell (any full-1024B non-input stack slot is gated by emits[]).
    [_]u8{OP_DROP} ++
    // emit access.grant.verify.result{ok}
    [_]u8{ OP_3, OP_0 } ++
    [_]u8{32} ++ RESULT_TYPE_HASH ++
    [_]u8{16} ++ RESULT_OWNER_PLACEHOLDER ++
    [_]u8{OP_CELLCREATE} ++
    [_]u8{ OP_1, OP_0, OP_WRITEPAYLOAD };

/// The verify-intent `.handler` bytecode. Stored as raw bytes here;
/// DAM-4 registers it under the `access.grant.verify.intent` typeHash
/// (the committed manifests carry handlers as hex of exactly these bytes).
pub const VERIFY_INTENT_HANDLER: []const u8 = &HANDLER_BYTES;

// ── Inline tests — the handler on the REAL 2-PDA (PR4b harness pattern) ────
//
// These drive the handler directly (manual stack push + manual sig Context),
// mirroring cells_mint_handler.zig's PR4b integration tests. The composite
// builder+handler end-to-end test lands in DAM-4; DAM-1's builder is already
// covered by its own 6 inline tests.

const testing = std.testing;
const executor = @import("executor");
const pda_mod = @import("pda");
const allocator_mod = @import("allocator");
const host = @import("host");
const hvps = @import("host_verify_partial_sig");
const constants = @import("constants");

const CELL_SIZE = constants.CELL_SIZE;
const HEADER_SIZE = constants.HEADER_SIZE; // 256
const HDR_LINEARITY_OFF = 16; // u32 LE — LINEAR(1)/AFFINE(2)/RELEVANT(3)
const ARENA_SIZE: usize = 64 * 1024; // == cells_mint_handler.HANDLER_ARENA_SIZE

/// Linearity field values (linearity.zig: LINEAR=1, AFFINE=2, RELEVANT=3).
const LINEARITY_LINEAR: u32 = 1;
const LINEARITY_RELEVANT: u32 = 3;

/// A minimal `access.grant` cell for the handler's OP_CHECKCAPABILITY gate:
/// a valid linearity field (offset 16) + the capability byte at payload[0].
/// That's all OP_CHECKCAPABILITY reads; the rest of the grant layout
/// (pubkey/expiry) is the builder's concern, already tested in DAM-1.
fn makeGrantCell(linearity_val: u32, cap: u8) [CELL_SIZE]u8 {
    var c: [CELL_SIZE]u8 = [_]u8{0} ** CELL_SIZE;
    std.mem.writeInt(u32, c[HDR_LINEARITY_OFF .. HDR_LINEARITY_OFF + 4][0..4], linearity_val, .little);
    c[HEADER_SIZE] = cap; // payload[0] = capability_type
    return c;
}

/// The input cell sits at slot 0, untouched by the reject paths — content
/// is immaterial (the emit-walker only runs on success, which DAM-2 doesn't
/// reach). A distinct fill keeps it visually separable from the grant.
fn makeIntentCell() [CELL_SIZE]u8 {
    return [_]u8{0xAA} ** CELL_SIZE;
}

const Harness = struct {
    pda: *pda_mod.PDA,
    arena_buf: []u8,
    arena: allocator_mod.ScriptArena,
    ctx: executor.ExecutionContext,

    fn init() !Harness {
        const pda = try testing.allocator.create(pda_mod.PDA);
        pda.initInPlace(1000);
        const arena_buf = try testing.allocator.alloc(u8, ARENA_SIZE);
        var h = Harness{
            .pda = pda,
            .arena_buf = arena_buf,
            .arena = allocator_mod.ScriptArena.init(arena_buf),
            .ctx = undefined,
        };
        h.ctx = executor.ExecutionContext.init(h.pda, &h.arena);
        return h;
    }

    fn deinit(self: *Harness) void {
        testing.allocator.free(self.arena_buf);
        testing.allocator.destroy(self.pda);
    }

    /// Push input cell at slot 0, grant at slot 1 — the dispatcher's order.
    fn pushCells(self: *Harness, intent: *const [CELL_SIZE]u8, grant: *const [CELL_SIZE]u8) !void {
        try self.pda.spushCell(intent, CELL_SIZE);
        try self.pda.spushCell(grant, CELL_SIZE);
    }
};

test "DAM-2 handler: wrong capability traps at OP_CHECKCAPABILITY" {
    var h = try Harness.init();
    defer h.deinit();

    const intent = makeIntentCell();
    const grant = makeGrantCell(LINEARITY_LINEAR, 5); // LINEAR but cap=TRANSFER(5), not DATA_ACCESS
    try h.pushCells(&intent, &grant);

    try h.ctx.loadScript(VERIFY_INTENT_HANDLER);
    // OP_CHECKCAPABILITY rejects cap mismatch BEFORE the sig gate / OP_CELLCREATE.
    try testing.expectError(error.capability_type_mismatch, executor.execute(&h.ctx));
}

test "DAM-2 handler: non-LINEAR grant traps at OP_CHECKCAPABILITY" {
    var h = try Harness.init();
    defer h.deinit();

    const intent = makeIntentCell();
    // A well-formed RELEVANT cell carrying the right cap byte — but the access
    // grant MUST be LINEAR (revocable state), so the cap gate rejects it.
    const grant = makeGrantCell(LINEARITY_RELEVANT, CAP_DATA_ACCESS);
    try h.pushCells(&intent, &grant);

    try h.ctx.loadScript(VERIFY_INTENT_HANDLER);
    // getLinearity -> .relevant; OP_CHECKCAPABILITY requires .linear -> mismatch.
    try testing.expectError(error.capability_type_mismatch, executor.execute(&h.ctx));
}

test "DAM-2 handler: bad challenge signature traps at OP_VERIFY" {
    host.resetRegistryForTest();
    try hvps.register();

    var h = try Harness.init();
    defer h.deinit();

    const intent = makeIntentCell();
    const grant = makeGrantCell(LINEARITY_LINEAR, CAP_DATA_ACCESS); // passes the capability gate
    try h.pushCells(&intent, &grant);

    // A syntactically-valid but cryptographically-bogus triple — host.checksig
    // returns false -> rc = RC_REJECTED(1) -> OP_0 OP_EQUAL -> FALSE -> OP_VERIFY traps.
    var pubkey = [_]u8{0x02} ** 33;
    var digest = [_]u8{0xAB} ** 32;
    var sig = [_]u8{0x30} ** 70;
    var sig_ctx = hvps.Context{ .pubkey = &pubkey, .digest = &digest, .signature = &sig };
    host.setExecutionContext(@ptrCast(&sig_ctx));
    defer host.setExecutionContext(null);

    try h.ctx.loadScript(VERIFY_INTENT_HANDLER);
    try testing.expectError(error.verify_failed, executor.execute(&h.ctx));
}

test "DAM-2 handler: bytecode shape is the cap gate -> sig gate -> emit" {
    // Guard the byte layout so an accidental edit can't silently reshape the
    // handler (the gates' relative order is load-bearing — see the header).
    const b = VERIFY_INTENT_HANDLER;
    // cap gate
    try testing.expectEqual(OP_2, b[0]);
    try testing.expectEqual(OP_CHECKCAPABILITY, b[1]);
    try testing.expectEqual(OP_DROP, b[2]);
    // name push
    try testing.expectEqual(@as(u8, HVPS_NAME.len), b[3]);
    try testing.expectEqualSlices(u8, HVPS_NAME, b[4 .. 4 + HVPS_NAME.len]);
    // sig gate immediately after the name
    const after_name = 4 + HVPS_NAME.len;
    try testing.expectEqual(OP_CALLHOST, b[after_name]);
    try testing.expectEqual(OP_0, b[after_name + 1]);
    try testing.expectEqual(OP_EQUAL, b[after_name + 2]);
    try testing.expectEqual(OP_VERIFY, b[after_name + 3]);
    // grant cell dropped before the emit (else the walker flags it as an emit)
    try testing.expectEqual(OP_DROP, b[after_name + 4]);
    // ends with the payload write
    try testing.expectEqual(OP_WRITEPAYLOAD, b[b.len - 1]);
    // result typeHash is the canonical sha256
    try testing.expectEqualSlices(u8, &sha256OfStr("access.grant.verify.result"), &RESULT_TYPE_HASH);
}

```
