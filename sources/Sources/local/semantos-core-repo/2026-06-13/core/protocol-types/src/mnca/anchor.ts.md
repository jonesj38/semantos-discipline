---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/anchor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.900917+00:00
---

# core/protocol-types/src/mnca/anchor.ts

```ts
/**
 * Wire formats for the `mnca.anchor.*` cell-type group — the second
 * worked example of the cleavage apparatus, per LOCKSCRIPT-CLEAVAGE.md
 * §7.2.
 *
 * MNCA grids evolve through deterministic ticks. Periodically the
 * operator anchors a snapshot on-chain: the spending tx consumes the
 * predecessor anchor UTXO + mints a new one committing to the new
 * payload hash. Combined with SPV proves the transition was applied
 * (PR-7); the cell-engine proves the determinism (this PR's handler
 * follow-on, PR-8b); the on-chain anchor proves the chain.
 *
 * Four cell types live in this group:
 *
 *   - `mnca.anchor.create.intent`      EPHEMERAL  initial anchor request
 *   - `mnca.anchor`                    LINEAR     the durable anchor state
 *   - `mnca.anchor.transition.intent`  EPHEMERAL  consume + mint successor
 *   - `mnca.anchor.transition.result`  EPHEMERAL  outcome + txid + status
 *
 * The state machine (anchor creation + N transitions):
 *
 *   T=0  operator mints `anchor.create.intent` carrying initial snapshot
 *        → handler validates + emits initial `anchor` LINEAR cell
 *   T=1  operator computes new snapshot off-chain (MNCA rule application)
 *        + mints `anchor.transition.intent{prev_anchor, next_snapshot,
 *          computation_proof}`
 *        → handler validates next_generation = prev.generation + 1
 *        → handler invokes (future) host_mnca_verify_transition to
 *          confirm determinism
 *        → handler constructs spending tx consuming prev_anchor UTXO +
 *          minting new anchor UTXO committing to next_snapshot hash
 *        → handler emits bsv.tx.sign.request (cross-cartridge edge into
 *          the bsv-anchor-bundle pipeline)
 *        → handler emits successor `anchor` LINEAR cell (status=Pending)
 *        → broker collects sig, builds + broadcasts tx, emits
 *          bsv.tx.broadcast.result, handler observes + emits
 *          `anchor.transition.result` with txid + final outcome
 *   T=N  repeat
 *
 * EPHEMERAL on intent + result gives replay resistance (§6.1 of the
 * cleavage design — once consumed, idempotency trap). LINEAR on the
 * anchor cell gives the one-shot destructor (transitioning consumes
 * the old anchor and mints a new one with `prev_anchor_hash` linked).
 */

// ─────────────────────────── Versions / caps ──────────────────────────

/** Wire-format version stamped at offset 0 of every payload in the group. */
export const MNCA_ANCHOR_WIRE_VERSION = 1 as const;

/** Compressed-secp256k1 public key size in bytes. */
export const COMPRESSED_PUBKEY_BYTES = 33 as const;

/** Cell-hash size in bytes (matches the 1024-byte cell SHA256 hash). */
export const CELL_HASH_BYTES = 32 as const;

/** Txid size in bytes (BSV internal byte order, same as cell-hash). */
export const TXID_BYTES = 32 as const;

/** Workflow ID size in bytes (caller-chosen opaque identifier). */
export const WORKFLOW_ID_BYTES = 16 as const;

/**
 * Upper bound on inline computation-proof bytes in a transition intent.
 *
 *   1024-byte cell budget − 256-byte CellHeader − 73-byte transition.
 *   intent prefix = 695 bytes; round down to 680 for forward-compat
 *   headroom (matches the conservative cap pattern from spv-verify.ts).
 *
 * Above this cap the proof must use a carriage chain (future PR, same
 * mechanism as `bsv.beef.carriage.head/body`). For typical MNCA grids
 * the proof is a list of (tile_hash, generation, pre/post state hash)
 * triples and fits comfortably inline.
 */
export const INLINE_COMPUTATION_PROOF_MAX_BYTES = 680 as const;

// ─────────────────────────── Status enums ─────────────────────────────

/**
 * Anchor lifecycle status. Strict enum — decoder rejects unknown values
 * rather than silently corrupting state machine semantics.
 */
export const AnchorStatus = {
  /** Active — anchor UTXO is unspent + canonical at current tip. */
  Active: 0,
  /** Spent — successor anchor exists; this one's UTXO has been consumed. */
  Spent: 1,
  /**
   * Reorged — a chain reorg invalidated this anchor's UTXO; the operator
   * must re-mint from an earlier active anchor. Until that happens the
   * state machine is stuck.
   */
  Reorged: 2,
} as const;
export type AnchorStatus = (typeof AnchorStatus)[keyof typeof AnchorStatus];

/** Transition-result outcome discriminant. */
export const TransitionOutcome = {
  /** Sign request emitted; broker has not yet returned a broadcast result. */
  Pending: 0,
  /** Successor anchor live on-chain. */
  Accepted: 1,
  /** Handler rejected (determinism check failed, stale predecessor, etc.). */
  Rejected: 2,
} as const;
export type TransitionOutcome = (typeof TransitionOutcome)[keyof typeof TransitionOutcome];

/** Transition-failure discriminant — short tag on the wire. */
export const TransitionErrorTag = {
  /** No error. */
  None: 0,
  /** Predecessor anchor is not the current tip (concurrent transition lost). */
  StalePredecessor: 1,
  /** host_mnca_verify_transition rejected the computation proof. */
  InvalidTransition: 2,
  /** ARC rejected the spending tx. */
  BroadcastFailed: 3,
  /** Computation proof exceeded INLINE_COMPUTATION_PROOF_MAX_BYTES. */
  ProofTooLarge: 4,
  /** Next generation != predecessor.generation + 1. */
  GenerationGap: 5,
} as const;
export type TransitionErrorTag =
  (typeof TransitionErrorTag)[keyof typeof TransitionErrorTag];

// ─────────────────────────── Anchor create intent ─────────────────────

/**
 * Decoded `mnca.anchor.create.intent` payload — the operator's request
 * to bring a fresh MNCA computation on-chain.
 *
 * Layout (fixed):
 *
 *     0   1   VERSION = 1
 *     1  32   initial_snapshot_hash    (mnca.snapshot cell-hash)
 *    33  33   initiator_pubkey         (compressed-secp256k1)
 *    66  16   workflow_id              (opaque caller identifier)
 *
 * Total: 82 bytes.
 */
export const MNCA_ANCHOR_CREATE_INTENT_BYTES = 82 as const;

export interface MncaAnchorCreateIntent {
  /** Cell-hash of the initial mnca.snapshot the anchor commits to. */
  readonly initialSnapshotHash: Uint8Array;
  /** Operator's compressed-secp256k1 pubkey for the anchor's locking script. */
  readonly initiatorPubkey: Uint8Array;
  /** Caller-chosen 16-byte opaque workflow identifier. */
  readonly workflowId: Uint8Array;
}

export function encodeMncaAnchorCreateIntent(
  i: MncaAnchorCreateIntent,
): Uint8Array {
  if (i.initialSnapshotHash.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodeMncaAnchorCreateIntent: initialSnapshotHash must be ${CELL_HASH_BYTES} bytes`,
    );
  }
  if (i.initiatorPubkey.length !== COMPRESSED_PUBKEY_BYTES) {
    throw new RangeError(
      `encodeMncaAnchorCreateIntent: initiatorPubkey must be ${COMPRESSED_PUBKEY_BYTES} bytes`,
    );
  }
  if (i.workflowId.length !== WORKFLOW_ID_BYTES) {
    throw new RangeError(
      `encodeMncaAnchorCreateIntent: workflowId must be ${WORKFLOW_ID_BYTES} bytes`,
    );
  }
  const out = new Uint8Array(MNCA_ANCHOR_CREATE_INTENT_BYTES);
  out[0] = MNCA_ANCHOR_WIRE_VERSION;
  out.set(i.initialSnapshotHash, 1);
  out.set(i.initiatorPubkey, 33);
  out.set(i.workflowId, 66);
  return out;
}

