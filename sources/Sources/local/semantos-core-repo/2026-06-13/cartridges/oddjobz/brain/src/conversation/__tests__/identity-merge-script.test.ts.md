---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/identity-merge-script.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.535175+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/identity-merge-script.test.ts

```ts
/**
 * D-OJ-conv-identity-merge-endpoint — integration tests for identity-merge-script.ts.
 *
 * Exercises the bun subprocess (identity-merge-script.ts) end-to-end by
 * spawning it with synthetic stdin and checking stdout.
 *
 * Guard: skipped when DATABASE_URL is not set (CI / dev environments
 * without a Postgres instance).
 *
 * Test matrix:
 *   IMS1 — operatorConfirmed=false → { ok:false, error:"not_confirmed" }
 *   IMS2 — same source and target  → { ok:false, error:"same_identity" }
 *   IMS3 — valid merge             → { ok:true, mergeId:string, chain:[src,tgt] }
 *   IMS4 — repeat merge (idempotent) → { ok:true, chain:[src,tgt] }
 *   IMS5 — process exits (doesn't hang) — implicit from test timeout
 */

import { describe, test, expect } from 'bun:test';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// ── Guard: skip when no DATABASE_URL ─────────────────────────────────────────

const DB_URL = process.env.DATABASE_URL;
if (!DB_URL) {
  console.log('skip: no DATABASE_URL — identity-merge-script integration tests skipped');
  process.exit(0);
}

// ── Script path ───────────────────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = join(__dirname, '../identity-merge-script.ts');

// ── Helper: unique participant id ─────────────────────────────────────────────

let _counter = 0;
function uniqueId(prefix: string): string {
  return `${prefix}-ims-${Date.now()}-${++_counter}`;
}

// ── Helper: seed a participant row directly via DATABASE_URL ──────────────────
//
// The script itself only reads/writes via processIdentityMerge → DB, so we
// need participant rows to exist before running a real merge.  We seed them
// using the same @semantos/semantic-objects `createObject` used in tests.

import { getDatabaseOrNull, resetDatabaseSingleton } from '../db.js';
import { createObject } from '@semantos/semantic-objects';

async function seedParticipant(id: string): Promise<void> {
  const db = getDatabaseOrNull();
  if (!db) throw new Error('No DB for seeding');
  await createObject(db, {
    id,
    objectKind: 'oddjobz.conversation.participant',
    payload: { participantId: id },
  });
}

// ── Helper: run the subprocess, return parsed stdout ─────────────────────────

interface ScriptInput {
  sourceParticipantId: string;
  targetParticipantId: string;
  challengeQuestion: string;
  challengeAnswer: string;
  operatorConfirmed: boolean;
}

async function runScript(input: ScriptInput): Promise<unknown> {
  const proc = Bun.spawn(['bun', 'run', SCRIPT_PATH], {
    stdin: 'pipe',
    stdout: 'pipe',
    stderr: 'inherit',
    env: { ...process.env, DATABASE_URL: DB_URL! },
  });

  proc.stdin.write(JSON.stringify(input));
  proc.stdin.end();

  const raw = await new Response(proc.stdout).text();
  await proc.exited;

  return JSON.parse(raw.trim());
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('identity-merge-script integration', () => {
  // Reset the DB singleton before each test so seeding picks up fresh state.
  // (resetDatabaseSingleton is exported from db.ts for tests.)
  // Note: We don't close the connection between tests — the singleton is
  // process-local and postgres.js will be force-exited by the script anyway.

  test('IMS1: operatorConfirmed=false → { ok:false, error:"not_confirmed" }', async () => {
    const src = uniqueId('src');
    const tgt = uniqueId('tgt');
    await seedParticipant(src);
    await seedParticipant(tgt);

    const result = await runScript({
      sourceParticipantId: src,
      targetParticipantId: tgt,
      challengeQuestion: 'What suburb?',
      challengeAnswer: 'Newtown',
      operatorConfirmed: false,
    });

    expect(result).toMatchObject({ ok: false, error: 'not_confirmed' });
  });

  test('IMS2: same source and target → { ok:false, error:"same_identity" }', async () => {
    const id = uniqueId('same');
    await seedParticipant(id);

    const result = await runScript({
      sourceParticipantId: id,
      targetParticipantId: id,
      challengeQuestion: 'What suburb?',
      challengeAnswer: 'Newtown',
      operatorConfirmed: true,
    });

    expect(result).toMatchObject({ ok: false, error: 'same_identity' });
  });

  test('IMS3: valid merge → { ok:true, mergeId, chain:[src,tgt] }', async () => {
    const src = uniqueId('src');
    const tgt = uniqueId('tgt');
    await seedParticipant(src);
    await seedParticipant(tgt);

    const result = await runScript({
      sourceParticipantId: src,
      targetParticipantId: tgt,
      challengeQuestion: 'What suburb?',
      challengeAnswer: 'Newtown',
      operatorConfirmed: true,
    }) as { ok: boolean; mergeId?: string; chain?: string[] };

    expect(result.ok).toBe(true);
    expect(typeof result.mergeId).toBe('string');
    expect(result.mergeId!.length).toBeGreaterThan(0);
    expect(Array.isArray(result.chain)).toBe(true);
    expect(result.chain).toContain(src);
    expect(result.chain).toContain(tgt);
  });

  test('IMS4: repeat merge (idempotent) → ok:true', async () => {
    const src = uniqueId('src');
    const tgt = uniqueId('tgt');
    await seedParticipant(src);
    await seedParticipant(tgt);

    const input: ScriptInput = {
      sourceParticipantId: src,
      targetParticipantId: tgt,
      challengeQuestion: 'What suburb?',
      challengeAnswer: 'Newtown',
      operatorConfirmed: true,
    };

    // First merge.
    const first = await runScript(input) as { ok: boolean };
    expect(first.ok).toBe(true);

    // Repeat (already_merged → idempotent ok:true).
    const second = await runScript(input) as { ok: boolean; chain?: string[] };
    expect(second.ok).toBe(true);
    expect(Array.isArray(second.chain)).toBe(true);
  });

  test('IMS5: process exits without hanging', async () => {
    const src = uniqueId('src');
    const tgt = uniqueId('tgt');
    await seedParticipant(src);
    await seedParticipant(tgt);

    const proc = Bun.spawn(['bun', 'run', SCRIPT_PATH], {
      stdin: 'pipe',
      stdout: 'pipe',
      stderr: 'inherit',
      env: { ...process.env, DATABASE_URL: DB_URL! },
    });

    proc.stdin.write(
      JSON.stringify({
        sourceParticipantId: src,
        targetParticipantId: tgt,
        challengeQuestion: 'Q',
        challengeAnswer: 'A',
        operatorConfirmed: true,
      }),
    );
    proc.stdin.end();

    // Should exit within 10 seconds.
    const exitCode = await Promise.race([
      proc.exited,
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error('subprocess did not exit within 10s')), 10_000),
      ),
    ]);

    expect(exitCode).toBe(0);
  });
});

```
