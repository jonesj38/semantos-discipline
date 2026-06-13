---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/bsv/tx-partial.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.869765+00:00
---

# core/protocol-types/src/bsv/tx-partial.ts

```ts
/**
 * Wire formats for the `bsv.tx.partial.*` cell-type group — the
 * partial-tx co-signing state machine per LOCKSCRIPT-CLEAVAGE.md §6.3
 * + §8.3.
 *
 * Four cell types live in this group:
 *
 *   - `bsv.tx.partial.shell`         LINEAR     the accumulating skeleton
 *   - `bsv.tx.partial.contribution`  EPHEMERAL  one party's signed input/output
 *   - `bsv.tx.partial.assemble`      EPHEMERAL  trigger broadcast
 *   - `bsv.tx.partial.cancel`        EPHEMERAL  abort the workflow
 *
 * The state machine (3-party co-sign example, §6.3):
 *
 *   T=0  initiator mints `partial.intent`   (workflow-specific intent;
 *                                            handler emits the shell)
 *   T=1  → handler emits LINEAR shell with
 *         { expected_counterparties: [A, B, C], collected: [] }
 *   T=2  party A mints `partial.contribution{party_index=0, sig_A}`
 *         → handler verifies sig_A vs shell-expected digest, emits
 *           successor LINEAR shell with collected = [A]
 *   T=3  party B contributes (collected = [A, B])
 *   T=4  party C contributes (collected = [A, B, C], full)
 *   T=5  initiator mints `partial.assemble`
 *         → handler verifies completeness, emits `bsv.tx.broadcast.intent`,
 *           shell transitions to status=broadcast_pending
 *   alt  any party mints `partial.cancel` while status=active
 *         → shell transitions to status=cancelled
 *
 * EPHEMERAL on contribution/assemble/cancel gives replay resistance
 * (§6.1): once consumed by the handler the contribution cannot be
 * re-applied to a later phase. LINEAR on shell gives the one-shot
 * destructor (one assemble OR one cancel) — see §6.2.
 *
 * Wire formats are designed to fit comfortably in the 1024-byte cell
 * payload budget even at the upper bound of MAX_COUNTERPARTIES = 16
 * and full collection.
 */

// ─────────────────────────── Versions / caps ──────────────────────────

/** Wire-format version stamped at offset 0 of every payload in the group. */
export const TX_PARTIAL_WIRE_VERSION = 1 as const;

/**
 * Upper bound on counterparties per shell. Sized so a fully-collected
 * shell still fits the 1024-byte cell budget with headroom:
 *
 *   shell prefix          24 bytes  (version + workflow_id + N + status
 *                                    + reserved)
 *   counterparties        20×N      (hash160 per party)
 *   contributions index   33×K      (party_index byte + contribution
 *                                    cell-hash; K ≤ N)
 *
 * At N=K=16: 24 + 320 + 528 = 872 bytes, leaves ~150-byte headroom.
 */
export const MAX_COUNTERPARTIES = 16 as const;

/**
 * Upper bound on inline signature bytes in a contribution payload.
 * Standard ECDSA-DER signatures are ≤ 72 bytes + 1 sighash-flag byte;
 * 80 leaves a margin for future flag-byte encodings.
 */
export const MAX_INLINE_SIG_BYTES = 80 as const;

/** Hash160 size in bytes (RIPEMD160(SHA256(pubkey))). */
export const HASH160_BYTES = 20 as const;

/** Compressed-secp256k1 public key size in bytes. */
export const COMPRESSED_PUBKEY_BYTES = 33 as const;

/** Cell-hash size in bytes (matches the 1024-byte cell SHA256 hash). */
export const CELL_HASH_BYTES = 32 as const;

/** Workflow ID size in bytes (caller-chosen opaque identifier). */
export const WORKFLOW_ID_BYTES = 16 as const;

// ─────────────────────────── Status enum ──────────────────────────────

/**
 * Shell lifecycle status. Strict enum — decoder rejects unknown values
 * rather than silently corrupting state machine semantics.
 */
export const PartialShellStatus = {
  /** Active — accepting contributions. */
  Active: 0,
  /** Assemble cell consumed the shell; broker is broadcasting. */
  BroadcastPending: 1,
  /** Broadcast accepted and confirmed; workflow finalised. */
  Finalised: 2,
  /** Cancel cell consumed the shell; workflow aborted. */
  Cancelled: 3,
} as const;
export type PartialShellStatus =
  (typeof PartialShellStatus)[keyof typeof PartialShellStatus];

/** Cancel-reason discriminant. Short tag on the wire; diagnostics in audit. */
export const PartialCancelReason = {
  /** Reason not specified. */
  Unspecified: 0,
  /** Initiator changed their mind before completion. */
  InitiatorAbort: 1,
  /** Workflow exceeded a deadline / TTL. */
  TimedOut: 2,
  /** A counterparty rejected the proposal. */
  CounterpartyRejected: 3,
  /** An out-of-band conflict (e.g., one of the input UTXOs spent). */
  InputConflict: 4,
} as const;
export type PartialCancelReason =
  (typeof PartialCancelReason)[keyof typeof PartialCancelReason];

// ─────────────────────────── Shell payload ────────────────────────────

/**
 * Decoded shell payload — the LINEAR cell that accumulates partial-tx
 * state across the workflow's lifetime.
 *
 * Layout (variable-length; see encoder for byte-exact offsets):
 *
 *     0   1   VERSION = 1
 *     1  16   workflow_id
 *    17   1   N (counterparties count, 1..MAX_COUNTERPARTIES)
 *    18  20N  counterparty_hash160[N]
 *    *    1   K (collected count, 0..N)
 *    *   33K  contributions[K] = (party_index: 1 + contribution_hash: 32)
 *    *    1   status (PartialShellStatus)
 *    *    1   reserved (must be 0)
 *
 * The `reserved` byte makes the prefix-after-counterparties length a
 * round 24+20N bytes from offset 0 to the end of `status`, and gives
 * a forward-compat slot for a flags byte without a wire version bump.
 */
export interface PartialShell {
  /** Caller-chosen 16-byte opaque workflow identifier. */
  readonly workflowId: Uint8Array;
  /** Hash160 of each expected counterparty's compressed pubkey. 1..16 entries. */
  readonly counterpartyHash160s: ReadonlyArray<Uint8Array>;
  /** Recorded contributions. `partyIndex` < counterpartyHash160s.length. */
  readonly contributions: ReadonlyArray<{
    readonly partyIndex: number;
    /** Cell-hash of the bsv.tx.partial.contribution cell. */
    readonly contributionCellHash: Uint8Array;
  }>;
  readonly status: PartialShellStatus;
}

function predictShellSize(shell: PartialShell): number {
  return (
    1 + // version
    WORKFLOW_ID_BYTES + // workflow_id
    1 + // N
    HASH160_BYTES * shell.counterpartyHash160s.length +
    1 + // K
    33 * shell.contributions.length + // (party_index + contribution_hash)
    1 + // status
    1 // reserved
  );
}

export function encodePartialShell(shell: PartialShell): Uint8Array {
  const n = shell.counterpartyHash160s.length;
  if (n < 1 || n > MAX_COUNTERPARTIES) {
    throw new RangeError(
      `encodePartialShell: N must be 1..${MAX_COUNTERPARTIES} (got ${n})`,
    );
  }
  if (shell.workflowId.length !== WORKFLOW_ID_BYTES) {
    throw new RangeError(
      `encodePartialShell: workflowId must be ${WORKFLOW_ID_BYTES} bytes ` +
        `(got ${shell.workflowId.length})`,
    );
  }
  for (let i = 0; i < n; i++) {
    if (shell.counterpartyHash160s[i].length !== HASH160_BYTES) {
      throw new RangeError(
        `encodePartialShell: counterpartyHash160s[${i}] must be ${HASH160_BYTES} bytes`,
      );
    }
  }
  const k = shell.contributions.length;
  if (k > n) {
    throw new RangeError(
      `encodePartialShell: K=${k} cannot exceed N=${n}`,
    );
  }
  for (let i = 0; i < k; i++) {
    const c = shell.contributions[i];
    if (c.partyIndex < 0 || c.partyIndex >= n) {
      throw new RangeError(
        `encodePartialShell: contributions[${i}].partyIndex=${c.partyIndex} ` +
          `out of range [0, ${n})`,
      );
    }
    if (c.contributionCellHash.length !== CELL_HASH_BYTES) {
      throw new RangeError(
        `encodePartialShell: contributions[${i}].contributionCellHash ` +
          `must be ${CELL_HASH_BYTES} bytes`,
      );
    }
  }
  const out = new Uint8Array(predictShellSize(shell));
  let w = 0;
  out[w++] = TX_PARTIAL_WIRE_VERSION;
  out.set(shell.workflowId, w);
  w += WORKFLOW_ID_BYTES;
  out[w++] = n;
  for (const h of shell.counterpartyHash160s) {
    out.set(h, w);
    w += HASH160_BYTES;
  }
  out[w++] = k;
  for (const c of shell.contributions) {
    out[w++] = c.partyIndex;
    out.set(c.contributionCellHash, w);
    w += CELL_HASH_BYTES;
  }
  out[w++] = shell.status;
  out[w++] = 0; // reserved
  return out;
}

export function decodePartialShell(payload: Uint8Array): PartialShell {
  // Minimum size: 1+16+1+20+1+0+1+1 = 41 bytes (N=1, K=0).
  if (payload.length < 41) {
    throw new RangeError(
      `decodePartialShell: payload too short (got ${payload.length})`,
    );
  }
  if (payload[0] !== TX_PARTIAL_WIRE_VERSION) {
    throw new RangeError(
      `decodePartialShell: unknown VERSION=${payload[0]}`,
    );
  }
  const workflowId = payload.slice(1, 1 + WORKFLOW_ID_BYTES);
  let r = 1 + WORKFLOW_ID_BYTES;
  const n = payload[r++];
  if (n < 1 || n > MAX_COUNTERPARTIES) {
    throw new RangeError(
      `decodePartialShell: N=${n} out of range [1, ${MAX_COUNTERPARTIES}]`,
    );
  }
  if (r + HASH160_BYTES * n + 1 > payload.length) {
    throw new RangeError(`decodePartialShell: truncated counterparties`);
  }
  const counterpartyHash160s: Uint8Array[] = [];
  for (let i = 0; i < n; i++) {
    counterpartyHash160s.push(payload.slice(r, r + HASH160_BYTES));
    r += HASH160_BYTES;
  }
  const k = payload[r++];
  if (k > n) {
    throw new RangeError(`decodePartialShell: K=${k} > N=${n}`);
  }
  if (r + 33 * k + 2 > payload.length) {
    throw new RangeError(`decodePartialShell: truncated contributions`);
  }
  const contributions: PartialShell["contributions"][number][] = [];
  for (let i = 0; i < k; i++) {
    const partyIndex = payload[r++];
    if (partyIndex >= n) {
      throw new RangeError(
        `decodePartialShell: contributions[${i}].partyIndex=${partyIndex} >= N=${n}`,
      );
    }
    contributions.push({
      partyIndex,
      contributionCellHash: payload.slice(r, r + CELL_HASH_BYTES),
    });
    r += CELL_HASH_BYTES;
  }
  const status = payload[r++] as PartialShellStatus;
  if (!isPartialShellStatus(status)) {
    throw new RangeError(`decodePartialShell: unknown status=${status}`);
  }
  const reserved = payload[r++];
  if (reserved !== 0) {
    throw new RangeError(
      `decodePartialShell: reserved byte must be 0 (got ${reserved})`,
    );
  }
  return { workflowId, counterpartyHash160s, contributions, status };
}

function isPartialShellStatus(v: number): v is PartialShellStatus {
  return (
    v === PartialShellStatus.Active ||
    v === PartialShellStatus.BroadcastPending ||
    v === PartialShellStatus.Finalised ||
    v === PartialShellStatus.Cancelled
  );
}

// ─────────────────────────── Contribution payload ─────────────────────

/**
 * Decoded contribution payload — one party's signed input/output pair,
 * referencing the parent shell.
 *
 * Layout:
 *
 *     0   1     VERSION = 1
 *     1  32     shell_cell_hash
 *    33   1     party_index
 *    34  33     contributor_pubkey (compressed-secp256k1)
 *    67   2     sig_len (LE u16; 1..MAX_INLINE_SIG_BYTES)
 *    69  sig_len  signature (DER + trailing sighash-flag byte)
 */
export const PARTIAL_CONTRIBUTION_PREFIX_BYTES = 69 as const;

export interface PartialContribution {
  /** Cell-hash of the parent bsv.tx.partial.shell cell. */
  readonly shellCellHash: Uint8Array;
  readonly partyIndex: number;
  /** Compressed-secp256k1 pubkey of the contributing party. */
  readonly contributorPubkey: Uint8Array;
  /** DER-encoded ECDSA signature with trailing sighash-flag byte. */
  readonly signature: Uint8Array;
}

export function encodePartialContribution(c: PartialContribution): Uint8Array {
  if (c.shellCellHash.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodePartialContribution: shellCellHash must be ${CELL_HASH_BYTES} bytes`,
    );
  }
  if (c.partyIndex < 0 || c.partyIndex > 255) {
    throw new RangeError(
      `encodePartialContribution: partyIndex out of byte range (${c.partyIndex})`,
    );
  }
  if (c.contributorPubkey.length !== COMPRESSED_PUBKEY_BYTES) {
    throw new RangeError(
      `encodePartialContribution: contributorPubkey must be ${COMPRESSED_PUBKEY_BYTES} bytes`,
    );
  }
  if (c.signature.length < 1 || c.signature.length > MAX_INLINE_SIG_BYTES) {
    throw new RangeError(
      `encodePartialContribution: signature length ${c.signature.length} ` +
        `out of range [1, ${MAX_INLINE_SIG_BYTES}]`,
    );
  }
  const out = new Uint8Array(
    PARTIAL_CONTRIBUTION_PREFIX_BYTES + c.signature.length,
  );
  out[0] = TX_PARTIAL_WIRE_VERSION;
  out.set(c.shellCellHash, 1);
  out[33] = c.partyIndex;
  out.set(c.contributorPubkey, 34);
  out[67] = c.signature.length & 0xff;
  out[68] = (c.signature.length >>> 8) & 0xff;
  out.set(c.signature, PARTIAL_CONTRIBUTION_PREFIX_BYTES);
  return out;
}

