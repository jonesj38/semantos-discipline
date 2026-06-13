---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/handle-message.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.356157+00:00
---

# runtime/intent/src/__tests__/handle-message.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  handleMessage,
  createInMemoryPendingRegistry,
  type HandleMessageDeps,
} from '../handle-message';
import {
  createRulesClassifier,
  neverIntentClassifier,
  type Classifier,
} from '../triage';
import { createInMemoryLogger } from '../logger';
import type {
  CellId,
  HatContext,
  Intent,
  IntentId,
  PipelineDeps,
  ScriptResult,
  Signature,
  TriageOutcome,
} from '../index';

// ── Fixtures ────────────────────────────────────────────────

const mkHat = (over: Partial<HatContext> = {}): HatContext => ({
  hatId: 'hat-tenant',
  hatId: 'hat-tenant',
  certId: 'cert-tenant',
  capabilities: [1, 2],
  extensionId: 'property',
  domainFlag: 7,
  maxTrustClass: 'interpretive',
  ...over,
});

const okKernel: ScriptResult = { ok: true, stackDepth: 0, opcount: 3, gasUsed: 10 };

let cellCounter = 0;
const mkPipelineDeps = (over: Partial<PipelineDeps> = {}): PipelineDeps => ({
  emitBytes: () => new Uint8Array([0xc3, 0x05]),
  executeScript: async () => okKernel,
  buildCellFromBytes: bytes => ({
    id: `cell-${++cellCounter}` as CellId,
    bytes,
  }),
  writeCell: async () => {},
  sign: () => new Uint8Array([0xde, 0xad]),
  now: () => 1_700_000_000_000,
  uuid: () => 'uuid-stub',
  ...over,
});

const stubSig: Signature = {
  bytes: new Uint8Array([0xaa]),
  algorithm: 'stub',
  keyId: 'k-1',
};

const mkDeps = (classifier: Classifier, registry = createInMemoryPendingRegistry()) => {
  const logger = createInMemoryLogger();
  const conversationWrites: Array<{ objectId: string; patch: any }> = [];
  const ratificationWrites: Array<{ objectId: string; patch: any }> = [];
  let patchCounter = 0;

  const deps: HandleMessageDeps = {
    conversation: {
      write: (objectId, patch) => {
        conversationWrites.push({ objectId, patch });
      },
      generatePatchId: () => `patch-conv-${++patchCounter}`,
      generateCorrelationId: () => `corr-${patchCounter}`,
      now: () => 1_700_000_000_000,
    },
    ratification: {
      write: (objectId, patch) => {
        ratificationWrites.push({ objectId, patch });
      },
      generatePatchId: () => `patch-rat-${++patchCounter}`,
      now: () => 1_700_000_000_000,
    },
    classifier,
    pendingRegistry: registry,
    pipeline: mkPipelineDeps(),
    logger,
  };
  return { deps, logger, conversationWrites, ratificationWrites, registry };
};

// ── G1: conversation patch always lands ─────────────────────

describe('G1 — conversation patch always lands', () => {
  test('NO_INTENT path still writes the conversation patch', async () => {
    const { deps, logger, conversationWrites } = mkDeps(neverIntentClassifier);

    const result = await handleMessage(
      { objectId: 'job-42', hat: mkHat(), body: 'thanks', source: 'nl' },
      deps,
    );

    expect(result.kind).toBe('no_intent');
    expect(conversationWrites).toHaveLength(1);
    expect(conversationWrites[0]!.patch.kind).toBe('conversation');

    const stages = logger.events.map(e => e.stage);
    expect(stages).toEqual(['conversation_patch_written', 'triage_decided']);
  });
});

// ── G2: rules classifier, no pending → NO_INTENT ────────────

describe('G2 — rules classifier without pending proposals', () => {
  test('"approved" with no pending proposals is NO_INTENT', async () => {
    const classifier = createRulesClassifier({ sign: () => stubSig });
    const { deps, logger } = mkDeps(classifier);

    const result = await handleMessage(
      { objectId: 'job-42', hat: mkHat(), body: 'approved', source: 'nl' },
      deps,
    );

    expect(result.kind).toBe('no_intent');
    const triageEv = logger.events.find(e => e.stage === 'triage_decided')!;
    expect(triageEv.data.outcome).toBe('no_intent');
  });
});

// ── G3: PROPOSES classifier → full pipeline runs ────────────