export function decodeMncaAnchorCreateIntent(
  payload: Uint8Array,
): MncaAnchorCreateIntent {
  if (payload.length < MNCA_ANCHOR_CREATE_INTENT_BYTES) {
    throw new RangeError(
      `decodeMncaAnchorCreateIntent: payload must be ≥ ${MNCA_ANCHOR_CREATE_INTENT_BYTES} ` +
        `bytes (got ${payload.length})`,
    );
  }
  if (payload[0] !== MNCA_ANCHOR_WIRE_VERSION) {
    throw new RangeError(
      `decodeMncaAnchorCreateIntent: unknown VERSION=${payload[0]}`,
    );
  }
  return {
    initialSnapshotHash: payload.slice(1, 33),
    initiatorPubkey: payload.slice(33, 66),
    workflowId: payload.slice(66, 82),
  };
}

// ─────────────────────────── Anchor (LINEAR) ──────────────────────────

/**
 * Decoded `mnca.anchor` payload — the durable LINEAR anchor state.
 * Carries the on-chain commitment + the lineage back to genesis.
 *
 * Layout:
 *
 *     0   1   VERSION = 1
 *     1  32   current_snapshot_hash    (mnca.snapshot cell-hash)
 *    33  32   prev_anchor_hash         (zero = initial)
 *    65   4   generation (LE u32)      MNCA tick at this anchor
 *    69  33   owner_pubkey             (compressed-secp256k1)
 *   102   1   status                   (AnchorStatus)
 *   103  32   anchor_txid              (zero = no on-chain commit yet)   ← PR-8b-vi-1
 *   135   4   anchor_vout (LE u32)     (zero when no commit)             ← PR-8b-vi-1
 *
 * Total: 139 bytes.
 *
 * **Backward compatibility (PR-8b-vi-1):** the decoder accepts BOTH
 * the legacy 103-byte (`MNCA_ANCHOR_BYTES_V1`) and the extended
 * 139-byte (`MNCA_ANCHOR_BYTES`) payloads. Legacy cells decode with
 * `anchorTxid` = 32 zero bytes and `anchorVout` = 0 — the correct
 * "no on-chain commit yet" semantics. The encoder always writes the
 * extended 139-byte form so newly-minted cells carry the explicit
 * UTXO ref fields the future broker fills in after broadcast.
 *
 * The brain's PR-8b-iv MNCA Context builder + PR-8b-v pre-builder
 * already handle the extended payload correctly because their write
 * paths only target the first 103 bytes (offsets 0..102); the new
 * fields stay at zero by default which is exactly the "uncommitted"
 * value.
 */
