---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/bsv-tx-broadcast.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.885884+00:00
---

# core/protocol-types/src/__tests__/bsv-tx-broadcast.test.ts

```ts
/**
 * Unit tests for the `bsv.tx.assemble.intent` / `bsv.tx.broadcast.intent`
 * / `bsv.tx.broadcast.result` wire formats (PR-6 / LOCKSCRIPT-CLEAVAGE.md
 * §8.3).
 */

import { describe, it, expect } from "@jest/globals";

import {
  TX_BROADCAST_WIRE_VERSION,
  INLINE_TX_MAX_BYTES,
  TX_ASSEMBLE_INTENT_BYTES,
  TX_BROADCAST_INTENT_PREFIX_BYTES,
  TX_BROADCAST_RESULT_BYTES,
  TxAssembleIntentFlag,
  TxBroadcastOutcome,
  TxBroadcastArcStatus,
  encodeTxAssembleIntent,
  decodeTxAssembleIntent,
  encodeTxBroadcastIntent,
  decodeTxBroadcastIntent,
  encodeTxBroadcastResult,
  decodeTxBroadcastResult,
} from "../bsv/tx-broadcast";
import { CELL_HASH_BYTES } from "../bsv/tx-partial";

function makeBytes(n: number, seed = 0): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 17 + seed) & 0xff;
  return b;
}

// ─────────────────────────── Assemble intent ──────────────────────────

describe("bsv.tx.assemble.intent — round-trip + layout", () => {
  it("round-trips zero-flags", () => {
    const a = { shellCellHash: makeBytes(CELL_HASH_BYTES, 1), flags: 0 };
    const wire = encodeTxAssembleIntent(a);
    expect(wire.length).toBe(TX_ASSEMBLE_INTENT_BYTES);
    expect(decodeTxAssembleIntent(wire)).toEqual(a);
  });

  it("round-trips with both flags set", () => {
    const a = {
      shellCellHash: makeBytes(CELL_HASH_BYTES, 2),
      flags:
        TxAssembleIntentFlag.DropChange |
        TxAssembleIntentFlag.BundleBeef,
    };
    expect(decodeTxAssembleIntent(encodeTxAssembleIntent(a))).toEqual(a);
  });

  it("rejects encode with undeclared flag bits", () => {
    expect(() =>
      encodeTxAssembleIntent({
        shellCellHash: makeBytes(CELL_HASH_BYTES),
        flags: 0x80, // bit 7 — not declared
      }),
    ).toThrow(/undeclared flag bits/);
  });

  it("rejects encode with wrong shellCellHash size", () => {
    expect(() =>
      encodeTxAssembleIntent({
        shellCellHash: makeBytes(20),
        flags: 0,
      }),
    ).toThrow(/shellCellHash must be 32 bytes/);
  });

  it("rejects decode with non-zero reserved bytes", () => {
    const wire = encodeTxAssembleIntent({
      shellCellHash: makeBytes(CELL_HASH_BYTES),
      flags: 0,
    });
    wire[35] = 1;
    expect(() => decodeTxAssembleIntent(wire)).toThrow(
      /reserved bytes must be 0/,
    );
  });
});

// ─────────────────────────── Broadcast intent ─────────────────────────

describe("bsv.tx.broadcast.intent — round-trip + layout", () => {
  it("round-trips a small tx", () => {
    const b = { txBytes: makeBytes(64, 1) };
    const wire = encodeTxBroadcastIntent(b);
    expect(wire.length).toBe(TX_BROADCAST_INTENT_PREFIX_BYTES + 64);
    expect(decodeTxBroadcastIntent(wire)).toEqual(b);
  });

  it("round-trips at INLINE_TX_MAX_BYTES boundary", () => {
    const b = { txBytes: makeBytes(INLINE_TX_MAX_BYTES, 2) };
    const wire = encodeTxBroadcastIntent(b);
    expect(wire.length).toBe(
      TX_BROADCAST_INTENT_PREFIX_BYTES + INLINE_TX_MAX_BYTES,
    );
    const decoded = decodeTxBroadcastIntent(wire);
    expect(decoded.txBytes.length).toBe(INLINE_TX_MAX_BYTES);
  });

  it("stamps VERSION + Inline flag", () => {
    const wire = encodeTxBroadcastIntent({ txBytes: makeBytes(8) });
    expect(wire[0]).toBe(TX_BROADCAST_WIRE_VERSION);
    expect(wire[1] & 1).toBe(1); // Inline bit set
  });

  it("rejects encode of empty tx", () => {
    expect(() => encodeTxBroadcastIntent({ txBytes: new Uint8Array() })).toThrow(
      /out of range/,
    );
  });

  it("rejects encode over INLINE_TX_MAX_BYTES", () => {
    expect(() =>
      encodeTxBroadcastIntent({ txBytes: makeBytes(INLINE_TX_MAX_BYTES + 1) }),
    ).toThrow(/out of range.*use a carriage chain/);
  });

  it("rejects decode without inline flag set", () => {
    const wire = encodeTxBroadcastIntent({ txBytes: makeBytes(8) });
    wire[1] = 0;
    expect(() => decodeTxBroadcastIntent(wire)).toThrow(
      /only inline form supported/,
    );
  });

  it("rejects decode of truncated payload (declared length > actual)", () => {
    const wire = encodeTxBroadcastIntent({ txBytes: makeBytes(8) });
    // Inflate declared tx_bytes_len without growing the buffer.
    wire[2] = 64;
    wire[3] = 0;
    expect(() => decodeTxBroadcastIntent(wire)).toThrow(/payload truncated/);
  });
});

// ─────────────────────────── Broadcast result ─────────────────────────

describe("bsv.tx.broadcast.result — round-trip + layout", () => {
  it("round-trips Accepted with confirmations", () => {
    const r = {
      outcome: TxBroadcastOutcome.Accepted,
      txid: makeBytes(32, 1),
      arcStatus: TxBroadcastArcStatus.Mined,
      confirmations: 6,
    };
    const wire = encodeTxBroadcastResult(r);
    expect(wire.length).toBe(TX_BROADCAST_RESULT_BYTES);
    expect(decodeTxBroadcastResult(wire)).toEqual(r);
  });

  it("round-trips Rejected with arcStatus=None confirmations=0", () => {
    const r = {
      outcome: TxBroadcastOutcome.Rejected,
      txid: makeBytes(32, 2),
      arcStatus: TxBroadcastArcStatus.None,
      confirmations: 0,
    };
    expect(decodeTxBroadcastResult(encodeTxBroadcastResult(r))).toEqual(r);
  });

  it("preserves high u32 confirmations", () => {
    const r = {
      outcome: TxBroadcastOutcome.Accepted,
      txid: makeBytes(32),
      arcStatus: TxBroadcastArcStatus.Seen,
      confirmations: 0xfeedbeef,
    };
    const decoded = decodeTxBroadcastResult(encodeTxBroadcastResult(r));
    expect(decoded.confirmations).toBe(0xfeedbeef);
  });

  it("rejects decode of unknown outcome", () => {
    const wire = encodeTxBroadcastResult({
      outcome: TxBroadcastOutcome.Accepted,
      txid: makeBytes(32),
      arcStatus: TxBroadcastArcStatus.Mined,
      confirmations: 1,
    });
    wire[1] = 99;
    expect(() => decodeTxBroadcastResult(wire)).toThrow(/unknown outcome=99/);
  });

  it("rejects decode of unknown arcStatus", () => {
    const wire = encodeTxBroadcastResult({
      outcome: TxBroadcastOutcome.Accepted,
      txid: makeBytes(32),
      arcStatus: TxBroadcastArcStatus.Mined,
      confirmations: 1,
    });
    wire[34] = 99;
    expect(() => decodeTxBroadcastResult(wire)).toThrow(
      /unknown arc_status=99/,
    );
  });

  it("rejects decode of truncated payload", () => {
    expect(() => decodeTxBroadcastResult(new Uint8Array(20))).toThrow(
      /must be ≥ 39 bytes/,
    );
  });
});

```
