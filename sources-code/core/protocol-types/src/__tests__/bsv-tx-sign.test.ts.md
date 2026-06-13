---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/bsv-tx-sign.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.883319+00:00
---

# core/protocol-types/src/__tests__/bsv-tx-sign.test.ts

```ts
/**
 * Unit tests for the `bsv.tx.sign.{request,response}` wire formats
 * (PR-6 / LOCKSCRIPT-CLEAVAGE.md §3.5 + §8.3).
 */

import { describe, it, expect } from "@jest/globals";

import {
  TX_SIGN_WIRE_VERSION,
  TX_SIGN_REQUEST_BYTES,
  TX_SIGN_RESPONSE_PREFIX_BYTES,
  encodeTxSignRequest,
  decodeTxSignRequest,
  encodeTxSignResponse,
  decodeTxSignResponse,
} from "../bsv/tx-sign";
import {
  CELL_HASH_BYTES,
  MAX_INLINE_SIG_BYTES,
} from "../bsv/tx-partial";

function makeBytes(n: number, seed = 0): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 17 + seed) & 0xff;
  return b;
}

describe("bsv.tx.sign.request — round-trip + layout", () => {
  it("round-trips a typical request", () => {
    const req = {
      digest: makeBytes(32, 1),
      recipeId: makeBytes(CELL_HASH_BYTES, 2),
      inputIndex: 3,
      sighashFlags: 0x41,
    };
    const wire = encodeTxSignRequest(req);
    expect(wire.length).toBe(TX_SIGN_REQUEST_BYTES);
    expect(decodeTxSignRequest(wire)).toEqual(req);
  });

  it("preserves high u32 inputIndex (unsigned)", () => {
    const req = {
      digest: makeBytes(32, 1),
      recipeId: makeBytes(CELL_HASH_BYTES, 2),
      inputIndex: 0xfeedbeef,
      sighashFlags: 0x41,
    };
    const decoded = decodeTxSignRequest(encodeTxSignRequest(req));
    expect(decoded.inputIndex).toBe(0xfeedbeef);
  });

  it("LE-encodes inputIndex at offsets 65..69 + sighashFlags at 69", () => {
    const wire = encodeTxSignRequest({
      digest: makeBytes(32),
      recipeId: makeBytes(CELL_HASH_BYTES),
      inputIndex: 0x01020304,
      sighashFlags: 0xc1,
    });
    expect(wire[0]).toBe(TX_SIGN_WIRE_VERSION);
    expect(wire[65]).toBe(0x04);
    expect(wire[66]).toBe(0x03);
    expect(wire[67]).toBe(0x02);
    expect(wire[68]).toBe(0x01);
    expect(wire[69]).toBe(0xc1);
  });

  it("rejects encode with wrong-size digest", () => {
    expect(() =>
      encodeTxSignRequest({
        digest: makeBytes(16),
        recipeId: makeBytes(CELL_HASH_BYTES),
        inputIndex: 0,
        sighashFlags: 0x41,
      }),
    ).toThrow(/digest must be 32 bytes/);
  });

  it("rejects decode of truncated payload", () => {
    expect(() => decodeTxSignRequest(new Uint8Array(20))).toThrow(
      /payload must be ≥ 70 bytes/,
    );
  });

  it("rejects decode with wrong VERSION", () => {
    const wire = encodeTxSignRequest({
      digest: makeBytes(32),
      recipeId: makeBytes(CELL_HASH_BYTES),
      inputIndex: 0,
      sighashFlags: 0x41,
    });
    wire[0] = 7;
    expect(() => decodeTxSignRequest(wire)).toThrow(/unknown VERSION=7/);
  });
});

describe("bsv.tx.sign.response — round-trip + layout", () => {
  it("round-trips a typical response", () => {
    const res = {
      requestCellHash: makeBytes(CELL_HASH_BYTES, 1),
      signature: makeBytes(71, 2),
    };
    const wire = encodeTxSignResponse(res);
    expect(wire.length).toBe(TX_SIGN_RESPONSE_PREFIX_BYTES + 71);
    expect(decodeTxSignResponse(wire)).toEqual(res);
  });

  it("round-trips at MAX_INLINE_SIG_BYTES boundary", () => {
    const res = {
      requestCellHash: makeBytes(CELL_HASH_BYTES, 1),
      signature: makeBytes(MAX_INLINE_SIG_BYTES, 2),
    };
    const wire = encodeTxSignResponse(res);
    const decoded = decodeTxSignResponse(wire);
    expect(decoded.signature.length).toBe(MAX_INLINE_SIG_BYTES);
  });

  it("rejects sig-over-MAX on encode", () => {
    expect(() =>
      encodeTxSignResponse({
        requestCellHash: makeBytes(CELL_HASH_BYTES),
        signature: makeBytes(MAX_INLINE_SIG_BYTES + 1),
      }),
    ).toThrow(/signature length/);
  });

  it("rejects decode of truncated payload", () => {
    expect(() => decodeTxSignResponse(new Uint8Array(10))).toThrow(
      /payload too short/,
    );
  });
});

```