export function decodePartialContribution(
  payload: Uint8Array,
): PartialContribution {
  if (payload.length < PARTIAL_CONTRIBUTION_PREFIX_BYTES) {
    throw new RangeError(
      `decodePartialContribution: payload too short ` +
        `(got ${payload.length}, need ≥ ${PARTIAL_CONTRIBUTION_PREFIX_BYTES})`,
    );
  }
  if (payload[0] !== TX_PARTIAL_WIRE_VERSION) {
    throw new RangeError(
      `decodePartialContribution: unknown VERSION=${payload[0]}`,
    );
  }
  const sigLen = payload[67] | (payload[68] << 8);
  if (sigLen < 1 || sigLen > MAX_INLINE_SIG_BYTES) {
    throw new RangeError(
      `decodePartialContribution: sig_len=${sigLen} out of range`,
    );
  }
  if (payload.length < PARTIAL_CONTRIBUTION_PREFIX_BYTES + sigLen) {
    throw new RangeError(`decodePartialContribution: payload truncated`);
  }
  return {
    shellCellHash: payload.slice(1, 33),
    partyIndex: payload[33],
    contributorPubkey: payload.slice(34, 67),
    signature: payload.slice(
      PARTIAL_CONTRIBUTION_PREFIX_BYTES,
      PARTIAL_CONTRIBUTION_PREFIX_BYTES + sigLen,
    ),
  };
}

