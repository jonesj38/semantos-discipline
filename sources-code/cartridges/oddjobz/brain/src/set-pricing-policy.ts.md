---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/set-pricing-policy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.476464+00:00
---

# cartridges/oddjobz/brain/src/set-pricing-policy.ts

```ts
/**
 * `set_pricing_policy` — the operator pricing-policy config-intent
 * mutating handler (DECISION-A5 / A5.P2.c).
 *
 * This is the WRITE seam for `oddjobz.pricing_policy.v1`
 * (`pricing-policy-projector.ts` is the READ seam). It mirrors the
 * `RatificationQueue.ratify` template (the grounded "ratify-walker"
 * pattern): a `Result<ok,err>` typed handler that
 *   1. kernel-gates on `cap.oddjobz.write_policy` (`checkDomainFlag`,
 *      the same OP_CHECKDOMAINFLAG stub the FSM genesis paths use),
 *   2. reads the latest policy revision for the hat from an injected
 *      store (no ambient I/O — pure + memory-store-testable),
 *   3. builds the next link in the append-only signed amendment chain
 *      (genesis v1 ⇒ no `prevPolicyHash`; amendment v>1 ⇒
 *      `prevPolicyHash` = sha256 of the predecessor's canonical packed
 *      bytes, `version` = prev+1, `policyId` stable across the chain),
 *   4. stamps `signedByOperatorId` provenance (the `lead.ratifiedBy`
 *      precedent — A5 ruling #2: mint-time hat-sign + provenance, NOT
 *      per-clause detached sigs),
 *   5. `pricingPolicyCellType.pack`s it (which re-validates the
 *      amendment-chain invariants + the embedded PricingPolicy), and
 *   6. appends the minted cell.
 *
 * Kernel linearity (RELEVANT) governs that the cell is never consumed;
 * the Ricardian amendment history is THIS version/prevPolicyHash chain
 * over accumulated cells. The Zig `verb.dispatch` walker adapter that
 * exposes this over the wire (A5.P2.d) is redeploy-gated and is NOT in
 * this slice — this TS handler is the worktree-verifiable core.
 */

import { createHash } from 'node:crypto';
import { randomUUID } from 'node:crypto';
import {
  pricingPolicyCellType,
  type OddjobzPricingPolicy,
} from './cell-types/pricing-policy.js';
import type { PricingPolicy } from './rom.js';
import {
  checkDomainFlag,
  ok,
  err,
  type Result,
  type PresentedCap,
  type KernelGateFailure,
} from './state-machines/kernel-gate.js';

/** Persistence seam for the policy amendment chain. Injected so the
 *  handler stays pure and memory-store-testable (the
 *  `RatificationQueue` storage-injection precedent). */
export interface PricingPolicyStore {
  /** The latest (highest-version) policy revision for `hatId`, or
   *  `null` when none exists yet (⇒ the next write is the genesis). */
  loadLatest(hatId: string): OddjobzPricingPolicy | null;
  /** Append a freshly-minted revision cell + its canonical bytes. */
  append(cell: OddjobzPricingPolicy, bytes: Uint8Array): void;
}

export interface SetPricingPolicyInput {
  /** Tenant/hat the policy governs (pricing is per-operator). */
  readonly hatId: string;
  /** Operator root-cert id (hex) that signed this revision under the
   *  operator hat → the `signedByOperatorId` provenance field. */
  readonly operatorCertId: string;
  /** The new machine-readable pricing contract (the config-intent
   *  payload — the EXACT `PricingPolicy` `calculateROM` consumes). */
  readonly policy: PricingPolicy;
  /** The presented `cap.oddjobz.write_policy` UTXO (or `null` —
   *  ⇒ `cap_required`). */
  readonly presentedCap: PresentedCap | null;
  /** ISO timestamp for this revision (injected — deterministic). */
  readonly nowIso: string;
  /** Genesis policy identity; defaults to a fresh UUID. Ignored on
   *  amendments (the chain reuses the predecessor's `policyId`). */
  readonly newPolicyId?: string;
}

export interface SetPricingPolicyResult {
  readonly cell: OddjobzPricingPolicy;
  readonly cellBytes: Uint8Array;
  readonly isGenesis: boolean;
}

/** sha256 hex of a predecessor's canonical packed bytes — the
 *  `prevPolicyHash` amendment-chain link. Deterministic + verifiable
 *  (re-pack the predecessor, re-hash, compare). 64 lowercase hex. */
export function policyCellHash(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

/**
 * Append the next pricing-policy revision under the operator hat.
 * Pure given `(input, store)` — same inputs ⇒ same minted cell.
 */
export function setPricingPolicy(
  input: SetPricingPolicyInput,
  store: PricingPolicyStore,
): Result<SetPricingPolicyResult, KernelGateFailure> {
  // 1. Kernel-gate: OP_CHECKDOMAINFLAG on cap.oddjobz.write_policy.
  const gate = checkDomainFlag('cap.oddjobz.write_policy', input.presentedCap);
  if (!gate.ok) return err(gate.error);

  // 2. Read the latest revision for the hat.
  const prev = store.loadLatest(input.hatId);
  const isGenesis = prev === null;

  // 3. Build the next chain link.
  const cell: OddjobzPricingPolicy = isGenesis
    ? {
        policyId: input.newPolicyId ?? randomUUID(),
        hatId: input.hatId,
        version: 1,
        signedByOperatorId: input.operatorCertId,
        policy: input.policy,
        createdAt: input.nowIso,
        updatedAt: input.nowIso,
      }
    : {
        policyId: prev!.policyId, // stable across the amendment chain
        hatId: input.hatId,
        version: prev!.version + 1,
        prevPolicyHash: policyCellHash(pricingPolicyCellType.pack(prev!)),
        signedByOperatorId: input.operatorCertId,
        policy: input.policy,
        createdAt: prev!.createdAt, // policy created once; amended over time
        updatedAt: input.nowIso,
      };

  // 5. Pack — re-validates amendment-chain invariants + embedded
  //    PricingPolicy. Throws on a malformed policy (caller's bug, not
  //    a kernel-gate failure) — surfaced, never swallowed.
  const cellBytes = pricingPolicyCellType.pack(cell);

  // 6. Append the minted revision.
  store.append(cell, cellBytes);

  return ok({ cell, cellBytes, isGenesis });
}

/**
 * Minimal in-memory {@link PricingPolicyStore} — the test/dev seam.
 * Keeps every appended revision; `loadLatest` returns the
 * highest-`version` cell for the hat. Production wires a substrate-
 * backed store (the Zig view-store, A5.P2.d).
 */
export function makeMemoryPricingPolicyStore(): PricingPolicyStore & {
  all(): readonly OddjobzPricingPolicy[];
} {
  const cells: OddjobzPricingPolicy[] = [];
  return {
    loadLatest(hatId: string): OddjobzPricingPolicy | null {
      let latest: OddjobzPricingPolicy | null = null;
      for (const c of cells) {
        if (c.hatId !== hatId) continue;
        if (latest === null || c.version > latest.version) latest = c;
      }
      return latest;
    },
    append(cell: OddjobzPricingPolicy): void {
      cells.push(cell);
    },
    all: () => cells.slice(),
  };
}

```
