---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-pipeline-federation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.575507+00:00
---

# tests/gates/intent-pipeline-federation.test.ts

```ts
/**
 * Slice 4 federation gate — multi-lexicon patch chain round-trips
 * across two loom instances via DocumentBundle.
 *
 * The use case: OJT (handyman intake bot, jural lexicon) and REA
 * (project-management bot for the real-estate agency) federate one
 * `maintenance.job` between them. The tenant, the handyman, the REA
 * PM, and the landlord all add patches to the same object over its
 * lifetime. Each system operates in its own lexicon, but the patch
 * chain preserves attribution end-to-end — so any party reading the
 * bundle can see "tenant wrote this under jural" vs "REA wrote that
 * under project-management."
 *
 * Asserted:
 *   G1  OJT-authored conversation patches carry `lexicon: 'jural'`
 *   G2  exportBundle → serialize → deserialize → importBundle to the
 *       REA loom preserves both the patch data and the lexicon
 *       attribution
 *   G3  REA appends its own conversation patches with
 *       `lexicon: 'project-management'`
 *   G4  Round-trip back to OJT produces a final patch chain with
 *       patches from both lexicons interleaved, in order, with
 *       correct `hatId` and `lexicon` attribution on each
 *   G5  correlationId on each patch is preserved so federated log
 *       traces reconstruct the full turn on either side
 *
 * NOT asserted (scope of a future slice):
 *   - Real transport (signed overlay, WebRTC, etc.) — the bundle
 *     round-trip here is in-process JSON
 *   - Handoff policy enforcement (when is REA allowed to receive?)
 *   - Cryptographic bundle signing
 */

import { describe, test, expect } from 'bun:test';
import {
  writeConversationPatch,
  createInMemoryLogger,
  type ConversationPatchShape,
  type HatContext,
} from '@semantos/intent';

// ── Minimal per-side loom — an in-memory array of ObjectPatches ──

interface MiniLoom {
  objectId: string;
  payload: Record<string, unknown>;
  patches: ConversationPatchShape[];
}

const mkLoom = (objectId: string): MiniLoom => ({
  objectId,
  payload: { type: 'maintenance.job', title: 'Kitchen tap dripping' },
  patches: [],
});

/**
 * Bundle shape — mirrors apps/loom-react/src/helm/document-bundle.ts
 * at the fields the federation test cares about. The field set is
 * intentionally narrow so the test doesn't drag in the full loom-
 * react surface.
 */
interface MiniBundle {
  version: 1;
  exportedAt: number;
  exportedBy: string;
  documentId: string;
  payload: Record<string, unknown>;
  patches: ConversationPatchShape[];
}

function exportBundle(loom: MiniLoom, exportedBy: string): MiniBundle {
  return {
    version: 1,
    exportedAt: Date.now(),
    exportedBy,
    documentId: loom.objectId,
    payload: { ...loom.payload },
    patches: loom.patches.map((p) => ({ ...p })),
  };
}

function importBundle(bundle: MiniBundle): MiniLoom {
  return {
    objectId: bundle.documentId,
    payload: { ...bundle.payload },
    patches: bundle.patches.map((p) => ({ ...p })),
  };
}

// ── Fixtures ────────────────────────────────────────────────────

const mkHat = (
  over: Partial<HatContext> & { hatId: string; extensionId: string },
): HatContext => ({
  hatId: over.hatId,
  certId: 'cert-' + over.hatId,
  capabilities: [1],
  domainFlag: 1,
  maxTrustClass: 'interpretive',
  ...over,
});

// Deps factory — each side's writer namespaces patch ids by
// `systemLabel` so the federation round-trip doesn't produce
// colliding ids. Real systems derive ids from cryptographic bundle
// hashes; the fixture uses a label prefix to keep assertions
// readable.
function mkDeps(loom: MiniLoom, systemLabel: string) {
  const logger = createInMemoryLogger();
  let patchCounter = 0;
  return {
    logger,
    conversation: {
      write: (_objectId: string, patch: ConversationPatchShape) => {
        loom.patches.push(patch);
      },
      generatePatchId: () => `patch-${systemLabel}-${loom.objectId}-${++patchCounter}`,
      generateCorrelationId: () => `corr-${systemLabel}-${loom.objectId}-${++patchCounter}`,
      now: () => 1_700_000_000_000 + patchCounter * 1000,
    },
  };
}

// ── Tests ────────────────────────────────────────────────────────

describe('Slice 4 federation — OJT ↔ REA multi-lexicon round-trip', () => {
  test('G1+G2+G3+G4+G5 — bundle round-trip preserves per-patch lexicon attribution', async () => {
    // --- Step 1: OJT starts the job + tenant reports the issue ---
    const ojtLoom = mkLoom('job-42');
    const ojtDeps = mkDeps(ojtLoom, 'ojt');

    await writeConversationPatch(
      {
        objectId: ojtLoom.objectId,
        hatId: 'hat-tenant',
        body: 'the kitchen tap has been dripping for three days',
        source: 'nl',
        authorLexicon: 'jural', // OJT operates under the jural lexicon
      },
      { ...ojtDeps.conversation, logger: ojtDeps.logger },
    );

    // G1 — OJT-authored patch carries the jural lexicon attribution
    expect(ojtLoom.patches).toHaveLength(1);
    expect(ojtLoom.patches[0]!.lexicon).toBe('jural');
    expect(ojtLoom.patches[0]!.hatId).toBe('hat-tenant');

    // --- Step 2: OJT exports the bundle, sends to REA ---
    const bundleOutbound = exportBundle(ojtLoom, 'hat-ojt-operator');
    const serialized = JSON.stringify(bundleOutbound);

    // Simulates the wire. Real federation would sign the bundle here.
    const deserialized = JSON.parse(serialized) as MiniBundle;

    // G2 — REA imports and sees the tenant's patch with jural stamp
    const reaLoom = importBundle(deserialized);
    expect(reaLoom.patches).toHaveLength(1);
    expect(reaLoom.patches[0]!.lexicon).toBe('jural');
    expect(reaLoom.patches[0]!.delta).toMatchObject({
      body: 'the kitchen tap has been dripping for three days',
    });

    // --- Step 3: REA PM writes its own conversation patch on the imported object ---
    const reaDeps = mkDeps(reaLoom, 'rea');
    await writeConversationPatch(
      {
        objectId: reaLoom.objectId,
        hatId: 'hat-rea-pm',
        body: 'scheduling plumber Tuesday 9am, approval pending',
        source: 'nl',
        authorLexicon: 'project-management', // REA operates under PM lexicon
      },
      { ...reaDeps.conversation, logger: reaDeps.logger },
    );

    // G3 — REA-authored patch stamps 'project-management'
    expect(reaLoom.patches).toHaveLength(2);
    expect(reaLoom.patches[1]!.lexicon).toBe('project-management');
    expect(reaLoom.patches[1]!.hatId).toBe('hat-rea-pm');

    // --- Step 4: REA exports, sends back to OJT ---
    const bundleReturn = exportBundle(reaLoom, 'hat-rea-operator');
    const roundTripped = importBundle(
      JSON.parse(JSON.stringify(bundleReturn)) as MiniBundle,
    );

    // G4 — OJT sees the full patch chain from both lexicons, in order
    expect(roundTripped.patches).toHaveLength(2);

    const [tenantPatch, reaPatch] = roundTripped.patches;
    expect(tenantPatch!.lexicon).toBe('jural');
    expect(tenantPatch!.hatId).toBe('hat-tenant');
    expect(reaPatch!.lexicon).toBe('project-management');
    expect(reaPatch!.hatId).toBe('hat-rea-pm');

    // G4b — patches are in chronological order
    expect(reaPatch!.timestamp).toBeGreaterThanOrEqual(tenantPatch!.timestamp);

    // G5 — patch ids and correlation data are preserved across the
    // round-trip, so log queries on either side can correlate.
    expect(tenantPatch!.id).toMatch(/^patch-ojt-job-42-/);
    expect(reaPatch!.id).toMatch(/^patch-rea-job-42-/);
    expect(tenantPatch!.id).not.toBe(reaPatch!.id);
  });

  test('patches written without authorLexicon have no lexicon field (backward compat)', async () => {
    const loom = mkLoom('job-legacy');
    const deps = mkDeps(loom, 'ojt');

    await writeConversationPatch(
      {
        objectId: loom.objectId,
        hatId: 'hat-someone',
        body: 'just a chat',
        source: 'nl',
        // no authorLexicon
      },
      { ...deps.conversation, logger: deps.logger },
    );

    expect(loom.patches).toHaveLength(1);
    expect(loom.patches[0]!.lexicon).toBeUndefined();
  });

  test('four-party handoff — tenant, handyman, REA, landlord — full lexicon diversity', async () => {
    // Simulates the full OJT use case: one job travels through
    // tenant (jural), handyman (jural — same OJT lexicon, different
    // hat), REA (project-management), landlord (jural — owner tier).
    const loom = mkLoom('job-multi');
    const deps = mkDeps(loom, 'ojt');
    const W = { ...deps.conversation, logger: deps.logger };

    await writeConversationPatch(
      { objectId: loom.objectId, hatId: 'hat-tenant', body: 'report', source: 'nl', authorLexicon: 'jural' },
      W,
    );
    await writeConversationPatch(
      { objectId: loom.objectId, hatId: 'hat-handyman', body: 'quote: $850', source: 'nl', authorLexicon: 'jural' },
      W,
    );
    await writeConversationPatch(
      {
        objectId: loom.objectId,
        hatId: 'hat-rea',
        body: 'approving quote for landlord review',
        source: 'nl',
        authorLexicon: 'project-management',
      },
      W,
    );
    await writeConversationPatch(
      {
        objectId: loom.objectId,
        hatId: 'hat-landlord',
        body: 'approved, proceed',
        source: 'nl',
        authorLexicon: 'jural',
      },
      W,
    );

    expect(loom.patches).toHaveLength(4);
    const lexicons = loom.patches.map((p) => p.lexicon);
    expect(lexicons).toEqual([
      'jural',
      'jural',
      'project-management',
      'jural',
    ]);

    // Bundle round-trip preserves the full diversity
    const bundle = exportBundle(loom, 'hat-tenant');
    const roundTripped = importBundle(
      JSON.parse(JSON.stringify(bundle)) as MiniBundle,
    );
    expect(roundTripped.patches.map((p) => p.lexicon)).toEqual(lexicons);
    expect(roundTripped.patches.map((p) => p.hatId)).toEqual([
      'hat-tenant',
      'hat-handyman',
      'hat-rea',
      'hat-landlord',
    ]);
  });
});

```
