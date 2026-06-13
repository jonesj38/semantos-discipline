---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/__tests__/capability.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.819295+00:00
---

# core/scg-relations/src/__tests__/capability.test.ts

```ts
/**
 * RM-022 capability binding tests.
 *
 * Verifies that `createRelation`, when handed the
 * `requireRelationMint(certId)` thunk in `capabilityCheck`, rejects
 * insertion if the bound `capabilityPort` returns `valid: false`.
 *
 * Uses the live `capabilityPort` singleton: each test binds a small
 * inline implementation and unbinds in afterEach. No DB needed for the
 * port wiring itself; the createRelation call needs the test DB.
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  capabilityPort,
  type CapabilityPort,
  type CapabilityCheck,
} from '@semantos/identity-ports';
import { createObject, type Database } from '@semantos/semantic-objects';
import { makeTestDb } from './setup.js';
import {
  CAPABILITY_ID_RELATION_MINT,
  RELATION_MINT_FLAG,
  RelationCapabilityError,
  createRelation,
  listRelationsFrom,
  requireRelationMint,
} from '../index.js';

function bindCapabilityPort(impl: CapabilityPort): void {
  // Singleton may have a residual binding from another test file.
  capabilityPort.unbind();
  capabilityPort.bind(impl);
}

function unbindAll(): void {
  capabilityPort.unbind();
}

describe('RM-022 capability binding', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    unbindAll();
    await close();
  });

  test('C1 RELATION_MINT slot matches RM-004 allocation (0x0001000c)', () => {
    expect(RELATION_MINT_FLAG).toBe(0x0001000c);
  });

  test('C2 createRelation succeeds when port returns valid', async () => {
    const presentations: Array<{ certId: string; capabilityId: string }> = [];
    bindCapabilityPort({
      present(certId, capabilityId): CapabilityCheck {
        presentations.push({ certId, capabilityId });
        return { valid: true, verifier: 'stub' };
      },
    });

    const source = await createObject(db, {
      objectKind: 'scg.cell',
      payload: {},
    });
    const target = await createObject(db, {
      objectKind: 'scg.cell',
      payload: {},
    });

    const rel = await createRelation(db, {
      kind: 'REPLIES_TO',
      sourceId: source.id,
      targetId: target.id,
      createdByCertId: 'cert-author',
      capabilityCheck: requireRelationMint('cert-author'),
    });

    expect(rel.payload.kind).toBe('REPLIES_TO');
    expect(presentations).toEqual([
      { certId: 'cert-author', capabilityId: CAPABILITY_ID_RELATION_MINT },
    ]);
  });

  test('C3 createRelation rejects when port returns invalid', async () => {
    bindCapabilityPort({
      present(): CapabilityCheck {
        return { valid: false, reason: 'cap UTXO spent', verifier: 'stub' };
      },
    });

    const source = await createObject(db, {
      objectKind: 'scg.cell',
      payload: {},
    });
    const target = await createObject(db, {
      objectKind: 'scg.cell',
      payload: {},
    });

    await expect(
      createRelation(db, {
        kind: 'SUPPORTS',
        sourceId: source.id,
        targetId: target.id,
        createdByCertId: 'cert-author',
        capabilityCheck: requireRelationMint('cert-author'),
      }),
    ).rejects.toBeInstanceOf(RelationCapabilityError);

    const after = await listRelationsFrom(db, source.id);
    expect(after).toHaveLength(0);
  });

  test('C4 RelationCapabilityError carries certId + capabilityId + reason', async () => {
    bindCapabilityPort({
      present(): CapabilityCheck {
        return { valid: false, reason: 'unknown cert', verifier: 'stub' };
      },
    });

    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    try {
      await createRelation(db, {
        kind: 'CITES',
        sourceId: a.id,
        targetId: a.id,
        createdByCertId: 'cert-x',
        capabilityCheck: requireRelationMint('cert-x'),
      });
      throw new Error('expected rejection');
    } catch (e) {
      expect(e).toBeInstanceOf(RelationCapabilityError);
      if (!(e instanceof RelationCapabilityError)) return;
      expect(e.certId).toBe('cert-x');
      expect(e.capabilityId).toBe(CAPABILITY_ID_RELATION_MINT);
      expect(e.reason).toBe('unknown cert');
      expect(e.code).toBe('RELATION_CAPABILITY_DENIED');
    }
  });

  test('C5 custom capabilityId overrides the default', async () => {
    const seen: string[] = [];
    bindCapabilityPort({
      present(_, capabilityId): CapabilityCheck {
        seen.push(capabilityId);
        return { valid: true, verifier: 'stub' };
      },
    });

    const a = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    await createRelation(db, {
      kind: 'CITES',
      sourceId: a.id,
      targetId: a.id,
      capabilityCheck: requireRelationMint('cert-x', 'cap.scg.delegated_mint'),
    });

    expect(seen).toEqual(['cap.scg.delegated_mint']);
  });
});

```