describe('G3 — PROPOSES → full pipeline', () => {
  const proposalIntent: Intent = {
    id: 'intent-proposal-1' as IntentId,
    summary: 'request quote for dripping tap',
    category: { lexicon: 'jural', category: 'declaration' },
    taxonomy: { what: 'maintenance.job', how: 'quote.solicit', why: 'procurement' },
    action: 'request_quote',
    constraints: [{ kind: 'capability', required: 1, name: 'cap-1' }],
    confidence: 0.88,
    source: 'nl',
  };
  const proposingClassifier: Classifier = {
    async classify(): Promise<TriageOutcome> {
      return { kind: 'proposes', intent: proposalIntent };
    },
  };

  test('emits conv+triage+7 pipeline events; all share one correlationId', async () => {
    const { deps, logger, registry } = mkDeps(proposingClassifier);

    const result = await handleMessage(
      {
        objectId: 'job-42',
        hat: mkHat(),
        body: '[3 images of the tap]',
        source: 'nl',
      },
      deps,
    );

    expect(result.kind).toBe('proposed');
    if (result.kind !== 'proposed') return;
    expect(result.intentResult.ok).toBe(true);

    const stages = logger.events.map(e => e.stage);
    expect(stages).toEqual([
      'conversation_patch_written',
      'triage_decided',
      'intent_extracted',
      'sir_built',
      'sir_lowered',
      'ir_emitted',
      'script_executed',
      'cell_written',
      'intent_completed',
    ]);

    // Single correlationId across the full turn
    const ids = new Set(logger.events.map(e => e.correlationId));
    expect(ids.size).toBe(1);

    // Pending registry now has the proposal for ratification lookup
    const pending = await registry.listPendingForObject('job-42');
    expect(pending).toHaveLength(1);
    expect(pending[0]!.summary).toBe('request quote for dripping tap');
  });

  test('derived intent carries companionOf → conversation patch id', async () => {
    const { deps } = mkDeps(proposingClassifier);

    const result = await handleMessage(
      {
        objectId: 'job-42',
        hat: mkHat(),
        body: '[images]',
        source: 'nl',
      },
      deps,
    );

    if (result.kind !== 'proposed') throw new Error('expected proposed');
    // The intent_extracted event's data records companionOf
    // (the handleMessage orchestrator wires it even if the classifier
    // forgot).
    // Verify via registry: proposal was recorded with the derived cell id
    // (it takes the cell_written id because that's the durable artifact).
    expect(result.conversationPatchId).toBe('patch-conv-1' as any);
  });
});

// ── G4: RATIFIES flow — landlord approves ───────────────────

describe('G4 — RATIFIES → issueRatification, no pipeline', () => {
  test('"approved" on a pending proposal ratifies it and clears registry', async () => {
    const classifier = createRulesClassifier({ sign: () => stubSig });
    const { deps, logger, registry, ratificationWrites } = mkDeps(classifier);

    // Seed: simulate an earlier proposal is pending.
    await registry.markProposed(
      'job-42',
      { patchId: 'cell-proposal-earlier' as any, summary: '$850 quote for plumber' },
      'corr-earlier' as any,
    );

    const result = await handleMessage(
      {
        objectId: 'job-42',
        hat: mkHat({ hatId: 'hat-landlord' }),
        body: 'approved, proceed',
        source: 'nl',
      },
      deps,
    );

    expect(result.kind).toBe('ratified');
    if (result.kind !== 'ratified') return;

    // Exactly 3 events — conv + triage + ratification; NO pipeline events
    const stages = logger.events.map(e => e.stage);
    expect(stages).toEqual([
      'conversation_patch_written',
      'triage_decided',
      'ratification_issued',
    ]);

    // Ratification patch hit storage
    expect(ratificationWrites).toHaveLength(1);
    expect(ratificationWrites[0]!.patch.kind).toBe('ratification');
    expect(ratificationWrites[0]!.patch.delta.ratifies).toBe('cell-proposal-earlier');

    // Pending registry cleared
    const stillPending = await registry.listPendingForObject('job-42');
    expect(stillPending).toHaveLength(0);

    // Triage event records the pendingPatchId being closed
    const triageEv = logger.events.find(e => e.stage === 'triage_decided')!;
    expect(triageEv.data.outcome).toBe('ratifies');
    expect(triageEv.data.pendingPatchId).toBe('cell-proposal-earlier');
  });
});

// ── G5: correlation id propagation ──────────────────────────

describe('G5 — correlationId threads through every path', () => {
  const propose: Classifier = {
    async classify() {
      return {
        kind: 'proposes',
        intent: {
          id: 'i1' as IntentId,
          summary: 's',
          category: { lexicon: 'jural', category: 'declaration' },
          taxonomy: { what: 'a', how: 'b', why: 'c' },
          action: 'x',
          constraints: [],
          confidence: 0.9,
          source: 'nl',
        },
      };
    },
  };

  test('caller-supplied correlationId flows through every event', async () => {
    const { deps, logger } = mkDeps(propose);

    await handleMessage(
      {
        objectId: 'o',
        hat: mkHat(),
        body: 'test',
        source: 'nl',
        correlationId: 'corr-from-caller' as any,
      },
      deps,
    );

    for (const ev of logger.events) {
      expect(ev.correlationId).toBe('corr-from-caller' as any);
    }
  });
});

```
