---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/bsv/cell-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.870358+00:00
---

# core/protocol-types/src/bsv/cell-types.ts

```ts
/**
 * BSV substrate cell-type names + transform graph.
 *
 * Identity (typeHash, triple, linearity) lives in
 * `cartridges/bsv-anchor-bundle/cartridge.json` `cellTypes[]` — read at
 * brain-load time via the cartridge manifest loader. This module
 * retains:
 *
 *   - The canonical name constants (`BsvCellTypeName`) — used by
 *     wire-format encoders + the brain-side cell dispatcher as
 *     readable handles.
 *   - The transform graph (`BsvTransformEdges`, `isBsvTransform`) —
 *     orthogonal to typeHash; describes which cell type can be emitted
 *     in response to which incoming cell type, enabling the cell-
 *     engine to advertise routing paths.
 *
 * Same pattern as `core/protocol-types/src/mnca/cell-types.ts`. The
 * actual typeHash bytes for each name come from
 * `buildTypeHash(s1, s2, s3, s4)` applied to the cartridge.json
 * triples at load time.
 *
 * Spec:  docs/design/LINEAR-CELL-SPV-STATE.md §2 (cell types catalog),
 *        §10 (migration from REST verbs to cells).
 *
 * Status: substrate catalog. PR-C11-7e declares the names + edges +
 * the SPV-verify wire format (see ./spv-verify.ts). The brain-side
 * handlers wire in PR-C11-7e-2; the carriage-chain + linear-anchor
 * wire formats land in PR-C11-7e-3.
 */

export const BSV_CELL_TYPE_HASH_SIZE = 32 as const;

/**
 * Canonical cell-type names for the BSV substrate, matching
 * `cartridges/bsv-anchor-bundle/cartridge.json` `cellTypes[].name`.
 *
 * **Treat as append-only.** Changing a value changes its typeHash and
 * breaks every cell ever minted under the old name.
 */
export const BsvCellTypeName = {
  // ── SPV verify (PR-C11-7e wire format lands here) ──────────────────

  /**
   * Dart → engine. Requests SPV verification of a BEEF + txid against
   * the brain's trusted-roots set (local chain). Payload shape: see
   * `encodeSpvVerifyIntent` / `decodeSpvVerifyIntent` in
   * `./spv-verify.ts`.
   *
   * Cell handler — once wired in PR-C11-7e-2 — invokes
   * `broker.hostVerifyBeefSpv` (the host call bound in PR-C11-7d) and
   * emits a `bsv.spv.verify.result` cell.
   */
  SPV_VERIFY_INTENT: 'bsv.spv.verify.intent',

  /**
   * Engine → Dart. Result of an SPV verification. Carries valid|invalid
   * + echoed txid + an optional brief error tag. See `./spv-verify.ts`.
   */
  SPV_VERIFY_RESULT: 'bsv.spv.verify.result',

  // ── Linear anchor (wire format → PR-C11-7e-3) ──────────────────────

  /**
   * Substrate state record. Carries `(anchor UTXO, payload hash,
   * leafPk, status, beefHead)` — the durable identity of a linear cell.
   * State transitions consume the old anchor + mint a new one with
   * the new payload hash committed to via OP_PUSHDROP.
   *
   * See LINEAR-CELL-SPV-STATE.md §1.1 for the schema; PR-C11-7e-3
   * ships the on-wire encoding.
   */
  LINEAR_ANCHOR: 'bsv.linear.anchor',

  /**
   * Engine-emitted notice that a linear cell's status changed
   * (pending → confirmed, confirmed → spent, reorg → failed, etc.).
   * Drives the renderer's UTXOs panel refresh.
   *
   * Wire format: PR-C11-7e-3.
   */
  LINEAR_STATUS: 'bsv.linear.status',

  // ── BEEF carriage chain (wire format → PR-C11-7e-3) ────────────────

  /**
   * First chunk of a BEEF that exceeds the 1024-byte cell budget.
   * Carries `(total_len, successor_hash, payload_chunk[0])`. The
   * intent or anchor cell that needs the BEEF references the head's
   * hash; the engine reassembles by walking head → body → body → … →
   * terminal.
   *
   * Chunking algorithm: LINEAR-CELL-SPV-STATE.md §5.
   */
  BEEF_CARRIAGE_HEAD: 'bsv.beef.carriage.head',

  /**
   * Subsequent chunks of a BEEF chain. Carries
   * `(successor_hash, payload_chunk[i])`. Terminal body has a
   * zero successor_hash.
   */
  BEEF_CARRIAGE_BODY: 'bsv.beef.carriage.body',

  // ── Partial-tx co-signing state machine (PR-6 of LOCKSCRIPT-CLEAVAGE §8.3) ──

  /**
   * LINEAR. The accumulating skeleton for a co-signed transaction.
   * Carries the expected counterparties + recorded contributions +
   * lifecycle status. Consumed by either an `assemble.intent`
   * (broadcast path) or a `partial.cancel` (abort path) — one-shot
   * destructor.
   *
   * Wire format: `./tx-partial.ts` → `encodePartialShell`.
   */
  PARTIAL_SHELL: 'bsv.tx.partial.shell',

  /**
   * EPHEMERAL. One counterparty's signed input/output contribution to
   * an active shell. Single-shot — replaying a contribution after the
   * shell has recorded it is trapped by the substrate's idempotency
   * check (see §6.1 of the design).
   *
   * Wire format: `./tx-partial.ts` → `encodePartialContribution`.
   */
  PARTIAL_CONTRIBUTION: 'bsv.tx.partial.contribution',

  /**
   * EPHEMERAL. Cartridge-side trigger: "all sigs collected, finalise
   * this shell and emit an assemble.intent." Consumed by the
   * substrate handler, which emits the assemble.intent and transitions
   * the shell to `BroadcastPending`.
   *
   * Wire format: `./tx-partial.ts` → `encodePartialAssemble`.
   */
  PARTIAL_ASSEMBLE: 'bsv.tx.partial.assemble',

  /**
   * EPHEMERAL. Abort the workflow. Consumed by the substrate handler,
   * which transitions the shell to `Cancelled`.
   *
   * Wire format: `./tx-partial.ts` → `encodePartialCancel`.
   */
  PARTIAL_CANCEL: 'bsv.tx.partial.cancel',

  // ── Sign / broadcast plumbing (PR-6 of LOCKSCRIPT-CLEAVAGE §8.3) ──

  /**
   * EPHEMERAL. Substrate → wallet. Carries a 32-byte sighash digest +
   * derivation context for the wallet to sign. The wallet NEVER sees
   * the handler script — only the digest (which has already committed
   * to scope via SIGHASH flags). This is the cleavage invariant
   * (§3.5).
   *
   * Wire format: `./tx-sign.ts` → `encodeTxSignRequest`.
   */
  TX_SIGN_REQUEST: 'bsv.tx.sign.request',

  /**
   * EPHEMERAL. Wallet → substrate. Carries the DER-encoded ECDSA
   * signature with the trailing sighash-flag byte. References the
   * request cell-hash for correlation.
   *
   * Wire format: `./tx-sign.ts` → `encodeTxSignResponse`.
   */
  TX_SIGN_RESPONSE: 'bsv.tx.sign.response',

  /**
   * EPHEMERAL. Broker's "assemble and broadcast" trigger. Consumes a
   * partial.shell + emits a broadcast.intent.
   *
   * Wire format: `./tx-broadcast.ts` → `encodeTxAssembleIntent`.
   */
  TX_ASSEMBLE_INTENT: 'bsv.tx.assemble.intent',

  /**
   * EPHEMERAL. Raw serialised tx for ARC. Standalone broadcast — not
   * bundled with a shell — typically minted by the substrate handler
   * chain in response to an assemble.intent, but also usable directly
   * by cartridges that have their own tx-assembly path.
   *
   * Wire format: `./tx-broadcast.ts` → `encodeTxBroadcastIntent`.
   */
  TX_BROADCAST_INTENT: 'bsv.tx.broadcast.intent',

  /**
   * EPHEMERAL. ARC's response: { txid, outcome, arc_status, confirmations }.
   *
   * Wire format: `./tx-broadcast.ts` → `encodeTxBroadcastResult`.
   */
  TX_BROADCAST_RESULT: 'bsv.tx.broadcast.result',
} as const;
export type BsvCellTypeName = (typeof BsvCellTypeName)[keyof typeof BsvCellTypeName];

/** All canonical BSV cell-type names, in declaration order. */
export const BSV_CELL_TYPE_NAMES: readonly BsvCellTypeName[] = Object.freeze(
  Object.values(BsvCellTypeName),
) as readonly BsvCellTypeName[];

/**
 * Directed transform edges in the BSV substrate cell-type graph.
 * Each edge `(from → to)` means a cell-engine node holding a `from`-
 * typed cell with the appropriate handler MAY emit a `to`-typed cell.
 *
 *   spv.verify.intent ─────────► spv.verify.result
 *
 *   linear.anchor ──────────────► linear.status         (reorg / confirm)
 *   linear.anchor ──────────────► linear.anchor         (state transition;
 *                                                        the new anchor
 *                                                        supersedes the old)
 *
 *   beef.carriage.head ────────► beef.carriage.body     (carriage walk —
 *   beef.carriage.body ────────► beef.carriage.body      describes successor
 *                                                        reference, not a
 *                                                        transformation per se)
 *
 * Carriage edges are reachability — useful for "given this head, what
 * follows" lookups — not state mutation. The engine's audit log records
 * carriage walks as `read` rather than `emit`.
 */
export const BsvTransformEdges: ReadonlyArray<readonly [BsvCellTypeName, BsvCellTypeName]> =
  Object.freeze([
    [BsvCellTypeName.SPV_VERIFY_INTENT, BsvCellTypeName.SPV_VERIFY_RESULT],
    [BsvCellTypeName.LINEAR_ANCHOR, BsvCellTypeName.LINEAR_STATUS],
    [BsvCellTypeName.LINEAR_ANCHOR, BsvCellTypeName.LINEAR_ANCHOR],
    [BsvCellTypeName.BEEF_CARRIAGE_HEAD, BsvCellTypeName.BEEF_CARRIAGE_BODY],
    [BsvCellTypeName.BEEF_CARRIAGE_BODY, BsvCellTypeName.BEEF_CARRIAGE_BODY],

    // PR-6: partial-tx state machine (LOCKSCRIPT-CLEAVAGE §6.3).
    //   shell ───contribution───► shell    (handler emits successor LINEAR
    //                                        shell with new contribution
    //                                        recorded; consumes old shell)
    //   shell ───assemble───────► assemble.intent
    //                              + shell.status:= BroadcastPending
    //   shell ───cancel─────────► shell.status:= Cancelled (no successor;
    //                                                       terminal)
    [BsvCellTypeName.PARTIAL_SHELL, BsvCellTypeName.PARTIAL_SHELL],
    [BsvCellTypeName.PARTIAL_SHELL, BsvCellTypeName.TX_ASSEMBLE_INTENT],

    // Sign request / response pair.
    //   ANY tx-build handler can emit a sign.request; the wallet emits
    //   sign.response back. No on-substrate transform consumes the
    //   response — the broker correlates by request_cell_hash and
    //   resumes the originating handler. The edges are reachability:
    //   "given a sign.request you may eventually see a sign.response".
    [BsvCellTypeName.TX_SIGN_REQUEST, BsvCellTypeName.TX_SIGN_RESPONSE],

    // Assemble.intent → broadcast.intent (the substrate handler chain
    // serializes the tx via host_assemble_tx + emits the broadcast.intent).
    [BsvCellTypeName.TX_ASSEMBLE_INTENT, BsvCellTypeName.TX_BROADCAST_INTENT],

    // Broadcast.intent → broadcast.result (broker calls ARC; emits the
    // result).
    [BsvCellTypeName.TX_BROADCAST_INTENT, BsvCellTypeName.TX_BROADCAST_RESULT],
  ]);

/** True when `(from → to)` is a declared BSV transform edge. */
export function isBsvTransform(from: BsvCellTypeName, to: BsvCellTypeName): boolean {
  return BsvTransformEdges.some(([f, t]) => f === from && t === to);
}

```
