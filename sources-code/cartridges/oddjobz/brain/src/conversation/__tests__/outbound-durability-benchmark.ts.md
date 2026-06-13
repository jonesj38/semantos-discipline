---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/outbound-durability-benchmark.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.536782+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/outbound-durability-benchmark.ts

```ts
/**
 * D-OJ-conv-outbound-routing — outbound durability benchmark.
 *
 * Addresses open question 13.6: where do async delivery callbacks
 * (`sent → delivered | failed`, arriving hours later from Twilio/SMTP/IG)
 * get persisted?
 *
 * Two candidates:
 *
 *   Option A (per-turn patch):
 *     UPDATE the `payload` JSONB on the existing sem_objects row for each
 *     state transition. One row per turn; state is embedded in the payload.
 *
 *   Option C (sidecar table):
 *     A lightweight `outbound_delivery_cursors` table (columns: turn_id TEXT PK,
 *     outbound_state TEXT, updated_at TIMESTAMPTZ, error TEXT). Upsert one row
 *     per delivery callback. The sem_objects turn row is never mutated.
 *
 * Benchmark:
 *   N=500 simulated delivery-callback writes under each option.
 *   Measures median + p95 write latency in ms.
 *
 * Decision rule (from the brief):
 *   If within 2×, prefer Option A (simpler, fewer moving parts).
 *   If Option C is >2× faster, use Option C.
 *
 * Run with:
 *   cd cartridges/oddjobz/brain
 *   pnpm tsx src/conversation/__tests__/outbound-durability-benchmark.ts
 *
 * (Not a vitest/bun:test file — standalone script so it can print results.)
 */

import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sql } from 'drizzle-orm';

const __dirname = dirname(fileURLToPath(import.meta.url));

const MIGRATION_PATH = join(
  __dirname,
  '../../../../../../core/semantic-objects/migrations/0000_init.sql',
);

const N = 500;

// ── PGlite setup ──────────────────────────────────────────────────────────────

function splitSql(sqlText: string): string[] {
  const out: string[] = [];
  const lines = sqlText.split('\n');
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

async function makeDb() {
  const pg = new PGlite();
  await pg.waitReady;
  const db = drizzle(pg);
  const sqlText = readFileSync(MIGRATION_PATH, 'utf-8');
  for (const stmt of splitSql(sqlText)) {
    const s = stmt.trim();
    if (!s) continue;
    await pg.exec(s);
  }
  return { pg, db };
}

// ── Statistics ────────────────────────────────────────────────────────────────

function percentile(sortedMs: number[], p: number): number {
  const idx = Math.ceil((p / 100) * sortedMs.length) - 1;
  return sortedMs[Math.max(0, idx)];
}

function stats(latencies: number[]): { median: number; p95: number; mean: number } {
  const sorted = [...latencies].sort((a, b) => a - b);
  return {
    median: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    mean: Math.round((latencies.reduce((a, b) => a + b, 0) / latencies.length) * 100) / 100,
  };
}

// ── Seed sem_objects rows (both options need existing rows) ───────────────────

async function seedTurns(pg: PGlite, n: number): Promise<string[]> {
  const ids: string[] = [];
  for (let i = 0; i < n; i++) {
    const id = `turn-bench-${i.toString().padStart(4, '0')}`;
    ids.push(id);
    await pg.exec(
      `INSERT INTO sem_objects (id, object_kind, payload)
       VALUES ('${id}', 'oddjobz.conversation.turn',
         '{"turnId":"${id}","direction":"outbound","outboundState":"sent"}'::jsonb)
       ON CONFLICT (id) DO NOTHING`,
    );
  }
  return ids;
}

// ── Option A: UPDATE payload JSONB on sem_objects ─────────────────────────────

async function benchmarkOptionA(pg: PGlite, turnIds: string[]): Promise<number[]> {
  const latencies: number[] = [];
  const states = ['delivered', 'failed'] as const;

  for (let i = 0; i < turnIds.length; i++) {
    const id = turnIds[i];
    const state = states[i % 2];
    const start = performance.now();

    await pg.exec(
      `UPDATE sem_objects
         SET payload = jsonb_set(payload, '{outboundState}', '"${state}"'),
             updated_at = now()
       WHERE id = '${id}'`,
    );

    latencies.push(performance.now() - start);
  }

  return latencies;
}

// ── Option C: Upsert to sidecar table ────────────────────────────────────────

async function setupSidecarTable(pg: PGlite): Promise<void> {
  await pg.exec(`
    CREATE TABLE IF NOT EXISTS outbound_delivery_cursors (
      turn_id      TEXT PRIMARY KEY,
      outbound_state TEXT NOT NULL,
      updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
      error        TEXT
    )
  `);
}

async function benchmarkOptionC(pg: PGlite, turnIds: string[]): Promise<number[]> {
  const latencies: number[] = [];
  const states = ['delivered', 'failed'] as const;

  for (let i = 0; i < turnIds.length; i++) {
    const id = turnIds[i];
    const state = states[i % 2];
    const start = performance.now();

    await pg.exec(
      `INSERT INTO outbound_delivery_cursors (turn_id, outbound_state, updated_at)
       VALUES ('${id}', '${state}', now())
       ON CONFLICT (turn_id) DO UPDATE
         SET outbound_state = EXCLUDED.outbound_state,
             updated_at     = EXCLUDED.updated_at,
             error          = NULL`,
    );

    latencies.push(performance.now() - start);
  }

  return latencies;
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`\nOutbound durability benchmark — N=${N} writes each\n`);

  const { pg: pgA } = await makeDb();
  const { pg: pgC } = await makeDb();

  // Seed N rows into both databases.
  console.log('Seeding rows...');
  const idsA = await seedTurns(pgA, N);
  const idsC = await seedTurns(pgC, N);
  await setupSidecarTable(pgC);

  // Warm up (10 writes, discarded).
  for (let i = 0; i < 10; i++) {
    await pgA.exec(`UPDATE sem_objects SET updated_at = now() WHERE id = '${idsA[i]}'`);
    await pgC.exec(
      `INSERT INTO outbound_delivery_cursors (turn_id, outbound_state)
       VALUES ('${idsC[i]}', 'sent')
       ON CONFLICT (turn_id) DO UPDATE SET outbound_state = EXCLUDED.outbound_state`,
    );
  }

  console.log(`\nRunning Option A (UPDATE payload JSONB on sem_objects)...`);
  const latenciesA = await benchmarkOptionA(pgA, idsA);
  const statsA = stats(latenciesA);

  console.log(`Running Option C (upsert to sidecar outbound_delivery_cursors)...`);
  const latenciesC = await benchmarkOptionC(pgC, idsC);
  const statsC = stats(latenciesC);

  await pgA.close();
  await pgC.close();

  // ── Results ────────────────────────────────────────────────────────────────

  console.log('\n════════════════════════════════════════════════');
  console.log('RESULTS');
  console.log('════════════════════════════════════════════════');
  console.log(`Option A — UPDATE payload JSONB on sem_objects:`);
  console.log(`  median = ${statsA.median.toFixed(3)} ms`);
  console.log(`  p95    = ${statsA.p95.toFixed(3)} ms`);
  console.log(`  mean   = ${statsA.mean.toFixed(3)} ms`);
  console.log('');
  console.log(`Option C — upsert to sidecar outbound_delivery_cursors:`);
  console.log(`  median = ${statsC.median.toFixed(3)} ms`);
  console.log(`  p95    = ${statsC.p95.toFixed(3)} ms`);
  console.log(`  mean   = ${statsC.mean.toFixed(3)} ms`);
  console.log('');

  const medianRatioAoverC = statsA.median / statsC.median;
  const medianRatioCoverA = statsC.median / statsA.median;

  if (medianRatioAoverC <= 2) {
    console.log(
      `DECISION: Option A wins (or ties) — ratio A/C = ${medianRatioAoverC.toFixed(2)}× ` +
        `(within 2× threshold → prefer A for simplicity).`,
    );
    console.log('');
    console.log('Option A selected: UPDATE payload JSONB on sem_objects.');
  } else {
    console.log(
      `DECISION: Option C wins — C is ${medianRatioCoverA.toFixed(2)}× faster than A ` +
        `(>2× threshold → use C).`,
    );
    console.log('');
    console.log('Option C selected: upsert to sidecar outbound_delivery_cursors.');
  }

  console.log('════════════════════════════════════════════════\n');

  // Return structured result for programmatic use (e.g. from tests).
  return {
    optionA: statsA,
    optionC: statsC,
    decision: medianRatioAoverC <= 2 ? 'A' : 'C',
    medianRatioAoverC,
  };
}

main().catch(err => {
  console.error('Benchmark failed:', err);
  process.exit(1);
});

```
