---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/tests/smoke/cross-vertical-smoke.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.514454+00:00
---

# packages/dispatch/dispatch/tests/smoke/cross-vertical-smoke.test.ts

```ts
/**
 * D-O11 phase O11c — cross-vertical dispatch envelope smoke test.
 *
 * The end-to-end federation primitive validation. Spins up two
 * in-process brains (PM running re-desk-stub; tradie running
 * oddjobz + dispatch handler) and drives the chapter-29 worked
 * example through a federated dispatch envelope.
 *
 * Per ODDJOBZ-EXTENSION-PLAN.md §3 phase O11 acceptance:
 *   (1) PM creates MaintenanceRequest → envelope flows to tradie →
 *       MaintenanceRequest exists as oddjobz.job.v1 in tradie's
 *       substrate, in `lead` state.
 *   (2) Tradie advances Job to `completed` → completion patch flows
 *       to PM → PM's MaintenanceRequest is now `completed`
 *       (specifically `invoiced` per the chapter-29 worked example).
 *   (3) AFFINE: tradie's margin-notes under tradie-MARGIN hat → PM
 *       hat does NOT see it (K3).
 *   (4) AFFINE: PM's owner-financial under PM-OWNER hat → tradie
 *       hat does NOT see it (K3).
 *   (5) K1: tradie has no accept-handler registered → envelope
 *       creation fails at the originating brain's gate; the
 *       MaintenanceRequest stays in `draft`.
 *   (6) Replay: same envelope arrives twice → second is idempotent.
 */

import { describe, expect, test } from 'bun:test';

import {
  PM_HAT_CONTEXT_TAG,
  PM_OWNER_HAT_CONTEXT_TAG,
  TRADIE_HAT_CONTEXT_TAG,
  TRADIE_MARGIN_HAT_CONTEXT_TAG,
  buildFederationUniverse,
  pmDispatchAndRequireDelivery,
  pmDispatchMaintenanceRequest,
  pmWriteOwnerFinancialPatch,
  readAffinePatchesUnderHat,
  tradieCompleteJob,
  tradieWriteMarginNotePatch,
} from './two-brain-harness.js';

import { processDispatchEnvelope } from '../../src/index.js';

const REQ_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const NOW_DISPATCH = '2026-05-01T09:00:00.000Z';
const NOW_COMPLETE = '2026-05-01T11:00:00.000Z';

describe('§O11c — cross-vertical dispatch end-to-end', () => {
  test('[§O11 acceptance #1] PM dispatch materialises an oddjobz.job in tradie substrate', async () => {
    const u = buildFederationUniverse();
    const result = await pmDispatchAndRequireDelivery(u.pmBrain, {
      requestId: REQ_ID,
      customer: 'Tenant 4B, 12 Smith St',
      description: 'HVAC failure',
      tradieRef: `${u.tradieBrain.tenantDomain}#${u.tradieBrain.hat.hatId}`,
      nowIso: NOW_DISPATCH,
    });
    expect(result.delivered).toBe(true);
    expect(result.rolledBack).toBe(false);

    // PM-side: MaintenanceRequest advanced draft → dispatched
    // (locally optimistic) and then dispatched → accepted on the
    // back-channel acceptance patch.
    const finalReq = u.pmBrain.maintenanceRequests.get(REQ_ID);
    expect(finalReq).toBeDefined();
    expect(finalReq?.state).toBe('accepted');
    expect(u.pmBrain.acceptedPatches).toHaveLength(1);
    expect(u.pmBrain.acceptedPatches[0]?.envelopeId).toBe(
      result.outcome.envelope.envelopeId,
    );
    expect(u.pmBrain.acceptedPatches[0]?.localCellType).toBe('oddjobz.job.v1');

    // Tradie-side: oddjobz.job.v1 materialised in `lead` state.
    expect(u.tradieBrain.jobs.size).toBe(1);
    const job = u.tradieBrain.jobs.get(REQ_ID);
    expect(job).toBeDefined();
    expect(job?.status).toBe('lead');
    expect(job?.jobId).toBe(REQ_ID);
  });

  test('[§O11 acceptance #2] tradie completion → PM MaintenanceRequest reaches `invoiced`', async () => {
    const u = buildFederationUniverse();
    const dispatch = await pmDispatchAndRequireDelivery(u.pmBrain, {
      requestId: REQ_ID,
      customer: 'Tenant 4B',
      description: 'HVAC failure',
      tradieRef: `${u.tradieBrain.tenantDomain}#${u.tradieBrain.hat.hatId}`,
      nowIso: NOW_DISPATCH,
    });
    expect(dispatch.delivered).toBe(true);

    // Tradie drives lead → … → invoiced and emits completion patch.
    const finish = await tradieCompleteJob(u.tradieBrain, {
      envelopeId: dispatch.outcome.envelope.envelopeId,
      invoiceAmountCents: 87_500,
      nowIso: NOW_COMPLETE,
      originatorTenant: u.pmBrain.tenantDomain,
      originatorHat: u.pmBrain.hat.hatId,
    });
    expect(finish.job.status).toBe('invoiced');
    expect(finish.completion.completionKind).toBe('invoiced');
    expect(finish.completion.invoiceAmountCents).toBe(87_500);

    // PM-side: completion patch arrived, MaintenanceRequest advanced
    // accepted → in_progress → completed → invoiced.
    expect(u.pmBrain.completionPatches).toHaveLength(1);
    expect(u.pmBrain.completionPatches[0]?.invoiceAmountCents).toBe(87_500);
    const finalReq = u.pmBrain.maintenanceRequests.get(REQ_ID);
    expect(finalReq?.state).toBe('invoiced');
  });
});

```
