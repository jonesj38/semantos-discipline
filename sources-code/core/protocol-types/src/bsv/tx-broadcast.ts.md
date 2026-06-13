---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/bsv/tx-broadcast.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.869197+00:00
---

# core/protocol-types/src/bsv/tx-broadcast.ts

```ts
/**
 * Wire formats for the three trigger/result cells the broker uses to
 * drive tx assembly and broadcast, per LOCKSCRIPT-CLEAVAGE.md §8.3:
 *
 *   - `bsv.tx.assemble.intent`     EPHEMERAL  broker's "assemble-and-broadcast"
 *                                              trigger (consumes a partial.shell
 *                                              + emits a broadcast.intent)
 *   - `bsv.tx.broadcast.intent`    EPHEMERAL  standalone broadcast request
 *                                              (not bundled with a shell;
 *                                              carries the serialized tx bytes)
 *   - `bsv.tx.broadcast.result`    EPHEMERAL  { txid, accepted, arcStatus }
 *
 * The split between `assemble.intent` and `broadcast.intent` mirrors
 * how the broker orchestrates: an assemble.intent says "load the shell,
 * resolve templates, finalize, then broadcast" — it's a multi-phase
 * operation handled by the cartridge-side substrate handler chain. A
 * broadcast.intent is the lower-level primitive: "I have these raw tx
 * bytes; send them to ARC."
 *
 * Most cartridges only ever mint `assemble.intent` cells; the
 * substrate-side handler chain emits the broadcast.intent for them as
 * a side effect of consuming the shell.
 */

import { TX_PARTIAL_WIRE_VERSION, CELL_HASH_BYTES } from "./tx-partial";

/** Re-exported for callers wiring only broadcast (no partial-tx group). */
export const TX_BROADCAST_WIRE_VERSION = TX_PARTIAL_WIRE_VERSION;

/**
 * Upper bound on inline tx bytes carried in a broadcast.intent payload.
 *
 *   1024-byte cell budget − 62-byte CellHeader − 8-byte broadcast.intent
 *   prefix = 954 bytes; round down to 940 to leave forward-compat
 *   headroom (matches the conservative cap pattern from spv-verify.ts).
 *
 * Above this cap the broker must use a carriage chain (future PR, same
 * mechanism as bsv.beef.carriage.head/body — see LINEAR-CELL-SPV-STATE
 * §5). For typical partial-tx workflows (≤ 16 inputs / 16 outputs with
 * standard P2PKH-style scripts) the inline form suffices.
 */
export const INLINE_TX_MAX_BYTES = 940 as const;

// ─────────────────────────── Assemble intent ──────────────────────────

/**
 * Decoded `bsv.tx.assemble.intent` payload — the broker's trigger to
 * consume a partial.shell, finalize it, and broadcast.
 *
 * Layout (fixed):
 *
 *     0   1   VERSION = 1
 *     1  32   shell_cell_hash      (the partial.shell to consume)
 *    33   1   FLAGS                (bit 0 = drop_change, bit 1 = bundle_beef)
 *    34   3   reserved (must be 0)
 *
 * Total: 37 bytes. Minimal by design — the shell carries all the state;
 * this cell just authorises the broker to move it forward.
 */
export const TX_ASSEMBLE_INTENT_BYTES = 37 as const;

/** Bit flags for the FLAGS byte. */
export const TxAssembleIntentFlag = {
  /** Drop any change output below the dust threshold. */
  DropChange: 1 << 0,
  /** Bundle a BEEF proof into the broadcast envelope. */
  BundleBeef: 1 << 1,
} as const;

export interface TxAssembleIntent {
  /** Cell-hash of the bsv.tx.partial.shell to consume. */
  readonly shellCellHash: Uint8Array;
  /** OR-ed flags. */
  readonly flags: number;
}

export function encodeTxAssembleIntent(a: TxAssembleIntent): Uint8Array {
  if (a.shellCellHash.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodeTxAssembleIntent: shellCellHash must be ${CELL_HASH_BYTES} bytes`,
    );
  }
  if (a.flags < 0 || a.flags > 0xff) {
    throw new RangeError(`encodeTxAssembleIntent: flags out of byte range`);
  }
  // Reject bits outside the declared flag set so callers don't quietly
  // smuggle semantics into reserved positions.
  const declared =
    TxAssembleIntentFlag.DropChange | TxAssembleIntentFlag.BundleBeef;
  if ((a.flags & ~declared) !== 0) {
    throw new RangeError(
      `encodeTxAssembleIntent: undeclared flag bits set 0x${a.flags.toString(16)}`,
    );
  }
  const out = new Uint8Array(TX_ASSEMBLE_INTENT_BYTES);
  out[0] = TX_BROADCAST_WIRE_VERSION;
  out.set(a.shellCellHash, 1);
  out[33] = a.flags;
  // 34, 35, 36 = reserved zeros
  return out;
}

