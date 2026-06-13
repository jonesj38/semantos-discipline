---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/access-gate.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.817322+00:00
---

# core/scg-relations/src/access-gate.ts

```ts
/**
 * 402-style access gate — RM-063.
 *
 * `requirePaymentRelation` is the substrate-level access primitive
 * for paid content: callers ask "has the requester paid for access
 * to this target", and the gate returns either an access decision
 * or an `AccessChallenge` the renderer can surface (typically as an
 * HTTP 402 Payment Required response with the demanded amount).
 *
 * The gate is intentionally narrow:
 *   - It looks for a `PAYS` (or `GRANTS_ACCESS`) relation from the
 *     requester to the target, with `amount >= requiredAmount` in
 *     the matching currency.
 *   - It does NOT verify on-chain anchoring — that's the caller's
 *     responsibility once `txAnchor` is set (see
 *     `@semantos/anchor-attestation::verifyAnchor`).
 *   - It does NOT mint anything. Payments are authored via
 *     `createRelation({ kind: 'PAYS', ... })` upstream of the gate.
 *
 * Latency budget (SCG §8.2): ≤ 5ms in-memory cache. The gate reads
 * a single `listRelationsTo` slice — Postgres index hit, sub-ms.
 */
import type { Database } from '@semantos/semantic-objects';
import { listRelationsTo } from './operations.js';
import type { RelationRow } from './types.js';

export interface RequirePaymentInput {
  /** The cell the requester wants to access. */
  targetId: string;
  /** Hex `sem_objects.id` of the cell that authored the payment.
   *  Typically a user identity cert id wrapped as a sem_objects row.
   *  We match payments where `relation.sourceId === requesterId`. */
  requesterId: string;
  /** Minimum amount required (smallest unit, e.g. satoshis). */
  amount: number;
  /** Currency code. Must match the payment relation's currency. */
  currency: string;
  /** If true, the gate also accepts a `GRANTS_ACCESS` relation
   *  without an amount check (admin override / promotional grant). */
  honorGrantAccess?: boolean;
}

export type AccessDecision =
  | {
      ok: true;
      /** The relation that satisfied the gate. */
      reason: 'paid' | 'granted';
      relation: RelationRow;
    }
  | {
      ok: false;
      challenge: AccessChallenge;
    };

export interface AccessChallenge {
  /** HTTP 402-style demand. */
  status: 402;
  targetId: string;
  requiredAmount: number;
  currency: string;
  /** Suggested human-readable reason (renderer can override). */
  reason: string;
}

/**
 * Resolve access for a `(requester, target, amount, currency)` tuple.
 * Returns a typed decision; the caller decides how to surface a
 * challenge (HTTP response, UI overlay, retry-after header, etc.).
 */
export async function requirePaymentRelation(
  db: Database,
  input: RequirePaymentInput,
): Promise<AccessDecision> {
  const incoming = await listRelationsTo(db, input.targetId, {
    kind: input.honorGrantAccess
      ? ['PAYS', 'GRANTS_ACCESS']
      : ['PAYS'],
  });

  // Look for any payment row from the requester that meets the bar.
  const granting = incoming.find(
    (r) =>
      r.payload.sourceId === input.requesterId &&
      r.payload.kind === 'GRANTS_ACCESS',
  );
  if (granting && input.honorGrantAccess) {
    return { ok: true, reason: 'granted', relation: granting };
  }

  const paid = incoming.find(
    (r) =>
      r.payload.sourceId === input.requesterId &&
      r.payload.kind === 'PAYS' &&
      r.payload.currency === input.currency &&
      typeof r.payload.amount === 'number' &&
      r.payload.amount >= input.amount,
  );
  if (paid) {
    return { ok: true, reason: 'paid', relation: paid };
  }

  return {
    ok: false,
    challenge: {
      status: 402,
      targetId: input.targetId,
      requiredAmount: input.amount,
      currency: input.currency,
      reason: `Payment of ${input.amount} ${input.currency} required to access ${input.targetId}`,
    },
  };
}

```
