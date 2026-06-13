---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/chat-resolver.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.152942+00:00
---

# runtime/legacy-ingest/src/__tests__/chat-resolver.test.ts

```ts
/**
 * T9 — chat resolver conformance tests.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §TDD Gate / T9.
 *
 * The keystone PRD invariant: "quote 500 for the pergola job"
 * disambiguates to a single job_cell when exactly one open job
 * carries the 'pergola' service tag, ambiguous when ≥2 carry it,
 * and none when zero match.
 */

import { describe, test, expect } from 'bun:test';
import {
  resolveJobReference,
  extractServiceTags,
  detectIntent,
  extractMoneyAmounts,
  type JobsView,
  type JobSummary,
} from '../chat-resolver';

/* ──────────────────────────────────────────────────────────────────────
 * Test helpers
 * ────────────────────────────────────────────────────────────────────── */

function viewWith(jobs: readonly JobSummary[]): JobsView {
  return {
    async findActiveByServices(services) {
      if (services.length === 0) return jobs;
      const set = new Set(services);
      return jobs.filter(j => j.services.some(s => set.has(s)));
    },
  };
}

function jobWith(overrides: Partial<JobSummary> & { cellId: string }): JobSummary {
  return {
    cellId: overrides.cellId,
    services: overrides.services ?? [],
    state: overrides.state ?? 'lead',
    displayName: overrides.displayName,
    siteId: overrides.siteId ?? null,
    issuanceDate: overrides.issuanceDate ?? null,
  };
}

/* ──────────────────────────────────────────────────────────────────────
 * The keystone PRD example
 * ────────────────────────────────────────────────────────────────────── */

describe('T9 keystone: "quote 500 for the pergola job"', () => {
  test('single pergola job → unique match', async () => {
    const view = viewWith([
      jobWith({ cellId: 'A'.repeat(64), services: ['pergola'], state: 'quoted' }),
      jobWith({ cellId: 'B'.repeat(64), services: ['plumbing'], state: 'lead' }),
    ]);
    const r = await resolveJobReference({
      utterance: 'quote 500 for the pergola job',
      jobsView: view,
    });
    expect(r.kind).toBe('match');
    if (r.kind === 'match') {
      expect(r.cellId).toBe('A'.repeat(64));
      expect(r.intent).toBe('quote');
      expect(r.confidence).toBeGreaterThanOrEqual(0.9);
    }
  });

  test('two pergola jobs → ambiguous, surfaces both candidates', async () => {
    const view = viewWith([
      jobWith({ cellId: 'A'.repeat(64), services: ['pergola'], state: 'lead', displayName: 'Pergola @ 10 List' }),
      jobWith({ cellId: 'B'.repeat(64), services: ['pergola'], state: 'lead', displayName: 'Pergola @ 12 Oak' }),
      jobWith({ cellId: 'C'.repeat(64), services: ['roof-repair'], state: 'lead' }),
    ]);
    const r = await resolveJobReference({
      utterance: 'quote 500 for the pergola job',
      jobsView: view,
    });
    expect(r.kind).toBe('ambiguous');
    if (r.kind === 'ambiguous') {
      expect(r.candidates).toHaveLength(2);
      expect(r.intent).toBe('quote');
    }
  });

  test('zero pergola jobs → none', async () => {
    const view = viewWith([
      jobWith({ cellId: 'A'.repeat(64), services: ['plumbing'], state: 'lead' }),
      jobWith({ cellId: 'B'.repeat(64), services: ['roof-repair'], state: 'lead' }),
    ]);
    const r = await resolveJobReference({
      utterance: 'quote 500 for the pergola job',
      jobsView: view,
    });
    expect(r.kind).toBe('none');
    if (r.kind === 'none') {
      expect(r.intent).toBe('quote');
    }
  });

  test('site hint disambiguates two pergola jobs', async () => {
    const SITE_A = '11111111'.repeat(8);
    const SITE_B = '22222222'.repeat(8);
    const view = viewWith([
      jobWith({ cellId: 'A'.repeat(64), services: ['pergola'], siteId: SITE_A }),
      jobWith({ cellId: 'B'.repeat(64), services: ['pergola'], siteId: SITE_B }),
    ]);
    const r = await resolveJobReference({
      utterance: 'quote 500 for the pergola job',
      jobsView: view,
      siteHint: SITE_A,
    });
    expect(r.kind).toBe('match');
    if (r.kind === 'match') expect(r.cellId).toBe('A'.repeat(64));
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Service-tag extraction
 * ────────────────────────────────────────────────────────────────────── */

describe('extractServiceTags: vocabulary coverage', () => {
  const cases: Array<[string, string[]]> = [
    ['the pergola at 10 List Lane', ['pergola']],
    ['leaking tap in the kitchen', ['tap-replacement', 'leak-investigation']],
    ['fence and gate repair', ['fence-replacement', 'gate-repair']],
    ['roof and gutters', ['roof-repair', 'gutter-repair']],
    ['hot water system not working', ['hot-water-system']],
    ['oven broken — and dishwasher leaking', ['oven-repair', 'dishwasher-repair', 'leak-investigation']],
    ['plumber for the bathroom leak', ['leak-investigation', 'plumbing']],
    ['electrician to check the powerpoints', ['electrical']],
    ['painter for the lounge', ['painting']],
    ['tiling the bathroom', ['tiling']],
    ['no service words here', []],
    ['', []],
  ];
  for (const [u, expected] of cases) {
    test(`"${u}" → [${expected.join(', ')}]`, () => {
      const out = extractServiceTags(u);
      expect(new Set(out)).toEqual(new Set(expected));
    });
  }
});

/* ──────────────────────────────────────────────────────────────────────
 * Intent detection
 * ────────────────────────────────────────────────────────────────────── */

describe('detectIntent', () => {
  const cases: Array<[string, string]> = [
    ['quote 500 for the pergola', 'quote'],
    ['estimate for the roof', 'quote'],
    ['schedule the plumber for Tuesday', 'schedule'],
    ['book the electrician', 'schedule'],
    ['job is complete', 'complete'],
    ['finished the pergola', 'complete'],
    ['send invoice', 'invoice'],
    ['bill the owner', 'invoice'],
    ['status update on the roof', 'status'],
    ["where's the leak job up to", 'status'],
    ['note: tenant prefers SMS', 'note'],
    ['hello there', 'unknown'],
  ];
  for (const [u, intent] of cases) {
    test(`"${u}" → ${intent}`, () => {
      expect(detectIntent(u)).toBe(intent);
    });
  }
});

/* ──────────────────────────────────────────────────────────────────────
 * Money extraction
 * ────────────────────────────────────────────────────────────────────── */

describe('extractMoneyAmounts', () => {
  test('parses $500', () => {
    expect(extractMoneyAmounts('quote $500 for the pergola')).toEqual([500]);
  });
  test('parses bare 500 dollars', () => {
    expect(extractMoneyAmounts('500 dollars for the work')).toEqual([500]);
  });
  test('parses ranges (two numbers)', () => {
    const out = extractMoneyAmounts('quote 500 to 700 for the pergola');
    expect(out).toEqual([500, 700]);
  });
  test('parses comma-separated thousands', () => {
    expect(extractMoneyAmounts('quote $1,250.50 for the build')).toEqual([1250.5]);
  });
  test('ignores irrelevant numbers under 10', () => {
    // Heuristic: short bare-numbers without a money marker get ignored
    // because they're usually unit counts / addresses, not amounts.
    // (Pattern requires 2+ digits.)
    const out = extractMoneyAmounts('5 panels needed');
    expect(out).toEqual([]);
  });
  test('empty utterance', () => {
    expect(extractMoneyAmounts('')).toEqual([]);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Single-candidate-when-no-tag-match fallback
 * ────────────────────────────────────────────────────────────────────── */

describe('no service tag in utterance', () => {
  test('one open job → match with reduced confidence', async () => {
    const view = viewWith([
      jobWith({ cellId: 'A'.repeat(64), services: ['plumbing'], state: 'lead' }),
    ]);
    const r = await resolveJobReference({
      utterance: 'send me an update',
      jobsView: view,
    });
    expect(r.kind).toBe('match');
    if (r.kind === 'match') {
      expect(r.cellId).toBe('A'.repeat(64));
      expect(r.confidence).toBeLessThan(1.0);
    }
  });

  test('multiple open jobs → ambiguous', async () => {
    const view = viewWith([
      jobWith({ cellId: 'A'.repeat(64), services: ['plumbing'] }),
      jobWith({ cellId: 'B'.repeat(64), services: ['roof-repair'] }),
    ]);
    const r = await resolveJobReference({
      utterance: 'send me an update',
      jobsView: view,
    });
    expect(r.kind).toBe('ambiguous');
    if (r.kind === 'ambiguous') expect(r.candidates).toHaveLength(2);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Most-recent tie-breaker for `complete` / `invoice` intents
 * ────────────────────────────────────────────────────────────────────── */

describe('most-recent tie-breaker for complete/invoice intents', () => {
  test('complete + 2 pergolas → most-recent wins', async () => {
    const view = viewWith([
      jobWith({ cellId: 'OLD'.padEnd(64, '0'), services: ['pergola'], issuanceDate: '2026-01-10' }),
      jobWith({ cellId: 'NEW'.padEnd(64, '0'), services: ['pergola'], issuanceDate: '2026-05-10' }),
    ]);
    const r = await resolveJobReference({
      utterance: 'completed the pergola',
      jobsView: view,
    });
    expect(r.kind).toBe('match');
    if (r.kind === 'match') {
      expect(r.cellId).toBe('NEW'.padEnd(64, '0'));
      expect(r.confidence).toBeCloseTo(0.75, 1);
    }
  });

  test('quote intent does NOT auto-pick most-recent', async () => {
    const view = viewWith([
      jobWith({ cellId: 'OLD'.padEnd(64, '0'), services: ['pergola'], issuanceDate: '2026-01-10' }),
      jobWith({ cellId: 'NEW'.padEnd(64, '0'), services: ['pergola'], issuanceDate: '2026-05-10' }),
    ]);
    const r = await resolveJobReference({
      utterance: 'quote the pergola job',
      jobsView: view,
    });
    expect(r.kind).toBe('ambiguous');
  });

  test('same-date jobs stay ambiguous even on complete', async () => {
    const view = viewWith([
      jobWith({ cellId: 'A'.padEnd(64, '0'), services: ['pergola'], issuanceDate: '2026-05-10' }),
      jobWith({ cellId: 'B'.padEnd(64, '0'), services: ['pergola'], issuanceDate: '2026-05-10' }),
    ]);
    const r = await resolveJobReference({
      utterance: 'completed the pergola',
      jobsView: view,
    });
    expect(r.kind).toBe('ambiguous');
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Reasons trace (debuggability)
 * ────────────────────────────────────────────────────────────────────── */

describe('reasons trace', () => {
  test('match path includes intent + tags', async () => {
    const view = viewWith([
      jobWith({ cellId: 'A'.repeat(64), services: ['pergola'] }),
    ]);
    const r = await resolveJobReference({
      utterance: 'quote 500 for the pergola job',
      jobsView: view,
    });
    expect(r.reasons.some(s => s.includes('intent: quote'))).toBe(true);
    expect(r.reasons.some(s => s.includes('pergola'))).toBe(true);
  });
});

```
