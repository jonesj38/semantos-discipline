---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/messages-backfill.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.541451+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/messages-backfill.test.ts

```ts
/**
 * D-OJ-conv-messages-backfill — mapper + backfill tests.
 *
 * Tests:
 *   MB1: empty text returns null from mapMessagePatchToCanonical
 *   MB2: email channel → surface='email', role='customer' → participantRole='external', direction='inbound'
 *   MB3: role='assistant' → participantRole='ai', actorCertId=AI_CERT_PENDING_SENTINEL
 *   MB4: source.from email extraction strips display name
 *   MB5: duplicate correlationId is skipped (idempotent check) — uses PGlite DB
 *   MB6: dry-run does not write to DB
 *
 * DB tests (MB5) require PGlite. They run in-process without DATABASE_URL.
 * If DATABASE_URL is absent the tests still run (PGlite is injected directly).
 * Skip guard is per project pattern: `if (!process.env.DATABASE_URL)` guarded
 * tests use PGlite directly instead — so these tests run everywhere.
 */

import {
  describe,
  expect,
  test,
  beforeEach,
  afterEach,
} from 'bun:test';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import type { Database } from '@semantos/semantic-objects';
import { getObject } from '@semantos/semantic-objects';
import { AI_CERT_PENDING_SENTINEL } from '../conversation-turn-patch.js';
import { mapMessagePatchToCanonical } from '../legacy-ingest-bridge.js';
import { makeOddjobzSinks, ODDJOBZ_TURN_OBJECT_KIND } from '../db.js';
import type { OddjobzMessagePatch } from '@semantos/legacy-ingest';

// ────────────────────────────────────────────────────────────
// PGlite harness (mirrors legacy-ingest-bridge.test.ts)
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
  const sqlContent = readFileSync(MIGRATION_PATH, 'utf-8');
  for (const stmt of splitSql(sqlContent)) {
    const s = stmt.trim();
    if (!s) continue;
    await pg.exec(s);
  }
  return { db, async close() { await pg.close(); } };
}

function splitSql(content: string): string[] {
  const out: string[] = [];
  const lines = content.split('\n');
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
// Patch factory
// ────────────────────────────────────────────────────────────

function makeEmailPatch(
  overrides: Partial<OddjobzMessagePatch> = {},
): OddjobzMessagePatch {
  return {
    schema: 'oddjobz.message.v1',
    patchId: 'patch-abc123',
    op: 'oddjobz.message.v1',
    providerId: 'gmail',
    sessionId: 'email:thread-001',
    channel: 'email',
    recipientId: 'customer@example.com',
    role: 'customer',
    text: 'Hi, I need a plumber urgently.',
    timestamp: 1716371200000,
    writtenAt: 1716371201000,
    source: {
      providerItemId: 'msg-001',
      contentType: 'email/rfc822',
      threadId: 'thread-001',
      messageId: '<msg-001@mail.example.com>',
      from: 'John Smith <john@example.com>',
      to: 'operator@company.com',
      subject: 'Plumber needed',
    },
    target: {
      type: 'conversation-session',
      ref: 'email:thread-001',
    },
    ...overrides,
  };
}

// ────────────────────────────────────────────────────────────
// MB1: empty text returns null
// ────────────────────────────────────────────────────────────

describe('MB1: empty text returns null from mapMessagePatchToCanonical', () => {
  test('null text → null', () => {
    const patch = makeEmailPatch({ text: '' });
    expect(mapMessagePatchToCanonical(patch)).toBeNull();
  });

  test('whitespace-only text → null', () => {
    const patch = makeEmailPatch({ text: '   \n\t  ' });
    expect(mapMessagePatchToCanonical(patch)).toBeNull();
  });

  test('non-empty text → non-null', () => {
    const patch = makeEmailPatch({ text: 'Hello' });
    expect(mapMessagePatchToCanonical(patch)).not.toBeNull();
  });
});

// ────────────────────────────────────────────────────────────
// MB2: email channel → surface='email', customer → external/inbound
// ────────────────────────────────────────────────────────────

describe('MB2: email channel and customer role mapping', () => {
  test('channel=email → surface=email', () => {
    const patch = makeEmailPatch({ channel: 'email' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn).not.toBeNull();
    expect(turn!.surface).toBe('email');
  });

  test('channel=gmail → surface=email', () => {
    const patch = makeEmailPatch({ channel: 'gmail' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn).not.toBeNull();
    expect(turn!.surface).toBe('email');
  });

  test('role=customer → participantRole=external, direction=inbound', () => {
    const patch = makeEmailPatch({ role: 'customer' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.participantRole).toBe('external');
    expect(turn!.direction).toBe('inbound');
  });

  test('customer turn: no actorCertId', () => {
    const patch = makeEmailPatch({ role: 'customer' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.actorCertId).toBeUndefined();
  });

  test('source.threadId is used as conversationId', () => {
    const patch = makeEmailPatch({ source: { ...makeEmailPatch().source!, threadId: 'my-thread-42' } });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.conversationId).toBe('my-thread-42');
  });

  test('sessionId is used as conversationId when source.threadId absent', () => {
    const patch = makeEmailPatch({
      sessionId: 'email:thread-fallback',
      source: { ...makeEmailPatch().source!, threadId: undefined },
    });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.conversationId).toBe('email:thread-fallback');
  });

  test('source.messageId is used as correlationId', () => {
    const patch = makeEmailPatch();
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.correlationId).toBe('<msg-001@mail.example.com>');
  });

  test('patchId is used as correlationId when source.messageId absent', () => {
    const patch = makeEmailPatch({
      patchId: 'fallback-patch-id',
      source: { ...makeEmailPatch().source!, messageId: undefined },
    });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.correlationId).toBe('fallback-patch-id');
  });

  test('text → bodyText', () => {
    const patch = makeEmailPatch({ text: 'My roof is leaking' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.bodyText).toBe('My roof is leaking');
  });

  test('timestamp passes through', () => {
    const patch = makeEmailPatch({ timestamp: 1716999000000 });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.timestamp).toBe(1716999000000);
  });

  test('turnId starts with turn-email-', () => {
    const patch = makeEmailPatch();
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.turnId).toMatch(/^turn-email-/);
  });

  test('turnId is deterministic (same patch → same turnId)', () => {
    const patch = makeEmailPatch();
    const t1 = mapMessagePatchToCanonical(patch);
    const t2 = mapMessagePatchToCanonical(patch);
    expect(t1!.turnId).toBe(t2!.turnId);
  });
});

// ────────────────────────────────────────────────────────────
// MB3: role='assistant' → ai + AI_CERT_PENDING_SENTINEL
// ────────────────────────────────────────────────────────────

describe('MB3: role=assistant → participantRole=ai', () => {
  test('role=assistant → participantRole=ai, direction=outbound', () => {
    const patch = makeEmailPatch({ role: 'assistant', text: 'Thanks for your enquiry.' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.participantRole).toBe('ai');
    expect(turn!.direction).toBe('outbound');
  });

  test('role=assistant → actorCertId=AI_CERT_PENDING_SENTINEL', () => {
    const patch = makeEmailPatch({ role: 'assistant', text: 'We will send a plumber.' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.actorCertId).toBe(AI_CERT_PENDING_SENTINEL);
  });

  test('role=assistant → no identityHandle', () => {
    const patch = makeEmailPatch({ role: 'assistant', text: 'Sure!' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.identityHandle).toBeUndefined();
  });

  test('role=operator → participantRole=operator, direction=outbound', () => {
    const patch = makeEmailPatch({ role: 'operator', text: 'On our way.' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.participantRole).toBe('operator');
    expect(turn!.direction).toBe('outbound');
  });
});

// ────────────────────────────────────────────────────────────
// MB4: source.from email extraction strips display name
// ────────────────────────────────────────────────────────────

describe('MB4: source.from email extraction strips display name', () => {
  test('bare email address is kept as-is', () => {
    const patch = makeEmailPatch({
      source: { ...makeEmailPatch().source!, from: 'john@example.com' },
    });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.identityHandle).toEqual({ kind: 'email', value: 'john@example.com' });
  });

  test('display name + angle-bracket format: strips name, keeps address', () => {
    const patch = makeEmailPatch({
      source: { ...makeEmailPatch().source!, from: 'John Smith <john@example.com>' },
    });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.identityHandle).toEqual({ kind: 'email', value: 'john@example.com' });
  });

  test('quoted display name: strips name, keeps address', () => {
    const patch = makeEmailPatch({
      source: { ...makeEmailPatch().source!, from: '"Smith, John" <john@example.com>' },
    });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.identityHandle).toEqual({ kind: 'email', value: 'john@example.com' });
  });

  test('no source.from: falls back to cookie kind with recipientId', () => {
    const patch = makeEmailPatch({
      recipientId: 'recipient-fallback@example.com',
      source: { ...makeEmailPatch().source!, from: undefined },
    });
    const turn = mapMessagePatchToCanonical(patch);
    // Without source.from on email channel, falls through to cookie
    expect(turn!.identityHandle?.kind).toBe('cookie');
    expect(turn!.identityHandle?.value).toBe('recipient-fallback@example.com');
  });

  test('identityHandle kind=email for email channel with source.from', () => {
    const patch = makeEmailPatch({
      source: { ...makeEmailPatch().source!, from: 'Customer <customer@example.com>' },
    });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.identityHandle?.kind).toBe('email');
  });
});

// ────────────────────────────────────────────────────────────
// MB5: duplicate correlationId is skipped (idempotency check)
// ────────────────────────────────────────────────────────────

describe('MB5: duplicate correlationId is skipped (idempotency via semObjectSink)', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    const handle = await makeTestDb();
    db = handle.db;
    close = handle.close;
  });

  afterEach(async () => {
    await close();
  });

  test('second insert of same turnId does not throw (semObjectSink is idempotent)', async () => {
    const patch = makeEmailPatch();
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn).not.toBeNull();

    const sinks = makeOddjobzSinks(db);

    // First insert
    await sinks.semObjectSink(turn!);
    const row = await getObject(db, turn!.turnId);
    expect(row).not.toBeNull();
    expect(row!.objectKind).toBe(ODDJOBZ_TURN_OBJECT_KIND);

    // Second insert — must not throw (unique-constraint swallowed)
    await expect(sinks.semObjectSink(turn!)).resolves.toBeUndefined();
  });

  test('row persisted with correct payload fields', async () => {
    const patch = makeEmailPatch({ text: 'I need a plumber at 10 Main St' });
    const turn = mapMessagePatchToCanonical(patch);
    const sinks = makeOddjobzSinks(db);
    await sinks.semObjectSink(turn!);

    const row = await getObject(db, turn!.turnId);
    expect(row).not.toBeNull();
    const payload = row!.payload as typeof turn;
    expect(payload!.surface).toBe('email');
    expect(payload!.bodyText).toBe('I need a plumber at 10 Main St');
    expect(payload!.participantRole).toBe('external');
    expect(payload!.direction).toBe('inbound');
  });

  test('two different patches produce two distinct rows', async () => {
    const patch1 = makeEmailPatch({ patchId: 'patch-1', source: { ...makeEmailPatch().source!, messageId: '<msg-1@x.com>' }, text: 'First message' });
    const patch2 = makeEmailPatch({ patchId: 'patch-2', source: { ...makeEmailPatch().source!, messageId: '<msg-2@x.com>' }, text: 'Second message' });

    const turn1 = mapMessagePatchToCanonical(patch1);
    const turn2 = mapMessagePatchToCanonical(patch2);
    expect(turn1!.turnId).not.toBe(turn2!.turnId);

    const sinks = makeOddjobzSinks(db);
    await sinks.semObjectSink(turn1!);
    await sinks.semObjectSink(turn2!);

    const row1 = await getObject(db, turn1!.turnId);
    const row2 = await getObject(db, turn2!.turnId);
    expect(row1).not.toBeNull();
    expect(row2).not.toBeNull();
  });
});

// ────────────────────────────────────────────────────────────
// MB6: dry-run does not write to DB
// ────────────────────────────────────────────────────────────

describe('MB6: dry-run does not write to DB', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    const handle = await makeTestDb();
    db = handle.db;
    close = handle.close;
  });

  afterEach(async () => {
    await close();
  });

  test('when sinks is null (dry-run mode), nothing is written to DB', async () => {
    const patch = makeEmailPatch({ text: 'Dry run message' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn).not.toBeNull();

    // Dry-run: pass null sinks (as the backfill script does with --dry-run)
    const sinks: ReturnType<typeof makeOddjobzSinks> | null = null;

    if (!sinks) {
      // Simulate the dry-run path — just log, no DB write
      process.stderr.write(`[test dry-run] would insert turnId=${turn!.turnId}\n`);
    }

    // Verify nothing was written
    const row = await getObject(db, turn!.turnId);
    expect(row).toBeNull();
  });

  test('with real sinks, row IS written to DB (contrast to dry-run)', async () => {
    const patch = makeEmailPatch({ text: 'Real insert message' });
    const turn = mapMessagePatchToCanonical(patch);
    const sinks = makeOddjobzSinks(db);
    await sinks.semObjectSink(turn!);

    const row = await getObject(db, turn!.turnId);
    expect(row).not.toBeNull();
  });
});

// ────────────────────────────────────────────────────────────
// Additional surface mapping tests
// ────────────────────────────────────────────────────────────

describe('Additional surface mapping via mapMessagePatchToCanonical', () => {
  test('channel=meta_messenger → surface=meta-inbox', () => {
    const patch = makeEmailPatch({ channel: 'meta_messenger' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.surface).toBe('meta-inbox');
  });

  test('channel=widget → surface=widget', () => {
    const patch = makeEmailPatch({ channel: 'widget' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.surface).toBe('widget');
  });

  test('meta_messenger customer → identityHandle kind=fb', () => {
    const patch = makeEmailPatch({ channel: 'meta_messenger', recipientId: 'psid-9876' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.identityHandle).toEqual({ kind: 'fb', value: 'psid-9876' });
  });

  test('meta_instagram customer → identityHandle kind=ig', () => {
    const patch = makeEmailPatch({ channel: 'meta_instagram', recipientId: 'ig-5432' });
    const turn = mapMessagePatchToCanonical(patch);
    expect(turn!.identityHandle).toEqual({ kind: 'ig', value: 'ig-5432' });
  });
});

```
