---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/metering/metering/src/policies.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.486352+00:00
---

# packages/metering/metering/src/policies.ts

```ts
/**
 * Metering channel policies — Lisp s-expressions compiled to WASM opcodes.
 *
 * Payment channel model (incrementing nSequence):
 *   - Funding tx locks sats in 2-of-2 multisig
 *   - Each tick produces a pre-signed tx with incremented nSequence
 *     spending the same funding UTXO, redistributing provider/consumer payouts
 *   - Cooperative close: last signer sets nSequence=0xFFFFFFFF + nLockTime=0,
 *     making the tx immediately broadcastable (finalised)
 *   - Unilateral close: broadcast the latest (highest nSequence) pre-signed tx
 *   - Dispute = counterparty broadcasts a stale (lower nSequence) tx;
 *     the other party proves they have a higher nSequence
 *
 * Phase 29.5 kernel enforcement sweep — metering settlement policies.
 */

import { parseExpression } from '../../../runtime/shell/src/lisp/parser';
import { LispCompiler } from '../../../runtime/shell/src/lisp/compiler';
import type { ScriptOutput } from '../../../runtime/shell/src/lisp/types';

// ── Policy Sources (Lisp S-Expressions) ──────────────────────────

/**
 * Fund: Channel must be in NEGOTIATING state and have a valid funding outpoint.
 * Guards: NEGOTIATING → FUNDED
 */
export const FUND_POLICY = `(and (channel-negotiating?) (has-funding-outpoint?))`;

/**
 * Activate: Channel must be funded.
 * Guards: FUNDED → ACTIVE
 */
export const ACTIVATE_POLICY = `(channel-funded?)`;

/**
 * Tick: Channel must be active, tick amount non-negative,
 * and payouts must sum to the funding amount (conservation).
 * Each tick increments nSequence and re-signs with the new payout split.
 * Guards: state stays ACTIVE, nSequence increments.
 */
export const TICK_POLICY = `(and (channel-active?) (tick-amount-valid?) (payouts-conserved?))`;

/**
 * Close request: Channel must be active or paused.
 * Guards: ACTIVE|PAUSED → CLOSING_REQUESTED
 */
export const CLOSE_REQUEST_POLICY = `(or (channel-active?) (channel-paused?))`;

/**
 * Close confirm: Channel must be in CLOSING_REQUESTED, both parties agree.
 * Guards: CLOSING_REQUESTED → CLOSING_CONFIRMED
 */
export const CLOSE_CONFIRM_POLICY = `(and (channel-closing-requested?) (both-parties-agree?))`;

/**
 * Settle: The submitted tx must spend the correct funding outpoint and
 * either be final (nSequence=0xFFFFFFFF, cooperative close) or carry the
 * highest nSequence seen (unilateral broadcast of latest tick tx).
 * Guards: CLOSING_CONFIRMED → SETTLED
 */
export const SETTLE_POLICY = `(and (channel-closing-confirmed?) (or (settlement-is-final?) (nsequence-is-latest?)) (spends-funding-outpoint?))`;

/**
 * Dispute: Counterparty broadcast a stale tx (lower nSequence).
 * The disputing party proves they hold a higher nSequence pre-signed tx.
 * Guards: ACTIVE|PAUSED|CLOSING_REQUESTED|CLOSING_CONFIRMED → DISPUTED
 */
export const DISPUTE_POLICY = `(and (not (channel-settled?)) (has-higher-nsequence?))`;

/**
 * Resolve: Channel must be in DISPUTED state, and the highest-nSequence
 * tx has been identified and will be used for final settlement.
 * Guards: DISPUTED → SETTLED
 */
export const RESOLVE_POLICY = `(and (channel-disputed?) (has-resolution?))`;

// ── Compiled Policy Cache ────────────────────────────────────────

export interface CompiledMeteringPolicies {
  fund: ScriptOutput;
  activate: ScriptOutput;
  tick: ScriptOutput;
  closeRequest: ScriptOutput;
  closeConfirm: ScriptOutput;
  settle: ScriptOutput;
  dispute: ScriptOutput;
  resolve: ScriptOutput;
}

const POLICY_MAP: Record<string, string> = {
  fund: FUND_POLICY,
  activate: ACTIVATE_POLICY,
  tick: TICK_POLICY,
  closeRequest: CLOSE_REQUEST_POLICY,
  closeConfirm: CLOSE_CONFIRM_POLICY,
  settle: SETTLE_POLICY,
  dispute: DISPUTE_POLICY,
  resolve: RESOLVE_POLICY,
};

/** Compile all metering policies once at init. */
export function compileMeteringPolicies(): CompiledMeteringPolicies {
  const compiler = new LispCompiler({ compiledAt: 'metering-init' });
  const result: Record<string, ScriptOutput> = {};
  for (const [name, source] of Object.entries(POLICY_MAP)) {
    const expr = parseExpression(source);
    result[name] = compiler.compile(expr);
  }
  return result as unknown as CompiledMeteringPolicies;
}

```