export const MNCA_ANCHOR_BYTES = 139 as const;

/**
 * Legacy payload length for v1 cells (PR-8 → PR-8b-v). Decoder accepts
 * both this and `MNCA_ANCHOR_BYTES`; encoder always writes the latter.
 */
export const MNCA_ANCHOR_BYTES_V1 = 103 as const;

/** Txid size in bytes (BSV internal byte order). */
export const ANCHOR_TXID_BYTES = 32 as const;

export interface MncaAnchor {
  /** Cell-hash of the mnca.snapshot this anchor commits to. */
  readonly currentSnapshotHash: Uint8Array;
  /**
   * Cell-hash of the predecessor mnca.anchor. All zeros for the
   * initial anchor in the chain.
   */
  readonly prevAnchorHash: Uint8Array;
  /** MNCA tick counter at this anchor (u32). */
  readonly generation: number;
  /** Owner pubkey for the anchor's locking script. */
  readonly ownerPubkey: Uint8Array;
  readonly status: AnchorStatus;
  /**
   * PR-8b-vi-1 — on-chain anchor UTXO transaction id (BSV internal
   * byte order). All zeros when the anchor has not yet been broadcast.
   * The broker writes the real value back after ARC accepts the
   * spending tx.
   */
  readonly anchorTxid: Uint8Array;
  /**
   * PR-8b-vi-1 — output index within `anchorTxid` that carries the
   * PushDrop committing to `currentSnapshotHash`. Zero when no
   * on-chain commit yet.
   */
  readonly anchorVout: number;
}

