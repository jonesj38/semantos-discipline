---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/ensure-lead-job.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.513465+00:00
---

# cartridges/oddjobz/brain/src/__tests__/ensure-lead-job.test.ts

```ts
/**
 * SD2 incr.1 ensure-lead-job conformance.
 *
 * Pins lead-on-contact: the genesis `jobs.create` (`add job "<name>"
 * lead`) the proven accept_rom seam needs to have a job to flip
 * lead→qualified. Exactly-once guard (persisted `leadJobCreated`),
 * no-name guard, name sanitisation (the brain `splitArgs` `"…"`
 * tokeniser breaks on embedded `"`/newlines), REPL wire shape, and
 * surfaced (not silent) failure. Deps-injected ⇒ ZERO live,
 * worktree-runnable. Additive/best-effort: a throw is the
 * intake-handler's to log; the reply + jsonl shadow are unaffected.
 */

import { describe, expect, test } from 'bun:test';
import {
  ensureLeadJob,
  sanitizeCustomerName,
  type EnsureLeadJobDeps,
} from '../conversation/ensure-lead-job.js';
import type { AccumulatedJobState } from '../conversation/accumulated-job-state.js';

const baseState = (
  over: Partial<AccumulatedJobState> = {},
): AccumulatedJobState =>
  ({
    customerName: 'Jenny Carter',
    customerPhone: '0498765432',
    suburb: 'Buderim',
    jobType: 'painting',
    scopeDescription: 'repaint two bedrooms, good condition',
    estimatePresented: false,
    ...over,
  }) as unknown as AccumulatedJobState;

function mkDeps(
  over: Partial<EnsureLeadJobDeps> = {},
): EnsureLeadJobDeps & { posted: { url: string; body: string }[] } {
  const posted: { url: string; body: string }[] = [];
  return {
    posted,
    brainReplUrl: 'https://oddjobtodd.info/api/v1/repl',
    brainBearer: 'beef'.repeat(16),
    fetchFn: async (url, init) => {
      posted.push({ url, body: init.body });
      return {
        status: 200,
        text: async () =>
          '{"id":"job-abc","customer_name":"Jenny Carter","state":"lead","status":"created"}',
      };
    },
    ...over,
  };
}

describe('sanitizeCustomerName', () => {
  test('strips quotes/newlines, collapses whitespace, caps length', () => {
    expect(sanitizeCustomerName('Jenny "JC" Carter')).toBe('Jenny JC Carter');
    expect(sanitizeCustomerName('  a\n\tb   c ')).toBe('a b c');
    expect(sanitizeCustomerName('x'.repeat(200)).length).toBe(120);
  });
});

describe('ensureLeadJob — guards (cannot regress reply/shadow)', () => {
  test('already created ⇒ skipped, NO POST', async () => {
    const d = mkDeps();
    const r = await ensureLeadJob(baseState({ leadJobCreated: true }), d);
    expect(r).toEqual({ created: false, skipped: 'already_created' });
    expect(d.posted).toHaveLength(0);
  });

  test('no customer name ⇒ skipped, NO POST', async () => {
    const d = mkDeps();
    const r = await ensureLeadJob(baseState({ customerName: null }), d);
    expect(r).toEqual({ created: false, skipped: 'no_customer_name' });
    expect(d.posted).toHaveLength(0);
  });
});

describe('ensureLeadJob — genesis create', () => {
  test('POSTs add job "<name>" lead with bearer; returns created', async () => {
    const d = mkDeps();
    const r = await ensureLeadJob(baseState(), d);
    expect(r.created).toBe(true);
    expect(d.posted).toHaveLength(1);
    expect(d.posted[0].url).toBe('https://oddjobtodd.info/api/v1/repl');
    const cmd = (JSON.parse(d.posted[0].body) as { cmd: string }).cmd;
    expect(cmd).toBe('add job "Jenny Carter" lead');
  });

  test('name with embedded quote is sanitised into the REPL cmd', async () => {
    const d = mkDeps();
    await ensureLeadJob(baseState({ customerName: 'Bob "The Builder"' }), d);
    const cmd = (JSON.parse(d.posted[0].body) as { cmd: string }).cmd;
    // No raw " inside the name slot ⇒ splitArgs keeps it one token.
    expect(cmd).toBe('add job "Bob The Builder" lead');
  });

  test('HTTP non-2xx ⇒ throws (surfaced, intake-handler logs it)', async () => {
    const d = mkDeps({
      fetchFn: async () => ({ status: 503, text: async () => 'down' }),
    });
    await expect(ensureLeadJob(baseState(), d)).rejects.toThrow(
      /jobs\.create HTTP 503/,
    );
  });

  test('dispatch failure / cap rejection body ⇒ throws (not silent-created)', async () => {
    const d = mkDeps({
      fetchFn: async () => ({
        status: 200,
        text: async () => 'jobs.create: dispatch failed: capability_denied',
      }),
    });
    await expect(ensureLeadJob(baseState(), d)).rejects.toThrow(
      /jobs\.create rejected/,
    );
  });
});

```