export function decodeTxAssembleIntent(payload: Uint8Array): TxAssembleIntent {
  if (payload.length < TX_ASSEMBLE_INTENT_BYTES) {
    throw new RangeError(
      `decodeTxAssembleIntent: payload must be ≥ ${TX_ASSEMBLE_INTENT_BYTES} ` +
        `bytes (got ${payload.length})`,
    );
  }
  if (payload[0] !== TX_BROADCAST_WIRE_VERSION) {
    throw new RangeError(
      `decodeTxAssembleIntent: unknown VERSION=${payload[0]}`,
    );
  }
  if (payload[34] !== 0 || payload[35] !== 0 || payload[36] !== 0) {
    throw new RangeError(
      `decodeTxAssembleIntent: reserved bytes must be 0`,
    );
  }
  return {
    shellCellHash: payload.slice(1, 33),
    flags: payload[33],
  };
}

// ─────────────────────────── Broadcast intent ─────────────────────────

/**
 * Decoded `bsv.tx.broadcast.intent` payload — raw tx bytes for ARC.
 *
 * Layout:
 *
 *     0   1     VERSION = 1
 *     1   1     FLAGS (bit 0 = inline; reserved otherwise)
 *     2   2     tx_bytes_len (LE u16; 1..INLINE_TX_MAX_BYTES)
 *     4   tx_bytes_len   raw serialized tx bytes (from host_assemble_tx)
 *
 * Total: 4 + tx_bytes_len bytes.
 */
export const TX_BROADCAST_INTENT_PREFIX_BYTES = 4 as const;

/** FLAGS bit positions. */
export const TxBroadcastIntentFlag = {
  /** Bit 0 — when set, the tx bytes are inline in this payload. */
  Inline: 1 << 0,
} as const;

export interface TxBroadcastIntent {
  /** Raw serialized tx bytes (from host_assemble_tx). */
  readonly txBytes: Uint8Array;
}

export function encodeTxBroadcastIntent(b: TxBroadcastIntent): Uint8Array {
  if (b.txBytes.length < 1 || b.txBytes.length > INLINE_TX_MAX_BYTES) {
    throw new RangeError(
      `encodeTxBroadcastIntent: txBytes length ${b.txBytes.length} ` +
        `out of range [1, ${INLINE_TX_MAX_BYTES}]; use a carriage chain ` +
        `for larger txs`,
    );
  }
  const out = new Uint8Array(TX_BROADCAST_INTENT_PREFIX_BYTES + b.txBytes.length);
  out[0] = TX_BROADCAST_WIRE_VERSION;
  out[1] = TxBroadcastIntentFlag.Inline;
  out[2] = b.txBytes.length & 0xff;
  out[3] = (b.txBytes.length >>> 8) & 0xff;
  out.set(b.txBytes, TX_BROADCAST_INTENT_PREFIX_BYTES);
  return out;
}

export function decodeTxBroadcastIntent(payload: Uint8Array): TxBroadcastIntent {
  if (payload.length < TX_BROADCAST_INTENT_PREFIX_BYTES) {
    throw new RangeError(
      `decodeTxBroadcastIntent: payload too short (got ${payload.length})`,
    );
  }
  if (payload[0] !== TX_BROADCAST_WIRE_VERSION) {
    throw new RangeError(
      `decodeTxBroadcastIntent: unknown VERSION=${payload[0]}`,
    );
  }
  if ((payload[1] & TxBroadcastIntentFlag.Inline) === 0) {
    throw new RangeError(
      `decodeTxBroadcastIntent: only inline form supported in v1 ` +
        `(FLAGS=0x${payload[1].toString(16)})`,
    );
  }
  const txLen = payload[2] | (payload[3] << 8);
  if (txLen < 1 || txLen > INLINE_TX_MAX_BYTES) {
    throw new RangeError(
      `decodeTxBroadcastIntent: tx_bytes_len=${txLen} out of range`,
    );
  }
  if (payload.length < TX_BROADCAST_INTENT_PREFIX_BYTES + txLen) {
    throw new RangeError(`decodeTxBroadcastIntent: payload truncated`);
  }
  return {
    txBytes: payload.slice(
      TX_BROADCAST_INTENT_PREFIX_BYTES,
      TX_BROADCAST_INTENT_PREFIX_BYTES + txLen,
    ),
  };
}

// ─────────────────────────── Broadcast result ─────────────────────────

/**
 * Broadcast outcome — coarse-grained on the wire. Detailed ARC error
 * messages live in the audit log.
 */
export const TxBroadcastOutcome = {
  /** ARC rejected the tx (consensus / policy failure). */
  Rejected: 0,
  /** ARC accepted the tx into the mempool. */
  Accepted: 1,
  /** Broker-side error before ARC could be reached. */
  Error: 2,
} as const;
export type TxBroadcastOutcome =
  (typeof TxBroadcastOutcome)[keyof typeof TxBroadcastOutcome];