export function encodeMncaAnchor(a: MncaAnchor): Uint8Array {
  if (a.currentSnapshotHash.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodeMncaAnchor: currentSnapshotHash must be ${CELL_HASH_BYTES} bytes`,
    );
  }
  if (a.prevAnchorHash.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodeMncaAnchor: prevAnchorHash must be ${CELL_HASH_BYTES} bytes ` +
        `(use 32 zero bytes for the initial anchor)`,
    );
  }
  if (a.ownerPubkey.length !== COMPRESSED_PUBKEY_BYTES) {
    throw new RangeError(
      `encodeMncaAnchor: ownerPubkey must be ${COMPRESSED_PUBKEY_BYTES} bytes`,
    );
  }
  if (a.generation < 0 || a.generation > 0xffffffff) {
    throw new RangeError(`encodeMncaAnchor: generation out of u32 range`);
  }
  if (a.anchorTxid.length !== ANCHOR_TXID_BYTES) {
    throw new RangeError(
      `encodeMncaAnchor: anchorTxid must be ${ANCHOR_TXID_BYTES} bytes ` +
        `(use 32 zero bytes when not yet broadcast)`,
    );
  }
  if (a.anchorVout < 0 || a.anchorVout > 0xffffffff) {
    throw new RangeError(`encodeMncaAnchor: anchorVout out of u32 range`);
  }
  const out = new Uint8Array(MNCA_ANCHOR_BYTES);
  out[0] = MNCA_ANCHOR_WIRE_VERSION;
  out.set(a.currentSnapshotHash, 1);
  out.set(a.prevAnchorHash, 33);
  out[65] = a.generation & 0xff;
  out[66] = (a.generation >>> 8) & 0xff;
  out[67] = (a.generation >>> 16) & 0xff;
  out[68] = (a.generation >>> 24) & 0xff;
  out.set(a.ownerPubkey, 69);
  out[102] = a.status;
  out.set(a.anchorTxid, 103);
  out[135] = a.anchorVout & 0xff;
  out[136] = (a.anchorVout >>> 8) & 0xff;
  out[137] = (a.anchorVout >>> 16) & 0xff;
  out[138] = (a.anchorVout >>> 24) & 0xff;
  return out;
}

export function decodeMncaAnchor(payload: Uint8Array): MncaAnchor {
  // Accept both legacy 103-byte v1 cells (no anchor_utxo_ref) and the
  // extended 139-byte form. v1 decodes with anchor_txid = zeros +
  // anchor_vout = 0, which is the correct "no on-chain commit yet"
  // semantics.
  if (payload.length < MNCA_ANCHOR_BYTES_V1) {
    throw new RangeError(
      `decodeMncaAnchor: payload must be ≥ ${MNCA_ANCHOR_BYTES_V1} bytes ` +
        `(got ${payload.length})`,
    );
  }
  if (payload[0] !== MNCA_ANCHOR_WIRE_VERSION) {
    throw new RangeError(`decodeMncaAnchor: unknown VERSION=${payload[0]}`);
  }
  const status = payload[102] as AnchorStatus;
  if (!isAnchorStatus(status)) {
    throw new RangeError(`decodeMncaAnchor: unknown status=${status}`);
  }
  const generation =
    (payload[65] |
      (payload[66] << 8) |
      (payload[67] << 16) |
      (payload[68] << 24)) >>>
    0;
  let anchorTxid: Uint8Array;
  let anchorVout = 0;
  if (payload.length >= MNCA_ANCHOR_BYTES) {
    anchorTxid = payload.slice(103, 135);
    anchorVout =
      (payload[135] |
        (payload[136] << 8) |
        (payload[137] << 16) |
        (payload[138] << 24)) >>>
      0;
  } else {
    anchorTxid = new Uint8Array(ANCHOR_TXID_BYTES);
  }
  return {
    currentSnapshotHash: payload.slice(1, 33),
    prevAnchorHash: payload.slice(33, 65),
    generation,
    ownerPubkey: payload.slice(69, 102),
    status,
    anchorTxid,
    anchorVout,
  };
}

function isAnchorStatus(v: number): v is AnchorStatus {
  return (
    v === AnchorStatus.Active ||
    v === AnchorStatus.Spent ||
    v === AnchorStatus.Reorged
  );
}

// ─────────────────────────── Transition intent ────────────────────────

/**
 * Decoded `mnca.anchor.transition.intent` payload — operator's request
 * to advance the anchor chain by one tick.
 *
 * Layout (variable-length):
 *
 *     0   1   VERSION = 1
 *     1  32   predecessor_anchor_hash  (mnca.anchor cell-hash being consumed)
 *    33  32   next_snapshot_hash       (mnca.snapshot cell-hash to commit)
 *    65   4   next_generation (LE u32) (must = predecessor.generation + 1)
 *    69   4   proof_len (LE u32; 0..INLINE_COMPUTATION_PROOF_MAX_BYTES)
 *    73   N   computation_proof        (bytes the future host_mnca_verify_
 *                                       transition hostcall validates)
 */
export const MNCA_TRANSITION_INTENT_PREFIX_BYTES = 73 as const;

