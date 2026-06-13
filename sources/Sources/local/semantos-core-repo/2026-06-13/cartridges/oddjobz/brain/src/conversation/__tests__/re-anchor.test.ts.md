---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/re-anchor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.538111+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/re-anchor.test.ts

```ts
/**
 * D-OJ-conv-re-anchor — tests for `getActiveAnchor` and `reAnchorTurn`.
 *
 * Uses PGlite (in-memory postgres) following the pattern established in
 * identity-merge.test.ts, per-turn-relation.test.ts, and db-sinks.test.ts.
 *
 * Test matrix:
 *   RA1 — non-existent turnId → turn_not_found
 *   RA2 — non-existent newEntityCellHash → entity_not_found
 *   RA3 — turn exists, no existing anchor → no_existing_anchor
 *   RA4 — valid re-anchor → ok=true, newRelationId and supersededRelationId present
 *   RA5 — re-anchor to same entity → already_anchored_to_same_entity
 *   RA6 — getActiveAnchor after valid re-anchor returns the new relation
 *   RA7 — double re-anchor (A→B, then B→C) → getActiveAnchor returns C's anchor
 *   RA8 — getActiveAnchor with no anchors → null
 */

import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createObject, type Database } from '@semantos/semantic-objects';
import { createRelation } from '@semantos/scg-relations';
import {
  getActiveAnchor,
  reAnchorTurn,
  type ReAnchorRequest,
} from '../re-anchor.js';

// ────────────────────────────────────────────────────────────
// PGlite harness — mirrors identity-merge.test.ts
// ────────────────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../../../../../core/semantic-objects/migrations/0000_init.sql',
);

async function makeTestDb(): Promise<{
  db: Database;
  close: () => Promise<void>;
}> {
  const pg = new PGlite();
  await pg.waitReady;
  const db = drizzle(pg) as unknown as Database;
  const sql = readFileSync(MIGRATION_PATH, 'utf-8');
  for (const stmt of splitSql(sql)) {
    const s = stmt.trim();
    if (!s) continue;
    await pg.exec(s);
  }
  return {
    db,
    async close() {
      await pg.close();
    },
  };
}

function splitSql(sql: string): string[] {
  const out: string[] = [];
  const lines = sql.split('\n');
  let buf: string[] = [];
  let inDoBlock = false;
  for (const line of lines) {
    if (line.trim().startsWith('--')) continue;
    buf.push(line);
    if (/\bDO \$\$/i.test(line)) inDoBlock = true;
    if (inDoBlock && /END \$\$;/.test(line)) {
      inDoBlock = false;
      out.push(buf.join('\n'));
      buf = [];
      continue;
    }
    if (!inDoBlock && line.trimEnd().endsWith(';')) {
      out.push(buf.join('\n'));
      buf = [];
    }
  }
  if (buf.length) out.push(buf.join('\n'));
  return out;
}

// ────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────

/** Seed a minimal sem_objects row for a conversation turn. */
async function seedTurn(db: Database, id: string): Promise<void> {
  await createObject(db, {
    id,
    objectKind: 'oddjobz.conversation.turn',
    payload: { turnId: id },
  });
}

/** Seed a minimal sem_objects row for an entity (job/site/customer). */
async function seedEntity(db: Database, id: string, kind: string): Promise<void> {
  await createObject(db, {
    id,
    objectKind: `oddjobz.${kind}`,
    payload: { id },
  });
}

/** Mint an initial BELONGS_TO_ENTITY relation for a turn → entity. */
async function seedAnchor(
  db: Database,
  turnId: string,
  entityCellHash: string,
  entityKind: 'job' | 'site' | 'customer' | 'lead',
): Promise<string> {
  const rel = await createRelation(db, {
    kind: 'BELONGS_TO_ENTITY',
    sourceId: turnId,
    targetId: entityCellHash,
    extra: { entityKind },
  });
  return rel.id;
}

/** Build a valid ReAnchorRequest. */
function validReq(
  turnId: string,
  newEntityCellHash: string,
  overrides?: Partial<ReAnchorRequest>,
): ReAnchorRequest {
  return {
    turnId,
    newEntityCellHash,
    newEntityKind: 'job',
    ...overrides,
  };
}

// ────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────

describe('reAnchorTurn', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  // ── RA1: non-existent turnId ──────────────────────────────

  test('RA1 non-existent turnId → turn_not_found', async () => {
    await seedEntity(db, 'entity-ra1', 'job');

    const result = await reAnchorTurn(db, validReq('turn-nonexistent', 'entity-ra1'));

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('turn_not_found');
    }
  });

  // ── RA2: non-existent newEntityCellHash ───────────────────

  test('RA2 non-existent newEntityCellHash → entity_not_found', async () => {
    await seedTurn(db, 'turn-ra2');

    const result = await reAnchorTurn(db, validReq('turn-ra2', 'entity-nonexistent'));

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('entity_not_found');
    }
  });

  // ── RA3: turn exists, no existing anchor ──────────────────

  test('RA3 turn exists but has no BELONGS_TO_ENTITY anchor → no_existing_anchor', async () => {
    await seedTurn(db, 'turn-ra3');
    await seedEntity(db, 'entity-ra3', 'site');

    const result = await reAnchorTurn(db, validReq('turn-ra3', 'entity-ra3', { newEntityKind: 'site' }));

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('no_existing_anchor');
    }
  });

  // ── RA4: valid re-anchor ──────────────────────────────────

  test('RA4 valid re-anchor → ok=true, newRelationId and supersededRelationId present', async () => {
    await seedTurn(db, 'turn-ra4');
    await seedEntity(db, 'entity-ra4-old', 'job');
    await seedEntity(db, 'entity-ra4-new', 'job');
    const oldRelId = await seedAnchor(db, 'turn-ra4', 'entity-ra4-old', 'job');

    const result = await reAnchorTurn(db, validReq('turn-ra4', 'entity-ra4-new'));

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(typeof result.newRelationId).toBe('string');
      expect(result.newRelationId.length).toBeGreaterThan(0);
      expect(result.supersededRelationId).toBe(oldRelId);
    }
  });

  // ── RA5: re-anchor to same entity ────────────────────────

  test('RA5 re-anchor to same entity → already_anchored_to_same_entity', async () => {
    await seedTurn(db, 'turn-ra5');
    await seedEntity(db, 'entity-ra5', 'customer');
    await seedAnchor(db, 'turn-ra5', 'entity-ra5', 'customer');

    const result = await reAnchorTurn(db, validReq('turn-ra5', 'entity-ra5', { newEntityKind: 'customer' }));

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('already_anchored_to_same_entity');
    }
  });
});

// ────────────────────────────────────────────────────────────
// getActiveAnchor tests
// ────────────────────────────────────────────────────────────

describe('getActiveAnchor', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  // ── RA6: after valid re-anchor, getActiveAnchor returns new relation ──

  test('RA6 getActiveAnchor after valid re-anchor returns new relation (targetId = newEntityCellHash)', async () => {
    await seedTurn(db, 'turn-ra6');
    await seedEntity(db, 'entity-ra6-old', 'job');
    await seedEntity(db, 'entity-ra6-new', 'site');
    await seedAnchor(db, 'turn-ra6', 'entity-ra6-old', 'job');

    const reAnchorResult = await reAnchorTurn(
      db,
      validReq('turn-ra6', 'entity-ra6-new', { newEntityKind: 'site' }),
    );
    expect(reAnchorResult.ok).toBe(true);

    const active = await getActiveAnchor(db, 'turn-ra6');
    expect(active).not.toBeNull();
    expect(active!.payload.targetId).toBe('entity-ra6-new');
  });

  // ── RA7: double re-anchor A→B, B→C → active is C's anchor ───────────

  test('RA7 double re-anchor A→B then B→C → getActiveAnchor returns C anchor', async () => {
    await seedTurn(db, 'turn-ra7');
    await seedEntity(db, 'entity-ra7-a', 'job');
    await seedEntity(db, 'entity-ra7-b', 'site');
    await seedEntity(db, 'entity-ra7-c', 'customer');
    await seedAnchor(db, 'turn-ra7', 'entity-ra7-a', 'job');

    // First re-anchor: A → B
    const r1 = await reAnchorTurn(db, validReq('turn-ra7', 'entity-ra7-b', { newEntityKind: 'site' }));
    expect(r1.ok).toBe(true);

    // Second re-anchor: B → C
    const r2 = await reAnchorTurn(db, validReq('turn-ra7', 'entity-ra7-c', { newEntityKind: 'customer' }));
    expect(r2.ok).toBe(true);

    const active = await getActiveAnchor(db, 'turn-ra7');
    expect(active).not.toBeNull();
    expect(active!.payload.targetId).toBe('entity-ra7-c');
  });

  // ── RA8: getActiveAnchor with no anchors → null ───────────

  test('RA8 getActiveAnchor with no BELONGS_TO_ENTITY relations → null', async () => {
    await seedTurn(db, 'turn-ra8');

    const active = await getActiveAnchor(db, 'turn-ra8');
    expect(active).toBeNull();
  });
});

```
