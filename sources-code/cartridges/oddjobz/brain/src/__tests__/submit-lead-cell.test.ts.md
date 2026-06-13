---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/submit-lead-cell.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.514357+00:00
---

# cartridges/oddjobz/brain/src/__tests__/submit-lead-cell.test.ts

```ts
/**
 * P3.5a submit-lead-cell conformance.
 *
 * Pins the live-bot seam orchestration: estimatePresented gating, P3.4
 * agent-cert, P3.1 pipeline → P3.2 brain-submit adapter, P3.4
 * accept_rom EnvelopeContext with the romBandCents money channel (the
 * EXACT range the customer was shown). All env-gated deps injected ⇒
 * ZERO live, worktree-runnable. Additive/best-effort: a throw is the
 * intake-handler's problem to log; the reply + jsonl shadow are
 * unaffected (asserted by the gating test — no work when not eligible).
 */

import { describe, expect, test } from 'bun:test';
import { submitLeadCell, type SubmitLeadDeps } from '../conversation/submit-lead-cell.js';
import type { AccumulatedJobState } from '../conversation/accumulated-job-state.js';

const baseState = (over: Partial<AccumulatedJobState> = {}): AccumulatedJobState =>
  ({
    customerName: 'Sam',
    customerPhone: '0475303187',
    suburb: 'Noosa',
    jobType: 'fencing',
    scopeDescription: 'back fence down, 16m, rotten posts',
    estimatePresented: false,
    ...over,
  }) as unknown as AccumulatedJobState;

const agentCert = { hatId: 'b'.repeat(32), certId: 'a'.repeat(32) };

function mkDeps(over: Partial<SubmitLeadDeps> = {}): SubmitLeadDeps & {
  posted: { url: string; body: string }[];
} {
  const posted: { url: string; body: string }[] = [];
  return {
    posted,
    getAgentCert: async () => agentCert,
    brainReplUrl: 'https://oddjobtodd.info/api/v1/repl',
    brainBearer: 'beef'.repeat(16),
    fetchFn: async (url, init) => {
      posted.push({ url, body: init.body });
      return { status: 200, text: async () => '{"ok":true,"cellId":"cell-z"}' };
    },
    runEdgePipeline: async ({ writeCell }) => {
      await writeCell(
        { id: 'cell-000006-deadbeef-aaaa1111', bytes: new Uint8Array([0xc3, 0x05, 0x51]) },
        { ok: true, opcount: 1, stackDepth: 0, gasUsed: 0, errorKind: null },
      );
      return { ok: true, cellId: 'cell-000006-deadbeef-aaaa1111' };
    },
    ...over,
  };
}

describe('submitLeadCell — gating (cannot regress reply/shadow)', () => {
  test('no estimate presented ⇒ skipped, NO agent-cert / pipeline / POST', async () => {
    let agentCalled = false;
    let pipelineCalled = false;
    const d = mkDeps({
      getAgentCert: async () => {
        agentCalled = true;
        return agentCert;
      },
      runEdgePipeline: async () => {
        pipelineCalled = true;
        return { ok: true, cellId: 'x' };
      },
    });
    const r = await submitLeadCell(baseState({ estimatePresented: false }), 'corr-1', d);
    expect(r).toEqual({ submitted: false, skipped: 'no_estimate_presented' });
    expect(agentCalled).toBe(false);
    expect(pipelineCalled).toBe(false);
    expect(d.posted).toHaveLength(0);
  });
});

describe('submitLeadCell — accept_rom mint on estimatePresented', () => {
  test('provisions agent cert, runs pipeline, POSTs the accept_rom envelope', async () => {
    const d = mkDeps();
    const r = await submitLeadCell(
      baseState({ estimatePresented: true, jobType: 'fencing' }),
      'corr-9',
      d,
    );
    expect(r.submitted).toBe(true);
    expect(r.cellId).toBe('cell-000006-deadbeef-aaaa1111');
    expect(d.posted).toHaveLength(1);
    expect(d.posted[0].url).toBe('https://oddjobtodd.info/api/v1/repl');
    const cmd = (JSON.parse(d.posted[0].body) as { cmd: string }).cmd;
    expect(cmd.startsWith('submit-intent-cell --envelope ')).toBe(true);
    const env = JSON.parse(
      Buffer.from(cmd.split(' ')[2]!, 'base64').toString('utf8'),
    );
    expect(env.kind).toBe('oddjobz.intent_cell.v1');
    expect(env.hatId).toBe('b'.repeat(32));
    expect(env.certId).toBe('a'.repeat(32));
    expect(env.cellId).toBe('cell-000006-deadbeef-aaaa1111');
    expect(env.originalIntent.action).toBe('accept_rom');
    // romBandCents('fencing') = [300,900] → cents 30000/90000 (the
    // exact range DEFAULT_ESTIMATOR_FN shows the customer).
    const t = JSON.parse(env.originalIntent.targetJson);
    expect(t.costMin).toBe(30000);
    expect(t.costMax).toBe(90000);
    expect(env.kernelResult.ok).toBe(true);
  });

  test('pipeline ok:false ⇒ submitted:false (surfaced, not silent-true)', async () => {
    const d = mkDeps({
      runEdgePipeline: async ({ writeCell }) => {
        await writeCell(
          { id: 'c', bytes: new Uint8Array([0x51]) },
          { ok: false, opcount: 0, stackDepth: 0, gasUsed: 0, errorKind: 'x' },
        );
        return { ok: false, cellId: null };
      },
    });
    const r = await submitLeadCell(baseState({ estimatePresented: true }), 'c', d);
    expect(r.submitted).toBe(false);
  });

  test('different jobType ⇒ its own shown band (general fallback)', async () => {
    const d = mkDeps();
    await submitLeadCell(
      baseState({ estimatePresented: true, jobType: 'unknown-trade' }),
      'c',
      d,
    );
    const env = JSON.parse(
      Buffer.from(
        (JSON.parse(d.posted[0].body) as { cmd: string }).cmd.split(' ')[2]!,
        'base64',
      ).toString('utf8'),
    );
    const t = JSON.parse(env.originalIntent.targetJson);
    expect(t.costMin).toBe(12000); // general [120,280] → cents
    expect(t.costMax).toBe(28000);
  });
});

```
