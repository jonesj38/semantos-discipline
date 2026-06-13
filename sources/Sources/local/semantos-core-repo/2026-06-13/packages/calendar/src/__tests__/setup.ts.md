---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/__tests__/setup.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.481370+00:00
---

# packages/calendar/src/__tests__/setup.ts

```ts
/**
 * PGlite test harness. Runs the semantic-objects migration then seeds a
 * schedule object + a few hats.
 */
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import type { Database } from '@semantos/semantic-objects';
import { readFileSync } from 'node:fs';
import { seedAll } from '../db/seed.js';

const SEM_OBJECTS_MIGRATION = new URL(
  '../../../../core/semantic-objects/migrations/0000_init.sql',
  import.meta.url,
).pathname;

export async function makeTestDb(opts: { withTestSchedule?: boolean } = {}): Promise<{
  db: Database;
  close: () => Promise<void>;
}> {
  const pg = new PGlite();
  await pg.waitReady;
  const db = drizzle(pg) as unknown as Database;
  const sql = readFileSync(SEM_OBJECTS_MIGRATION, 'utf-8');
  for (const stmt of splitSql(sql)) {
    const s = stmt.trim();
    if (!s) continue;
    await pg.exec(s);
  }
  if (opts.withTestSchedule ?? true) {
    await seedTestFixture(db);
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

/**
 * Canonical fixture: one schedule object + Todd topology +
 * `other-operator` root for isolation tests.
 */
export async function seedTestFixture(db: Database): Promise<void> {
  await seedAll(db, {
    ownerCertId: 'cert-todd',
    timezone: 'Australia/Brisbane',
    scheduleObjectId: 'schedule-primary',
    operatorHatId: 'todd-operator',
    operatorDisplayName: 'Todd',
    childHats: [
      { id: 'todd-handyman', displayName: 'Todd (handyman)' },
      { id: 'todd-advisor', displayName: 'Todd (advisor)' },
    ],
  });
}

export function d(isoOrDate: string | Date): Date {
  return isoOrDate instanceof Date ? isoOrDate : new Date(isoOrDate);
}

```
