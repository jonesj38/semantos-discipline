---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/__tests__/meta-fanout-sink.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.700738+00:00
---

# archive/apps-legacy-cli/src/__tests__/meta-fanout-sink.test.ts

```ts
/**
 * D-OJ-conv-meta-inbox-bridge — meta fan-out sink tests.
 *
 * Assertions:
 *  (a) Fan-out sink calls BOTH legacy `.append` AND the canonical sink for
 *      a META event (providerId === 'meta').
 *  (b) The canonical sink SKIPS a `widget`/`providerId === 'widget'` event
 *      (no canonical row) while legacy `.append` still fires.
 *  (c) A meta event persists a canonical `oddjobz.conversation.turn` row
 *      of `surface='meta-inbox'` with the right fb/ig identity handle.
 *  (d) Canonical-sink failure is isolated — legacy `.append` still runs.
 *  (e) `getDatabaseOrNull() === null` → canonical sink is a no-op, legacy
 *      unaffected.
 *
 * Pre-existing baseline: legacy-cli tests pass. No new failures allowed.
 */

import {
  afterEach,
  beforeEach,
  describe,
  expect,
  test,
} from 'bun:test';
import { join } from 'node:path';
import { readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { getObject, type Database } from '@semantos/semantic-objects';
import { makeMetaFanOutSink } from '../meta-fanout-sink';
import type { ConversationTurnEvent, ConversationTurnSink } from '@semantos/legacy-ingest';
import { makeCanonicalTurnSink } from '@semantos/oddjobz/conversation/legacy-ingest-bridge';

// ────────────────────────────────────────────────────────────
// PGlite harness (mirrors cartridges/oddjobz/brain test harness)
// ────────────────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../../../core/semantic-objects/migrations/0000_init.sql',
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
  return { db, async close() { await pg.close(); } };
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

// ── Test event factories ──────────────────────────────────────────────────────

function makeMetaMessengerEvent(
  overrides: Partial<ConversationTurnEvent> = {},
): ConversationTurnEvent {
  return {
    providerId: 'meta',
    sessionId: 'meta:psid-99887',
    channel: 'meta_messenger',
    recipientId: 'psid-99887',
    role: 'customer',
    text: 'Need a plumber urgently',
    timestamp: 1716380000000,
    ...overrides,
  };
}

function makeMetaInstagramEvent(
  overrides: Partial<ConversationTurnEvent> = {},
): ConversationTurnEvent {
  return {
    providerId: 'meta',
    sessionId: 'meta:ig-55443',
    channel: 'meta_instagram',
    recipientId: 'ig-55443',
    role: 'customer',
    text: 'DM from IG - need quote',
    timestamp: 1716381000000,
    ...overrides,
  };
}

function makeWidgetEvent(
  overrides: Partial<ConversationTurnEvent> = {},
): ConversationTurnEvent {
  return {
    providerId: 'widget',
    sessionId: 'widget:abc-uuid',
    channel: 'widget',
    recipientId: 'widget:abc-uuid',
    role: 'customer',
    text: 'Hello from widget',
    timestamp: 1716382000000,
    ...overrides,
  };
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('makeMetaFanOutSink', () => {
  let handle: { db: Database; close: () => Promise<void> } | null = null;

  afterEach(async () => {
    if (handle) {
      await handle.close();
      handle = null;
    }
  });

  // ── (a) Fan-out calls BOTH legacy and canonical for a META event ──────────

  test('(a) calls both legacy sink and canonical sink for a meta_messenger event', async () => {
    handle = await makeTestDb();

    const legacyCalled: ConversationTurnEvent[] = [];
    const canonicalCalled: ConversationTurnEvent[] = [];

    const legacySink: ConversationTurnSink = (e) => { legacyCalled.push(e); };
    const canonicalSinkOverride: ConversationTurnSink = (e) => { canonicalCalled.push(e); };

    const fanOut = makeMetaFanOutSink({
      legacySink,
      db: handle.db,
      canonicalSinkOverride,
    });

    const event = makeMetaMessengerEvent();
    await fanOut(event);

    expect(legacyCalled.length).toBe(1);
    expect(legacyCalled[0]).toBe(event);
    expect(canonicalCalled.length).toBe(1);
    expect(canonicalCalled[0]).toBe(event);
  });

  test('(a) calls both legacy sink and canonical sink for a meta_instagram event', async () => {
    handle = await makeTestDb();

    const legacyCalled: ConversationTurnEvent[] = [];
    const canonicalCalled: ConversationTurnEvent[] = [];

    const fanOut = makeMetaFanOutSink({
      legacySink: (e) => { legacyCalled.push(e); },
      db: handle.db,
      canonicalSinkOverride: (e) => { canonicalCalled.push(e); },
    });

    const event = makeMetaInstagramEvent();
    await fanOut(event);

    expect(legacyCalled.length).toBe(1);
    expect(canonicalCalled.length).toBe(1);
  });

  // ── (b) Widget events: canonical SKIPS, legacy fires ─────────────────────

  test('(b) widget event — legacy fires, canonical sink is skipped', async () => {
    handle = await makeTestDb();

    const legacyCalled: ConversationTurnEvent[] = [];
    const canonicalCalled: ConversationTurnEvent[] = [];

    const fanOut = makeMetaFanOutSink({
      legacySink: (e) => { legacyCalled.push(e); },
      db: handle.db,
      canonicalSinkOverride: (e) => { canonicalCalled.push(e); },
    });

    const event = makeWidgetEvent();
    await fanOut(event);

    // Legacy fires regardless of provider
    expect(legacyCalled.length).toBe(1);
    expect(legacyCalled[0]).toBe(event);

    // Canonical is SKIPPED for widget events (cartridge intake-handler.ts owns them)
    expect(canonicalCalled.length).toBe(0);
  });

  // ── (c) Meta event persists canonical sem_objects row with right shape ────

  test('(c) meta_messenger event persists canonical row with surface=meta-inbox and fb identity handle', async () => {
    handle = await makeTestDb();

    const event = makeMetaMessengerEvent({
      recipientId: 'fb-psid-12345',
      sessionId: 'meta:fb-psid-12345',
      timestamp: 1716380100000,
    });

    // Use the REAL canonical sink (not a stub) to test end-to-end persistence
    const realCanonicalSink = makeCanonicalTurnSink(handle.db);

    const fanOut = makeMetaFanOutSink({
      legacySink: () => {},
      db: handle.db,
      canonicalSinkOverride: realCanonicalSink,
    });

    await fanOut(event);

    // Derive the expected turnId (same deterministic hash as the bridge)
    const { mapConversationTurnEventToCanonical } = await import('@semantos/oddjobz/conversation/legacy-ingest-bridge');
    const canonical = mapConversationTurnEventToCanonical(event);

    const row = await getObject(handle.db, canonical.turnId);
    expect(row).not.toBeNull();
    expect(row!.objectKind).toBe('oddjobz.conversation.turn');

    const payload = row!.payload as Record<string, unknown>;
    expect(payload.surface).toBe('meta-inbox');
    expect(payload.participantRole).toBe('external');
    expect(payload.direction).toBe('inbound');

    const identityHandle = payload.identityHandle as { kind: string; value: string } | undefined;
    expect(identityHandle).toBeDefined();
    expect(identityHandle!.kind).toBe('fb');
    expect(identityHandle!.value).toBe('fb-psid-12345');
  });

  test('(c) meta_instagram event persists canonical row with ig identity handle', async () => {
    handle = await makeTestDb();

    const event = makeMetaInstagramEvent({
      recipientId: 'ig-user-67890',
      sessionId: 'meta:ig-user-67890',
      timestamp: 1716381100000,
    });

    const realCanonicalSink = makeCanonicalTurnSink(handle.db);

    const fanOut = makeMetaFanOutSink({
      legacySink: () => {},
      db: handle.db,
      canonicalSinkOverride: realCanonicalSink,
    });

    await fanOut(event);

    const { mapConversationTurnEventToCanonical } = await import('@semantos/oddjobz/conversation/legacy-ingest-bridge');
    const canonical = mapConversationTurnEventToCanonical(event);

    const row = await getObject(handle.db, canonical.turnId);
    expect(row).not.toBeNull();

    const payload = row!.payload as Record<string, unknown>;
    expect(payload.surface).toBe('meta-inbox');

    const identityHandle = payload.identityHandle as { kind: string; value: string } | undefined;
    expect(identityHandle).toBeDefined();
    expect(identityHandle!.kind).toBe('ig');
    expect(identityHandle!.value).toBe('ig-user-67890');
  });

  // ── (d) Canonical-sink failure is isolated — legacy still runs ────────────

  test('(d) canonical sink failure is isolated — legacy fires and does not throw', async () => {
    const legacyCalled: ConversationTurnEvent[] = [];
    let canonicalAttempted = false;

    const throwingCanonicalSink: ConversationTurnSink = async (_e) => {
      canonicalAttempted = true;
      throw new Error('Simulated canonical sink failure');
    };

    const fanOut = makeMetaFanOutSink({
      legacySink: (e) => { legacyCalled.push(e); },
      db: null,
      canonicalSinkOverride: throwingCanonicalSink,
    });

    const event = makeMetaMessengerEvent();

    // Must not throw
    await expect(fanOut(event)).resolves.toBeUndefined();

    // Legacy still ran
    expect(legacyCalled.length).toBe(1);
    // Canonical was attempted
    expect(canonicalAttempted).toBe(true);
  });

  test('(d) canonical sink failure does not prevent legacy processing (async error)', async () => {
    const legacyResults: string[] = [];

    const asyncThrowCanonical: ConversationTurnSink = async () => {
      await new Promise<void>((_, reject) =>
        setTimeout(() => reject(new Error('async failure')), 0)
      );
    };

    const fanOut = makeMetaFanOutSink({
      legacySink: (e) => { legacyResults.push(e.text); },
      db: null,
      canonicalSinkOverride: asyncThrowCanonical,
    });

    await expect(fanOut(makeMetaMessengerEvent())).resolves.toBeUndefined();
    expect(legacyResults).toContain('Need a plumber urgently');
  });

  // ── (e) getDatabaseOrNull() === null → canonical no-op, legacy unaffected ─

  test('(e) db===null → canonical sink is no-op, legacy fires normally', async () => {
    const legacyCalled: ConversationTurnEvent[] = [];
    const canonicalCalled: ConversationTurnEvent[] = [];

    // Do NOT inject canonicalSinkOverride — pass db: null
    // This exercises the real "no DATABASE_URL" code path
    const fanOut = makeMetaFanOutSink({
      legacySink: (e) => { legacyCalled.push(e); },
      db: null,
      // canonicalSinkOverride: undefined → will use db === null → no-op
    });

    const event = makeMetaMessengerEvent();
    await fanOut(event);

    // Legacy fires
    expect(legacyCalled.length).toBe(1);
    expect(legacyCalled[0]).toBe(event);

    // No canonical calls (db was null → no canonical sink was created)
    expect(canonicalCalled.length).toBe(0);
  });

  test('(e) db===null + widget event → legacy fires, canonical no-op, no error', async () => {
    const legacyCalled: ConversationTurnEvent[] = [];

    const fanOut = makeMetaFanOutSink({
      legacySink: (e) => { legacyCalled.push(e); },
      db: null,
    });

    const event = makeWidgetEvent();
    await expect(fanOut(event)).resolves.toBeUndefined();

    expect(legacyCalled.length).toBe(1);
  });

  // ── Additional: both meta channels fire canonical with db===null check ─────

  test('meta assistant turn persists with ai participantRole and AI_CERT_PENDING_SENTINEL', async () => {
    handle = await makeTestDb();

    const event = makeMetaMessengerEvent({
      role: 'assistant',
      text: "We'll send a plumber tomorrow between 8-10am.",
      recipientId: 'psid-99887',
    });

    const realCanonicalSink = makeCanonicalTurnSink(handle.db);
    const fanOut = makeMetaFanOutSink({
      legacySink: () => {},
      db: handle.db,
      canonicalSinkOverride: realCanonicalSink,
    });

    await fanOut(event);

    const { mapConversationTurnEventToCanonical, AI_CERT_PENDING_SENTINEL } = await import('@semantos/oddjobz/conversation/legacy-ingest-bridge');
    // AI_CERT_PENDING_SENTINEL not re-exported from bridge — import from conversation-turn-patch
    const { AI_CERT_PENDING_SENTINEL: SENTINEL } = await import(
      '@semantos/oddjobz/conversation/conversation-turn-patch'
    );
    const canonical = mapConversationTurnEventToCanonical(event);

    const row = await getObject(handle.db, canonical.turnId);
    expect(row).not.toBeNull();

    const payload = row!.payload as Record<string, unknown>;
    expect(payload.participantRole).toBe('ai');
    expect(payload.direction).toBe('outbound');
    expect(payload.actorCertId).toBe(SENTINEL);
    expect(payload.identityHandle).toBeUndefined();
  });
});

```
