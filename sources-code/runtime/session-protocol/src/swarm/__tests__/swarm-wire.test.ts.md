---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/swarm-wire.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.077058+00:00
---

# runtime/session-protocol/src/swarm/__tests__/swarm-wire.test.ts

```ts
/**
 * Swarm wire frames — M2. Pins the byte layout of HAVE/REQUEST/CELL/PAY and
 * the full 12-byte-header packet. Wire drift between seeder and leecher is
 * silent and catastrophic, so every frame round-trips + rejects garbage. The
 * CELL frame is cross-validated against a real M0 inclusion proof.
 */
import { describe, expect, test } from 'bun:test';
import {
  publishFile,
  generateDataCellProof,
  verifyDataCell,
  bytesEqual,
} from '@semantos/protocol-types';
import {
  MSG_SWARM_HAVE,
  MSG_SWARM_REQUEST,
  MSG_SWARM_CELL,
  MSG_SWARM_PAY,
  encodeRequest,
  decodeRequest,
  encodeCell,
  decodeCell,
  encodePay,
  decodePay,
  frameSwarm,
  parseSwarm,
  isSwarmMsgType,
  type SwarmPayment,
} from '../swarm-wire';
import { bitfieldFor } from '../have-bitfield';

const ctx = { msgId: 7, nodeIdShort: 0x1234, timestamp: 1000 };
const payment: SwarmPayment = { txAnchor: new Uint8Array(32).fill(9), amount: 135n, currency: 'sat' };

describe('swarm-wire — REQUEST', () => {
  test('round-trips without payment', () => {
    const req = { infohash: new Uint8Array(32).fill(1), cellIndex: 42, requesterBca: new Uint8Array(16).fill(2) };
    const got = decodeRequest(encodeRequest(req));
    expect(got.cellIndex).toBe(42);
    expect(bytesEqual(got.requesterBca, req.requesterBca)).toBe(true);
    expect(got.payment).toBeUndefined();
  });

  test('round-trips with prepayment', () => {
    const req = { infohash: new Uint8Array(32).fill(1), cellIndex: 3, requesterBca: new Uint8Array(16).fill(2), payment };
    const got = decodeRequest(encodeRequest(req));
    expect(got.payment?.amount).toBe(135n);
    expect(got.payment?.currency).toBe('sat');
    expect(bytesEqual(got.payment!.txAnchor, payment.txAnchor)).toBe(true);
  });

  test('rejects bad lengths + truncation', () => {
    expect(() => encodeRequest({ infohash: new Uint8Array(31), cellIndex: 0, requesterBca: new Uint8Array(16) })).toThrow();
    expect(() => encodeRequest({ infohash: new Uint8Array(32), cellIndex: 0, requesterBca: new Uint8Array(15) })).toThrow();
    expect(() => decodeRequest(new Uint8Array(20))).toThrow();
    const withPay = encodeRequest({ infohash: new Uint8Array(32), cellIndex: 0, requesterBca: new Uint8Array(16), payment });
    expect(() => decodeRequest(withPay.subarray(0, 60))).toThrow(); // payment flag set, truncated
  });
});

describe('swarm-wire — CELL (with real proof)', () => {
  test('round-trips and the decoded cell + proof verifies against the manifest', () => {
    const pub = publishFile(Uint8Array.from({ length: 9000 }, (_, i) => i & 0xff), 'wire/file');
    const i = 5;
    const proof = generateDataCellProof(pub.dataCells, i);
    const encoded = encodeCell({ infohash: pub.infohash, cellIndex: i, proof, cellBytes: pub.dataCells[i]! });
    const got = decodeCell(encoded);
    expect(got.cellIndex).toBe(i);
    expect(got.proof.leafIndex).toBe(i);
    expect(got.proof.siblings.length).toBe(proof.siblings.length);
    expect(bytesEqual(got.cellBytes, pub.dataCells[i]!)).toBe(true);
    // The decoded frame is sufficient to verify against the manifest root.
    expect(verifyDataCell(pub.manifest, got.cellIndex, got.cellBytes, got.proof)).toBe(true);
  });

  test('single-leaf proof (1-cell file) round-trips', () => {
    const pub = publishFile(new Uint8Array(50).fill(1), 'tiny');
    const proof = generateDataCellProof(pub.dataCells, 0);
    const got = decodeCell(encodeCell({ infohash: pub.infohash, cellIndex: 0, proof, cellBytes: pub.dataCells[0]! }));
    expect(got.proof.siblings.length).toBe(0);
    expect(verifyDataCell(pub.manifest, 0, got.cellBytes, got.proof)).toBe(true);
  });

  test('rejects bad cell length + truncation', () => {
    expect(() => encodeCell({ infohash: new Uint8Array(32), cellIndex: 0, proof: { leafIndex: 0, siblings: [] }, cellBytes: new Uint8Array(1000) })).toThrow();
    expect(() => decodeCell(new Uint8Array(20))).toThrow();
    expect(() => decodeCell(new Uint8Array(37))).toThrow(); // header ok, no cell bytes
  });
});

describe('swarm-wire — PAY', () => {
  test('round-trips', () => {
    const got = decodePay(encodePay({ infohash: new Uint8Array(32).fill(4), cellIndex: 11, payment }));
    expect(got.cellIndex).toBe(11);
    expect(got.payment.amount).toBe(135n);
    expect(got.payment.currency).toBe('sat');
  });
  test('rejects truncation', () => {
    expect(() => decodePay(new Uint8Array(20))).toThrow();
  });
});

describe('swarm-wire — full packet (12-byte header)', () => {
  test('frame + parse round-trip carries msgType + payload', () => {
    const req = encodeRequest({ infohash: new Uint8Array(32).fill(1), cellIndex: 9, requesterBca: new Uint8Array(16).fill(2) });
    const packet = frameSwarm(MSG_SWARM_REQUEST, req, ctx);
    const { header, payload } = parseSwarm(packet);
    expect(header.msgType).toBe(MSG_SWARM_REQUEST);
    expect(header.msgId).toBe(7);
    expect(header.payloadLen).toBe(req.length);
    expect(decodeRequest(payload).cellIndex).toBe(9);
  });

  test('isSwarmMsgType classifies the 4 types', () => {
    for (const t of [MSG_SWARM_HAVE, MSG_SWARM_REQUEST, MSG_SWARM_CELL, MSG_SWARM_PAY]) {
      expect(isSwarmMsgType(t)).toBe(true);
    }
    expect(isSwarmMsgType(0x02)).toBe(false); // MSG_CELL (non-swarm)
    expect(isSwarmMsgType(0x14)).toBe(false);
  });

  test('parseSwarm rejects an undersized packet', () => {
    expect(() => parseSwarm(new Uint8Array(5))).toThrow();
  });

  test('HAVE frames through the header', () => {
    const bf = bitfieldFor([0, 2], 4);
    // encodeHave is re-exported from swarm-wire for symmetry.
    const { encodeHave, decodeHave } = require('../swarm-wire');
    const packet = frameSwarm(MSG_SWARM_HAVE, encodeHave(new Uint8Array(32).fill(7), 4, bf), ctx);
    const { header, payload } = parseSwarm(packet);
    expect(header.msgType).toBe(MSG_SWARM_HAVE);
    expect(decodeHave(payload).totalCells).toBe(4);
  });
});

```