export interface MncaAnchorTransitionIntent {
  /** Cell-hash of the predecessor anchor being consumed. */
  readonly predecessorAnchorHash: Uint8Array;
  /** Cell-hash of the new mnca.snapshot to commit. */
  readonly nextSnapshotHash: Uint8Array;
  /** MNCA tick after this transition (must = predecessor.generation + 1). */
  readonly nextGeneration: number;
  /**
   * Computation proof bytes. Format opaque at this layer — the future
   * `host_mnca_verify_transition` hostcall (PR-8b) interprets it.
   * Typically a serialized list of (tile_hash, generation, pre_state_hash,
   * post_state_hash) triples that let the verifier re-derive the
   * next_snapshot_hash deterministically.
   */
  readonly computationProof: Uint8Array;
}

export function encodeMncaAnchorTransitionIntent(
  t: MncaAnchorTransitionIntent,
): Uint8Array {
  if (t.predecessorAnchorHash.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodeMncaAnchorTransitionIntent: predecessorAnchorHash must be ${CELL_HASH_BYTES} bytes`,
    );
  }
  if (t.nextSnapshotHash.length !== CELL_HASH_BYTES) {
    throw new RangeError(
      `encodeMncaAnchorTransitionIntent: nextSnapshotHash must be ${CELL_HASH_BYTES} bytes`,
    );
  }
  if (t.nextGeneration < 0 || t.nextGeneration > 0xffffffff) {
    throw new RangeError(
      `encodeMncaAnchorTransitionIntent: nextGeneration out of u32 range`,
    );
  }
  if (t.computationProof.length > INLINE_COMPUTATION_PROOF_MAX_BYTES) {
    throw new RangeError(
      `encodeMncaAnchorTransitionIntent: computationProof length ` +
        `${t.computationProof.length} exceeds inline cap ` +
        `${INLINE_COMPUTATION_PROOF_MAX_BYTES}; use a carriage chain for larger proofs`,
    );
  }
  const out = new Uint8Array(
    MNCA_TRANSITION_INTENT_PREFIX_BYTES + t.computationProof.length,
  );
  out[0] = MNCA_ANCHOR_WIRE_VERSION;
  out.set(t.predecessorAnchorHash, 1);
  out.set(t.nextSnapshotHash, 33);
  out[65] = t.nextGeneration & 0xff;
  out[66] = (t.nextGeneration >>> 8) & 0xff;
  out[67] = (t.nextGeneration >>> 16) & 0xff;
  out[68] = (t.nextGeneration >>> 24) & 0xff;
  out[69] = t.computationProof.length & 0xff;
  out[70] = (t.computationProof.length >>> 8) & 0xff;
  out[71] = (t.computationProof.length >>> 16) & 0xff;
  out[72] = (t.computationProof.length >>> 24) & 0xff;
  out.set(t.computationProof, MNCA_TRANSITION_INTENT_PREFIX_BYTES);
  return out;
}

export function decodeMncaAnchorTransitionIntent(
  payload: Uint8Array,
): MncaAnchorTransitionIntent {
  if (payload.length < MNCA_TRANSITION_INTENT_PREFIX_BYTES) {
    throw new RangeError(
      `decodeMncaAnchorTransitionIntent: payload too short (got ${payload.length})`,
    );
  }
  if (payload[0] !== MNCA_ANCHOR_WIRE_VERSION) {
    throw new RangeError(
      `decodeMncaAnchorTransitionIntent: unknown VERSION=${payload[0]}`,
    );
  }
  const proofLen =
    (payload[69] |
      (payload[70] << 8) |
      (payload[71] << 16) |
      (payload[72] << 24)) >>>
    0;
  if (proofLen > INLINE_COMPUTATION_PROOF_MAX_BYTES) {
    throw new RangeError(
      `decodeMncaAnchorTransitionIntent: proof_len=${proofLen} exceeds inline cap`,
    );
  }
  if (payload.length < MNCA_TRANSITION_INTENT_PREFIX_BYTES + proofLen) {
    throw new RangeError(
      `decodeMncaAnchorTransitionIntent: payload truncated; declared proof_len=${proofLen}`,
    );
  }
  const nextGeneration =
    (payload[65] |
      (payload[66] << 8) |
      (payload[67] << 16) |
      (payload[68] << 24)) >>>
    0;
  return {
    predecessorAnchorHash: payload.slice(1, 33),
    nextSnapshotHash: payload.slice(33, 65),
    nextGeneration,
    computationProof: payload.slice(
      MNCA_TRANSITION_INTENT_PREFIX_BYTES,
      MNCA_TRANSITION_INTENT_PREFIX_BYTES + proofLen,
    ),
  };
}

// ─────────────────────────── Transition result ────────────────────────

/**
 * Decoded `mnca.anchor.transition.result` payload.
 *
 * Layout (fixed):
 *
 *     0   1   VERSION = 1
 *     1   1   OUTCOME      (TransitionOutcome)
 *     2  32   txid         (BSV tx id, all zeros when outcome=Pending)
 *    34   1   error_tag    (TransitionErrorTag)
 *    35   4   confirmed_generation (LE u32; the generation now anchored)
 *
 * Total: 39 bytes.
 */
export const MNCA_TRANSITION_RESULT_BYTES = 39 as const;

export interface MncaAnchorTransitionResult {
  readonly outcome: TransitionOutcome;
  /** BSV tx id from the broadcast — zero-padded when outcome=Pending. */
  readonly txid: Uint8Array;
  readonly errorTag: TransitionErrorTag;
  /** The generation now anchored on-chain (the next generation on success). */
  readonly confirmedGeneration: number;
}

export function encodeMncaAnchorTransitionResult(
  r: MncaAnchorTransitionResult,
): Uint8Array {
  if (r.txid.length !== TXID_BYTES) {
    throw new RangeError(
      `encodeMncaAnchorTransitionResult: txid must be ${TXID_BYTES} bytes`,
    );
  }
  if (r.confirmedGeneration < 0 || r.confirmedGeneration > 0xffffffff) {
    throw new RangeError(
      `encodeMncaAnchorTransitionResult: confirmedGeneration out of u32 range`,
    );
  }
  const out = new Uint8Array(MNCA_TRANSITION_RESULT_BYTES);
  out[0] = MNCA_ANCHOR_WIRE_VERSION;
  out[1] = r.outcome;
  out.set(r.txid, 2);
  out[34] = r.errorTag;
  out[35] = r.confirmedGeneration & 0xff;
  out[36] = (r.confirmedGeneration >>> 8) & 0xff;
  out[37] = (r.confirmedGeneration >>> 16) & 0xff;
  out[38] = (r.confirmedGeneration >>> 24) & 0xff;
  return out;
}

export function decodeMncaAnchorTransitionResult(
  payload: Uint8Array,
): MncaAnchorTransitionResult {
  if (payload.length < MNCA_TRANSITION_RESULT_BYTES) {
    throw new RangeError(
      `decodeMncaAnchorTransitionResult: payload must be ≥ ${MNCA_TRANSITION_RESULT_BYTES} ` +
        `bytes (got ${payload.length})`,
    );
  }
  if (payload[0] !== MNCA_ANCHOR_WIRE_VERSION) {
    throw new RangeError(
      `decodeMncaAnchorTransitionResult: unknown VERSION=${payload[0]}`,
    );
  }
  const outcome = payload[1] as TransitionOutcome;
  if (!isTransitionOutcome(outcome)) {
    throw new RangeError(
      `decodeMncaAnchorTransitionResult: unknown outcome=${outcome}`,
    );
  }
  const errorTag = payload[34] as TransitionErrorTag;
  if (!isTransitionErrorTag(errorTag)) {
    throw new RangeError(
      `decodeMncaAnchorTransitionResult: unknown error_tag=${errorTag}`,
    );
  }
  const confirmedGeneration =
    (payload[35] |
      (payload[36] << 8) |
      (payload[37] << 16) |
      (payload[38] << 24)) >>>
    0;
  return {
    outcome,
    txid: payload.slice(2, 34),
    errorTag,
    confirmedGeneration,
  };
}

function isTransitionOutcome(v: number): v is TransitionOutcome {
  return (
    v === TransitionOutcome.Pending ||
    v === TransitionOutcome.Accepted ||
    v === TransitionOutcome.Rejected
  );
}

function isTransitionErrorTag(v: number): v is TransitionErrorTag {
  return (
    v === TransitionErrorTag.None ||
    v === TransitionErrorTag.StalePredecessor ||
    v === TransitionErrorTag.InvalidTransition ||
    v === TransitionErrorTag.BroadcastFailed ||
    v === TransitionErrorTag.ProofTooLarge ||
    v === TransitionErrorTag.GenerationGap
  );
}

```
