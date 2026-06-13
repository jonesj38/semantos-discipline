---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/identity-merge.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.534217+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/identity-merge.test.ts

```ts
/**
 * D-OJ-conv-identity-merge — tests for `processIdentityMerge` and `followMerges`.
 *
 * Uses PGlite (in-memory postgres) following the pattern established in
 * per-turn-relation.test.ts and db-sinks.test.ts.
 *
 * Test matrix:
 *   IM1 — operatorConfirmed=false → { ok:false, reason:'challenge_not_confirmed' }
 *   IM2 — same source+target id   → { ok:false, reason:'same_identity' }
 *   IM3 — valid merge             → emits MERGES relation, { ok:true, relationId }
 *   IM4 — followMerges with no MERGES → returns [participantId] (self)
 *   IM5 — followMerges A→B         → returns [A, B]
 *   IM6 — followMerges transitive A→B→C → returns [A, B, C]
 *   IM7 — cycle guard A→B, B→A does not infinite loop
 *
 * Additional coverage:
 *   IM3b — already_merged guard: duplicate merge request → { ok:false, reason:'already_merged' }
 *   IM3c — challenge data stored in relation extra for audit trail
 */

import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createObject, type Database } from '@semantos/semantic-objects';
import { listRelationsFrom } from '@semantos/scg-relations';
import {
  processIdentityMerge,
  followMerges,
  type IdentityMergeRequest,
} from '../identity-merge.js';

// ────────────────────────────────────────────────────────────
// PGlite harness — mirrors per-turn-relation.test.ts
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

/** Seed a minimal sem_objects row for a participant id. The processIdentityMerge
 *  function operates on participant ids as sem_objects.id values, so we need
 *  them to exist in the table for createRelation to reference them. */
async function seedParticipant(db: Database, id: string): Promise<void> {
  await createObject(db, {
    id,
    objectKind: 'oddjobz.conversation.participant',
    payload: { participantId: id },
  });
}

/** Build a valid IdentityMergeRequest with operator confirmation. */
function validMergeReq(
  sourceParticipantId: string,
  targetParticipantId: string,
  overrides?: Partial<IdentityMergeRequest>,
): IdentityMergeRequest {
  return {
    sourceParticipantId,
    targetParticipantId,
    challengeQuestion: 'What was the address of your last job?',
    challengeAnswer: '42 Acacia Avenue, Springfield',
    operatorConfirmed: true,
    ...overrides,
  };
}

// ────────────────────────────────────────────────────────────
// processIdentityMerge tests
// ────────────────────────────────────────────────────────────

describe('processIdentityMerge', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  // ── IM1: operatorConfirmed=false ──────────────────────────

  test('IM1 operatorConfirmed=false → challenge_not_confirmed (no DB write)', async () => {
    await seedParticipant(db, 'participant-a');
    await seedParticipant(db, 'participant-b');

    const result = await processIdentityMerge(
      db,
      validMergeReq('participant-a', 'participant-b', { operatorConfirmed: false }),
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('challenge_not_confirmed');
    }

    // No relation should have been minted.
    const rels = await listRelationsFrom(db, 'participant-a', { kind: 'MERGES' });
    expect(rels).toHaveLength(0);
  });

  // ── IM2: same source and target ───────────────────────────

  test('IM2 same source+target id → same_identity (no DB write)', async () => {
    await seedParticipant(db, 'participant-same');

    const result = await processIdentityMerge(
      db,
      validMergeReq('participant-same', 'participant-same'),
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('same_identity');
    }

    const rels = await listRelationsFrom(db, 'participant-same', { kind: 'MERGES' });
    expect(rels).toHaveLength(0);
  });

  // ── IM3: valid merge ──────────────────────────────────────

  test('IM3 valid merge → emits MERGES relation, returns { ok:true, relationId }', async () => {
    await seedParticipant(db, 'participant-new');
    await seedParticipant(db, 'participant-canonical');

    const req = validMergeReq('participant-new', 'participant-canonical');
    const result = await processIdentityMerge(db, req);

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(typeof result.relationId).toBe('string');
      expect(result.relationId.length).toBeGreaterThan(0);
    }

    // Verify the relation was persisted with correct shape.
    const rels = await listRelationsFrom(db, 'participant-new', { kind: 'MERGES' });
    expect(rels).toHaveLength(1);
    expect(rels[0]!.payload.kind).toBe('MERGES');
    expect(rels[0]!.payload.sourceId).toBe('participant-new');
    expect(rels[0]!.payload.targetId).toBe('participant-canonical');
  });

  // ── IM3b: already_merged guard ────────────────────────────

  test('IM3b duplicate merge request → already_merged', async () => {
    await seedParticipant(db, 'participant-dup-src');
    await seedParticipant(db, 'participant-dup-tgt');

    const req = validMergeReq('participant-dup-src', 'participant-dup-tgt');

    // First merge succeeds.
    const first = await processIdentityMerge(db, req);
    expect(first.ok).toBe(true);

    // Second merge with same source+target is refused.
    const second = await processIdentityMerge(db, req);
    expect(second.ok).toBe(false);
    if (!second.ok) {
      expect(second.reason).toBe('already_merged');
    }

    // Still only one relation in the DB.
    const rels = await listRelationsFrom(db, 'participant-dup-src', { kind: 'MERGES' });
    expect(rels).toHaveLength(1);
  });

  // ── IM3c: challenge data in extra ─────────────────────────

  test('IM3c challenge question+answer stored in relation extra for audit trail', async () => {
    await seedParticipant(db, 'participant-audit-src');
    await seedParticipant(db, 'participant-audit-tgt');

    const req = validMergeReq('participant-audit-src', 'participant-audit-tgt', {
      challengeQuestion: 'What suburb was the last job in?',
      challengeAnswer: 'Newtown',
    });

    const result = await processIdentityMerge(db, req);
    expect(result.ok).toBe(true);

    const rels = await listRelationsFrom(db, 'participant-audit-src', { kind: 'MERGES' });
    expect(rels).toHaveLength(1);
    expect(rels[0]!.payload.extra?.['challengeQuestion']).toBe('What suburb was the last job in?');
    expect(rels[0]!.payload.extra?.['challengeAnswer']).toBe('Newtown');
  });
});

// ────────────────────────────────────────────────────────────
// followMerges tests
// ────────────────────────────────────────────────────────────

describe('followMerges', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  // ── IM4: no MERGES → self ─────────────────────────────────

  test('IM4 identity with no MERGES → returns [participantId] (self)', async () => {
    await seedParticipant(db, 'standalone-participant');

    const chain = await followMerges(db, 'standalone-participant');

    expect(chain).toHaveLength(1);
    expect(chain[0]).toBe('standalone-participant');
  });

  // ── IM5: A→B ─────────────────────────────────────────────

  test('IM5 A MERGES→B → followMerges(A) returns [A, B]', async () => {
    await seedParticipant(db, 'participant-fm-a');
    await seedParticipant(db, 'participant-fm-b');

    await processIdentityMerge(
      db,
      validMergeReq('participant-fm-a', 'participant-fm-b'),
    );

    const chain = await followMerges(db, 'participant-fm-a');

    expect(chain).toHaveLength(2);
    expect(chain[0]).toBe('participant-fm-a');
    expect(chain[1]).toBe('participant-fm-b');
  });

  // ── IM6: transitive A→B→C ────────────────────────────────

  test('IM6 transitive A→B→C → followMerges(A) returns [A, B, C]', async () => {
    await seedParticipant(db, 'participant-chain-a');
    await seedParticipant(db, 'participant-chain-b');
    await seedParticipant(db, 'participant-chain-c');

    await processIdentityMerge(
      db,
      validMergeReq('participant-chain-a', 'participant-chain-b'),
    );
    await processIdentityMerge(
      db,
      validMergeReq('participant-chain-b', 'participant-chain-c'),
    );

    const chain = await followMerges(db, 'participant-chain-a');

    expect(chain).toHaveLength(3);
    expect(chain[0]).toBe('participant-chain-a');
    expect(chain[1]).toBe('participant-chain-b');
    expect(chain[2]).toBe('participant-chain-c');
  });

  // ── IM7: cycle guard ──────────────────────────────────────

  test('IM7 cycle A→B and B→A does not infinite loop', async () => {
    await seedParticipant(db, 'participant-cycle-a');
    await seedParticipant(db, 'participant-cycle-b');

    // Create A→B and B→A relations directly via createRelation (bypassing
    // processIdentityMerge's already_merged guard, since A→B is not B→A).
    const { createRelation: _createRelation } = await import('@semantos/scg-relations');
    await _createRelation(db, {
      kind: 'MERGES',
      sourceId: 'participant-cycle-a',
      targetId: 'participant-cycle-b',
    });
    await _createRelation(db, {
      kind: 'MERGES',
      sourceId: 'participant-cycle-b',
      targetId: 'participant-cycle-a',
    });

    // Must not infinite loop and must return a finite result.
    const chain = await followMerges(db, 'participant-cycle-a');

    // Both ids should appear exactly once.
    expect(chain).toContain('participant-cycle-a');
    expect(chain).toContain('participant-cycle-b');
    // No duplicates.
    const unique = new Set(chain);
    expect(unique.size).toBe(chain.length);
    // Terminates — implicit by the test completing.
  });
});

```
