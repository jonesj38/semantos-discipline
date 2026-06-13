---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/vectors/generate-vectors.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.353595+00:00
---

# proofs/vectors/generate-vectors.ts

```ts
#!/usr/bin/env bun
/**
 * Phase 12 D12.1: Generate differential test vectors from the Lean model.
 *
 * These vectors encode the proven behavior from the Lean theorems:
 * - LinearityK1.lean: permission matrix, LINEAR uniqueness
 * - AuthSoundnessK2.lean: identity/capability checks
 * - DomainIsolationK3.lean: domain flag checks
 * - FailureAtomicK4.lean: error paths preserve stack
 * - TerminationK5.lean: stack bounds
 *
 * Run: bun proofs/vectors/generate-vectors.ts
 */

import { writeFileSync } from "fs";
import { join } from "path";

const VECTORS_DIR = import.meta.dir;

// ── Constants matching Lean model + Zig constants.zig ──

const LINEARITY = { LINEAR: 1, AFFINE: 2, RELEVANT: 3, DEBUG: 4 };
const OPS = { duplicate: "duplicate", discard: "discard", consume: "consume", swap: "swap", inspect: "inspect" };

const MAGIC = [0xEFBEADDE, 0xBEBAFECA, 0x37133713, 0x42424242]; // LE bytes
const MAIN_STACK_DEPTH = 1024;
const AUX_STACK_DEPTH = 256;

// Test cell: 1024 bytes with header fields
function makeCell(opts: {
  linearity: number;
  domainFlag?: number;
  typeHash?: string;
  ownerId?: string;
  capabilityType?: number;
  privKey?: string;          // 64-hex priv_key written to payload byte 0..32 (OP_SIGN / budget)
  budgetRemaining?: number;  // u64 written to payload byte 32..40 (budget cells)
}) {
  const cell: any = {
    linearity: opts.linearity,
    domain_flag: opts.domainFlag ?? 1,
    type_hash: opts.typeHash ?? "aa".repeat(32),
    owner_id: opts.ownerId ?? "bb".repeat(16),
    capability_type: opts.capabilityType ?? 0,
  };
  if (opts.privKey !== undefined) cell.priv_key = opts.privKey;
  if (opts.budgetRemaining !== undefined) cell.budget_remaining = opts.budgetRemaining;
  return cell;
}

// ── Permission matrix (from Lean: Linearity.lean linearityPermits) ──

const PERMISSION_TABLE: Record<string, Record<string, boolean>> = {
  "1": { duplicate: false, discard: false, consume: true, swap: true, inspect: true },
  "2": { duplicate: false, discard: true,  consume: true, swap: true, inspect: true },
  "3": { duplicate: true,  discard: false, consume: true, swap: true, inspect: true },
  "4": { duplicate: true,  discard: true,  consume: true, swap: true, inspect: true },
};

type Vector = {
  test_id: string;
  description: string;
  kernel_invariant: string;
  lean_theorem?: string;
  setup: {
    main_stack: ReturnType<typeof makeCell>[];
    aux_stack: ReturnType<typeof makeCell>[];
    enforcement_enabled: boolean;
  };
  operation: {
    type: string;
    op?: string;
    opcode?: number;
    argument?: any;
    // `args` is the multi-arg form for opcodes like OP_READHEADER (offset + size),
    // OP_CELLCREATE (4 args), OP_SIGN (msg + sighash), OP_REFILL_BUDGET (4 args).
    // Each entry is pushed in order after the main_stack cells. Supported types:
    //   i64        — script-number-encoded (sign-magnitude LE)
    //   hex        — raw bytes from hex string
    //   capability — single-byte u8
    //   domain_flag — 4-byte u32 LE
    //   owner_id   — 16-byte from hex string
    //   type_hash  — 32-byte from hex string
    args?: Array<{ type: string; value: any }>;
    target?: string;
  };
  expected: {
    result: "ok" | "error";
    error_code?: string;
    main_sp_after: number;
    aux_sp_after?: number;
  };
};

// ── Generate linearity vectors ──

function generateLinearityVectors(): Vector[] {
  const vectors: Vector[] = [];

  // All 20 permission matrix combinations (K1)
  for (const [linStr, perms] of Object.entries(PERMISSION_TABLE)) {
    const lin = parseInt(linStr);
    const linName = ["", "LINEAR", "AFFINE", "RELEVANT", "DEBUG"][lin];

    for (const [op, allowed] of Object.entries(perms)) {
      const errorCodes: Record<string, Record<string, string>> = {
        "1": { duplicate: "cannot_duplicate_linear", discard: "cannot_discard_linear" },
        "2": { duplicate: "cannot_duplicate_affine" },
        "3": { discard: "cannot_discard_relevant" },
      };

      vectors.push({
        test_id: `K1_${linName}_${op.toUpperCase()}`,
        description: `${linName} cell ${op} ${allowed ? "permitted" : "denied"}`,
        kernel_invariant: "K1",
        lean_theorem: `linearityPermits .${linName.toLowerCase()} .${op}`,
        setup: {
          main_stack: [makeCell({ linearity: lin })],
          aux_stack: [],
          enforcement_enabled: true,
        },
        operation: { type: "linearity_check", op },
        expected: allowed
          ? { result: "ok", main_sp_after: 1 }
          : { result: "error", error_code: errorCodes[linStr]?.[op] ?? "linearity_check_failed", main_sp_after: 1 },
      });
    }
  }

  // Edge cases
  vectors.push({
    test_id: "K1_ENFORCEMENT_OFF_LINEAR_DUP",
    description: "LINEAR DUP succeeds when enforcement is disabled",
    kernel_invariant: "K1",
    setup: {
      main_stack: [makeCell({ linearity: LINEARITY.LINEAR })],
      aux_stack: [],
      enforcement_enabled: false,
    },
    operation: { type: "stack_op", op: "dup" },
    expected: { result: "ok", main_sp_after: 2 },
  });

  vectors.push({
    test_id: "K1_ENFORCEMENT_OFF_LINEAR_DROP",
    description: "LINEAR DROP succeeds when enforcement is disabled",
    kernel_invariant: "K1",
    setup: {
      main_stack: [makeCell({ linearity: LINEARITY.LINEAR })],
      aux_stack: [],
      enforcement_enabled: false,
    },
    operation: { type: "stack_op", op: "drop" },
    expected: { result: "ok", main_sp_after: 0 },
  });

  vectors.push({
    test_id: "K1_EMPTY_STACK_DUP",
    description: "DUP on empty stack returns stack_underflow",
    kernel_invariant: "K1",
    setup: { main_stack: [], aux_stack: [], enforcement_enabled: true },
    operation: { type: "stack_op", op: "dup" },
    expected: { result: "error", error_code: "stack_underflow", main_sp_after: 0 },
  });

  vectors.push({
    test_id: "K1_EMPTY_STACK_DROP",
    description: "DROP on empty stack returns stack_underflow",
    kernel_invariant: "K1",
    setup: { main_stack: [], aux_stack: [], enforcement_enabled: true },
    operation: { type: "stack_op", op: "drop" },
    expected: { result: "error", error_code: "stack_underflow", main_sp_after: 0 },
  });

  return vectors;
}

// ── Generate plexus vectors ──

function generatePlexusVectors(): Vector[] {
  const vectors: Vector[] = [];
  const linearCell = makeCell({ linearity: LINEARITY.LINEAR, domainFlag: 1, typeHash: "aa".repeat(32), ownerId: "bb".repeat(16), capabilityType: 2 });
  const affineCell = makeCell({ linearity: LINEARITY.AFFINE, domainFlag: 5, typeHash: "cc".repeat(32), ownerId: "dd".repeat(16) });
  const relevantCell = makeCell({ linearity: LINEARITY.RELEVANT, domainFlag: 10, typeHash: "ee".repeat(32), ownerId: "ff".repeat(16) });

  // 0xC0 CHECKLINEARTYPE
  vectors.push({
    test_id: "K2_CHECKLINEARTYPE_LINEAR_PASS",
    description: "0xC0 on LINEAR cell pushes TRUE",
    kernel_invariant: "K2",
    lean_theorem: "k2c_capability_requires_linear",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC0 },
    expected: { result: "ok", main_sp_after: 2 },
  });
  vectors.push({
    test_id: "K2_CHECKLINEARTYPE_AFFINE_FAIL",
    description: "0xC0 on AFFINE cell returns linearity_check_failed",
    kernel_invariant: "K2",
    setup: { main_stack: [affineCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC0 },
    expected: { result: "error", error_code: "linearity_check_failed", main_sp_after: 1 },
  });

  // 0xC1 CHECKAFFINETYPE
  vectors.push({
    test_id: "K2_CHECKAFFINETYPE_AFFINE_PASS",
    description: "0xC1 on AFFINE cell pushes TRUE",
    kernel_invariant: "K2",
    setup: { main_stack: [affineCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC1 },
    expected: { result: "ok", main_sp_after: 2 },
  });
  vectors.push({
    test_id: "K2_CHECKAFFINETYPE_LINEAR_FAIL",
    description: "0xC1 on LINEAR cell returns linearity_check_failed",
    kernel_invariant: "K2",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC1 },
    expected: { result: "error", error_code: "linearity_check_failed", main_sp_after: 1 },
  });

  // 0xC2 CHECKRELEVANTTYPE
  vectors.push({
    test_id: "K2_CHECKRELEVANTTYPE_RELEVANT_PASS",
    description: "0xC2 on RELEVANT cell pushes TRUE",
    kernel_invariant: "K2",
    setup: { main_stack: [relevantCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC2 },
    expected: { result: "ok", main_sp_after: 2 },
  });

  // 0xC3 CHECKCAPABILITY — requires LINEAR cell + matching cap byte
  vectors.push({
    test_id: "K2_CHECKCAPABILITY_MATCH",
    description: "0xC3 with matching capability on LINEAR cell pushes TRUE",
    kernel_invariant: "K2",
    lean_theorem: "k2c_capability_requires_linear",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC3, argument: { type: "capability", value: 2 } },
    expected: { result: "ok", main_sp_after: 2 },
  });
  vectors.push({
    test_id: "K2_CHECKCAPABILITY_MISMATCH",
    description: "0xC3 with mismatching capability returns capability_type_mismatch",
    kernel_invariant: "K2",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC3, argument: { type: "capability", value: 99 } },
    expected: { result: "error", error_code: "capability_type_mismatch", main_sp_after: 2 },
  });
  vectors.push({
    test_id: "K2_CHECKCAPABILITY_NOT_LINEAR",
    description: "0xC3 on non-LINEAR cell returns capability_type_mismatch",
    kernel_invariant: "K2",
    setup: { main_stack: [affineCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC3, argument: { type: "capability", value: 0 } },
    expected: { result: "error", error_code: "capability_type_mismatch", main_sp_after: 2 },
  });

  // 0xC4 CHECKIDENTITY
  vectors.push({
    test_id: "K2_CHECKIDENTITY_MATCH",
    description: "0xC4 with matching owner_id pushes TRUE",
    kernel_invariant: "K2",
    lean_theorem: "k2a_identity_mismatch_error",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC4, argument: { type: "owner_id", value: "bb".repeat(16) } },
    expected: { result: "ok", main_sp_after: 2 },
  });
  vectors.push({
    test_id: "K2_CHECKIDENTITY_MISMATCH",
    description: "0xC4 with mismatching owner_id returns owner_id_mismatch, stack unchanged",
    kernel_invariant: "K2",
    lean_theorem: "k2a_identity_mismatch_error",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC4, argument: { type: "owner_id", value: "cc".repeat(16) } },
    expected: { result: "error", error_code: "owner_id_mismatch", main_sp_after: 2 },
  });

  // 0xC5 ASSERTLINEAR
  vectors.push({
    test_id: "K2_ASSERTLINEAR_PASS",
    description: "0xC5 on LINEAR cell succeeds (no push)",
    kernel_invariant: "K2",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC5 },
    expected: { result: "ok", main_sp_after: 1 },
  });
  vectors.push({
    test_id: "K2_ASSERTLINEAR_FAIL",
    description: "0xC5 on AFFINE cell returns linearity_check_failed",
    kernel_invariant: "K2",
    setup: { main_stack: [affineCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC5 },
    expected: { result: "error", error_code: "linearity_check_failed", main_sp_after: 1 },
  });

  // 0xC6 CHECKDOMAINFLAG
  vectors.push({
    test_id: "K3_CHECKDOMAINFLAG_MATCH",
    description: "0xC6 with matching domain flag pushes TRUE",
    kernel_invariant: "K3",
    lean_theorem: "k3b_domain_flag_match",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC6, argument: { type: "domain_flag", value: 1 } },
    expected: { result: "ok", main_sp_after: 2 },
  });
  vectors.push({
    test_id: "K3_CHECKDOMAINFLAG_MISMATCH",
    description: "0xC6 with mismatching domain flag returns error, stack unchanged (K4)",
    kernel_invariant: "K3",
    lean_theorem: "k3a_domain_flag_mismatch",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC6, argument: { type: "domain_flag", value: 999 } },
    expected: { result: "error", error_code: "domain_flag_mismatch", main_sp_after: 2 },
  });

  // 0xC7 CHECKTYPEHASH
  vectors.push({
    test_id: "K3_CHECKTYPEHASH_MATCH",
    description: "0xC7 with matching type hash pushes TRUE",
    kernel_invariant: "K3",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC7, argument: { type: "type_hash", value: "aa".repeat(32) } },
    expected: { result: "ok", main_sp_after: 2 },
  });
  vectors.push({
    test_id: "K3_CHECKTYPEHASH_MISMATCH",
    description: "0xC7 with mismatching type hash returns error, stack unchanged (K4)",
    kernel_invariant: "K3",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC7, argument: { type: "type_hash", value: "ff".repeat(32) } },
    expected: { result: "error", error_code: "type_hash_mismatch", main_sp_after: 2 },
  });

  // 0xC8 DEREF_POINTER — requires host_fetch_cell (not testable in native Zig)
  // Documented here for completeness; the opcode is tested in WASM integration tests
  vectors.push({
    test_id: "K4_DEREF_POINTER_NOT_POINTER_CELL",
    description: "0xC8 on non-pointer cell returns invalid_pointer_cell, stack unchanged (K4)",
    kernel_invariant: "K4",
    lean_theorem: "k4_plexus_failure_atomic",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: { type: "plexus", opcode: 0xC8 },
    expected: { result: "error", error_code: "invalid_pointer_cell", main_sp_after: 1 },
  });

  // ── 0xC9 OP_READHEADER — read bytes from a cell's header (offset 0..256) ──
  // Stack: [cell, offset, size] → [cell, header_bytes]
  // Failure-atomic: stack unchanged on out-of-bounds read.
  vectors.push({
    test_id: "K3_READHEADER_LINEARITY_FIELD",
    description: "0xC9 reads linearity field (offset=16, size=4), cell remains on stack",
    kernel_invariant: "K3",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xC9,
      args: [
        { type: "i64", value: 16 }, // offset (linearity at byte 16)
        { type: "i64", value: 4 },  // size
      ],
    },
    expected: { result: "ok", main_sp_after: 2 },
  });
  vectors.push({
    test_id: "K4_READHEADER_OUT_OF_BOUNDS",
    description: "0xC9 with offset+size > HEADER_SIZE returns invalid_header_offset, stack unchanged (K4)",
    kernel_invariant: "K4",
    lean_theorem: "k4_plexus_failure_atomic",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xC9,
      args: [
        { type: "i64", value: 250 }, // offset
        { type: "i64", value: 10 },  // 250 + 10 > 256 (HEADER_SIZE)
      ],
    },
    expected: { result: "error", error_code: "invalid_header_offset", main_sp_after: 3 },
  });

  // ── 0xCA OP_CELLCREATE — construct a new cell from header field args ──
  // Stack: [linearity, domain_flag, type_hash, owner_id] → [new_cell]
  vectors.push({
    test_id: "K3_CELLCREATE_LINEAR_OK",
    description: "0xCA constructs a LINEAR cell with valid header; returns the new cell on stack",
    kernel_invariant: "K3",
    setup: { main_stack: [], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCA,
      args: [
        { type: "i64", value: 1 },              // linearity = LINEAR
        { type: "i64", value: 1 },              // domain_flag
        { type: "type_hash", value: "aa".repeat(32) },
        { type: "owner_id", value: "bb".repeat(16) },
      ],
    },
    expected: { result: "ok", main_sp_after: 1 },
  });
  vectors.push({
    test_id: "K4_CELLCREATE_INVALID_LINEARITY",
    description: "0xCA with linearity=0 returns invalid_cell_construction, stack unchanged (K4)",
    kernel_invariant: "K4",
    lean_theorem: "k4_plexus_failure_atomic",
    setup: { main_stack: [], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCA,
      args: [
        { type: "i64", value: 0 },              // invalid linearity
        { type: "i64", value: 1 },              // domain_flag
        { type: "type_hash", value: "aa".repeat(32) },
        { type: "owner_id", value: "bb".repeat(16) },
      ],
    },
    expected: { result: "error", error_code: "invalid_cell_construction", main_sp_after: 4 },
  });

  // ── 0xCB OP_DEMOTE — LINEAR cell can demote to AFFINE or RELEVANT only ──
  // Stack: [cell, target_linearity] → [demoted_cell]
  vectors.push({
    test_id: "K3_DEMOTE_LINEAR_TO_AFFINE",
    description: "0xCB demotes LINEAR cell to AFFINE; new cell replaces old on stack",
    kernel_invariant: "K3",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCB,
      args: [{ type: "i64", value: 2 }], // target = AFFINE
    },
    expected: { result: "ok", main_sp_after: 1 },
  });
  vectors.push({
    test_id: "K4_DEMOTE_AFFINE_TO_LINEAR_FAILS",
    description: "0xCB on AFFINE→LINEAR rejected (only LINEAR may demote); stack unchanged (K4)",
    kernel_invariant: "K4",
    lean_theorem: "k4_plexus_failure_atomic",
    setup: { main_stack: [affineCell], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCB,
      args: [{ type: "i64", value: 1 }], // target = LINEAR — invalid transition
    },
    expected: { result: "error", error_code: "invalid_linearity_transition", main_sp_after: 2 },
  });

  // ── 0xCC OP_READPAYLOAD — read bytes from a cell's payload (256..1024) ──
  // Stack: [cell, offset, size] → [cell, payload_bytes]
  vectors.push({
    test_id: "K3_READPAYLOAD_FIRST_4_BYTES",
    description: "0xCC reads first 4 payload bytes (offset=0, size=4); cell remains on stack",
    kernel_invariant: "K3",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCC,
      args: [
        { type: "i64", value: 0 }, // offset
        { type: "i64", value: 4 }, // size
      ],
    },
    expected: { result: "ok", main_sp_after: 2 },
  });
  vectors.push({
    test_id: "K4_READPAYLOAD_OUT_OF_BOUNDS",
    description: "0xCC with offset+size > PAYLOAD_SIZE returns invalid_payload_offset, stack unchanged (K4)",
    kernel_invariant: "K4",
    lean_theorem: "k4_plexus_failure_atomic",
    setup: { main_stack: [linearCell], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCC,
      args: [
        { type: "i64", value: 800 }, // offset
        { type: "i64", value: 10 },  // 800 + 10 > 768 (PAYLOAD_SIZE)
      ],
    },
    expected: { result: "error", error_code: "invalid_payload_offset", main_sp_after: 3 },
  });

  // ── 0xCD OP_SIGN (Phase W1) — sign a 32-byte digest with key cell priv_key ──
  // Stack: [key_cell, msg_digest, sighash_type] → [sig] (LINEAR consumed)
  //                                            or [key_cell, sig] (AFFINE preserved)
  //
  // Happy path requires BSVZ (default profile). The vector verifies operational
  // success and stack-depth contract, not the sig bytes themselves.
  const signKeyCellLinear = makeCell({
    linearity: LINEARITY.LINEAR,
    domainFlag: 0x10000003, // TIER1 base
    typeHash: "00".repeat(32),
    ownerId: "00".repeat(16),
    privKey: "00".repeat(31) + "42", // low-scalar deterministic test key
  });
  vectors.push({
    test_id: "K11_SIGN_LINEAR_CONSUMES_KEY",
    description: "0xCD on LINEAR key cell signs digest and consumes the key (sp 3→1)",
    kernel_invariant: "K11",
    setup: { main_stack: [signKeyCellLinear], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCD,
      args: [
        { type: "hex", value: "00".repeat(16) + "0102030405060708090a0b0c0d0e0f10" }, // 32-byte digest
        { type: "i64", value: 0x41 }, // SIGHASH_ALL | FORKID
      ],
    },
    expected: { result: "ok", main_sp_after: 1 },
  });
  vectors.push({
    test_id: "K4_SIGN_RELEVANT_CELL_REJECTED",
    description: "0xCD on RELEVANT key cell returns linearity_check_failed, stack unchanged (K4)",
    kernel_invariant: "K4",
    lean_theorem: "k4_plexus_failure_atomic",
    setup: {
      main_stack: [makeCell({
        linearity: LINEARITY.RELEVANT,
        privKey: "00".repeat(31) + "42",
      })],
      aux_stack: [],
      enforcement_enabled: true,
    },
    operation: {
      type: "plexus",
      opcode: 0xCD,
      args: [
        { type: "hex", value: "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20" },
        { type: "i64", value: 0x41 },
      ],
    },
    expected: { result: "error", error_code: "linearity_check_failed", main_sp_after: 3 },
  });

  // ── 0xCE OP_DECREMENT_BUDGET (Phase W3) — debit a Tier-0 AFFINE budget cell ──
  // Stack: [budget_cell, amount] → [budget_cell']  (in-place replacement)
  const budgetCell1M = makeCell({
    linearity: LINEARITY.AFFINE,
    domainFlag: 0x10000001, // hot/Tier-0
    typeHash: "00".repeat(32),
    ownerId: "00".repeat(16),
    budgetRemaining: 1_000_000,
  });
  const budgetCell100 = makeCell({
    linearity: LINEARITY.AFFINE,
    domainFlag: 0x10000001,
    typeHash: "00".repeat(32),
    ownerId: "00".repeat(16),
    budgetRemaining: 100,
  });
  vectors.push({
    test_id: "K11_DECREMENT_BUDGET_SIMPLE_DEBIT",
    description: "0xCE debits 12345 from a 1_000_000 budget; cell stays on stack with reduced remaining",
    kernel_invariant: "K11",
    setup: { main_stack: [budgetCell1M], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCE,
      args: [{ type: "i64", value: 12345 }],
    },
    expected: { result: "ok", main_sp_after: 1 },
  });
  vectors.push({
    test_id: "K4_DECREMENT_BUDGET_INSUFFICIENT",
    description: "0xCE with amount>remaining returns insufficient_budget, stack unchanged (K4)",
    kernel_invariant: "K4",
    lean_theorem: "k4_plexus_failure_atomic",
    setup: { main_stack: [budgetCell100], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCE,
      args: [{ type: "i64", value: 200 }], // > remaining=100
    },
    expected: { result: "error", error_code: "insufficient_budget", main_sp_after: 2 },
  });

  // ── 0xCF OP_REFILL_BUDGET (Phase W3) — credit a budget under parent signature ──
  // Stack: [budget_cell, refill_amount, parent_pubkey, parent_sig] → [budget_cell']
  // Happy path requires a real ECDSA sig generated outside the JSON; both vectors
  // here exercise the negative path with malformed/garbage inputs to confirm
  // failure-atomicity.
  vectors.push({
    test_id: "K4_REFILL_BUDGET_BAD_PUBKEY_LEN",
    description: "0xCF with parent_pubkey of wrong length returns invalid_refill_signature, stack unchanged (K4)",
    kernel_invariant: "K4",
    lean_theorem: "k4_plexus_failure_atomic",
    setup: { main_stack: [budgetCell1M], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCF,
      args: [
        { type: "i64", value: 500 },             // refill amount
        { type: "hex", value: "aa".repeat(20) }, // pubkey — must be 33 or 65 bytes, this is 20
        { type: "hex", value: "30".repeat(40) }, // garbage sig
      ],
    },
    expected: { result: "error", error_code: "invalid_refill_signature", main_sp_after: 4 },
  });
  vectors.push({
    test_id: "K4_REFILL_BUDGET_BAD_SIG",
    description: "0xCF with well-shaped pubkey but invalid sig returns invalid_refill_signature, stack unchanged (K4)",
    kernel_invariant: "K4",
    lean_theorem: "k4_plexus_failure_atomic",
    setup: { main_stack: [budgetCell1M], aux_stack: [], enforcement_enabled: true },
    operation: {
      type: "plexus",
      opcode: 0xCF,
      args: [
        { type: "i64", value: 500 },
        { type: "hex", value: "02" + "aa".repeat(32) }, // 33-byte compressed pubkey (well-shaped, random)
        { type: "hex", value: "30" + "44" + "02" + "20" + "bb".repeat(32) + "02" + "20" + "cc".repeat(32) }, // shaped-but-invalid DER (70 bytes)
      ],
    },
    expected: { result: "error", error_code: "invalid_refill_signature", main_sp_after: 4 },
  });

  // Empty stack for all plexus opcodes
  for (const op of [0xC0, 0xC1, 0xC2, 0xC5]) {
    vectors.push({
      test_id: `K4_EMPTY_STACK_0x${op.toString(16).toUpperCase()}`,
      description: `0x${op.toString(16).toUpperCase()} on empty stack returns stack_underflow`,
      kernel_invariant: "K4",
      setup: { main_stack: [], aux_stack: [], enforcement_enabled: true },
      operation: { type: "plexus", opcode: op },
      expected: { result: "error", error_code: "stack_underflow", main_sp_after: 0 },
    });
  }

  return vectors;
}

// ── Generate stack bounds vectors ──

function generateStackVectors(): Vector[] {
  const vectors: Vector[] = [];

  vectors.push({
    test_id: "K5_MAIN_STACK_DEPTH",
    description: "Main stack depth is exactly 1024",
    kernel_invariant: "K5",
    lean_theorem: "k5_execution_terminates_with_fuel",
    setup: { main_stack: [], aux_stack: [], enforcement_enabled: false },
    operation: { type: "bounds_check", target: "main_stack_depth" },
    expected: { result: "ok", main_sp_after: 0 },
  });

  vectors.push({
    test_id: "K5_AUX_STACK_DEPTH",
    description: "Aux stack depth is exactly 256",
    kernel_invariant: "K5",
    setup: { main_stack: [], aux_stack: [], enforcement_enabled: false },
    operation: { type: "bounds_check", target: "aux_stack_depth" },
    expected: { result: "ok", main_sp_after: 0, aux_sp_after: 0 },
  });

  vectors.push({
    test_id: "K5_MAIN_OVERFLOW",
    description: "Push beyond 1024 returns stack_overflow",
    kernel_invariant: "K5",
    setup: { main_stack: [], aux_stack: [], enforcement_enabled: false },
    operation: { type: "bounds_check", target: "main_overflow" },
    expected: { result: "error", error_code: "stack_overflow", main_sp_after: 1024 },
  });

  vectors.push({
    test_id: "K5_AUX_OVERFLOW",
    description: "Push beyond 256 on aux returns stack_overflow",
    kernel_invariant: "K5",
    setup: { main_stack: [], aux_stack: [], enforcement_enabled: false },
    operation: { type: "bounds_check", target: "aux_overflow" },
    expected: { result: "error", error_code: "stack_overflow", main_sp_after: 0, aux_sp_after: 256 },
  });

  vectors.push({
    test_id: "K5_EMPTY_POP",
    description: "Pop from empty main stack returns stack_underflow",
    kernel_invariant: "K5",
    setup: { main_stack: [], aux_stack: [], enforcement_enabled: false },
    operation: { type: "stack_op", op: "pop" },
    expected: { result: "error", error_code: "stack_underflow", main_sp_after: 0 },
  });

  vectors.push({
    test_id: "K7_PUSH_POP_ROUNDTRIP",
    description: "Push then pop preserves cell contents (K7 immutability)",
    kernel_invariant: "K7",
    lean_theorem: "k7a_push_preserves_cell",
    setup: { main_stack: [], aux_stack: [], enforcement_enabled: false },
    operation: { type: "roundtrip_check" },
    expected: { result: "ok", main_sp_after: 0 },
  });

  return vectors;
}

// ── Main ──

const linearityVectors = generateLinearityVectors();
const plexusVectors = generatePlexusVectors();
const stackVectors = generateStackVectors();

const total = linearityVectors.length + plexusVectors.length + stackVectors.length;

writeFileSync(join(VECTORS_DIR, "linearity-vectors.json"), JSON.stringify(linearityVectors, null, 2) + "\n");
writeFileSync(join(VECTORS_DIR, "plexus-vectors.json"), JSON.stringify(plexusVectors, null, 2) + "\n");
writeFileSync(join(VECTORS_DIR, "stack-vectors.json"), JSON.stringify(stackVectors, null, 2) + "\n");

console.log(`Generated ${total} test vectors:`);
console.log(`  linearity-vectors.json: ${linearityVectors.length} vectors`);
console.log(`  plexus-vectors.json:    ${plexusVectors.length} vectors`);
console.log(`  stack-vectors.json:     ${stackVectors.length} vectors`);

```