/**
 * ARC status discriminant. Maps the broker's understanding of ARC's
 * lifecycle into a stable enum on the wire.
 */
export const TxBroadcastArcStatus = {
  /** No ARC status (e.g., outcome=Error before ARC was reached). */
  None: 0,
  /** Received by ARC; not yet seen by miners. */
  Received: 1,
  /** Stored in ARC's mempool. */
  Stored: 2,
  /** Announced to the network. */
  Announced: 3,
  /** Seen by ≥1 miner. */
  Seen: 4,
  /** Mined into a block. */
  Mined: 5,
  /** Rejected by ARC. */
  Rejected: 6,
} as const;
export type TxBroadcastArcStatus =
  (typeof TxBroadcastArcStatus)[keyof typeof TxBroadcastArcStatus];

/**
 * Decoded `bsv.tx.broadcast.result` payload.
 *
 * Layout (fixed):
 *
 *     0   1   VERSION = 1
 *     1   1   OUTCOME      (TxBroadcastOutcome)
 *     2  32   txid         (32-byte internal byte order; echoed for correlation)
 *    34   1   arc_status   (TxBroadcastArcStatus)
 *    35   4   confirmations (LE u32; 0 if not yet seen at depth)
 *
 * Total: 39 bytes.
 */
export const TX_BROADCAST_RESULT_BYTES = 39 as const;

export interface TxBroadcastResult {
  readonly outcome: TxBroadcastOutcome;
  readonly txid: Uint8Array;
  readonly arcStatus: TxBroadcastArcStatus;
  /** Block-depth confirmations; 0 means not yet mined / not yet observed. */
  readonly confirmations: number;
}

export function encodeTxBroadcastResult(r: TxBroadcastResult): Uint8Array {
  if (r.txid.length !== 32) {
    throw new RangeError(
      `encodeTxBroadcastResult: txid must be 32 bytes (got ${r.txid.length})`,
    );
  }
  if (r.confirmations < 0 || r.confirmations > 0xffffffff) {
    throw new RangeError(
      `encodeTxBroadcastResult: confirmations out of u32 range`,
    );
  }
  const out = new Uint8Array(TX_BROADCAST_RESULT_BYTES);
  out[0] = TX_BROADCAST_WIRE_VERSION;
  out[1] = r.outcome;
  out.set(r.txid, 2);
  out[34] = r.arcStatus;
  out[35] = r.confirmations & 0xff;
  out[36] = (r.confirmations >>> 8) & 0xff;
  out[37] = (r.confirmations >>> 16) & 0xff;
  out[38] = (r.confirmations >>> 24) & 0xff;
  return out;
}

export function decodeTxBroadcastResult(payload: Uint8Array): TxBroadcastResult {
  if (payload.length < TX_BROADCAST_RESULT_BYTES) {
    throw new RangeError(
      `decodeTxBroadcastResult: payload must be ≥ ${TX_BROADCAST_RESULT_BYTES} ` +
        `bytes (got ${payload.length})`,
    );
  }
  if (payload[0] !== TX_BROADCAST_WIRE_VERSION) {
    throw new RangeError(
      `decodeTxBroadcastResult: unknown VERSION=${payload[0]}`,
    );
  }
  const outcome = payload[1] as TxBroadcastOutcome;
  if (!isTxBroadcastOutcome(outcome)) {
    throw new RangeError(`decodeTxBroadcastResult: unknown outcome=${outcome}`);
  }
  const arcStatus = payload[34] as TxBroadcastArcStatus;
  if (!isTxBroadcastArcStatus(arcStatus)) {
    throw new RangeError(
      `decodeTxBroadcastResult: unknown arc_status=${arcStatus}`,
    );
  }
  const confirmations =
    (payload[35] |
      (payload[36] << 8) |
      (payload[37] << 16) |
      (payload[38] << 24)) >>>
    0;
  return {
    outcome,
    txid: payload.slice(2, 34),
    arcStatus,
    confirmations,
  };
}

function isTxBroadcastOutcome(v: number): v is TxBroadcastOutcome {
  return (
    v === TxBroadcastOutcome.Rejected ||
    v === TxBroadcastOutcome.Accepted ||
    v === TxBroadcastOutcome.Error
  );
}

function isTxBroadcastArcStatus(v: number): v is TxBroadcastArcStatus {
  return (
    v === TxBroadcastArcStatus.None ||
    v === TxBroadcastArcStatus.Received ||
    v === TxBroadcastArcStatus.Stored ||
    v === TxBroadcastArcStatus.Announced ||
    v === TxBroadcastArcStatus.Seen ||
    v === TxBroadcastArcStatus.Mined ||
    v === TxBroadcastArcStatus.Rejected
  );
}

```
