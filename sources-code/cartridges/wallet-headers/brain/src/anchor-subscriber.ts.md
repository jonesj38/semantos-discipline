---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/anchor-subscriber.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.645688+00:00
---

# cartridges/wallet-headers/brain/src/anchor-subscriber.ts

```ts
// Anchor subscriber — consumes brain `cell.created` events and mints
// the on-chain anchor commitment.
//
// Reference: docs/prd/ANCHOR-BACKEND-BRIDGE.md §4 (Option A — in-brain
//            bun-child runner per Todd 2026-05-25); brain emitBsv +
//            event shape from runtime/semantos-brain/src/anchor_emitter.zig
//            (the upstream publisher this module mirrors).
//
// This module is a pure library — it does NOT subscribe to the brain
// broker directly.  PR-3a-bridge-2c lands the bun-child runner that
// pipes broker events here; this PR provides the structurally complete
// + unit-tested handler the runner will call.  Splitting brain wiring
// + cartridge subscriber + runner across three PRs keeps each
// reviewable and lets PR-3a-bridge-2b proceed in parallel.
//
// Architectural shape (matching Zig AnchorEmitter):
//
//   brain.AnchorEmitter.emitBsv(...)
//     → broker.publish("cell.created", { cell_hash, type_hash, ... })
//       → [runner pipes the event to this subscriber]
//         → handleCellCreated(event, identity, createAction)
//           → derive anchor SK via BRC-42
//           → build cell-anchor lock script
//           → createAction (wallet builds + signs + broadcasts tx)
//           → return { status: 'broadcast', txid }
//
// Recursion break: events carrying ANCHOR_ATTESTATION_ENTITY_TAG are
// rejected with status=skipped — same belt + suspenders as the
// brain-side check at anchor_emitter.zig:159.

import { deriveCellAnchorSk, buildCellAnchorPushDropLock } from './cell-anchor';

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

/**
 * Entity tag identifying AnchorAttestation cells.  Anchoring an anchor
 * cell would loop forever — short-circuit to `skipped`.  Keep in sync
 * with `ANCHOR_ATTESTATION_ENTITY_TAG` in
 * runtime/semantos-brain/src/anchor_emitter.zig (line 57: value 0x20).
 */
export const ANCHOR_ATTESTATION_ENTITY_TAG = 0x20;

// ─────────────────────────────────────────────────────────────────────
// Wire types — shape the brain publishes via emitBsv
// ─────────────────────────────────────────────────────────────────────

/**
 * Decoded form of the brain's `cell.created` broker event.  Hex
 * strings on the wire (per anchor_emitter.zig emitBsv payload format);
 * this interface assumes the runner has already JSON-parsed the
 * payload but NOT yet hex-decoded the hashes.  handleCellCreated does
 * the decode + validation in one step so callers don't need to
 * pre-validate.
 */
export interface CellCreatedEvent {
  /** 64-hex-char SHA-256 of the 1024-byte cell. */
  cell_hash: string;
  /** 64-hex-char canonical typeHash (cell header offset 30). */
  type_hash: string;
  /** u32 entity_tag from the cell header.  Used by the recursion-break filter. */
  entity_tag: number;
  /** Hint for routing / audit-log tagging.  May be empty. */
  cartridge_id: string;
  /** Trace id for audit-log threading.  May be empty. */
  correlation_id: string;
}

// ─────────────────────────────────────────────────────────────────────
// Result types
// ─────────────────────────────────────────────────────────────────────

/**
 * Stable status tokens — mirror the Zig `AnchorStatus` enum (pending /
 * confirmed / failed / skipped) but renamed to match what this
 * subscriber actually does: synchronously call createAction and return
 * its outcome.  `broadcast` ≈ Zig's `pending` (tx is in flight; mining
 * confirmation is a separate later event).
 */
export type AnchorStatus = 'broadcast' | 'skipped' | 'failed';

/**
 * Stable error tokens — every reject path returns one of these.
 * Borrowed from a fixed set; mobile + audit-log consumers pattern-match
 * on the literal string.  No throwing — failures are encoded in the
 * outcome, same as the Zig AnchorResult contract.
 */
export type AnchorErrorKind =
  | 'invalid_event'
  | 'derivation_failed'
  | 'lock_build_failed'
  | 'broadcast_failed';

export interface AnchorOutcome {
  status: AnchorStatus;
  /** Tx id (64-hex lowercase) populated only when status === 'broadcast'. */
  txid?: string;
  error_kind?: AnchorErrorKind;
  /** Human-readable detail for diagnostics; not load-bearing for routing. */
  detail?: string;
}

// ─────────────────────────────────────────────────────────────────────
// Injected adapters — production wires the wallet; tests mock
// ─────────────────────────────────────────────────────────────────────

/**
 * Where the identitySk comes from + how to allocate an anchor index.
 *
 * Production: the wallet runtime supplies identitySk from its
 * KEK-decrypted slot; anchorIndex is a monotonic counter per typeHash
 * that the wallet persists so spending the anchor UTXO later can
 * recover the spending key (per cell-anchor.ts:79 doc comment).
 *
 * Tests: a stub IdentityProvider with a fixed identitySk + index
 * counter is fine.
 */
export interface IdentityProvider {
  /** 32-byte secp256k1 scalar. */
  getIdentitySk(): Uint8Array;
  /**
   * Next anchor index for the given typeHash.  Wallet persists per-
   * typeHash counters so the spend recovery path can iterate the
   * historical anchor indices.  Tests can return 0 every call.
   */
  nextAnchorIndex(typeHashHex: string): number;
}

/**
 * createAction adapter — given a lock script + satoshi amount, the
 * wallet selects UTXOs, signs, broadcasts, and returns a txid (or a
 * structured failure).  Production: bind to the wallet's BRC-100
 * createAction (dispatcher.ts).  Tests: mock with a deterministic txid
 * or a failure stub.
 *
 * The adapter encapsulates the entire BSV-tx-building pipeline so this
 * subscriber stays focused on the cartridge-side logic.
 */
export type CreateActionAdapter = (params: {
  description: string;
  outputs: Array<{ satoshis: number; lockingScript: Uint8Array }>;
}) => Promise<
  | { ok: true; txid: string }
  | { ok: false; reason: string }
>;

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

/**
 * Decode 64-hex into 32-byte Uint8Array.  Returns null on any malformed
 * input — keeps the callers branchless on the validity check.
 */
function hexToBytes32(hex: string): Uint8Array | null {
  if (hex.length !== 64) return null;
  const out = new Uint8Array(32);
  for (let i = 0; i < 32; i++) {
    const hi = parseHexNibble(hex.charCodeAt(i * 2));
    const lo = parseHexNibble(hex.charCodeAt(i * 2 + 1));
    if (hi < 0 || lo < 0) return null;
    out[i] = (hi << 4) | lo;
  }
  return out;
}

function parseHexNibble(code: number): number {
  if (code >= 0x30 && code <= 0x39) return code - 0x30; // '0'..'9'
  if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10; // 'a'..'f'
  if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10; // 'A'..'F'
  return -1;
}

// ─────────────────────────────────────────────────────────────────────
// Handler
// ─────────────────────────────────────────────────────────────────────

/**
 * Process a single `cell.created` event.  Pure async function — no
 * shared state, no side effects beyond the injected adapters' effects.
 * Callers (the bun-child runner) invoke this once per event; the
 * handler builds the anchor lock + asks the wallet to broadcast.
 *
 * Failure handling: returns an `AnchorOutcome` with `status='failed'`
 * + an `error_kind` from the stable set.  Never throws under normal
 * operation (input validation, derivation, lock construction,
 * broadcast all encode failures structurally).  The runner is free
 * to log + continue without a try/catch hot path.
 */
export async function handleCellCreated(
  event: CellCreatedEvent,
  identity: IdentityProvider,
  createAction: CreateActionAdapter,
): Promise<AnchorOutcome> {
  // 1. Recursion break — defense in depth.  Brain-side emitBsv also
  //    filters; both layers do because a schema-drift bug at either
  //    layer would otherwise infinite-loop the anchor pipeline.
  if (event.entity_tag === ANCHOR_ATTESTATION_ENTITY_TAG) {
    return { status: 'skipped' };
  }

  // 2. Decode + validate the hex hashes.  Bad hex shouldn't be
  //    possible if the brain published correctly, but a corrupted
  //    pipe between broker and runner is a real failure mode.
  const typeHash = hexToBytes32(event.type_hash);
  const cellHash = hexToBytes32(event.cell_hash);
  if (!typeHash || !cellHash) {
    return {
      status: 'failed',
      error_kind: 'invalid_event',
      detail: 'cell_hash or type_hash not a valid 64-char hex string',
    };
  }

  // 3. Derive the cell-anchor spending key.  deriveCellAnchorSk
  //    returns null on the (astronomically unlikely) curve-arithmetic
  //    degenerate cases.  We surface that as a structured failure
  //    rather than retrying — the wallet's anchor-index counter is
  //    monotonic so retrying with the same (identitySk, typeHash,
  //    anchorIndex) would produce the same null.
  const identitySk = identity.getIdentitySk();
  const anchorIndex = identity.nextAnchorIndex(event.type_hash);
  const childSk = deriveCellAnchorSk(identitySk, typeHash, anchorIndex);
  if (!childSk) {
    return {
      status: 'failed',
      error_kind: 'derivation_failed',
      detail: `deriveCellAnchorSk returned null for anchorIndex=${anchorIndex}`,
    };
  }

  // 4. Build the PushDrop anchor lock script (Todd 2026-05-26).  Both
  //    cell_hash AND type_hash get pushed before OP_2DROP, then
  //    PUSHDATA(33) <derived pubkey> OP_CHECKSIG closes the spend
  //    condition.  This publishes the (cell_hash, type_hash)
  //    commitment ON-CHAIN — anyone can verify "this anchor commits
  //    to exactly this cell" without consulting the brain's audit log.
  //    Counterpart to deriveCellAnchorSk — the wallet later spends
  //    the anchor UTXO by calling deriveCellAnchorSk(identitySk,
  //    typeHash, anchorIndex) and signing.
  const lockingScript = buildCellAnchorPushDropLock(
    identitySk,
    typeHash,
    cellHash,
    anchorIndex,
  );
  if (!lockingScript) {
    return {
      status: 'failed',
      error_kind: 'lock_build_failed',
      detail: 'buildCellAnchorPushDropLock returned null',
    };
  }

  // 5. Hand off to the wallet's createAction — UTXO select, sign,
  //    broadcast in one call.  The wallet emits its own audit-log
  //    entry for the broadcast; we just relay the outcome.
  const description = formatActionDescription(event);
  const result = await createAction({
    description,
    outputs: [{ satoshis: 1, lockingScript }],
  });

  if (!result.ok) {
    return {
      status: 'failed',
      error_kind: 'broadcast_failed',
      detail: result.reason,
    };
  }

  return {
    status: 'broadcast',
    txid: result.txid,
  };
}

/**
 * Plain-English description string the wallet attaches to the created
 * action.  Some wallet UIs (Metanet Desktop verified 2026-05-26)
 * render descriptions through a chip / label component that crashes
 * if the string contains `:` and is parsed as a structured token —
 * e.g., `"anchor:16:foo"` triggered `AppChip: label prop must be a
 * string!` in Metanet Desktop's permission dialog.  Sticking to plain
 * English with no separators is the safe shape.
 *
 * Observability data (entity_tag, cartridge_id, cell_hash) travels
 * through the broker event payload + audit log, not through this
 * wallet-facing description.
 */
function formatActionDescription(event: CellCreatedEvent): string {
  const cart = event.cartridge_id || 'unknown';
  return `Semantos cell anchor (${cart})`;
}

```
