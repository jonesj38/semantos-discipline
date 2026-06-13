---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/bsv-spv-verify.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.883033+00:00
---

# core/protocol-types/src/__tests__/bsv-spv-verify.test.ts

```ts
/**
 * Unit tests for the SPV verify wire format (PR-C11-7e).
 *
 * Pinpoints:
 *   1. round-trip identity (encode then decode is identity)
 *   2. wire-byte layout (offsets + lengths match the spec)
 *   3. error paths (malformed input rejected with RangeError)
 *   4. the INLINE_BEEF_MAX_BYTES boundary
 */

import { describe, it, expect } from '@jest/globals';

import {
  encodeSpvVerifyIntent,
  decodeSpvVerifyIntent,
  encodeSpvVerifyResult,
  decodeSpvVerifyResult,
  SpvVerifyIntentFlag,
  SpvVerifyOutcome,
  SpvVerifyErrorTag,
  SPV_VERIFY_WIRE_VERSION,
  SPV_VERIFY_INTENT_PREFIX_BYTES,
  SPV_VERIFY_RESULT_BYTES,
  INLINE_BEEF_MAX_BYTES,
} from '../bsv/spv-verify';

function makeTxid(seed: number): Uint8Array {
  const b = new Uint8Array(32);
  for (let i = 0; i < 32; i++) b[i] = (i * 7 + seed) & 0xff;
  return b;
}

function makeBeef(n: number, seed = 0): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 13 + seed) & 0xff;
  return b;
}

describe('bsv.spv.verify intent — round-trip', () => {
  it('round-trips empty BEEF', () => {
    const intent = { txid: makeTxid(1), beef: new Uint8Array() };
    const wire = encodeSpvVerifyIntent(intent);
    expect(wire.length).toBe(SPV_VERIFY_INTENT_PREFIX_BYTES);
    const decoded = decodeSpvVerifyIntent(wire);
    expect(decoded.txid).toEqual(intent.txid);
    expect(decoded.beef.length).toBe(0);
  });

  it('round-trips a small BEEF', () => {
    const intent = { txid: makeTxid(2), beef: makeBeef(64) };
    const wire = encodeSpvVerifyIntent(intent);
    const decoded = decodeSpvVerifyIntent(wire);
    expect(decoded.txid).toEqual(intent.txid);
    expect(decoded.beef).toEqual(intent.beef);
  });

  it('round-trips at the INLINE_BEEF_MAX_BYTES boundary', () => {
    const intent = { txid: makeTxid(3), beef: makeBeef(INLINE_BEEF_MAX_BYTES) };
    const wire = encodeSpvVerifyIntent(intent);
    expect(wire.length).toBe(
      SPV_VERIFY_INTENT_PREFIX_BYTES + INLINE_BEEF_MAX_BYTES,
    );
    const decoded = decodeSpvVerifyIntent(wire);
    expect(decoded.beef.length).toBe(INLINE_BEEF_MAX_BYTES);
    expect(decoded.beef[INLINE_BEEF_MAX_BYTES - 1]).toBe(
      intent.beef[INLINE_BEEF_MAX_BYTES - 1],
    );
  });
});

describe('bsv.spv.verify intent — wire layout', () => {
  it('stamps VERSION at offset 0', () => {
    const wire = encodeSpvVerifyIntent({ txid: makeTxid(4), beef: makeBeef(8) });
    expect(wire[0]).toBe(SPV_VERIFY_WIRE_VERSION);
  });

  it('places the txid at offset 1..33', () => {
    const txid = makeTxid(5);
    const wire = encodeSpvVerifyIntent({ txid, beef: new Uint8Array() });
    expect(wire.slice(1, 33)).toEqual(txid);
  });

  it('sets the inline-beef FLAGS bit at offset 33', () => {
    const wire = encodeSpvVerifyIntent({ txid: makeTxid(6), beef: makeBeef(4) });
    expect(wire[33] & SpvVerifyIntentFlag.InlineBeef).not.toBe(0);
  });

  it('writes beef_len as u16 LE at offset 34', () => {
    // 0x0234 = 564 bytes — fits within INLINE_BEEF_MAX_BYTES (920) and
    // exercises both bytes of the u16 (low: 0x34, high: 0x02).
    const beef = makeBeef(0x0234);
    const wire = encodeSpvVerifyIntent({ txid: makeTxid(7), beef });
    expect(wire[34]).toBe(0x34);
    expect(wire[35]).toBe(0x02);
  });

  it('places the BEEF bytes starting at offset 36', () => {
    const beef = makeBeef(32, /* seed */ 99);
    const wire = encodeSpvVerifyIntent({ txid: makeTxid(8), beef });
    expect(wire.slice(36, 36 + 32)).toEqual(beef);
  });
});

describe('bsv.spv.verify intent — error paths', () => {
  it('rejects a txid that is not 32 bytes', () => {
    expect(() =>
      encodeSpvVerifyIntent({ txid: new Uint8Array(31), beef: new Uint8Array() }),
    ).toThrow(RangeError);
  });

  it('rejects a BEEF that exceeds INLINE_BEEF_MAX_BYTES', () => {
    expect(() =>
      encodeSpvVerifyIntent({
        txid: makeTxid(0),
        beef: makeBeef(INLINE_BEEF_MAX_BYTES + 1),
      }),
    ).toThrow(RangeError);
  });

  it('rejects an empty payload on decode', () => {
    expect(() => decodeSpvVerifyIntent(new Uint8Array())).toThrow(RangeError);
  });

  it('rejects a payload too short for the prefix', () => {
    expect(() => decodeSpvVerifyIntent(new Uint8Array(35))).toThrow(RangeError);
  });

  it('rejects an unknown VERSION', () => {
    const wire = encodeSpvVerifyIntent({ txid: makeTxid(9), beef: new Uint8Array() });
    wire[0] = 99;
    expect(() => decodeSpvVerifyIntent(wire)).toThrow(/VERSION=99/);
  });

  it('rejects a payload with the inline-beef flag clear (carriage form not yet supported)', () => {
    const wire = encodeSpvVerifyIntent({ txid: makeTxid(10), beef: new Uint8Array() });
    wire[33] = 0;
    expect(() => decodeSpvVerifyIntent(wire)).toThrow(/inline-beef/);
  });

  it('rejects a payload truncated below the declared beef_len', () => {
    const wire = encodeSpvVerifyIntent({ txid: makeTxid(11), beef: makeBeef(128) });
    // Drop the trailing 10 BEEF bytes.
    const truncated = wire.slice(0, wire.length - 10);
    expect(() => decodeSpvVerifyIntent(truncated)).toThrow(/truncated/);
  });
});

describe('bsv.spv.verify result — round-trip + layout', () => {
  it('round-trips a Valid result with no error tag', () => {
    const result = {
      outcome: SpvVerifyOutcome.Valid,
      txid: makeTxid(12),
      errorTag: SpvVerifyErrorTag.None,
    };
    const wire = encodeSpvVerifyResult(result);
    expect(wire.length).toBe(SPV_VERIFY_RESULT_BYTES);
    expect(decodeSpvVerifyResult(wire)).toEqual(result);
  });

  it('round-trips an Invalid result', () => {
    const result = {
      outcome: SpvVerifyOutcome.Invalid,
      txid: makeTxid(13),
      errorTag: SpvVerifyErrorTag.None,
    };
    expect(decodeSpvVerifyResult(encodeSpvVerifyResult(result))).toEqual(result);
  });

  it('round-trips an Error result with a specific tag', () => {
    const result = {
      outcome: SpvVerifyOutcome.Error,
      txid: makeTxid(14),
      errorTag: SpvVerifyErrorTag.RootNotTrusted,
    };
    expect(decodeSpvVerifyResult(encodeSpvVerifyResult(result))).toEqual(result);
  });

  it('places fields at the right offsets', () => {
    const txid = makeTxid(15);
    const wire = encodeSpvVerifyResult({
      outcome: SpvVerifyOutcome.Valid,
      txid,
      errorTag: SpvVerifyErrorTag.None,
    });
    expect(wire[0]).toBe(SPV_VERIFY_WIRE_VERSION);
    expect(wire[1]).toBe(SpvVerifyOutcome.Valid);
    expect(wire.slice(2, 34)).toEqual(txid);
    expect(wire[34]).toBe(SpvVerifyErrorTag.None);
  });

  it('rejects encode with a non-32-byte txid', () => {
    expect(() =>
      encodeSpvVerifyResult({
        outcome: SpvVerifyOutcome.Valid,
        txid: new Uint8Array(31),
        errorTag: SpvVerifyErrorTag.None,
      }),
    ).toThrow(RangeError);
  });

  it('rejects decode of a short payload', () => {
    expect(() => decodeSpvVerifyResult(new Uint8Array(34))).toThrow(RangeError);
  });

  it('rejects decode with an unknown OUTCOME', () => {
    const wire = encodeSpvVerifyResult({
      outcome: SpvVerifyOutcome.Valid,
      txid: makeTxid(16),
      errorTag: SpvVerifyErrorTag.None,
    });
    wire[1] = 99;
    expect(() => decodeSpvVerifyResult(wire)).toThrow(/OUTCOME=99/);
  });

  it('rejects decode with an unknown error_tag', () => {
    const wire = encodeSpvVerifyResult({
      outcome: SpvVerifyOutcome.Error,
      txid: makeTxid(17),
      errorTag: SpvVerifyErrorTag.BeefParseFailed,
    });
    wire[34] = 99;
    expect(() => decodeSpvVerifyResult(wire)).toThrow(/error_tag=99/);
  });
});

```
