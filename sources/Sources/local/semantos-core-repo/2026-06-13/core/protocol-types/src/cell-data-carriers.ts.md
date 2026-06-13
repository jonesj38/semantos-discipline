---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-data-carriers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.837932+00:00
---

# core/protocol-types/src/cell-data-carriers.ts

```ts
/**
 * Cell data-carrier variants — three BSV-script shapes for carrying
 * canonical cell bytes as a spendable UTXO without OP_RETURN.
 *
 * CW Lift L13 (docs/canon/cw-lift-matrix.yml).
 *
 * Three carrier options now on the table; all three avoid OP_RETURN and
 * all three leave a spendable tail. Existing semantos code (the MNCA
 * mainnet anchor of 2026-05-22) uses (a). (b) and (c) are added here
 * as alternative options. (a) is re-exported from `cell-pushdrop.ts`
 * unchanged so existing call sites continue working without modification.
 *
 *   (a) PUSHDROP  (existing, default)
 *       <cell> OP_DROP <pubkey> OP_CHECKSIG
 *       1063 bytes for canonical 1024B cell + 33B compressed pubkey.
 *       Spendable via P2PK-style key in the spending tx.
 *
 *   (b) OP_FALSE OP_IF  (from prof-faustus/verifiable-accounting-bsv)
 *       OP_FALSE OP_IF <cell> OP_ENDIF <pubkey> OP_CHECKSIG
 *       1065 bytes for canonical 1024B cell + 33B compressed pubkey.
 *       The IF body is unreachable (OP_FALSE never satisfies OP_IF) so
 *       the cell is pure data carriage; the OP_CHECKSIG tail remains
 *       spendable. Decouples data from the drop semantics — useful when
 *       a script-level tool inspects opcodes and gets confused by
 *       OP_DROP-of-large-push (some BSV indexers).
 *
 *   (c) OP_DROP + P2PKH  (from prof-faustus/idattr-onchain, verified
 *       live on Teranode regtest 2026-06-02, anchor tx 068093ae...)
 *       <cell> OP_DROP OP_DUP OP_HASH160 <pkh20> OP_EQUALVERIFY OP_CHECKSIG
 *       1051 bytes for canonical 1024B cell + 20B pkh.
 *       The trailing P2PKH is the most wallet-compatible spend script;
 *       generic BSV wallets recognise the output. SCARCITY-compliant per
 *       Craig's REQ-CHAIN-0003 (state root committed by a possession tx).
 *
 * All three are pure encoders/decoders — no signing, no broadcast. The
 * builder takes the canonical cell bytes + the spend-side material
 * (pubkey for (a)/(b), pkh20 for (c)) and produces locking-script
 * bytes. The parser recognises the exact shape it produces and rejects
 * variants.
 *
 * Choosing a carrier is a deployment decision, not a wire decision —
 * any single semantos anchor batch uses one carrier shape consistently,
 * and the verifier knows which one based on script-shape discrimination.
 *
 * Source repos (both MIT):
 *   - (b): prof-faustus/verifiable-accounting-bsv @
 *     packages/bsv/src/scriptdataenvelope.ts
 *   - (c): prof-faustus/idattr-onchain @ src/main.rs
 */

import {
  COMPRESSED_PUBKEY_SIZE,
  OP_CHECKSIG,
  OP_DROP,
  UNCOMPRESSED_PUBKEY_SIZE,
  buildPushdropLockingScript,
  parsePushdropLockingScript,
  pushPrefix,
} from './cell-pushdrop.js';

// ── Additional opcodes used by (b) and (c) ────────────────────────

export const OP_FALSE = 0x00 as const;
export const OP_IF = 0x63 as const;
export const OP_ENDIF = 0x68 as const;
export const OP_DUP = 0x76 as const;
export const OP_HASH160 = 0xa9 as const;
export const OP_EQUALVERIFY = 0x88 as const;

/** P2PKH pubkey-hash is RIPEMD160(SHA256(pubkey)), always 20 bytes. */
export const PKH_SIZE = 20 as const;

// ── Carrier discriminator ─────────────────────────────────────────

export type DataCarrierShape =
  | 'pushdrop'         // (a) <cell> OP_DROP <pubkey> OP_CHECKSIG
  | 'op_false_op_if'   // (b) OP_FALSE OP_IF <cell> OP_ENDIF <pubkey> OP_CHECKSIG
  | 'op_drop_p2pkh';   // (c) <cell> OP_DROP OP_DUP OP_HASH160 <pkh> OP_EQUALVERIFY OP_CHECKSIG

/** Components recovered by parsing a carrier locking script. */
export type ParsedCarrier =
  | { shape: 'pushdrop'; cellBytes: Uint8Array; pubkey: Uint8Array }
  | { shape: 'op_false_op_if'; cellBytes: Uint8Array; pubkey: Uint8Array }
  | { shape: 'op_drop_p2pkh'; cellBytes: Uint8Array; pkh: Uint8Array };

// ── (a) pushdrop — re-exported, unchanged ─────────────────────────

export {
  buildPushdropLockingScript,
  parsePushdropLockingScript,
  OP_DROP,
  OP_CHECKSIG,
};

// ── (b) OP_FALSE OP_IF data carrier ───────────────────────────────

/**
 * Build an `OP_FALSE OP_IF <cell> OP_ENDIF <pubkey> OP_CHECKSIG`
 * locking script.
 *
 * The IF body is unreachable (OP_FALSE never satisfies OP_IF), so the
 * cell is pure data carriage. The OP_CHECKSIG tail at the end remains
 * the actual spend predicate.
 *
 * Byte layout for canonical 1024B cell + 33B compressed pubkey:
 *
 *     0x00                    OP_FALSE
 *     0x63                    OP_IF
 *     0x4d 0x00 0x04          OP_PUSHDATA2 + LE length 0x0400 (1024)
 *     <1024 bytes>            cell data
 *     0x68                    OP_ENDIF
 *     0x21                    push 33 bytes
 *     <33 bytes>              pubkey
 *     0xac                    OP_CHECKSIG
 *
 * Total: 1065 bytes (2 bytes more than pushdrop — the OP_FALSE + OP_IF
 * + OP_ENDIF framing).
 */
export function buildOpFalseIfCarrierScript(
  cellBytes: Uint8Array,
  pubkey: Uint8Array,
): Uint8Array {
  if (cellBytes.length === 0) {
    throw new Error('buildOpFalseIfCarrierScript: cell must be non-empty');
  }
  if (cellBytes.length > 65535) {
    throw new Error(
      `buildOpFalseIfCarrierScript: cell ${cellBytes.length} bytes exceeds PUSHDATA2 max (65535)`,
    );
  }
  if (pubkey.length !== COMPRESSED_PUBKEY_SIZE && pubkey.length !== UNCOMPRESSED_PUBKEY_SIZE) {
    throw new Error(
      `buildOpFalseIfCarrierScript: pubkey must be ${COMPRESSED_PUBKEY_SIZE} or ${UNCOMPRESSED_PUBKEY_SIZE} bytes (got ${pubkey.length})`,
    );
  }
  const cellPrefix = pushPrefix(cellBytes.length);
  const pubkeyPrefix = pushPrefix(pubkey.length);
  const total =
    /* OP_FALSE */ 1 +
    /* OP_IF */ 1 +
    cellPrefix.length +
    cellBytes.length +
    /* OP_ENDIF */ 1 +
    pubkeyPrefix.length +
    pubkey.length +
    /* OP_CHECKSIG */ 1;
  const out = new Uint8Array(total);
  let off = 0;
  out[off++] = OP_FALSE;
  out[off++] = OP_IF;
  out.set(cellPrefix, off);
  off += cellPrefix.length;
  out.set(cellBytes, off);
  off += cellBytes.length;
  out[off++] = OP_ENDIF;
  out.set(pubkeyPrefix, off);
  off += pubkeyPrefix.length;
  out.set(pubkey, off);
  off += pubkey.length;
  out[off++] = OP_CHECKSIG;
  return out;
}

/** Strict parser for the exact (b) shape produced by
 *  `buildOpFalseIfCarrierScript`. Variants are rejected. */
export function parseOpFalseIfCarrierScript(script: Uint8Array): {
  cellBytes: Uint8Array;
  pubkey: Uint8Array;
} {
  if (script.length < 5) {
    throw new Error(`parseOpFalseIfCarrierScript: too short (${script.length})`);
  }
  if (script[0] !== OP_FALSE) {
    throw new Error(
      `parseOpFalseIfCarrierScript: expected OP_FALSE at offset 0, got 0x${script[0]!.toString(16)}`,
    );
  }
  if (script[1] !== OP_IF) {
    throw new Error(
      `parseOpFalseIfCarrierScript: expected OP_IF at offset 1, got 0x${script[1]!.toString(16)}`,
    );
  }
  let off = 2;
  const cellPush = readPushBytesLocal(script, off);
  off = cellPush.offsetAfter;
  const cellBytes = cellPush.data;
  if (script[off] !== OP_ENDIF) {
    throw new Error(
      `parseOpFalseIfCarrierScript: expected OP_ENDIF at offset ${off}, got 0x${(script[off] ?? 0).toString(16)}`,
    );
  }
  off += 1;
  const pubPush = readPushBytesLocal(script, off);
  off = pubPush.offsetAfter;
  const pubkey = pubPush.data;
  if (pubkey.length !== COMPRESSED_PUBKEY_SIZE && pubkey.length !== UNCOMPRESSED_PUBKEY_SIZE) {
    throw new Error(
      `parseOpFalseIfCarrierScript: pubkey must be ${COMPRESSED_PUBKEY_SIZE} or ${UNCOMPRESSED_PUBKEY_SIZE} bytes (got ${pubkey.length})`,
    );
  }
  if (script[off] !== OP_CHECKSIG) {
    throw new Error(
      `parseOpFalseIfCarrierScript: expected OP_CHECKSIG at offset ${off}, got 0x${(script[off] ?? 0).toString(16)}`,
    );
  }
  off += 1;
  if (off !== script.length) {
    throw new Error(
      `parseOpFalseIfCarrierScript: trailing bytes after OP_CHECKSIG (offset ${off} of ${script.length})`,
    );
  }
  return { cellBytes, pubkey };
}

// ── (c) OP_DROP + P2PKH data carrier ──────────────────────────────

/**
 * Build a `<cell> OP_DROP OP_DUP OP_HASH160 <pkh> OP_EQUALVERIFY OP_CHECKSIG`
 * locking script.
 *
 * The trailing P2PKH (5 opcodes + 20-byte pkh) is the standard
 * Bitcoin/BSV pay-to-pubkey-hash spend predicate — the most wallet-
 * compatible spend shape; generic BSV wallets recognise the output.
 *
 * Byte layout for canonical 1024B cell + 20B pkh:
 *
 *     0x4d 0x00 0x04          OP_PUSHDATA2 + LE length 0x0400 (1024)
 *     <1024 bytes>            cell data
 *     0x75                    OP_DROP
 *     0x76                    OP_DUP
 *     0xa9                    OP_HASH160
 *     0x14                    push 20 bytes
 *     <20 bytes>              pubkey hash (RIPEMD160(SHA256(pubkey)))
 *     0x88                    OP_EQUALVERIFY
 *     0xac                    OP_CHECKSIG
 *
 * Total: 1051 bytes (12 bytes less than pushdrop — pkh is 20B vs
 * pubkey 33B, partly offset by the extra P2PKH opcodes).
 */
export function buildOpDropP2pkhCarrierScript(
  cellBytes: Uint8Array,
  pkh: Uint8Array,
): Uint8Array {
  if (cellBytes.length === 0) {
    throw new Error('buildOpDropP2pkhCarrierScript: cell must be non-empty');
  }
  if (cellBytes.length > 65535) {
    throw new Error(
      `buildOpDropP2pkhCarrierScript: cell ${cellBytes.length} bytes exceeds PUSHDATA2 max (65535)`,
    );
  }
  if (pkh.length !== PKH_SIZE) {
    throw new Error(
      `buildOpDropP2pkhCarrierScript: pkh must be ${PKH_SIZE} bytes (got ${pkh.length})`,
    );
  }
  const cellPrefix = pushPrefix(cellBytes.length);
  // pkh push prefix is always direct push of length 0x14 (20)
  const total =
    cellPrefix.length +
    cellBytes.length +
    /* OP_DROP */ 1 +
    /* OP_DUP */ 1 +
    /* OP_HASH160 */ 1 +
    /* push20 */ 1 +
    /* pkh */ 20 +
    /* OP_EQUALVERIFY */ 1 +
    /* OP_CHECKSIG */ 1;
  const out = new Uint8Array(total);
  let off = 0;
  out.set(cellPrefix, off);
  off += cellPrefix.length;
  out.set(cellBytes, off);
  off += cellBytes.length;
  out[off++] = OP_DROP;
  out[off++] = OP_DUP;
  out[off++] = OP_HASH160;
  out[off++] = 0x14; // direct push of 20 bytes
  out.set(pkh, off);
  off += 20;
  out[off++] = OP_EQUALVERIFY;
  out[off++] = OP_CHECKSIG;
  return out;
}

/** Strict parser for the exact (c) shape produced by
 *  `buildOpDropP2pkhCarrierScript`. */
export function parseOpDropP2pkhCarrierScript(script: Uint8Array): {
  cellBytes: Uint8Array;
  pkh: Uint8Array;
} {
  if (script.length < 7) {
    throw new Error(`parseOpDropP2pkhCarrierScript: too short (${script.length})`);
  }
  let off = 0;
  const cellPush = readPushBytesLocal(script, off);
  off = cellPush.offsetAfter;
  const cellBytes = cellPush.data;
  // Now expect: OP_DROP OP_DUP OP_HASH160 0x14 <20> OP_EQUALVERIFY OP_CHECKSIG
  if (script[off] !== OP_DROP) {
    throw new Error(
      `parseOpDropP2pkhCarrierScript: expected OP_DROP at offset ${off}, got 0x${(script[off] ?? 0).toString(16)}`,
    );
  }
  off += 1;
  if (script[off] !== OP_DUP) {
    throw new Error(
      `parseOpDropP2pkhCarrierScript: expected OP_DUP at offset ${off}, got 0x${(script[off] ?? 0).toString(16)}`,
    );
  }
  off += 1;
  if (script[off] !== OP_HASH160) {
    throw new Error(
      `parseOpDropP2pkhCarrierScript: expected OP_HASH160 at offset ${off}, got 0x${(script[off] ?? 0).toString(16)}`,
    );
  }
  off += 1;
  if (script[off] !== 0x14) {
    throw new Error(
      `parseOpDropP2pkhCarrierScript: expected direct push 0x14 (20) at offset ${off}, got 0x${(script[off] ?? 0).toString(16)}`,
    );
  }
  off += 1;
  if (off + 20 > script.length) {
    throw new Error('parseOpDropP2pkhCarrierScript: truncated pkh');
  }
  const pkh = script.slice(off, off + 20);
  off += 20;
  if (script[off] !== OP_EQUALVERIFY) {
    throw new Error(
      `parseOpDropP2pkhCarrierScript: expected OP_EQUALVERIFY at offset ${off}, got 0x${(script[off] ?? 0).toString(16)}`,
    );
  }
  off += 1;
  if (script[off] !== OP_CHECKSIG) {
    throw new Error(
      `parseOpDropP2pkhCarrierScript: expected OP_CHECKSIG at offset ${off}, got 0x${(script[off] ?? 0).toString(16)}`,
    );
  }
  off += 1;
  if (off !== script.length) {
    throw new Error(
      `parseOpDropP2pkhCarrierScript: trailing bytes after OP_CHECKSIG (offset ${off} of ${script.length})`,
    );
  }
  return { cellBytes, pkh };
}

// ── Discriminator ─────────────────────────────────────────────────

/**
 * Identify which of the three carrier shapes a locking script uses
 * (or `null` if it matches none of them). Cheap byte-pattern check
 * by opcode prefix; does not parse the full body.
 */
export function detectDataCarrierShape(script: Uint8Array): DataCarrierShape | null {
  if (script.length < 4) return null;
  if (script[0] === OP_FALSE && script[1] === OP_IF) return 'op_false_op_if';
  // shapes (a) and (c) both start with a push of cell bytes. Disambiguate
  // by what follows the push: (a) has <push><cellBytes> OP_DROP <push><pubkey> OP_CHECKSIG;
  // (c) has <push><cellBytes> OP_DROP OP_DUP OP_HASH160 0x14 ...
  let off: number;
  try {
    const cellPush = readPushBytesLocal(script, 0);
    off = cellPush.offsetAfter;
  } catch {
    return null;
  }
  if (script[off] !== OP_DROP) return null;
  off += 1;
  if (script[off] === OP_DUP && script[off + 1] === OP_HASH160) {
    return 'op_drop_p2pkh';
  }
  // Otherwise expect a push of pubkey then OP_CHECKSIG (the pushdrop shape).
  return 'pushdrop';
}

/**
 * Parse any of the three known carrier shapes, returning a tagged
 * `ParsedCarrier`. Throws if the script matches no recognised shape
 * (including OP_RETURN — semantos does not use OP_RETURN for cell
 * carriage; see L14 + the BSV-only invariant).
 */
export function parseDataCarrier(script: Uint8Array): ParsedCarrier {
  const shape = detectDataCarrierShape(script);
  if (shape === null) {
    throw new Error(
      `parseDataCarrier: script does not match any known carrier shape ` +
        `(pushdrop | op_false_op_if | op_drop_p2pkh); ` +
        `first byte = 0x${(script[0] ?? 0).toString(16)}`,
    );
  }
  if (shape === 'pushdrop') {
    const p = parsePushdropLockingScript(script);
    return { shape: 'pushdrop', cellBytes: p.cellBytes, pubkey: p.pubkey };
  }
  if (shape === 'op_false_op_if') {
    const p = parseOpFalseIfCarrierScript(script);
    return { shape: 'op_false_op_if', cellBytes: p.cellBytes, pubkey: p.pubkey };
  }
  // op_drop_p2pkh
  const p = parseOpDropP2pkhCarrierScript(script);
  return { shape: 'op_drop_p2pkh', cellBytes: p.cellBytes, pkh: p.pkh };
}

// ── Size constants (for fee estimation) ───────────────────────────

/** (a) pushdrop with canonical 1024B cell + 33B compressed pubkey. */
export const CANONICAL_CELL_PUSHDROP_SIZE = 3 + 1024 + 1 + 1 + 33 + 1; // 1063
/** (b) OP_FALSE OP_IF with canonical 1024B cell + 33B compressed pubkey. */
export const CANONICAL_CELL_OP_FALSE_IF_SIZE = 1 + 1 + 3 + 1024 + 1 + 1 + 33 + 1; // 1065
/** (c) OP_DROP + P2PKH with canonical 1024B cell + 20B pkh. */
export const CANONICAL_CELL_OP_DROP_P2PKH_SIZE = 3 + 1024 + 1 + 1 + 1 + 1 + 20 + 1 + 1; // 1053

// ── Internal helpers ──────────────────────────────────────────────

interface PushBytes {
  data: Uint8Array;
  offsetAfter: number;
}
/** Local copy of readPushBytes for use within this module. Mirrors
 *  the implementation in cell-pushdrop.ts. */
function readPushBytesLocal(script: Uint8Array, off: number): PushBytes {
  if (off >= script.length) {
    throw new Error(`readPushBytes: out of bounds at offset ${off}`);
  }
  const op = script[off]!;
  if (op >= 0x01 && op <= 0x4b) {
    const len = op;
    const start = off + 1;
    const end = start + len;
    if (end > script.length) {
      throw new Error(`readPushBytes: truncated direct push (need ${len} bytes from ${start})`);
    }
    return { data: script.slice(start, end), offsetAfter: end };
  }
  if (op === 0x4c /* PUSHDATA1 */) {
    if (off + 1 >= script.length) throw new Error('readPushBytes: truncated PUSHDATA1 length');
    const len = script[off + 1]!;
    const start = off + 2;
    const end = start + len;
    if (end > script.length) throw new Error('readPushBytes: truncated PUSHDATA1 body');
    return { data: script.slice(start, end), offsetAfter: end };
  }
  if (op === 0x4d /* PUSHDATA2 */) {
    if (off + 2 >= script.length) throw new Error('readPushBytes: truncated PUSHDATA2 length');
    const len = script[off + 1]! | (script[off + 2]! << 8);
    const start = off + 3;
    const end = start + len;
    if (end > script.length) throw new Error('readPushBytes: truncated PUSHDATA2 body');
    return { data: script.slice(start, end), offsetAfter: end };
  }
  if (op === 0x4e /* PUSHDATA4 */) {
    if (off + 4 >= script.length) throw new Error('readPushBytes: truncated PUSHDATA4 length');
    const len =
      (script[off + 1]! |
        (script[off + 2]! << 8) |
        (script[off + 3]! << 16) |
        (script[off + 4]! << 24)) >>>
      0;
    const start = off + 5;
    const end = start + len;
    if (end > script.length) throw new Error('readPushBytes: truncated PUSHDATA4 body');
    return { data: script.slice(start, end), offsetAfter: end };
  }
  throw new Error(`readPushBytes: opcode 0x${op.toString(16)} at offset ${off} is not a push`);
}

```
