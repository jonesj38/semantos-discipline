---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-pushdrop.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.841228+00:00
---

# core/protocol-types/src/cell-pushdrop.ts

```ts
/**
 * Cell-pushdrop codec — wrap a canonical 1024-byte cell as a BSV
 * "pushdrop" locking script so the cell becomes a spendable UTXO.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §3.1 — the
 * pushdrop pattern.
 *
 * Locking script layout:
 *
 *     <cell_bytes> OP_DROP <owner_pubkey> OP_CHECKSIG
 *
 * Concrete byte layout for a canonical 1024-byte cell + compressed
 * 33-byte pubkey:
 *
 *     0x4d 0x00 0x04          OP_PUSHDATA2 + LE length 0x0400 (1024)
 *     <1024 bytes>            cell data
 *     0x75                    OP_DROP
 *     0x21                    push 33 bytes (compressed pubkey marker)
 *     <33 bytes>              owner pubkey
 *     0xac                    OP_CHECKSIG
 *
 * Total: 1063 bytes of locking-script bytecode for the canonical case.
 *
 * The codec is intentionally agnostic about the BSV SDK / transaction
 * builder — it produces the locking-script bytes only. Higher layers
 * (wallet-headers cartridge, ARC broadcaster) wrap the bytes in a tx
 * output with the chosen satoshi value.
 */

// ── BSV script opcodes used in the pushdrop locking script ──
export const OP_DROP = 0x75 as const;
export const OP_CHECKSIG = 0xac as const;
export const OP_PUSHDATA1 = 0x4c as const;
export const OP_PUSHDATA2 = 0x4d as const;
export const OP_PUSHDATA4 = 0x4e as const;

/** A compressed secp256k1 pubkey is 33 bytes (0x02/0x03 prefix + X). */
export const COMPRESSED_PUBKEY_SIZE = 33 as const;
/** An uncompressed secp256k1 pubkey is 65 bytes (0x04 prefix + X + Y). */
export const UNCOMPRESSED_PUBKEY_SIZE = 65 as const;

/**
 * Build the BSV-script push prefix for `data.length` bytes. Returns the
 * minimal-encoded prefix per consensus rules:
 *
 *   - 1..75 bytes:    single opcode 0x01..0x4b (the length itself)
 *   - 76..255 bytes:  OP_PUSHDATA1 + 1-byte length
 *   - 256..65535:     OP_PUSHDATA2 + 2-byte LE length
 *   - >= 65536:       OP_PUSHDATA4 + 4-byte LE length
 */
export function pushPrefix(dataLen: number): Uint8Array {
  if (dataLen < 0) throw new Error(`pushPrefix: negative length ${dataLen}`);
  if (dataLen <= 75) {
    return new Uint8Array([dataLen]);
  }
  if (dataLen <= 255) {
    return new Uint8Array([OP_PUSHDATA1, dataLen]);
  }
  if (dataLen <= 65535) {
    return new Uint8Array([OP_PUSHDATA2, dataLen & 0xff, (dataLen >>> 8) & 0xff]);
  }
  // Past 65535 bytes; PUSHDATA4. Canonical cells stay well below this.
  return new Uint8Array([
    OP_PUSHDATA4,
    dataLen & 0xff,
    (dataLen >>> 8) & 0xff,
    (dataLen >>> 16) & 0xff,
    (dataLen >>> 24) & 0xff,
  ]);
}

/**
 * Build a `<cell> OP_DROP <pubkey> OP_CHECKSIG` locking script.
 *
 * `pubkey` MUST be either 33 bytes (compressed) or 65 bytes (uncompressed);
 * `cellBytes` MUST be non-empty and at most 65535 bytes (PUSHDATA2 max).
 */
export function buildPushdropLockingScript(
  cellBytes: Uint8Array,
  pubkey: Uint8Array,
): Uint8Array {
  if (cellBytes.length === 0) {
    throw new Error(`buildPushdropLockingScript: cell must be non-empty`);
  }
  if (cellBytes.length > 65535) {
    throw new Error(
      `buildPushdropLockingScript: cell ${cellBytes.length} bytes exceeds PUSHDATA2 max (65535)`,
    );
  }
  if (pubkey.length !== COMPRESSED_PUBKEY_SIZE && pubkey.length !== UNCOMPRESSED_PUBKEY_SIZE) {
    throw new Error(
      `buildPushdropLockingScript: pubkey must be ${COMPRESSED_PUBKEY_SIZE} or ${UNCOMPRESSED_PUBKEY_SIZE} bytes (got ${pubkey.length})`,
    );
  }
  const cellPrefix = pushPrefix(cellBytes.length);
  const pubkeyPrefix = pushPrefix(pubkey.length);
  const total =
    cellPrefix.length + cellBytes.length + 1 + pubkeyPrefix.length + pubkey.length + 1;
  const out = new Uint8Array(total);
  let off = 0;
  out.set(cellPrefix, off);
  off += cellPrefix.length;
  out.set(cellBytes, off);
  off += cellBytes.length;
  out[off++] = OP_DROP;
  out.set(pubkeyPrefix, off);
  off += pubkeyPrefix.length;
  out.set(pubkey, off);
  off += pubkey.length;
  out[off++] = OP_CHECKSIG;
  return out;
}

/** Parsed components of a pushdrop locking script. */
export interface ParsedPushdrop {
  cellBytes: Uint8Array;
  pubkey: Uint8Array;
}

/**
 * Parse a `<cell> OP_DROP <pubkey> OP_CHECKSIG` locking script. Throws if
 * the script doesn't match the canonical pushdrop shape.
 *
 * This is intentionally strict — it accepts only the exact 4-element
 * script that `buildPushdropLockingScript` produces. Variants (extra
 * pushes, different opcodes between drop and checksig, etc.) are not
 * recognised by this codec; consumers wanting flexibility should parse
 * the script themselves.
 */
export function parsePushdropLockingScript(script: Uint8Array): ParsedPushdrop {
  if (script.length < 4) {
    throw new Error(`parsePushdropLockingScript: too short (${script.length})`);
  }
  let off = 0;
  const cellPush = readPushBytes(script, off);
  off = cellPush.offsetAfter;
  const cellBytes = cellPush.data;
  if (script[off] !== OP_DROP) {
    throw new Error(
      `parsePushdropLockingScript: expected OP_DROP at offset ${off}, got 0x${(script[off] ?? 0).toString(16)}`,
    );
  }
  off += 1;
  const pubPush = readPushBytes(script, off);
  off = pubPush.offsetAfter;
  const pubkey = pubPush.data;
  if (pubkey.length !== COMPRESSED_PUBKEY_SIZE && pubkey.length !== UNCOMPRESSED_PUBKEY_SIZE) {
    throw new Error(
      `parsePushdropLockingScript: pubkey must be ${COMPRESSED_PUBKEY_SIZE} or ${UNCOMPRESSED_PUBKEY_SIZE} bytes (got ${pubkey.length})`,
    );
  }
  if (script[off] !== OP_CHECKSIG) {
    throw new Error(
      `parsePushdropLockingScript: expected OP_CHECKSIG at offset ${off}, got 0x${(script[off] ?? 0).toString(16)}`,
    );
  }
  off += 1;
  if (off !== script.length) {
    throw new Error(
      `parsePushdropLockingScript: trailing bytes after OP_CHECKSIG (offset ${off} of ${script.length})`,
    );
  }
  return { cellBytes, pubkey };
}

interface PushBytes {
  data: Uint8Array;
  offsetAfter: number;
}
function readPushBytes(script: Uint8Array, off: number): PushBytes {
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
  if (op === OP_PUSHDATA1) {
    if (off + 1 >= script.length) throw new Error('readPushBytes: truncated PUSHDATA1 length');
    const len = script[off + 1]!;
    const start = off + 2;
    const end = start + len;
    if (end > script.length) throw new Error('readPushBytes: truncated PUSHDATA1 body');
    return { data: script.slice(start, end), offsetAfter: end };
  }
  if (op === OP_PUSHDATA2) {
    if (off + 2 >= script.length) throw new Error('readPushBytes: truncated PUSHDATA2 length');
    const len = script[off + 1]! | (script[off + 2]! << 8);
    const start = off + 3;
    const end = start + len;
    if (end > script.length) throw new Error('readPushBytes: truncated PUSHDATA2 body');
    return { data: script.slice(start, end), offsetAfter: end };
  }
  if (op === OP_PUSHDATA4) {
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

/**
 * The locking-script size for a canonical 1024-byte cell + 33-byte
 * compressed pubkey — used for fee estimation at the originator.
 */
export const CANONICAL_CELL_PUSHDROP_SCRIPT_SIZE = 3 + 1024 + 1 + 1 + 33 + 1; // = 1063

```
