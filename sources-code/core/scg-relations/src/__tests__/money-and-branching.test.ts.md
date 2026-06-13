---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/__tests__/money-and-branching.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.818461+00:00
---

# core/scg-relations/src/__tests__/money-and-branching.test.ts

```ts
/**
 * Money-bearing relation kinds (RM-060), branching ops (RM-080), and the
 * 402-style access-gate helper (RM-063).
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { createObject, type Database } from '@semantos/semantic-objects';
import { makeTestDb } from './setup.js';
import {
  createRelation,
  forkSubgraph,
  mergeSubgraph,
  requirePaymentRelation,
} from '../index.js';

describe('RM-060 — money-bearing relation kinds', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('M1 PAYS requires amount + currency; payload round-trips', async () => {
    const payer = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const target = await createObject(db, { objectKind: 'scg.cell', payload: {} });

    const rel = await createRelation(db, {
      kind: 'PAYS',
      sourceId: payer.id,
      targetId: target.id,
      amount: 1000,
      currency: 'sats',
      txAnchor: 'deadbeef',
    });
    expect(rel.payload.kind).toBe('PAYS');
    expect(rel.payload.amount).toBe(1000);
    expect(rel.payload.currency).toBe('sats');
    expect(rel.payload.txAnchor).toBe('deadbeef');
  });

  test('M2 PAYS without amount throws', async () => {
    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await expect(
      createRelation(db, {
        kind: 'PAYS',
        sourceId: a.id,
        targetId: b.id,
        currency: 'sats',
      }),
    ).rejects.toThrow(/amount/);
  });

  test('M3 PAYS without currency throws', async () => {
    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await expect(
      createRelation(db, {
        kind: 'PAYS',
        sourceId: a.id,
        targetId: b.id,
        amount: 100,
      }),
    ).rejects.toThrow(/currency/);
  });

  test('M4 ESCROW_LOCKS and ESCROW_RELEASES require amount + currency', async () => {
    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const lock = await createRelation(db, {
      kind: 'ESCROW_LOCKS',
      sourceId: a.id,
      targetId: b.id,
      amount: 250,
      currency: 'sats',
    });
    expect(lock.payload.kind).toBe('ESCROW_LOCKS');
    expect(lock.payload.amount).toBe(250);

    const release = await createRelation(db, {
      kind: 'ESCROW_RELEASES',
      sourceId: a.id,
      targetId: b.id,
      amount: 250,
      currency: 'sats',
    });
    expect(release.payload.kind).toBe('ESCROW_RELEASES');

    await expect(
      createRelation(db, {
        kind: 'ESCROW_LOCKS',
        sourceId: a.id,
        targetId: b.id,
      }),
    ).rejects.toThrow(/amount/);
  });
});

describe('RM-063 — requirePaymentRelation access gate', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('G1 returns 402 challenge when no payment exists', async () => {
    const target = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const requester = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const decision = await requirePaymentRelation(db, {
      targetId: target.id,
      requesterId: requester.id,
      amount: 100,
      currency: 'sats',
    });
    expect(decision.ok).toBe(false);
    if (decision.ok) return;
    expect(decision.challenge.status).toBe(402);
    expect(decision.challenge.requiredAmount).toBe(100);
    expect(decision.challenge.currency).toBe('sats');
  });

  test('G2 returns ok=paid when a matching PAYS exists', async () => {
    const target = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const requester = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await createRelation(db, {
      kind: 'PAYS',
      sourceId: requester.id,
      targetId: target.id,
      amount: 100,
      currency: 'sats',
    });
    const decision = await requirePaymentRelation(db, {
      targetId: target.id,
      requesterId: requester.id,
      amount: 100,
      currency: 'sats',
    });
    expect(decision.ok).toBe(true);
    if (!decision.ok) return;
    expect(decision.reason).toBe('paid');
  });

  test('G3 accepts payments above the required amount', async () => {
    const target = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const requester = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await createRelation(db, {
      kind: 'PAYS',
      sourceId: requester.id,
      targetId: target.id,
      amount: 500,
      currency: 'sats',
    });
    const decision = await requirePaymentRelation(db, {
      targetId: target.id,
      requesterId: requester.id,
      amount: 100,
      currency: 'sats',
    });
    expect(decision.ok).toBe(true);
  });

  test('G4 rejects when currency does not match', async () => {
    const target = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const requester = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await createRelation(db, {
      kind: 'PAYS',
      sourceId: requester.id,
      targetId: target.id,
      amount: 1000,
      currency: 'USD',
    });
    const decision = await requirePaymentRelation(db, {
      targetId: target.id,
      requesterId: requester.id,
      amount: 100,
      currency: 'sats',
    });
    expect(decision.ok).toBe(false);
  });

  test('G5 rejects when amount is below the required floor', async () => {
    const target = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const requester = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await createRelation(db, {
      kind: 'PAYS',
      sourceId: requester.id,
      targetId: target.id,
      amount: 50,
      currency: 'sats',
    });
    const decision = await requirePaymentRelation(db, {
      targetId: target.id,
      requesterId: requester.id,
      amount: 100,
      currency: 'sats',
    });
    expect(decision.ok).toBe(false);
  });

  test('G6 GRANTS_ACCESS is honored only when honorGrantAccess=true', async () => {
    const target = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const requester = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await createRelation(db, {
      kind: 'GRANTS_ACCESS',
      sourceId: requester.id,
      targetId: target.id,
    });

    const denied = await requirePaymentRelation(db, {
      targetId: target.id,
      requesterId: requester.id,
      amount: 100,
      currency: 'sats',
    });
    expect(denied.ok).toBe(false);

    const allowed = await requirePaymentRelation(db, {
      targetId: target.id,
      requesterId: requester.id,
      amount: 100,
      currency: 'sats',
      honorGrantAccess: true,
    });
    expect(allowed.ok).toBe(true);
    if (!allowed.ok) return;
    expect(allowed.reason).toBe('granted');
  });
});

describe('RM-080 — forkSubgraph + mergeSubgraph', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('F1 forkSubgraph creates a branch cell + FORKS relation back to the fork point', async () => {
    const trunk = await createObject(db, {
      objectKind: 'scg.cell',
      payload: { body: 'trunk' },
    });
    const result = await forkSubgraph(db, {
      forkPointId: trunk.id,
      branchObjectKind: 'scg.cell',
      branchPayload: { body: 'branch' },
      createdByCertId: 'cert-x',
    });
    expect(result.branchId).not.toBe(trunk.id);
    expect(result.forkRelation.payload.kind).toBe('FORKS');
    expect(result.forkRelation.payload.sourceId).toBe(result.branchId);
    expect(result.forkRelation.payload.targetId).toBe(trunk.id);
  });

  test('F2 mergeSubgraph requires ≥2 parents', async () => {
    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await expect(
      mergeSubgraph(db, {
        parentBranchIds: [a.id],
        mergeObjectKind: 'scg.cell',
      }),
    ).rejects.toThrow(/at least two parent branches/);
  });

  test('F3 mergeSubgraph emits one MERGES relation per parent', async () => {
    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const merge = await mergeSubgraph(db, {
      parentBranchIds: [a.id, b.id],
      mergeObjectKind: 'scg.cell',
    });
    expect(merge.mergeRelations.length).toBe(2);
    expect(merge.mergeRelations[0]!.payload.kind).toBe('MERGES');
    expect(merge.mergeRelations[0]!.payload.targetId).toBe(a.id);
    expect(merge.mergeRelations[1]!.payload.targetId).toBe(b.id);
  });

  test('F4 mergeSubgraph reports conflicts=false when parents share a state hash (or all null)', async () => {
    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const b = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const merge = await mergeSubgraph(db, {
      parentBranchIds: [a.id, b.id],
      mergeObjectKind: 'scg.cell',
    });
    expect(merge.conflicts).toBe(false);
  });

  test('F5 mergeSubgraph throws if any parent is missing', async () => {
    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await expect(
      mergeSubgraph(db, {
        parentBranchIds: [a.id, 'does-not-exist'],
        mergeObjectKind: 'scg.cell',
      }),
    ).rejects.toThrow(/not found/);
  });
});

```
