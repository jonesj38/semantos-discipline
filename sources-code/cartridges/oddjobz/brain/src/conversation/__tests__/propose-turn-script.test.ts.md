---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/propose-turn-script.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.542148+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/propose-turn-script.test.ts

```ts
/**
 * D-OJ-conv-propose-outbound — unit tests for propose-turn-script.ts
 * and customer-link.ts helpers.
 *
 * Test matrix:
 *   PT1 — missing conversationId in stdin → { ok: false }
 *   PT2 — valid propose → { ok: true, turnId, state: 'proposed' }
 *   PT3 — persisted turn has correct outboundState: 'proposed'
 *   PT4 — persisted turn has correct recipientHandle
 *   PT5 — persisted turn has correct includeCustomerLink
 *   PT6 — customer-link.ts createCustomerLink + resolveCustomerLink round-trip
 *
 * Guard: skipped when DATABASE_URL is not set.
 */

import { describe, test, expect } from 'bun:test';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// ── Guard: skip when no DATABASE_URL ─────────────────────────────────────────

const DB_URL = process.env.DATABASE_URL;
if (!DB_URL) {
  console.log('skip: no DATABASE_URL — propose-turn-script tests skipped');
  process.exit(0);
}

// ── Script path ───────────────────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = join(__dirname, '../propose-turn-script.ts');

// ── DB helpers ────────────────────────────────────────────────────────────────

import { getDatabaseOrNull, resetDatabaseSingleton } from '../db.js';
import { sql } from 'drizzle-orm';
import { createCustomerLink, resolveCustomerLink } from '../customer-link.js';
import type { OddjobzConversationTurnPayload } from '../conversation-turn-patch.js';

function uniqueId(prefix: string): string {
  return `${prefix}-pt-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

// ── Helper: run the propose-turn subprocess ───────────────────────────────────

interface ProposeTurnInput {
  conversationId?: string;
  surface?: string;
  bodyText?: string;
  participantRole?: string;
  recipientHandle?: { kind: string; value: string };
  includeCustomerLink?: boolean;
}

async function runScript(input: ProposeTurnInput): Promise<unknown> {
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

// ── Helper: read back the persisted turn payload ──────────────────────────────

async function getTurnPayload(turnId: string): Promise<OddjobzConversationTurnPayload | null> {
  const db = getDatabaseOrNull();
  if (!db) return null;
  const rows = await (db as any).execute(
    sql`SELECT payload FROM sem_objects WHERE id = ${turnId} LIMIT 1`,
  );
  const resultRows: Array<{ payload: unknown }> = Array.isArray(rows)
    ? rows
    : ((rows as any).rows ?? []);
  if (resultRows.length === 0) return null;
  return resultRows[0]!.payload as OddjobzConversationTurnPayload;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('propose-turn-script', () => {
  test('PT1: missing conversationId → { ok: false }', async () => {
    const result = await runScript({
      // conversationId deliberately omitted
      surface: 'sms',
      bodyText: 'Hello customer',
      participantRole: 'operator',
      recipientHandle: { kind: 'phone', value: '+61400000001' },
    });
    expect((result as any).ok).toBe(false);
  });

  test('PT2: valid propose → { ok: true, turnId, state: "proposed" }', async () => {
    const result = await runScript({
      conversationId: uniqueId('conv'),
      surface: 'sms',
      bodyText: 'Job confirmed for Tuesday',
      participantRole: 'operator',
      recipientHandle: { kind: 'phone', value: '+61400000002' },
    }) as { ok: boolean; turnId?: string; state?: string };

    expect(result.ok).toBe(true);
    expect(typeof result.turnId).toBe('string');
    expect(result.turnId!.length).toBeGreaterThan(0);
    expect(result.state).toBe('proposed');
  });

  test('PT3: persisted turn has outboundState: "proposed"', async () => {
    const result = await runScript({
      conversationId: uniqueId('conv'),
      surface: 'sms',
      bodyText: 'We are on our way',
      participantRole: 'operator',
      recipientHandle: { kind: 'phone', value: '+61400000003' },
    }) as { ok: boolean; turnId?: string };

    expect(result.ok).toBe(true);

    resetDatabaseSingleton();
    const payload = await getTurnPayload(result.turnId!);
    expect(payload).not.toBeNull();
    expect(payload!.outboundState).toBe('proposed');
  });

  test('PT4: persisted turn has correct recipientHandle', async () => {
    const phone = '+61400000004';
    const result = await runScript({
      conversationId: uniqueId('conv'),
      surface: 'sms',
      bodyText: 'Quote ready for review',
      participantRole: 'operator',
      recipientHandle: { kind: 'phone', value: phone },
    }) as { ok: boolean; turnId?: string };

    expect(result.ok).toBe(true);

    resetDatabaseSingleton();
    const payload = await getTurnPayload(result.turnId!);
    expect(payload).not.toBeNull();
    expect(payload!.recipientHandle).toEqual({ kind: 'phone', value: phone });
  });

  test('PT5: persisted turn has correct includeCustomerLink', async () => {
    const result = await runScript({
      conversationId: uniqueId('conv'),
      surface: 'widget',
      bodyText: 'Thanks for your enquiry',
      participantRole: 'operator',
      recipientHandle: { kind: 'phone', value: '+61400000005' },
      includeCustomerLink: true,
    }) as { ok: boolean; turnId?: string };

    expect(result.ok).toBe(true);

    resetDatabaseSingleton();
    const payload = await getTurnPayload(result.turnId!);
    expect(payload).not.toBeNull();
    expect(payload!.includeCustomerLink).toBe(true);
  });

  test('PT6: customer-link.ts createCustomerLink + resolveCustomerLink round-trip', async () => {
    resetDatabaseSingleton();
    const db = getDatabaseOrNull();
    if (!db) {
      console.log('skip PT6: no db handle');
      return;
    }

    const conversationId = uniqueId('conv');
    const entityTitle = 'job abc12345';

    const created = await createCustomerLink(db, conversationId, entityTitle);
    expect(typeof created.token).toBe('string');
    expect(created.token.length).toBeGreaterThanOrEqual(9);
    expect(created.url).toContain(created.token);
    expect(created.url).toContain('oddjobtodd.info');

    const resolved = await resolveCustomerLink(db, created.token);
    expect(resolved).not.toBeNull();
    expect(resolved!.conversationId).toBe(conversationId);
    expect(resolved!.entityTitle).toBe(entityTitle);
  });
});

```
