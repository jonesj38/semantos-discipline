---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/conversation/multi-hat-integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.489463+00:00
---

# cartridges/oddjobz/brain/tests/conversation/multi-hat-integration.test.ts

```ts
/**
 * D-O7 — multi-hat conversation integration test.
 *
 * The K3 isolation proof rendered in code: carpenter and musician
 * hats both interact with the same `oddjobz` substrate; their
 * conversation patches are correctly routed by contextTag and
 * isolated from one another. The Job FSM advances per-hat without
 * leaking state across hats.
 *
 * Wiring:
 *   - Two hats: carpenter (contextTag 0x01) + musician (contextTag 0x02).
 *   - Each hat mints a Job in `lead` state via `genesisJobLead` under
 *     a hat-scoped `cap.oddjobz.write_customer` cap.
 *   - The cap UTXO is built with `mintCapabilityCell(cap, contextTag,
 *     ownerId)` so the contextTag is on the wire bytes.
 *   - The conversation state-manager + accumulated state run for
 *     each hat independently; we verify a state mutation under one
 *     hat does NOT leak into the other's state.
 *   - The cryptographic-isolation gate is exercised by attempting to
 *     present the carpenter's cap UTXO under the musician's hat: the
 *     `assertHatScopedCap` predicate rejects.
 *   - The Job FSM transition `lead → quoted` advances independently
 *     per hat, and consumed-cell-id sets do not collide.
 *
 * Lean references:
 *   - `oddjobz_cap_isolation_cryptographic` (PR #279) —
 *     proofs/lean/Semantos/Capabilities/Oddjobz.lean line 283.
 *     Cryptographic spend-gate rejects when contextTags differ.
 *   - `job_fsm_transitions_total` —
 *     proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/JobFSM.lean.
 *     Transition function is total over the §O4 table.
 */

import { describe, expect, test } from 'bun:test';
import {
  buildHat,
  assertHatScopedCap,
  CARPENTER_CONTEXT_TAG,
  MUSICIAN_CONTEXT_TAG,
} from '../../src/conversation/hat-scoping.js';
import {
  emptyJobState,
  mergeExtraction,
} from '../../src/conversation/accumulated-job-state.js';
import { evaluateConversationState } from '../../src/conversation/state-manager.js';
import {
  genesisJobLead,
  jobTransition,
  jobCellId,
} from '../../src/state-machines/job-fsm.js';
import { makeConsumedCellSet } from '../../src/state-machines/kernel-gate.js';
import {
  capWriteCustomer,
  capQuote,
  mintCapabilityCell,
} from '../../src/capabilities.js';
import type { PresentedCap } from '../../src/state-machines/kernel-gate.js';

const NOW = '2026-05-01T09:00:00Z';
const STUB_OWNER_TODD = new Uint8Array(16);
STUB_OWNER_TODD[0] = 0xff; // distinguishable but not contextTag (cell mint
                           // overwrites byte 0 with contextTag).

const carpenterHat = buildHat({
  hatId: 'carpenter',
  contextTag: CARPENTER_CONTEXT_TAG,
  principal: 'operator',
  facetId: 'facet-todd',
});
const musicianHat = buildHat({
  hatId: 'musician',
  contextTag: MUSICIAN_CONTEXT_TAG,
  principal: 'operator',
  facetId: 'facet-todd',
});

// Cap UTXOs minted under each hat's contextTag — what the FSM gate
// ultimately reads via OP_CHECKDOMAINFLAG + the hat-isolation gate.
const carpenterWriteCustomerCell = mintCapabilityCell(
  capWriteCustomer,
  CARPENTER_CONTEXT_TAG,
  STUB_OWNER_TODD,
);
const carpenterQuoteCell = mintCapabilityCell(
  capQuote,
  CARPENTER_CONTEXT_TAG,
  STUB_OWNER_TODD,
);
const musicianWriteCustomerCell = mintCapabilityCell(
  capWriteCustomer,
  MUSICIAN_CONTEXT_TAG,
  STUB_OWNER_TODD,
);

const carpenterWriteCustomerCap: PresentedCap = {
  kind: 'cell',
  cell: carpenterWriteCustomerCell,
};
const carpenterQuoteCap: PresentedCap = {
  kind: 'cell',
  cell: carpenterQuoteCell,
};
const musicianWriteCustomerCap: PresentedCap = {
  kind: 'cell',
  cell: musicianWriteCustomerCell,
};

describe('D-O7 — multi-hat integration — K3 cryptographic isolation', () => {
  test("carpenter's cap UTXO does NOT pass musician's hat-scoping gate", () => {
    // The K3 gate at the application seam — cryptographic check is
    // proved by oddjobz_cap_isolation_cryptographic (PR #279).
    const result = assertHatScopedCap(
      musicianHat,
      carpenterWriteCustomerCap,
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.kind).toBe('wrong_cap');
      expect(result.error.hatScope?.expectedContextTag).toBe(
        MUSICIAN_CONTEXT_TAG,
      );
      expect(result.error.hatScope?.presentedContextTag).toBe(
        CARPENTER_CONTEXT_TAG,
      );
      expect(result.error.message).toMatch(
        /oddjobz_cap_isolation_cryptographic/,
      );
    }
  });

  test("musician's cap UTXO does NOT pass carpenter's hat-scoping gate", () => {
    const result = assertHatScopedCap(
      carpenterHat,
      musicianWriteCustomerCap,
    );
    expect(result.ok).toBe(false);
  });

  test("each hat's cap UTXO passes ITS OWN hat-scoping gate", () => {
    expect(
      assertHatScopedCap(carpenterHat, carpenterWriteCustomerCap).ok,
    ).toBe(true);
    expect(
      assertHatScopedCap(musicianHat, musicianWriteCustomerCap).ok,
    ).toBe(true);
  });
});

describe('D-O7 — multi-hat integration — Job FSM advances per-hat', () => {
  test('genesisJobLead succeeds under carpenter hat', () => {
    const result = genesisJobLead({
      jobId: 'a0000000-0000-4000-8000-000000000001',
      principal: 'operator',
      presentedCap: carpenterWriteCustomerCap,
      nowIso: NOW,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.status).toBe('lead');
    }
  });

  test('genesisJobLead succeeds under musician hat with its own UTXO', () => {
    const result = genesisJobLead({
      jobId: 'b0000000-0000-4000-8000-000000000002',
      principal: 'operator',
      presentedCap: musicianWriteCustomerCap,
      nowIso: NOW,
    });
    expect(result.ok).toBe(true);
  });

  test('lead → quoted transitions advance independently for both hats', () => {
    // Both hats use the same ConsumedCellSet — proving the cell-ids
    // are disjoint by virtue of the (jobId, status) -> cellId
    // derivation. The contextTag wedge is in the cap UTXO, not the
    // job-cell-id.
    const consumed = makeConsumedCellSet();

    // Carpenter hat: mint + advance.
    const carpenterJobId = 'a0000000-0000-4000-8000-000000000001';
    const carpenterLead = genesisJobLead({
      jobId: carpenterJobId,
      principal: 'operator',
      presentedCap: carpenterWriteCustomerCap,
      nowIso: NOW,
    });
    expect(carpenterLead.ok).toBe(true);
    if (!carpenterLead.ok) return;

    const carpenterAdvance = jobTransition({
      cell: carpenterLead.value,
      to: 'quoted',
      presentedCap: carpenterQuoteCap,
      principal: 'operator',
      nowIso: NOW,
      consumed,
    });
    expect(carpenterAdvance.ok).toBe(true);
    if (carpenterAdvance.ok) {
      expect(carpenterAdvance.value.cell.status).toBe('quoted');
    }
    expect(consumed.has(jobCellId(carpenterJobId, 'lead'))).toBe(true);

    // Musician hat: mint a job under its own cap.
    const musicianJobId = 'b0000000-0000-4000-8000-000000000002';
    const musicianLead = genesisJobLead({
      jobId: musicianJobId,
      principal: 'operator',
      presentedCap: musicianWriteCustomerCap,
      nowIso: NOW,
    });
    expect(musicianLead.ok).toBe(true);
    if (!musicianLead.ok) return;

    // Musician's lead cell-id is NOT in the consumed set (carpenter's
    // advance only consumed carpenter's lead).
    expect(consumed.has(jobCellId(musicianJobId, 'lead'))).toBe(false);
  });

  test("FSM gate accepts carpenter's quote cap on a carpenter lead even though musician's quote cap was never minted", () => {
    // Verifies the FSM doesn't conflate the two hats' cap UTXOs.
    const consumed = makeConsumedCellSet();
    const lead = genesisJobLead({
      jobId: 'c0000000-0000-4000-8000-000000000003',
      principal: 'operator',
      presentedCap: carpenterWriteCustomerCap,
      nowIso: NOW,
    });
    expect(lead.ok).toBe(true);
    if (!lead.ok) return;
    const advance = jobTransition({
      cell: lead.value,
      to: 'quoted',
      presentedCap: carpenterQuoteCap,
      principal: 'operator',
      nowIso: NOW,
      consumed,
    });
    expect(advance.ok).toBe(true);
  });
});

describe('D-O7 — multi-hat integration — conversation state isolation', () => {
  test('a state mutation under carpenter does NOT leak into musician state', () => {
    // Each hat owns its OWN AccumulatedJobState; the mutation seam is
    // the merger function (mergeExtraction). We hold two separate
    // states and prove they don't share storage.
    let carpenterState = emptyJobState();
    let musicianState = emptyJobState();

    const c1 = mergeExtraction(carpenterState, {
      jobType: 'fencing',
      scopeDescription: 'paling fence repair, side fence, 6m',
      suburb: 'Noosa Heads',
    });
    carpenterState = c1.state;

    expect(carpenterState.jobType).toBe('fencing');
    expect(musicianState.jobType).toBeNull();
    expect(musicianState.scopeDescription).toBeNull();

    const m1 = mergeExtraction(musicianState, {
      jobType: 'general',
      scopeDescription: 'session-musician booking, jazz duo, 2 hours',
      suburb: 'Brisbane',
    });
    musicianState = m1.state;

    expect(musicianState.jobType).toBe('general');
    expect(carpenterState.jobType).toBe('fencing'); // still fencing
    expect(carpenterState.suburb).toBe('Noosa Heads');
  });

  test('conversation state-manager runs independently per hat', () => {
    // The cascade is pure — same input, same output. Two distinct
    // states drive two distinct decisions; no global state coupling.
    const carpenterState = mergeExtraction(emptyJobState(), {
      jobType: 'fencing',
      scopeDescription:
        'paling fence repair on the side fence, 6m of fence, posts okay',
      suburb: 'Noosa Heads',
      quantity: '6m',
      materials: 'paling',
    }).state;
    const musicianState = mergeExtraction(emptyJobState(), {
      jobType: 'general',
      scopeDescription: 'session jazz duo booking 2hr',
      suburb: 'Brisbane',
    }).state;

    const carpenterAction = evaluateConversationState(carpenterState);
    const musicianAction = evaluateConversationState(musicianState);

    // The decisions can be different — that's the point. We just
    // verify no exception, no shared state.
    expect(carpenterAction).toBeDefined();
    expect(musicianAction).toBeDefined();
  });
});

```