// ─────────────────────────── Assemble payload ─────────────────────────

/**
 * Decoded assemble payload — the trigger to broadcast a fully-signed
 * shell.
 *
 * Layout:
 *
 *     0   1   VERSION = 1
 *     1  32   shell_cell_hash
 *    33   4   n_lock_time (LE u32) — substrate's chosen nLockTime
 */
export const PARTIAL_ASSEMBLE_BYTES = 37 as const;

export interface PartialAssemble {
  readonly shellCellHash: Uint8Array;
  readonly nLockTime: number;
}

export function encodePartialAssemble(a: PartialAssemble): Uint8Array {
  if (a.shellCellHash.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodePartialAssemble: shellCellHash must be ${CELL_HASH_BYTES} bytes`,
    );
  }
  if (a.nLockTime < 0 || a.nLockTime > 0xffffffff) {
    throw new RangeError(
      `encodePartialAssemble: nLockTime out of u32 range`,
    );
  }
  const out = new Uint8Array(PARTIAL_ASSEMBLE_BYTES);
  out[0] = TX_PARTIAL_WIRE_VERSION;
  out.set(a.shellCellHash, 1);
  out[33] = a.nLockTime & 0xff;
  out[34] = (a.nLockTime >>> 8) & 0xff;
  out[35] = (a.nLockTime >>> 16) & 0xff;
  out[36] = (a.nLockTime >>> 24) & 0xff;
  return out;
}

export function decodePartialAssemble(payload: Uint8Array): PartialAssemble {
  if (payload.length < PARTIAL_ASSEMBLE_BYTES) {
    throw new RangeError(
      `decodePartialAssemble: payload must be ≥ ${PARTIAL_ASSEMBLE_BYTES} ` +
        `bytes (got ${payload.length})`,
    );
  }
  if (payload[0] !== TX_PARTIAL_WIRE_VERSION) {
    throw new RangeError(
      `decodePartialAssemble: unknown VERSION=${payload[0]}`,
    );
  }
  const nLockTime =
    payload[33] |
    (payload[34] << 8) |
    (payload[35] << 16) |
    (payload[36] << 24);
  return {
    shellCellHash: payload.slice(1, 33),
    // Coerce to unsigned (>>> 0); shift-by-24 of a high bit lands negative
    // in JS number space without this.
    nLockTime: nLockTime >>> 0,
  };
}

// ─────────────────────────── Cancel payload ───────────────────────────

/**
 * Decoded cancel payload — aborts the workflow.
 *
 * Layout:
 *
 *     0   1   VERSION = 1
 *     1  32   shell_cell_hash
 *    33   1   reason (PartialCancelReason)
 */
export const PARTIAL_CANCEL_BYTES = 34 as const;

export interface PartialCancel {
  readonly shellCellHash: Uint8Array;
  readonly reason: PartialCancelReason;
}

export function encodePartialCancel(c: PartialCancel): Uint8Array {
  if (c.shellCellHash.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodePartialCancel: shellCellHash must be ${CELL_HASH_BYTES} bytes`,
    );
  }
  const out = new Uint8Array(PARTIAL_CANCEL_BYTES);
  out[0] = TX_PARTIAL_WIRE_VERSION;
  out.set(c.shellCellHash, 1);
  out[33] = c.reason;
  return out;
}

export function decodePartialCancel(payload: Uint8Array): PartialCancel {
  if (payload.length < PARTIAL_CANCEL_BYTES) {
    throw new RangeError(
      `decodePartialCancel: payload must be ≥ ${PARTIAL_CANCEL_BYTES} bytes`,
    );
  }
  if (payload[0] !== TX_PARTIAL_WIRE_VERSION) {
    throw new RangeError(
      `decodePartialCancel: unknown VERSION=${payload[0]}`,
    );
  }
  const reason = payload[33] as PartialCancelReason;
  if (!isPartialCancelReason(reason)) {
    throw new RangeError(`decodePartialCancel: unknown reason=${reason}`);
  }
  return { shellCellHash: payload.slice(1, 33), reason };
}

function isPartialCancelReason(v: number): v is PartialCancelReason {
  return (
    v === PartialCancelReason.Unspecified ||
    v === PartialCancelReason.InitiatorAbort ||
    v === PartialCancelReason.TimedOut ||
    v === PartialCancelReason.CounterpartyRejected ||
    v === PartialCancelReason.InputConflict
  );
}

```
