---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/mnca-anchor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.884458+00:00
---

# core/protocol-types/src/__tests__/mnca-anchor.test.ts

```ts
/**
 * Unit tests for the `mnca.anchor.*` wire formats (PR-8 / LOCKSCRIPT-
 * CLEAVAGE.md §7.2).
 *
 * Pinpoints:
 *   1. round-trip identity for all four payload shapes
 *   2. boundary conditions (CELL_HASH_BYTES, COMPRESSED_PUBKEY_BYTES,
 *      WORKFLOW_ID_BYTES, INLINE_COMPUTATION_PROOF_MAX_BYTES)
 *   3. strict enum validation (unknown status / outcome / error_tag)
 *   4. wire-byte layout assertions (VERSION at offset 0, LE u32 encoding)
 *   5. error paths (truncated, wrong-length, out-of-range)
 */

import { describe, it, expect } from "@jest/globals";

import {
  MNCA_ANCHOR_WIRE_VERSION,
  COMPRESSED_PUBKEY_BYTES as MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES,
  CELL_HASH_BYTES as MNCA_ANCHOR_CELL_HASH_BYTES,
  TXID_BYTES,
  WORKFLOW_ID_BYTES as MNCA_ANCHOR_WORKFLOW_ID_BYTES,
  INLINE_COMPUTATION_PROOF_MAX_BYTES,
  MNCA_ANCHOR_CREATE_INTENT_BYTES,
  MNCA_ANCHOR_BYTES,
  MNCA_TRANSITION_INTENT_PREFIX_BYTES,
  MNCA_TRANSITION_RESULT_BYTES,
  AnchorStatus,
  TransitionOutcome,
  TransitionErrorTag,
  encodeMncaAnchorCreateIntent,
  decodeMncaAnchorCreateIntent,
  encodeMncaAnchor,
  decodeMncaAnchor,
  encodeMncaAnchorTransitionIntent,
  decodeMncaAnchorTransitionIntent,
  encodeMncaAnchorTransitionResult,
  decodeMncaAnchorTransitionResult,
} from "../mnca/anchor";

function makeBytes(n: number, seed = 0): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 17 + seed) & 0xff;
  return b;
}

// ─────────────────────────── Anchor create intent ─────────────────────

describe("mnca.anchor.create.intent — round-trip + layout", () => {
  it("round-trips a typical request", () => {
    const i = {
      initialSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 1),
      initiatorPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES, 2),
      workflowId: makeBytes(MNCA_ANCHOR_WORKFLOW_ID_BYTES, 3),
    };
    const wire = encodeMncaAnchorCreateIntent(i);
    expect(wire.length).toBe(MNCA_ANCHOR_CREATE_INTENT_BYTES);
    expect(decodeMncaAnchorCreateIntent(wire)).toEqual(i);
  });

  it("stamps VERSION at offset 0", () => {
    const wire = encodeMncaAnchorCreateIntent({
      initialSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
      initiatorPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES),
      workflowId: makeBytes(MNCA_ANCHOR_WORKFLOW_ID_BYTES),
    });
    expect(wire[0]).toBe(MNCA_ANCHOR_WIRE_VERSION);
  });

  it("rejects encode with wrong-size hash / pubkey / workflowId", () => {
    expect(() =>
      encodeMncaAnchorCreateIntent({
        initialSnapshotHash: makeBytes(8),
        initiatorPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES),
        workflowId: makeBytes(MNCA_ANCHOR_WORKFLOW_ID_BYTES),
      }),
    ).toThrow(/initialSnapshotHash must be 32 bytes/);

    expect(() =>
      encodeMncaAnchorCreateIntent({
        initialSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
        initiatorPubkey: makeBytes(20),
        workflowId: makeBytes(MNCA_ANCHOR_WORKFLOW_ID_BYTES),
      }),
    ).toThrow(/initiatorPubkey must be 33 bytes/);

    expect(() =>
      encodeMncaAnchorCreateIntent({
        initialSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
        initiatorPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES),
        workflowId: makeBytes(8),
      }),
    ).toThrow(/workflowId must be 16 bytes/);
  });

  it("rejects decode of truncated payload", () => {
    expect(() => decodeMncaAnchorCreateIntent(new Uint8Array(20))).toThrow(
      /payload must be ≥ 82 bytes/,
    );
  });
});

// ─────────────────────────── Anchor (LINEAR) ──────────────────────────

describe("mnca.anchor — round-trip + layout", () => {
  it("round-trips initial anchor (zeros for prev / anchor_utxo_ref)", () => {
    const a = {
      currentSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 1),
      prevAnchorHash: new Uint8Array(MNCA_ANCHOR_CELL_HASH_BYTES),
      generation: 0,
      ownerPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES, 2),
      status: AnchorStatus.Active,
      anchorTxid: new Uint8Array(32),
      anchorVout: 0,
    };
    const wire = encodeMncaAnchor(a);
    expect(wire.length).toBe(MNCA_ANCHOR_BYTES);
    expect(decodeMncaAnchor(wire)).toEqual(a);
  });

  it("round-trips successor anchor with high generation + anchor_utxo_ref", () => {
    const a = {
      currentSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 1),
      prevAnchorHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 2),
      generation: 0xfeedbeef,
      ownerPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES, 3),
      status: AnchorStatus.Spent,
      anchorTxid: makeBytes(32, 5),
      anchorVout: 7,
    };
    const decoded = decodeMncaAnchor(encodeMncaAnchor(a));
    expect(decoded.generation).toBe(0xfeedbeef); // u32 unsignedness preserved
    expect(decoded.status).toBe(AnchorStatus.Spent);
    expect(decoded.anchorTxid).toEqual(a.anchorTxid);
    expect(decoded.anchorVout).toBe(7);
  });

  it("LE-encodes generation at offsets 65..69", () => {
    const wire = encodeMncaAnchor({
      currentSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
      prevAnchorHash: new Uint8Array(MNCA_ANCHOR_CELL_HASH_BYTES),
      generation: 0x01020304,
      ownerPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES),
      status: AnchorStatus.Active,
      anchorTxid: new Uint8Array(32),
      anchorVout: 0,
    });
    expect(wire[65]).toBe(0x04);
    expect(wire[66]).toBe(0x03);
    expect(wire[67]).toBe(0x02);
    expect(wire[68]).toBe(0x01);
  });

  it("rejects decode of unknown status", () => {
    const wire = encodeMncaAnchor({
      currentSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
      prevAnchorHash: new Uint8Array(MNCA_ANCHOR_CELL_HASH_BYTES),
      generation: 0,
      ownerPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES),
      status: AnchorStatus.Active,
      anchorTxid: new Uint8Array(32),
      anchorVout: 0,
    });
    wire[102] = 99;
    expect(() => decodeMncaAnchor(wire)).toThrow(/unknown status=99/);
  });

  // ── PR-8b-vi-1: anchor_utxo_ref extension ─────────────────────────────

  it("PR-8b-vi-1: encoder writes 139 bytes (v1 was 103)", () => {
    const wire = encodeMncaAnchor({
      currentSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
      prevAnchorHash: new Uint8Array(MNCA_ANCHOR_CELL_HASH_BYTES),
      generation: 0,
      ownerPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES),
      status: AnchorStatus.Active,
      anchorTxid: new Uint8Array(32),
      anchorVout: 0,
    });
    expect(wire.length).toBe(139);
    expect(wire.length).toBe(MNCA_ANCHOR_BYTES);
  });

  it("PR-8b-vi-1: LE-encodes anchor_vout at offsets 135..139", () => {
    const wire = encodeMncaAnchor({
      currentSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
      prevAnchorHash: new Uint8Array(MNCA_ANCHOR_CELL_HASH_BYTES),
      generation: 0,
      ownerPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES),
      status: AnchorStatus.Active,
      anchorTxid: makeBytes(32, 7),
      anchorVout: 0x01020304,
    });
    // anchor_txid at offsets 103..135
    expect(wire.slice(103, 135)).toEqual(makeBytes(32, 7));
    expect(wire[135]).toBe(0x04);
    expect(wire[136]).toBe(0x03);
    expect(wire[137]).toBe(0x02);
    expect(wire[138]).toBe(0x01);
  });

  it("PR-8b-vi-1: decoder accepts legacy v1 (103-byte) payload with zero utxo_ref", () => {
    // Synthesize a v1-style 103-byte payload (no anchor_utxo_ref tail).
    const legacy = new Uint8Array(103);
    legacy[0] = 1; // VERSION
    legacy.set(makeBytes(32, 1), 1); // currentSnapshotHash
    legacy.set(makeBytes(32, 2), 33); // prevAnchorHash
    legacy[65] = 5; // generation = 5
    legacy.set(makeBytes(33, 3), 69); // ownerPubkey
    legacy[102] = AnchorStatus.Active;

    const decoded = decodeMncaAnchor(legacy);
    expect(decoded.generation).toBe(5);
    expect(decoded.status).toBe(AnchorStatus.Active);
    // anchor_utxo_ref defaults to zeros when reading legacy payload.
    expect(decoded.anchorTxid).toEqual(new Uint8Array(32));
    expect(decoded.anchorVout).toBe(0);
  });

  it("PR-8b-vi-1: decoder preserves anchor_utxo_ref through round-trip", () => {
    const a = {
      currentSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 1),
      prevAnchorHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 2),
      generation: 100,
      ownerPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES, 3),
      status: AnchorStatus.Active,
      anchorTxid: makeBytes(32, 11), // non-zero txid
      anchorVout: 1,
    };
    const decoded = decodeMncaAnchor(encodeMncaAnchor(a));
    expect(decoded).toEqual(a);
  });

  it("PR-8b-vi-1: encoder rejects wrong-size anchorTxid", () => {
    expect(() =>
      encodeMncaAnchor({
        currentSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
        prevAnchorHash: new Uint8Array(MNCA_ANCHOR_CELL_HASH_BYTES),
        generation: 0,
        ownerPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES),
        status: AnchorStatus.Active,
        anchorTxid: makeBytes(16), // wrong size
        anchorVout: 0,
      }),
    ).toThrow(/anchorTxid must be 32 bytes/);
  });

  it("PR-8b-vi-1: encoder rejects anchorVout out of u32 range", () => {
    expect(() =>
      encodeMncaAnchor({
        currentSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
        prevAnchorHash: new Uint8Array(MNCA_ANCHOR_CELL_HASH_BYTES),
        generation: 0,
        ownerPubkey: makeBytes(MNCA_ANCHOR_COMPRESSED_PUBKEY_BYTES),
        status: AnchorStatus.Active,
        anchorTxid: new Uint8Array(32),
        anchorVout: 0x1_0000_0000, // > u32 max
      }),
    ).toThrow(/anchorVout out of u32 range/);
  });
});

// ─────────────────────────── Transition intent ────────────────────────

describe("mnca.anchor.transition.intent — round-trip + layout", () => {
  it("round-trips with empty computation proof", () => {
    const t = {
      predecessorAnchorHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 1),
      nextSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 2),
      nextGeneration: 1,
      computationProof: new Uint8Array(),
    };
    const wire = encodeMncaAnchorTransitionIntent(t);
    expect(wire.length).toBe(MNCA_TRANSITION_INTENT_PREFIX_BYTES);
    expect(decodeMncaAnchorTransitionIntent(wire)).toEqual(t);
  });

  it("round-trips with a small proof", () => {
    const t = {
      predecessorAnchorHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 1),
      nextSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 2),
      nextGeneration: 42,
      computationProof: makeBytes(128, 3),
    };
    const wire = encodeMncaAnchorTransitionIntent(t);
    const decoded = decodeMncaAnchorTransitionIntent(wire);
    expect(decoded.computationProof).toEqual(t.computationProof);
    expect(decoded.nextGeneration).toBe(42);
  });

  it("round-trips at INLINE_COMPUTATION_PROOF_MAX_BYTES boundary", () => {
    const t = {
      predecessorAnchorHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 1),
      nextSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES, 2),
      nextGeneration: 1,
      computationProof: makeBytes(INLINE_COMPUTATION_PROOF_MAX_BYTES, 4),
    };
    const decoded = decodeMncaAnchorTransitionIntent(
      encodeMncaAnchorTransitionIntent(t),
    );
    expect(decoded.computationProof.length).toBe(
      INLINE_COMPUTATION_PROOF_MAX_BYTES,
    );
  });

  it("rejects encode over INLINE_COMPUTATION_PROOF_MAX_BYTES", () => {
    expect(() =>
      encodeMncaAnchorTransitionIntent({
        predecessorAnchorHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
        nextSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
        nextGeneration: 1,
        computationProof: makeBytes(INLINE_COMPUTATION_PROOF_MAX_BYTES + 1),
      }),
    ).toThrow(/exceeds inline cap/);
  });

  it("rejects decode of truncated payload (declared len > actual)", () => {
    const wire = encodeMncaAnchorTransitionIntent({
      predecessorAnchorHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
      nextSnapshotHash: makeBytes(MNCA_ANCHOR_CELL_HASH_BYTES),
      nextGeneration: 1,
      computationProof: makeBytes(8),
    });
    // Inflate the declared proof_len without growing the buffer.
    wire[69] = 200;
    wire[70] = 0;
    wire[71] = 0;
    wire[72] = 0;
    expect(() => decodeMncaAnchorTransitionIntent(wire)).toThrow(/truncated/);
  });
});

// ─────────────────────────── Transition result ────────────────────────

describe("mnca.anchor.transition.result — round-trip + layout", () => {
  it("round-trips Pending outcome (txid zero, error_tag None)", () => {
    const r = {
      outcome: TransitionOutcome.Pending,
      txid: new Uint8Array(TXID_BYTES),
      errorTag: TransitionErrorTag.None,
      confirmedGeneration: 0,
    };
    const wire = encodeMncaAnchorTransitionResult(r);
    expect(wire.length).toBe(MNCA_TRANSITION_RESULT_BYTES);
    expect(decodeMncaAnchorTransitionResult(wire)).toEqual(r);
  });

  it("round-trips Accepted with txid + high confirmedGeneration", () => {
    const r = {
      outcome: TransitionOutcome.Accepted,
      txid: makeBytes(TXID_BYTES, 1),
      errorTag: TransitionErrorTag.None,
      confirmedGeneration: 0xfeedbeef,
    };
    const decoded = decodeMncaAnchorTransitionResult(
      encodeMncaAnchorTransitionResult(r),
    );
    expect(decoded.outcome).toBe(TransitionOutcome.Accepted);
    expect(decoded.confirmedGeneration).toBe(0xfeedbeef);
    expect(decoded.txid).toEqual(r.txid);
  });

  it("round-trips Rejected with each TransitionErrorTag", () => {
    for (const tag of Object.values(TransitionErrorTag) as number[]) {
      const r = {
        outcome: TransitionOutcome.Rejected,
        txid: new Uint8Array(TXID_BYTES),
        errorTag: tag as TransitionErrorTag,
        confirmedGeneration: 0,
      };
      const decoded = decodeMncaAnchorTransitionResult(
        encodeMncaAnchorTransitionResult(r),
      );
      expect(decoded.errorTag).toBe(tag);
    }
  });

  it("rejects decode of unknown outcome", () => {
    const wire = encodeMncaAnchorTransitionResult({
      outcome: TransitionOutcome.Pending,
      txid: new Uint8Array(TXID_BYTES),
      errorTag: TransitionErrorTag.None,
      confirmedGeneration: 0,
    });
    wire[1] = 99;
    expect(() => decodeMncaAnchorTransitionResult(wire)).toThrow(
      /unknown outcome=99/,
    );
  });

  it("rejects decode of unknown error_tag", () => {
    const wire = encodeMncaAnchorTransitionResult({
      outcome: TransitionOutcome.Pending,
      txid: new Uint8Array(TXID_BYTES),
      errorTag: TransitionErrorTag.None,
      confirmedGeneration: 0,
    });
    wire[34] = 99;
    expect(() => decodeMncaAnchorTransitionResult(wire)).toThrow(
      /unknown error_tag=99/,
    );
  });
});

```
