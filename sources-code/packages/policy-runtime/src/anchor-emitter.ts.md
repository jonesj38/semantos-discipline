---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/policy-runtime/src/anchor-emitter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.491968+00:00
---

# packages/policy-runtime/src/anchor-emitter.ts

```ts
/**
 * Anchor emitter — converts packed terminal-event cells into signed BSV anchor
 * transactions via the Plexus adapter.
 *
 * Phase 29.5 / D29.5.5
 */

import { Hash } from '@bsv/sdk';

// ── Interfaces ──────────────────────────────────────────────

export interface AnchorEmitter {
  emit(cell: Uint8Array, opts: AnchorOptions): Promise<AnchorResult>;
}

export interface AnchorOptions {
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT';
  anchorPolicy: 'always' | 'terminal-only' | 'regulatory-only' | 'never';
  /** Idempotency key — re-emitting the same event returns the original txid. */
  idempotencyKey: string;
  /** Which Plexus instance to broadcast through. */
  plexusInstance?: string;
}

export interface AnchorResult {
  txid: string;
  beefEnvelope: Uint8Array;
  broadcastedAt: string;
  /** True if idempotent cache hit — no double broadcast. */
  reused: boolean;
}

// ── Dev-mode implementation ─────────────────────────────────

/**
 * Dev-mode anchor emitter — produces structurally valid BEEF envelopes
 * without network I/O. For gate tests and demos.
 *
 * BEEF v1 structure:
 * - 4-byte magic: 0x0100BEEF
 * - 1 BUMP: blockHeight=0, treeHeight=1, single leaf with zero-hash
 * - 1 TX: version 2, 1 input (coinbase-like), 1 output (OP_FALSE OP_RETURN + cell payload)
 */
export class DevModeAnchorEmitter implements AnchorEmitter {
  private readonly cache = new Map<string, AnchorResult>();

  async emit(cell: Uint8Array, opts: AnchorOptions): Promise<AnchorResult> {
    if (opts.anchorPolicy === 'never') {
      return {
        txid: '0'.repeat(64),
        beefEnvelope: new Uint8Array(0),
        broadcastedAt: new Date().toISOString(),
        reused: false,
      };
    }

    // Idempotency check: sha256(cellBytes) as key
    const cellHash = sha256hex(cell);
    const cacheKey = opts.idempotencyKey || cellHash;

    const cached = this.cache.get(cacheKey);
    if (cached) {
      return { ...cached, reused: true };
    }

    // Build structurally valid BEEF envelope
    const beefEnvelope = buildDevBeef(cell);

    // txid = sha256(sha256(raw_tx)) — use cell hash as a stand-in
    const txid = cellHash;

    const result: AnchorResult = {
      txid,
      beefEnvelope,
      broadcastedAt: new Date().toISOString(),
      reused: false,
    };

    this.cache.set(cacheKey, result);
    return result;
  }
}

// ── BEEF construction ───────────────────────────────────────

/**
 * Build a structurally valid BEEF v1 envelope for dev mode.
 * Not SPV-verifiable (no real merkle proof), but passes structural checks.
 */
function buildDevBeef(cellPayload: Uint8Array): Uint8Array {
  // BEEF v1 magic: 0x0100BEEF (little-endian: EF BE 00 01)
  const magic = new Uint8Array([0xEF, 0xBE, 0x00, 0x01]);

  // BUMP count: 1 (varint)
  const bumpCount = new Uint8Array([0x01]);

  // BUMP: blockHeight=0, treeHeight=1, single leaf
  // blockHeight: varint 0
  // treeHeight: 1
  // leaf count at level 0: 1
  // leaf: offset=0, flags=0x00 (txid leaf), hash=32 zero bytes
  const bump = new Uint8Array([
    0x00,       // blockHeight = 0 (varint)
    0x01,       // treeHeight = 1
    0x01,       // 1 leaf at level 0
    0x00,       // offset = 0 (varint)
    0x00,       // flags = 0x00 (txid leaf)
    ...new Array(32).fill(0), // 32-byte zero hash
  ]);

  // TX count: 1 (varint)
  const txCount = new Uint8Array([0x01]);

  // Build a minimal transaction:
  // version (4 bytes LE) = 2
  // input count = 1
  //   prevTxid = 32 zero bytes (coinbase)
  //   prevVout = 0xFFFFFFFF
  //   scriptSig len = 0
  //   nSequence = 0xFFFFFFFF
  // output count = 1
  //   value = 0 (8 bytes LE)
  //   scriptPubKey = OP_FALSE OP_RETURN <cell payload>
  const opReturn = buildOpReturnScript(cellPayload);

  const txVersion = new Uint8Array([0x02, 0x00, 0x00, 0x00]);
  const inputCount = new Uint8Array([0x01]);
  const prevTxid = new Uint8Array(32); // zeros = coinbase
  const prevVout = new Uint8Array([0xFF, 0xFF, 0xFF, 0xFF]);
  const scriptSigLen = new Uint8Array([0x00]);
  const nSequence = new Uint8Array([0xFF, 0xFF, 0xFF, 0xFF]);
  const outputCount = new Uint8Array([0x01]);
  const outputValue = new Uint8Array(8); // 0 satoshis
  const scriptLen = encodeVarint(opReturn.length);
  const nLockTime = new Uint8Array([0x00, 0x00, 0x00, 0x00]);

  // has_bump flag: 0x01 (this tx has a BUMP at index 0)
  const hasBump = new Uint8Array([0x01]);
  const bumpIndex = new Uint8Array([0x00]); // varint: BUMP index 0

  // Assemble
  const parts = [
    magic, bumpCount, bump, txCount,
    txVersion, inputCount, prevTxid, prevVout, scriptSigLen, nSequence,
    outputCount, outputValue, scriptLen, opReturn, nLockTime,
    hasBump, bumpIndex,
  ];

  const totalLen = parts.reduce((sum, p) => sum + p.length, 0);
  const result = new Uint8Array(totalLen);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function buildOpReturnScript(payload: Uint8Array): Uint8Array {
  // OP_FALSE (0x00) OP_RETURN (0x6A) <pushdata payload>
  const pushdata = encodePushdata(payload);
  const script = new Uint8Array(2 + pushdata.length);
  script[0] = 0x00; // OP_FALSE
  script[1] = 0x6A; // OP_RETURN
  script.set(pushdata, 2);
  return script;
}

function encodePushdata(data: Uint8Array): Uint8Array {
  if (data.length <= 75) {
    const result = new Uint8Array(1 + data.length);
    result[0] = data.length;
    result.set(data, 1);
    return result;
  } else if (data.length <= 255) {
    const result = new Uint8Array(2 + data.length);
    result[0] = 0x4C; // OP_PUSHDATA1
    result[1] = data.length;
    result.set(data, 2);
    return result;
  } else {
    const result = new Uint8Array(3 + data.length);
    result[0] = 0x4D; // OP_PUSHDATA2
    result[1] = data.length & 0xFF;
    result[2] = (data.length >> 8) & 0xFF;
    result.set(data, 3);
    return result;
  }
}

function encodeVarint(n: number): Uint8Array {
  if (n < 0xFD) return new Uint8Array([n]);
  if (n <= 0xFFFF) return new Uint8Array([0xFD, n & 0xFF, (n >> 8) & 0xFF]);
  return new Uint8Array([0xFE, n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF]);
}

function sha256hex(data: Uint8Array): string {
  const hash = Hash.sha256(data);
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('');
}

```
