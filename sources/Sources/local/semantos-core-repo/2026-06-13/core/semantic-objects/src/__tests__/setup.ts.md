---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantic-objects/src/__tests__/setup.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.937276+00:00
---

# core/semantic-objects/src/__tests__/setup.ts

```ts
/**
 * PGlite-backed test harness for semantic-objects.
 */
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { readFileSync } from 'node:fs';
import type { Database } from '../types.js';

const MIGRATION_PATH = new URL('../../migrations/0000_init.sql', import.meta.url).pathname;

export async function makeTestDb(): Promise<{ db: Database; close: () => Promise<void> }> {
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

```
