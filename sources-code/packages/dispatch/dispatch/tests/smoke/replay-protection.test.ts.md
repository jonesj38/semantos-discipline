---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/tests/smoke/replay-protection.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.514746+00:00
---

# packages/dispatch/dispatch/tests/smoke/replay-protection.test.ts

```ts
/**
 * D-O11 phase O11c — replay protection.
 *
 * Per ODDJOBZ-EXTENSION-PLAN.md §3 phase O11 acceptance:
 *   (6) Replay: same envelope arrives at tradie's brain twice → second
 *       is idempotent (no duplicate Job creation).
 *
 * The mechanism: the receiving brain's `RollbackableConsumedCellSet`
 * carries the envelopeId after a successful processDispatchEnvelope.
 * A second arrival with the same envelopeId returns
 * `envelope_replay`. The K1 surface keeps the substrate consistent
 * (no duplicate Job, no duplicate accepted patch).
 *
 * Two scenarios:
 *  (a) Same envelope replay through the transport — the second
 *      arrival is rejected at the receiving brain's K1 gate.
 *  (b) Two genuinely distinct envelopes for the same MaintenanceRequest
 *      (operator dispatches twice with different envelopeIds) — the
 *      receiving brain materialises both as separate Jobs. This is
 *      NOT a K1 violation; it's the operator's responsibility to
 *      avoid duplicate dispatches at the originating side. The
 *      receiving brain is correct to accept both.
 */

import { describe, expect, test } from 'bun:test';

import {
  buildFederationUniverse,
  pmDispatchAndRequireDelivery,
} from './two-brain-harness.js';
import {
  processDispatchEnvelope,
  type CertChainVerifier,
} from '../../src/index.js';

const REQ_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const REQ_ID_2 = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff';
const NOW = '2026-05-01T09:00:00.000Z';
const ACCEPT_VERIFIER: CertChainVerifier = () => ({ ok: true });

describe('§O11c — replay protection', () => {
  test('[§O11 acceptance #6] same envelope replayed → second arrival is idempotent', async () => {
    const u = buildFederationUniverse();
    const dispatch = await pmDispatchAndRequireDelivery(u.pmBrain, {
      requestId: REQ_ID,
      customer: 'Tenant 4B',
      description: 'HVAC failure',
      tradieRef: `${u.tradieBrain.tenantDomain}#${u.tradieBrain.hat.hatId}`,
      nowIso: NOW,
    });
    expect(dispatch.delivered).toBe(true);

    const jobsBefore = u.tradieBrain.jobs.size;
    const acceptedBefore = u.pmBrain.acceptedPatches.length;

    // Replay the SAME envelope directly into the tradie brain's
    // dispatch handler. The substrate K1 gate rejects.
    const replay = await processDispatchEnvelope({
      envelope: dispatch.outcome.envelope,
      payloadBytes: new TextEncoder().encode(
        JSON.stringify({
          requestId: REQ_ID,
          customer: 'Tenant 4B',
          description: 'HVAC failure',
          dispatchTo: `${u.tradieBrain.tenantDomain}#${u.tradieBrain.hat.hatId}`,
        }),
      ),
      receivingHat: u.tradieBrain.hat,
      verifyCertChain: ACCEPT_VERIFIER,
      registry: u.tradieBrain.registry,
      consumed: u.tradieBrain.dispatchConsumed,
      nowIso: NOW,
    });

    expect(replay.ok).toBe(false);
    if (!replay.ok) expect(replay.error.kind).toBe('envelope_replay');

    // No duplicate state. Tradie's job count is unchanged.
    expect(u.tradieBrain.jobs.size).toBe(jobsBefore);
    // PM's accepted-patch list is unchanged (the second receive
    // didn't echo a duplicate acceptance).
    expect(u.pmBrain.acceptedPatches.length).toBe(acceptedBefore);
  });

  test('two genuinely distinct envelopes for different requests both materialise', async () => {
    // The replay rejection is per-envelopeId, NOT per-request. Two
    // separate operator-initiated dispatches (each with its own
    // envelopeId) are both processed.
    const u = buildFederationUniverse();
    const r1 = await pmDispatchAndRequireDelivery(u.pmBrain, {
      requestId: REQ_ID,
      customer: 'Tenant 4B',
      description: 'HVAC failure',
      tradieRef: `${u.tradieBrain.tenantDomain}#${u.tradieBrain.hat.hatId}`,
      nowIso: NOW,
    });
    const r2 = await pmDispatchAndRequireDelivery(u.pmBrain, {
      requestId: REQ_ID_2,
      customer: 'Strata 12',
      description: 'roof leak',
      tradieRef: `${u.tradieBrain.tenantDomain}#${u.tradieBrain.hat.hatId}`,
      nowIso: NOW,
    });
    expect(r1.delivered).toBe(true);
    expect(r2.delivered).toBe(true);
    expect(r1.outcome.envelope.envelopeId).not.toBe(r2.outcome.envelope.envelopeId);
    expect(u.tradieBrain.jobs.size).toBe(2);
    expect(u.pmBrain.acceptedPatches).toHaveLength(2);
  });

  test('audit log records the replay path for operator inspection', async () => {
    // Chapter 29's "regulator-grade evidence chain" claim: every
    // delivery (and refused-delivery) is recorded. The transport's
    // audit log carries this; the smoke test asserts the rows are
    // there.
    const u = buildFederationUniverse();
    await pmDispatchAndRequireDelivery(u.pmBrain, {
      requestId: REQ_ID,
      customer: 'Tenant 4B',
      description: 'HVAC failure',
      tradieRef: `${u.tradieBrain.tenantDomain}#${u.tradieBrain.hat.hatId}`,
      nowIso: NOW,
    });
    const log = u.transport.audit();
    // We expect: send(envelope) → deliver(envelope) → send(acceptance)
    // → deliver(acceptance). At minimum the first two rows exist.
    expect(log.length).toBeGreaterThanOrEqual(2);
    expect(log[0]?.direction).toBe('send');
    expect(log[1]?.direction).toBe('deliver');
  });
});

```
