---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/converged-seam.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.150054+00:00
---

# runtime/legacy-ingest/src/__tests__/converged-seam.test.ts

```ts
/**
 * U2 converged-seam CellWriter conformance.
 *
 * Pins the RETIRE decision (operator 2026-05-18): gmail/meta ingest
 * mints the SAME genesis `lead` job through the SAME cap-gated REPL
 * `add job "<name>" lead` as the proven chat seam (SD2 incr.1) — NOT
 * the old oddjobz.ratify_proposal/JSONL island. Name derivation
 * (pointOfContact → primaryContact → null), sanitisation (brain
 * splitArgs `"…"` tokeniser), REPL wire shape, and surfaced (not
 * silent) failure. Deps-injected ⇒ ZERO live, worktree-runnable.
 */

import { describe, expect, test } from 'bun:test';
import type { Proposal } from '../extractor/types';
import type { SIRProgram } from '@semantos/semantos-sir';
import {
  makeConvergedSeamCellWriter,
  proposalLeadName,
  sanitizeName,
  proposalJobAction,
  parseCreatedJobId,
  type ConvergedSeamDeps,
} from '../cell-writer/converged-seam';

const PROGRAM = {} as unknown as SIRProgram; // genesis-only (no action node)

/** A SIRProgram whose first node carries the extractor's classification
 *  action (email.ts:mapJobTypeToAction). */
function makeProgram(action: string): SIRProgram {
  return { nodes: [{ id: '$s0', action }] } as unknown as SIRProgram;
}

function makeProposal(overrides: Partial<Proposal> = {}): Proposal {
  return {
    proposalId: 'prop-test-001',
    confidence: 0.9,
    status: 'pending',
    provenance: {
      providerId: 'gmail',
      providerItemId: 'item-001',
      fetchedAt: 1_700_000_000_000,
      extractorVersion: 'email-rfc822-v0.3',
      promptHash: 'h0',
    },
    extractedAt: 1_700_000_001_000,
    program: PROGRAM,
    summary: 'AcmeCorp wants a deck rebuild',
    ...overrides,
  } as Proposal;
}

function mkDeps(
  over: Partial<ConvergedSeamDeps> = {},
): ConvergedSeamDeps & { posted: { url: string; body: string }[] } {
  const posted: { url: string; body: string }[] = [];
  return {
    posted,
    brainReplUrl: 'http://127.0.0.1:8080/api/v1/repl',
    brainBearer: 'beef'.repeat(16),
    fetchFn: async (url, init) => {
      posted.push({ url, body: init.body });
      return {
        status: 200,
        text: async () =>
          '{"id":"job-xyz","customer_name":"Robert James Realty","state":"lead","status":"created"}',
      };
    },
    ...over,
  };
}

describe('proposalLeadName + sanitizeName', () => {
  test('prefers pointOfContact, falls back to primaryContact.name, else null', () => {
    expect(proposalLeadName(makeProposal({ pointOfContact: 'Robert James Realty' }))).toBe(
      'Robert James Realty',
    );
    expect(
      proposalLeadName(
        makeProposal({
          pointOfContact: undefined,
          primaryContact: { name: 'Jane Tenant', role: 'tenant', phone: null, email: null },
        }),
      ),
    ).toBe('Jane Tenant');
    expect(proposalLeadName(makeProposal({ pointOfContact: undefined }))).toBeNull();
  });

  test('sanitizeName strips quotes/newlines, collapses ws, caps 120', () => {
    expect(sanitizeName('Bob "The Builder"')).toBe('Bob The Builder');
    expect(sanitizeName('  a\n\tb  c ')).toBe('a b c');
    expect(sanitizeName('x'.repeat(200)).length).toBe(120);
  });
});

describe('makeConvergedSeamCellWriter', () => {
  test('happy path: POSTs add job "<name>" lead w/ bearer, returns proposalId', async () => {
    const d = mkDeps();
    const writer = makeConvergedSeamCellWriter(d);
    const proposal = makeProposal({ pointOfContact: 'Robert James Realty' });
    const id = await writer({ program: PROGRAM, proposal });
    expect(id).toBe('prop-test-001');
    expect(d.posted).toHaveLength(1);
    expect(d.posted[0].url).toBe('http://127.0.0.1:8080/api/v1/repl');
    const cmd = (JSON.parse(d.posted[0].body) as { cmd: string }).cmd;
    expect(cmd).toBe('add job "Robert James Realty" lead');
  });

  test('embedded quote in name is sanitised into the REPL cmd', async () => {
    const d = mkDeps();
    const writer = makeConvergedSeamCellWriter(d);
    await writer({
      program: PROGRAM,
      proposal: makeProposal({ pointOfContact: 'Bob "The Builder"' }),
    });
    const cmd = (JSON.parse(d.posted[0].body) as { cmd: string }).cmd;
    expect(cmd).toBe('add job "Bob The Builder" lead');
  });

  test('no usable name ⇒ null, NO POST (writer no-ops)', async () => {
    const d = mkDeps();
    const writer = makeConvergedSeamCellWriter(d);
    const id = await writer({
      program: PROGRAM,
      proposal: makeProposal({ pointOfContact: undefined }),
    });
    expect(id).toBeNull();
    expect(d.posted).toHaveLength(0);
  });

  test('HTTP non-2xx ⇒ throws (orchestrator surfaces cell_write_error)', async () => {
    const d = mkDeps({
      fetchFn: async () => ({ status: 503, text: async () => 'down' }),
    });
    const writer = makeConvergedSeamCellWriter(d);
    await expect(
      writer({ program: PROGRAM, proposal: makeProposal({ pointOfContact: 'X Co' }) }),
    ).rejects.toThrow(/converged-seam jobs\.create HTTP 503/);
  });

  test('dispatch/cap rejection body ⇒ throws (not silent success)', async () => {
    const d = mkDeps({
      fetchFn: async () => ({
        status: 200,
        text: async () => 'jobs.create: dispatch failed: capability_denied',
      }),
    });
    const writer = makeConvergedSeamCellWriter(d);
    await expect(
      writer({ program: PROGRAM, proposal: makeProposal({ pointOfContact: 'X Co' }) }),
    ).rejects.toThrow(/converged-seam jobs\.create rejected/);
  });
});

describe('proposalJobAction + parseCreatedJobId', () => {
  test('proposalJobAction reads the first node action; null when none', () => {
    expect(proposalJobAction(makeProgram('create_work_order'))).toBe('create_work_order');
    expect(proposalJobAction(PROGRAM)).toBeNull();
  });
  test('parseCreatedJobId handles raw and REPL-enveloped forms', () => {
    expect(parseCreatedJobId('{"id":"job-xyz","status":"created"}')).toBe('job-xyz');
    expect(
      parseCreatedJobId(
        '{"result":"{\\"id\\":\\"b0e3\\",\\"status\\":\\"created\\"}\\n","exit":"continue"}',
      ),
    ).toBe('b0e3');
    expect(parseCreatedJobId('not json at all')).toBeNull();
  });
});

describe('SD2 incr.2 — WO-classifier (lead→authorized)', () => {
  test('work_order ⇒ create THEN transition job <id> authorized (2 POSTs)', async () => {
    const d = mkDeps();
    const writer = makeConvergedSeamCellWriter(d);
    const id = await writer({
      program: makeProgram('create_work_order'),
      proposal: makeProposal({ pointOfContact: 'Clever Property' }),
    });
    expect(id).toBe('prop-test-001');
    expect(d.posted).toHaveLength(2);
    expect(JSON.parse(d.posted[0].body).cmd).toBe('add job "Clever Property" lead');
    expect(JSON.parse(d.posted[1].body).cmd).toBe('transition job job-xyz authorized');
  });

  test('maintenance_order ⇒ also transitions to authorized', async () => {
    const d = mkDeps();
    const writer = makeConvergedSeamCellWriter(d);
    await writer({
      program: makeProgram('create_maintenance_order'),
      proposal: makeProposal({ pointOfContact: 'RJR PM' }),
    });
    expect(d.posted).toHaveLength(2);
    expect(JSON.parse(d.posted[1].body).cmd).toBe('transition job job-xyz authorized');
  });

  test('quote_request ⇒ stays lead (NO transition, 1 POST)', async () => {
    const d = mkDeps();
    const writer = makeConvergedSeamCellWriter(d);
    await writer({
      program: makeProgram('create_quote_request'),
      proposal: makeProposal({ pointOfContact: 'A Customer' }),
    });
    expect(d.posted).toHaveLength(1);
  });

  test('no action node ⇒ stays lead (uniform lead-on-contact, 1 POST)', async () => {
    const d = mkDeps();
    const writer = makeConvergedSeamCellWriter(d);
    await writer({
      program: PROGRAM,
      proposal: makeProposal({ pointOfContact: 'A Customer' }),
    });
    expect(d.posted).toHaveLength(1);
  });

  test('transition rejection ⇒ throws (surfaced as cell_write_error)', async () => {
    let n = 0;
    const d = mkDeps({
      fetchFn: async (url, init) => {
        n += 1;
        if (n === 1)
          return {
            status: 200,
            text: async () => '{"id":"job-xyz","status":"created"}',
          };
        return {
          status: 200,
          text: async () => 'jobs.transition: invalid state transition lead→authorized',
        };
      },
    });
    const writer = makeConvergedSeamCellWriter(d);
    await expect(
      writer({
        program: makeProgram('create_work_order'),
        proposal: makeProposal({ pointOfContact: 'X Co' }),
      }),
    ).rejects.toThrow(/converged-seam jobs\.transition rejected/);
  });
});

```
