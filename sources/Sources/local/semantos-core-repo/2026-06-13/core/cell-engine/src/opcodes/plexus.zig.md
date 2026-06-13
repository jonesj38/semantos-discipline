---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/opcodes/plexus.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.000785+00:00
---

# core/cell-engine/src/opcodes/plexus.zig

```zig
// Plexus custom opcodes (0xC0-0xCF) — Phase 4
// Type enforcement, identity, and capability checking for semantic objects.
// Reference: CORE:OPCODES (opcodes.ts), PHASE-4-PLEXUS-OPCODES.md
//
// OP_WRITEPAYLOAD (0xD1) is the one Plexus-family op that lives outside
// the 0xC0-0xCF range — the original range filled up before payload-
// write semantics landed. It's carved out of the hostcall reserved
// range (0xD0-0xDF, with only 0xD0 = OP_CALLHOST in use). The executor
// dispatches it explicitly next to the 0xD0 branch and calls back
// into executePlexus with opcode 0xD1.

const std = @import("std");
const pda_mod = @import("pda");
const linearity = @import("linearity");
const constants = @import("constants");
const pointer = @import("pointer");
const host = @import("host");

pub const PlexusError = pda_mod.PDAError || linearity.LinearityError || error{
    reserved_opcode,
    invalid_pointer_cell,
    host_fetch_failed,
    invalid_header_offset,
    invalid_payload_offset,
    invalid_linearity_transition,
    invalid_cell_construction,
    sign_failed,
    // Phase W3: wallet budget opcodes
    insufficient_budget,
    invalid_refill_signature,
};

/// Budget cell payload field offsets (relative to payload start = byte 256).
/// Mirrors §6.1 of WALLET-TIER-CUSTODY.md.
///
/// Note: Tier-0 budget cells and Tier-N base key cells (§6.2) both place
/// priv_key at payload byte 0, deliberately not using the cap-type-in-byte-0
/// convention shared by other cell types. Budget cells are identified by
/// linearity=AFFINE plus domain_flag in the hot-tier range; the engine does
/// not read a capability-type byte from a budget cell's payload.
pub const BUDGET_OFFSET_PRIVKEY: u32 = 0;
pub const BUDGET_OFFSET_REMAINING: u32 = 32;
pub const BUDGET_OFFSET_EPOCH_START: u32 = 40;
pub const BUDGET_OFFSET_EPOCH_DURATION: u32 = 48;
pub const BUDGET_OFFSET_PARENT_SIG: u32 = 56;
pub const BUDGET_PARENT_SIG_LEN: u32 = 64;

/// Tier-3 vault cell payload field offsets (relative to payload start = byte 256).
/// Mirrors §6.2.1 of WALLET-TIER-CUSTODY.md extended for v0.2 multisig per
/// `docs/design/VAULT-MULTISIG-NSEQUENCE.md`.
///
/// A vault cell is a Tier-3 leaf cell extended with multisig metadata: up to
/// `VAULT_MAX_MEMBERS` (5) compressed-secp256k1 member pubkeys, an `m` threshold,
/// the relative-locktime `nSequence` (BIP-68) baked into the consuming UTXO,
/// and the parent UTXO txid that satisfies the cooldown chain (§4.4 v0.2).
///
/// Layout summary (payload bytes 0..768):
///   [00..32]    leaf_priv_key (per-tx, BRC-42 derived from vault base) — §6.2.1
///   [32..48]    protocol_hash (16 bytes)                                — §6.2.1
///   [48..63]    counterparty (33 bytes)                                 — §6.2.1
///                Note: these reuse the §6.2.1 leaf cell prefix verbatim.
///   [63..64]    threshold (u8)                                          — VAULT_OFFSET_THRESHOLD
///   [64..229]   member_pubkeys[5 * 33] (any unused slots zeroed)        — VAULT_OFFSET_MEMBER_PUBKEYS_START
///   [229..233]  nsequence (u32 LE, BIP-68 relative locktime)            — VAULT_OFFSET_NSEQUENCE
///   [233..265]  parent_txid (32 bytes — the UTXO this spend consumes)   — VAULT_OFFSET_PARENT_TXID
///   [265..768]  zero-padded
///
/// Vault cells must be LINEAR (per-tx leaf, consumed by OP_SIGN), with
/// domain_flag = 0x10000005 (Tier-3) and capability_type = TIER3_VAULT_KEY.
/// The engine itself does not introspect these offsets — `host_checkmultisig`
/// is sufficient. The constants are exposed so TS/Zig wallet glue can
/// build/parse the cell consistently across runtimes.
pub const VAULT_OFFSET_PROTOCOL_HASH: u32 = 32;
pub const VAULT_OFFSET_COUNTERPARTY: u32 = 48;
pub const VAULT_OFFSET_THRESHOLD: u32 = 63;
pub const VAULT_OFFSET_MEMBER_PUBKEYS_START: u32 = 64;
pub const VAULT_OFFSET_NSEQUENCE: u32 = 229;
pub const VAULT_OFFSET_PARENT_TXID: u32 = 233;

/// Maximum number of member pubkeys a vault cell can carry. 5 is enough for
/// 3-of-5 (the largest threshold the design contemplates) and keeps the
/// vault metadata block under 256 bytes inside the 768-byte payload.
pub const VAULT_MAX_MEMBERS: u32 = 5;
/// Compressed secp256k1 pubkey length (33 bytes; 0x02/0x03 prefix + X coord).
pub const VAULT_MEMBER_PUBKEY_LEN: u32 = 33;
/// BIP-68 bit-22 flag: when set, nSequence encodes time (512s units), else blocks.
pub const VAULT_NSEQUENCE_TYPE_FLAG: u32 = 1 << 22;
/// BIP-68 disable flag: bit 31 set ⇒ no relative locktime constraint.
pub const VAULT_NSEQUENCE_DISABLE_FLAG: u32 = 1 << 31;
/// BIP-68 value mask: low 16 bits hold the actual relative-locktime value.
pub const VAULT_NSEQUENCE_VALUE_MASK: u32 = 0xFFFF;
/// BIP-68 granularity: each unit of "time" mode = 512 seconds.
pub const VAULT_NSEQUENCE_TIME_UNIT_SECONDS: u32 = 512;

/// Dispatch a Plexus opcode (0xC0-0xCF).
pub fn executePlexus(p: *pda_mod.PDA, opcode: u8) PlexusError!void {
    switch (opcode) {
        0xC0 => try opCheckLinearType(p),
        0xC1 => try opCheckAffineType(p),
        0xC2 => try opCheckRelevantType(p),
        0xC3 => try opCheckCapability(p),
        0xC4 => try opCheckIdentity(p),
        0xC5 => try opAssertLinear(p),
        constants.OP_CHECKDOMAINFLAG => try opCheckDomainFlag(p),
        constants.OP_CHECKTYPEHASH => try opCheckTypeHash(p),
        constants.OP_DEREF_POINTER => try opDerefPointer(p),
        0xC9 => try opReadHeader(p),
        0xCA => try opCellCreate(p),
        0xCB => try opDemote(p),
        0xCC => try opReadPayload(p),
        0xCD => try opSign(p),
        0xCE => try opDecrementBudget(p),
        0xCF => try opRefillBudget(p),
        0xD1 => try opWritePayload(p),
        else => unreachable,
    }
}

/// 0xC0 OP_CHECKLINEARTYPE
/// Peek top cell. Verify linearity == LINEAR. Push TRUE.
fn opCheckLinearType(p: *pda_mod.PDA) PlexusError!void {
    const top = try p.speek();
    const lin = try linearity.getLinearity(top.data);
    if (lin != .linear) return error.linearity_check_failed;
    try pushTrue(p);
}

/// 0xC1 OP_CHECKAFFINETYPE
/// Peek top cell. Verify linearity == AFFINE. Push TRUE.
fn opCheckAffineType(p: *pda_mod.PDA) PlexusError!void {
    const top = try p.speek();
    const lin = try linearity.getLinearity(top.data);
    if (lin != .affine) return error.linearity_check_failed;
    try pushTrue(p);
}

/// 0xC2 OP_CHECKRELEVANTTYPE
/// Peek top cell. Verify linearity == RELEVANT. Push TRUE.
fn opCheckRelevantType(p: *pda_mod.PDA) PlexusError!void {
    const top = try p.speek();
    const lin = try linearity.getLinearity(top.data);
    if (lin != .relevant) return error.linearity_check_failed;
    try pushTrue(p);
}

/// 0xC3 OP_CHECKCAPABILITY
/// Failure-atomic: stack unchanged on error.
/// Stack: [cell, expected_cap] → [cell, TRUE]  (on success)
/// Stack: [cell, expected_cap] → [cell, expected_cap]  (on failure — unchanged)
fn opCheckCapability(p: *pda_mod.PDA) PlexusError!void {
    // Precheck depth before any mutation
    if (p.sdepth() < 2) return error.stack_underflow;

    // Peek both without consuming — inspect first, mutate last
    const cap_item = try p.speekAt(0); // top: expected cap
    const expected_cap: u8 = if (cap_item.len > 0) cap_item.data[0] else 0;

    const cell_item = try p.speekAt(1); // second: cell to check

    // Verify cell is LINEAR
    const lin = try linearity.getLinearity(cell_item.data);
    if (lin != .linear) return error.capability_type_mismatch;

    // Verify capability type at payload byte 0
    const actual_cap = linearity.getCapabilityType(cell_item.data) catch return error.capability_type_mismatch;
    if (actual_cap != expected_cap) return error.capability_type_mismatch;

    // All checks passed — now mutate: drop expected, push TRUE
    _ = p.spop() catch unreachable;
    try pushTrue(p);
}

/// 0xC4 OP_CHECKIDENTITY
/// Failure-atomic: stack unchanged on error.
/// Stack: [cell, expected_owner_id] → [cell, TRUE]  (on success)
/// Stack: [cell, expected_owner_id] → [cell, expected_owner_id]  (on failure — unchanged)
fn opCheckIdentity(p: *pda_mod.PDA) PlexusError!void {
    // Precheck depth before any mutation
    if (p.sdepth() < 2) return error.stack_underflow;

    // Peek both without consuming
    const id_item = try p.speekAt(0); // top: expected owner_id
    if (id_item.len < 16) return error.owner_id_mismatch;
    var expected_id: [16]u8 = undefined;
    @memcpy(&expected_id, id_item.data[0..16]);

    const cell_item = try p.speekAt(1); // second: cell to check
    const actual_id = linearity.getOwnerId(cell_item.data) catch return error.owner_id_mismatch;

    if (!std.mem.eql(u8, &actual_id, &expected_id)) return error.owner_id_mismatch;

    // All checks passed — now mutate: drop expected, push TRUE
    _ = p.spop() catch unreachable;
    try pushTrue(p);
}

/// 0xC5 OP_ASSERTLINEAR
/// Peek top cell. If linearity != LINEAR, script fails. No TRUE push — assertion only.
fn opAssertLinear(p: *pda_mod.PDA) PlexusError!void {
    const top = try p.speek();
    const lin = try linearity.getLinearity(top.data);
    if (lin != .linear) return error.linearity_check_failed;
    // No push — assertion succeeds silently
}

/// 0xC6 OP_CHECKDOMAINFLAG
/// Failure-atomic: stack unchanged on error.
/// Stack: [cell, expected_flag] → [cell, TRUE]  (on success)
/// Stack: [cell, expected_flag] → [cell, expected_flag]  (on failure — unchanged)
fn opCheckDomainFlag(p: *pda_mod.PDA) PlexusError!void {
    // Precheck depth before any mutation
    if (p.sdepth() < 2) return error.stack_underflow;

    // Peek both without consuming
    const flag_item = try p.speekAt(0); // top: expected flag
    const expected_flag = cellToU32(flag_item.data[0..flag_item.len]);

    const cell_item = try p.speekAt(1); // second: cell to check
    const actual_flag = try linearity.getDomainFlag(cell_item.data);

    if (actual_flag != expected_flag) return error.domain_flag_mismatch;

    // All checks passed — now mutate: drop expected, push TRUE
    _ = p.spop() catch unreachable;
    try pushTrue(p);
}

/// 0xC7 OP_CHECKTYPEHASH
/// Failure-atomic: stack unchanged on error.
/// Stack: [cell, expected_hash] → [cell, TRUE]  (on success)
/// Stack: [cell, expected_hash] → [cell, expected_hash]  (on failure — unchanged)
fn opCheckTypeHash(p: *pda_mod.PDA) PlexusError!void {
    // Precheck depth before any mutation
    if (p.sdepth() < 2) return error.stack_underflow;

    // Peek both without consuming
    const hash_item = try p.speekAt(0); // top: expected hash
    if (hash_item.len < 32) return error.type_hash_mismatch;
    var expected_hash: [32]u8 = undefined;
    @memcpy(&expected_hash, hash_item.data[0..32]);

    const cell_item = try p.speekAt(1); // second: cell to check
    const actual_hash = linearity.getTypeHash(cell_item.data) catch return error.type_hash_mismatch;

    if (!std.mem.eql(u8, &actual_hash, &expected_hash)) return error.type_hash_mismatch;

    // All checks passed — now mutate: drop expected, push TRUE
    _ = p.spop() catch unreachable;
    try pushTrue(p);
}

/// 0xC8 OP_DEREF_POINTER
/// Failure-atomic: peek first, validate, fetch, then mutate stack.
/// Stack unchanged on error (same pattern as opCheckCapability et al.).
/// Does NOT auto-dereference nested pointers — each level requires explicit 0xC8.
/// Pointer cells are always RELEVANT linearity.
fn opDerefPointer(p: *pda_mod.PDA) PlexusError!void {
    // Peek at the top cell WITHOUT consuming it — failure-atomic
    const item = try p.speek();
    const cell_data: *const [constants.CELL_SIZE]u8 = @ptrCast(item.data);

    // Verify it's a pointer cell (stack unchanged on failure)
    if (!pointer.isPointerCell(cell_data)) return error.invalid_pointer_cell;

    // Extract the octave address from the pointer payload
    const addr = pointer.getOctaveAddress(cell_data) catch return error.invalid_pointer_cell;

    // Call host_fetch_cell (stack still unchanged on failure)
    var fetched: [constants.CELL_SIZE]u8 = undefined;
    const ok = host.fetchCell(
        @intFromEnum(addr.octave),
        @as(u32, addr.slot),
        addr.offset,
        &fetched,
    );
    if (!ok) return error.host_fetch_failed;

    // All checks passed — now mutate: pop pointer, push fetched cell
    _ = p.spop() catch unreachable;
    try p.spush(&fetched);
}

/// 0xC9 OP_READHEADER
/// Stack: [cell, offset, size] → [cell, field_bytes]
/// Failure-atomic. Reads bytes from a cell's header region (first 256 bytes).
fn opReadHeader(p: *pda_mod.PDA) PlexusError!void {
    if (p.sdepth() < 3) return error.stack_underflow;

    const size_item = try p.speekAt(0);
    const offset_item = try p.speekAt(1);
    const cell_item = try p.speekAt(2);

    const size_val = pda_mod.cellToI64(size_item.data[0..size_item.len]);
    const offset_val = pda_mod.cellToI64(offset_item.data[0..offset_item.len]);

    if (size_val < 0 or offset_val < 0) return error.invalid_header_offset;
    const size: u32 = @intCast(@as(u64, @intCast(size_val)));
    const offset: u32 = @intCast(@as(u64, @intCast(offset_val)));

    if (offset + size > constants.HEADER_SIZE) return error.invalid_header_offset;
    if (size > pda_mod.CELL_SIZE) return error.invalid_header_offset;

    // All checks passed — mutate
    _ = p.spop() catch unreachable; // size
    _ = p.spop() catch unreachable; // offset
    // cell remains on stack

    // Extract header bytes from the cell
    var result: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    if (size > 0) {
        @memcpy(result[0..size], cell_item.data[offset..offset + size]);
    }
    try p.spushCell(&result, size);
}

/// 0xCA OP_CELLCREATE
/// Stack: [linearity, domainFlag, typeHash, ownerId] → [new_cell]
/// ownerId is on top of stack. Constructs a new cell with valid header.
fn opCellCreate(p: *pda_mod.PDA) PlexusError!void {
    if (p.sdepth() < 4) return error.stack_underflow;

    // Peek linearity to validate before any mutation
    const lin_item = try p.speekAt(3);
    const lin_val = pda_mod.cellToI64(lin_item.data[0..lin_item.len]);
    if (lin_val < 1 or lin_val > 3) return error.invalid_cell_construction;

    // All checks passed — pop all 4 arguments
    const owner_item = p.spop() catch unreachable;
    const hash_item = p.spop() catch unreachable;
    const flag_item = p.spop() catch unreachable;
    _ = p.spop() catch unreachable; // linearity

    // Construct new 1024-byte cell
    var new_cell: [constants.CELL_SIZE]u8 = [_]u8{0} ** constants.CELL_SIZE;

    // Magic bytes (offset 0, 16 bytes)
    std.mem.writeInt(u32, new_cell[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, new_cell[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, new_cell[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, new_cell[12..16], constants.MAGIC_4, .little);

    // Linearity (offset 16, 4 bytes)
    const lin_byte: u8 = @intCast(@as(u64, @intCast(lin_val)));
    std.mem.writeInt(u32, new_cell[16..20], @as(u32, lin_byte), .little);

    // Version (offset 20, 4 bytes) = 1
    std.mem.writeInt(u32, new_cell[20..24], constants.VERSION, .little);

    // Domain flag (offset 24, 4 bytes)
    const flag_val: u32 = @intCast(@as(u64, @intCast(pda_mod.cellToI64(flag_item.data[0..flag_item.len]))));
    std.mem.writeInt(u32, new_cell[24..28], flag_val, .little);

    // Type hash (offset 30, 32 bytes) — copy from hash_item
    const hash_len = @min(hash_item.len, 32);
    if (hash_len > 0) @memcpy(new_cell[30..30 + hash_len], hash_item.data[0..hash_len]);

    // Owner ID (offset 62, 16 bytes) — copy from owner_item
    // Zig 0.15 infers @min(x, 16) as u5 (smallest type holding 16), and
    // u5 can't represent the literal 62 in `62 + owner_len`. Force usize.
    const owner_len: usize = @min(owner_item.len, 16);
    if (owner_len > 0) @memcpy(new_cell[62 .. 62 + owner_len], owner_item.data[0..owner_len]);

    try p.spush(&new_cell);
}

/// 0xCB OP_DEMOTE
/// Stack: [cell, target_linearity] → [demoted_cell]
/// Failure-atomic. Only LINEAR→AFFINE and LINEAR→RELEVANT are valid transitions.
fn opDemote(p: *pda_mod.PDA) PlexusError!void {
    if (p.sdepth() < 2) return error.stack_underflow;

    const target_item = try p.speekAt(0);
    const cell_item = try p.speekAt(1);

    const target_lin = pda_mod.cellToI64(target_item.data[0..target_item.len]);

    // Read current linearity from cell header (offset 16, 4 bytes LE)
    if (cell_item.len < 20) return error.cell_too_short;
    const current_lin = @as(u32, cell_item.data[16]) |
        (@as(u32, cell_item.data[17]) << 8) |
        (@as(u32, cell_item.data[18]) << 16) |
        (@as(u32, cell_item.data[19]) << 24);

    // Valid transitions: LINEAR(1)→AFFINE(2), LINEAR(1)→RELEVANT(3)
    if (current_lin != constants.LINEARITY_LINEAR) return error.invalid_linearity_transition;
    if (target_lin != constants.LINEARITY_AFFINE and target_lin != constants.LINEARITY_RELEVANT) return error.invalid_linearity_transition;

    // All checks passed — mutate
    _ = p.spop() catch unreachable; // target
    const orig = p.spop() catch unreachable; // cell

    // Copy cell data, update linearity field at offset 16
    var demoted: pda_mod.Cell = undefined;
    @memcpy(demoted[0..orig.len], orig.data[0..orig.len]);
    const new_lin_byte: u8 = @intCast(@as(u64, @intCast(target_lin)));
    demoted[16] = new_lin_byte;
    demoted[17] = 0;
    demoted[18] = 0;
    demoted[19] = 0;

    try p.spushCell(&demoted, orig.len);
}

/// 0xCC OP_READPAYLOAD
/// Stack: [cell, offset, size] → [cell, field_bytes]
/// Failure-atomic. Reads bytes from a cell's payload region (256-1024).
fn opReadPayload(p: *pda_mod.PDA) PlexusError!void {
    if (p.sdepth() < 3) return error.stack_underflow;

    const size_item = try p.speekAt(0);
    const offset_item = try p.speekAt(1);
    const cell_item = try p.speekAt(2);

    const size_val = pda_mod.cellToI64(size_item.data[0..size_item.len]);
    const offset_val = pda_mod.cellToI64(offset_item.data[0..offset_item.len]);

    if (size_val < 0 or offset_val < 0) return error.invalid_payload_offset;
    const size: u32 = @intCast(@as(u64, @intCast(size_val)));
    const offset: u32 = @intCast(@as(u64, @intCast(offset_val)));

    // Payload starts at byte 256 and has size 768
    const payload_base: u32 = constants.HEADER_SIZE;
    if (offset + size > constants.PAYLOAD_SIZE) return error.invalid_payload_offset;
    if (size > pda_mod.CELL_SIZE) return error.invalid_payload_offset;

    // All checks passed — mutate
    _ = p.spop() catch unreachable; // size
    _ = p.spop() catch unreachable; // offset
    // cell remains on stack

    // Extract payload bytes from the cell (base + offset)
    var result: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    if (size > 0) {
        const abs_offset = payload_base + offset;
        @memcpy(result[0..size], cell_item.data[abs_offset..abs_offset + size]);
    }
    try p.spushCell(&result, size);
}

/// 0xD1 OP_WRITEPAYLOAD
/// Stack: [cell, bytes, offset] → [cell_with_payload_modified]
/// Failure-atomic. Writes `bytes` into the cell's payload region
/// (256-1024) starting at `offset` (relative to payload start). The
/// header bytes 0..256 are preserved verbatim.
///
/// Bounds:
///   - offset >= 0
///   - offset + bytes.len <= PAYLOAD_SIZE (768)
///   - cell must be a full CELL_SIZE buffer
///
/// On any bounds violation, the stack is left untouched and
/// invalid_payload_offset is returned.
fn opWritePayload(p: *pda_mod.PDA) PlexusError!void {
    if (p.sdepth() < 3) return error.stack_underflow;

    const offset_item = try p.speekAt(0);
    const bytes_item = try p.speekAt(1);
    const cell_item = try p.speekAt(2);

    const offset_val = pda_mod.cellToI64(offset_item.data[0..offset_item.len]);
    if (offset_val < 0 or offset_val > constants.PAYLOAD_SIZE) return error.invalid_payload_offset;
    const offset: u32 = @intCast(offset_val);

    const write_len: u32 = bytes_item.len;
    if (write_len > constants.PAYLOAD_SIZE) return error.invalid_payload_offset;
    if (offset + write_len > constants.PAYLOAD_SIZE) return error.invalid_payload_offset;

    if (cell_item.len < constants.CELL_SIZE) return error.cell_too_short;

    // All checks passed — mutate.
    _ = p.spop() catch unreachable; // offset
    _ = p.spop() catch unreachable; // bytes
    const orig = p.spop() catch unreachable; // cell

    var new_cell: [constants.CELL_SIZE]u8 = undefined;
    @memcpy(&new_cell, orig.data[0..constants.CELL_SIZE]);
    if (write_len > 0) {
        const abs_offset = constants.HEADER_SIZE + offset;
        @memcpy(new_cell[abs_offset .. abs_offset + write_len], bytes_item.data[0..write_len]);
    }

    try p.spush(&new_cell);
}

/// 0xCD OP_SIGN  (Phase W1 — wallet tier-key signing)
/// Stack: [key_cell, msg_digest, sighash_type] → [sig]
/// The key cell must be LINEAR (consumed on success — fresh-key-per-tx leaf)
/// or AFFINE (kept on stack — Tier-0 budget cell with embedded priv_key).
/// Failure-atomic: stack unchanged on any error.
fn opSign(p: *pda_mod.PDA) PlexusError!void {
    if (p.sdepth() < 3) return error.stack_underflow;

    // Peek all three without consuming
    const sighash_item = try p.speekAt(0);
    const msg_item = try p.speekAt(1);
    const key_item = try p.speekAt(2);

    // Validate the key cell linearity FIRST (stack unchanged on error).
    // RELEVANT keys are forbidden — vault keys must not be RELEVANT-class.
    const lin = try linearity.getLinearity(key_item.data);
    if (lin != .linear and lin != .affine) {
        return error.linearity_check_failed;
    }

    // Extract the priv_key from cell payload byte 0..32 (HEADER_SIZE = 256).
    if (key_item.len < constants.HEADER_SIZE + 32) return error.cell_too_short;
    const sk_offset: usize = constants.HEADER_SIZE;
    const sk: []const u8 = key_item.data[sk_offset .. sk_offset + 32];

    // Message digest must be exactly 32 bytes (mirrors checksig convention).
    if (msg_item.len != 32) return error.cell_too_short;
    const msg_hash: []const u8 = msg_item.data[0..32];

    // Read sighash type — single byte from script-number-encoded item. Empty = 0.
    const sighash_type: u8 = if (sighash_item.len > 0) sighash_item.data[0] else 0;

    // Sign with host_sign — DER signature, low-S normalized, no sighash byte yet.
    var sig_buf: [73]u8 = undefined; // 72-byte max DER + 1 sighash byte
    var sig_len: u32 = 0;
    const ok = host.sign(sk, msg_hash, sig_buf[0..72], &sig_len);
    if (!ok) return error.sign_failed;
    if (sig_len == 0 or sig_len > 72) return error.sign_failed;

    // Append sighash byte (BSV convention — checksig strips it before DER decode).
    sig_buf[sig_len] = sighash_type;
    sig_len += 1;

    // All checks passed — now mutate.
    _ = p.spop() catch unreachable; // sighash_type
    _ = p.spop() catch unreachable; // msg_digest
    if (lin == .linear) {
        _ = p.spop() catch unreachable; // consume LINEAR leaf key
    } // AFFINE: leave key on stack (Tier-0 fast path)

    try p.spush(sig_buf[0..sig_len]);
}

/// Read the `remaining_satoshis` u64 LE field from a budget cell payload.
fn readRemaining(cell_data: []const u8) PlexusError!u64 {
    const off = constants.HEADER_SIZE + BUDGET_OFFSET_REMAINING;
    if (cell_data.len < off + 8) return error.cell_too_short;
    return std.mem.readInt(u64, cell_data[off..][0..8], .little);
}

/// Write a new `remaining_satoshis` u64 LE into a freshly-cloned budget cell.
fn writeRemainingInPlace(cell_buf: *pda_mod.Cell, new_remaining: u64) void {
    const off = constants.HEADER_SIZE + BUDGET_OFFSET_REMAINING;
    std.mem.writeInt(u64, cell_buf[off..][0..8], new_remaining, .little);
}

/// 0xCE OP_DECREMENT_BUDGET  (Phase W3 — Tier-0 micropayment debit)
/// Stack: [budget_cell, amount] → [budget_cell']
/// Budget cell must be AFFINE (per §6.1). On success the cell is replaced
/// in place by a copy with `remaining_satoshis -= amount`.
/// Failure-atomic: stack unchanged on any error.
fn opDecrementBudget(p: *pda_mod.PDA) PlexusError!void {
    if (p.sdepth() < 2) return error.stack_underflow;

    const amount_item = try p.speekAt(0);
    const cell_item = try p.speekAt(1);

    // Validate cell linearity (must be AFFINE — budget cells stay on stack).
    const lin = try linearity.getLinearity(cell_item.data);
    if (lin != .affine) return error.linearity_check_failed;

    if (cell_item.len < pda_mod.CELL_SIZE) return error.cell_too_short;
    const remaining = try readRemaining(cell_item.data);

    // Read amount as a script i64 number, reject negatives.
    const amount_signed = pda_mod.cellToI64(amount_item.data[0..amount_item.len]);
    if (amount_signed < 0) return error.insufficient_budget;
    const amount: u64 = @intCast(amount_signed);

    if (amount > remaining) return error.insufficient_budget;
    const new_remaining = remaining - amount;

    // All checks passed — mutate.
    _ = p.spop() catch unreachable; // amount
    const orig = p.spop() catch unreachable; // cell

    var new_cell: pda_mod.Cell = undefined;
    @memcpy(&new_cell, orig.data);
    writeRemainingInPlace(&new_cell, new_remaining);

    try p.spushCell(&new_cell, orig.len);
}

/// 0xCF OP_REFILL_BUDGET  (Phase W3 — credit a Tier-0 budget under parent auth)
/// Stack: [budget_cell, refill_amount, parent_pubkey, parent_sig] → [budget_cell']
/// Verifies that `parent_sig` is a valid ECDSA signature by `parent_pubkey`
/// over HASH256(budget_cell.header || refill_amount_le8) before crediting.
/// On success, also updates the budget cell's `parent_capability_signature`
/// field to the new sig (audit trail).
/// Failure-atomic: stack unchanged on any error.
fn opRefillBudget(p: *pda_mod.PDA) PlexusError!void {
    if (p.sdepth() < 4) return error.stack_underflow;

    const sig_item = try p.speekAt(0);
    const pk_item = try p.speekAt(1);
    const amount_item = try p.speekAt(2);
    const cell_item = try p.speekAt(3);

    // Validate cell linearity (must be AFFINE).
    const lin = try linearity.getLinearity(cell_item.data);
    if (lin != .affine) return error.linearity_check_failed;

    if (cell_item.len < pda_mod.CELL_SIZE) return error.cell_too_short;
    const remaining = try readRemaining(cell_item.data);

    const amount_signed = pda_mod.cellToI64(amount_item.data[0..amount_item.len]);
    if (amount_signed < 0) return error.insufficient_budget;
    const amount: u64 = @intCast(amount_signed);

    // Build the refill message: budget cell header (256 bytes) || amount (8 LE).
    var refill_msg: [constants.HEADER_SIZE + 8]u8 = undefined;
    @memcpy(refill_msg[0..constants.HEADER_SIZE], cell_item.data[0..constants.HEADER_SIZE]);
    std.mem.writeInt(u64, refill_msg[constants.HEADER_SIZE..][0..8], amount, .little);

    var msg_hash: [32]u8 = undefined;
    host.hash256(&refill_msg, &msg_hash);

    // Verify parent_sig: pubkey_len = 33 (compressed sec1) or 65 (uncompressed).
    if (pk_item.len != 33 and pk_item.len != 65) return error.invalid_refill_signature;
    if (sig_item.len < 9 or sig_item.len > 73) return error.invalid_refill_signature;
    const ok = host.checksig(pk_item.data[0..pk_item.len], &msg_hash, sig_item.data[0..sig_item.len]);
    if (!ok) return error.invalid_refill_signature;

    // Avoid u64 overflow on credit.
    if (remaining > std.math.maxInt(u64) - amount) return error.insufficient_budget;
    const new_remaining = remaining + amount;

    // All checks passed — mutate.
    _ = p.spop() catch unreachable; // sig
    _ = p.spop() catch unreachable; // pubkey
    _ = p.spop() catch unreachable; // amount
    const orig = p.spop() catch unreachable; // cell

    var new_cell: pda_mod.Cell = undefined;
    @memcpy(&new_cell, orig.data);
    writeRemainingInPlace(&new_cell, new_remaining);

    // Record the refill sig in parent_capability_signature for audit.
    const sig_off = constants.HEADER_SIZE + BUDGET_OFFSET_PARENT_SIG;
    @memset(new_cell[sig_off .. sig_off + BUDGET_PARENT_SIG_LEN], 0);
    const copy_len = @min(@as(u32, @intCast(sig_item.len)), BUDGET_PARENT_SIG_LEN);
    @memcpy(new_cell[sig_off .. sig_off + copy_len], sig_item.data[0..copy_len]);

    try p.spushCell(&new_cell, orig.len);
}

// ── Helpers ──

fn pushTrue(p: *pda_mod.PDA) pda_mod.PDAError!void {
    try p.spush(&[_]u8{0x01});
}

/// Interpret stack item as Bitcoin Script number (sign-magnitude LE via cellToI64),
/// then clamp to u32 range. Empty → 0, negative → 0.
fn cellToU32(data: []const u8) u32 {
    if (data.len == 0) return 0;
    const val = pda_mod.cellToI64(data);
    if (val < 0) return 0;
    return @intCast(@as(u64, @intCast(val)) & 0xFFFFFFFF);
}

```
