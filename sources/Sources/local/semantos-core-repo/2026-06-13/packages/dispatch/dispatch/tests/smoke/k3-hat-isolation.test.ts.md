---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/tests/smoke/k3-hat-isolation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.515038+00:00
---

# packages/dispatch/dispatch/tests/smoke/k3-hat-isolation.test.ts

```ts
/**
 * D-O11 phase O11c — K3 hat-isolation tests for the cross-vertical case.
 *
 * Per ODDJOBZ-EXTENSION-PLAN.md §3 phase O11 acceptance:
 *   (3) AFFINE patches authored under tradie-MARGIN hat are NOT
 *       visible to PM hat.
 *   (4) AFFINE patches authored under PM-OWNER hat are NOT visible
 *       to tradie hat.
 *
 * The K3 enforcement is cryptographic per
 * `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean` and the
 * `oddjobz_cap_isolation_cryptographic` corollary in
 * `proofs/lean/Semantos/Capabilities/Oddjobz.lean` line 283 (PR #279).
 * The §2.5 carpenter+musician property generalises here to PM/tradie
 * cross-vertical: each hat has its own contextTag; AFFINE patches
 * under hat A's contextTag cannot be decrypted under hat B's child
 * key.
 *
 * The harness models this filter-at-read-time (decryption-failure is
 * the substrate seam; here we filter by contextTag match, mirroring
 * what the BKDS-derived child key would expose). The test asserts
 * the structural invisibility property the K3 theorem proves.
 */

import { describe, expect, test } from 'bun:test';

import {
  PM_HAT_CONTEXT_TAG,
  PM_OWNER_HAT_CONTEXT_TAG,
  TRADIE_HAT_CONTEXT_TAG,
  TRADIE_MARGIN_HAT_CONTEXT_TAG,
  buildFederationUniverse,
  pmDispatchAndRequireDelivery,
  pmWriteOwnerFinancialPatch,
  readAffinePatchesUnderHat,
  tradieCompleteJob,
  tradieWriteMarginNotePatch,
} from './two-brain-harness.js';

const REQ_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const NOW = '2026-05-01T09:00:00.000Z';

describe('§O11c — K3 cross-vertical hat-isolation', () => {
  test('[§O11 acceptance #3] PM hat cannot read tradie\'s margin-notes AFFINE patches', async () => {
    const u = buildFederationUniverse();
    const dispatch = await pmDispatchAndRequireDelivery(u.pmBrain, {
      requestId: REQ_ID,
      customer: 'Tenant 4B',
      description: 'HVAC failure',
      tradieRef: `${u.tradieBrain.tenantDomain}#${u.tradieBrain.hat.hatId}`,
      nowIso: NOW,
    });
    expect(dispatch.delivered).toBe(true);

    // Tradie writes a margin-notes AFFINE patch under contextTag 0x11
    // (TRADIE_MARGIN_HAT_CONTEXT_TAG). The patch is structurally
    // encrypted to that hat's BKDS-derived child key.
    tradieWriteMarginNotePatch(u.tradieBrain, {
      jobId: REQ_ID,
      note: '$120/h labour, $400 parts markup, retain 35% margin',
    });
    tradieWriteMarginNotePatch(u.tradieBrain, {
      jobId: REQ_ID,
      note: 'Customer is repeat — discount considered for next job',
    });

    expect(u.tradieBrain.marginNotePatches).toHaveLength(2);
    expect(u.tradieBrain.marginNotePatches.every(
      (p) => p.contextTag === TRADIE_MARGIN_HAT_CONTEXT_TAG,
    )).toBe(true);

    // Tradie reading under their own margin-hat: SEES BOTH PATCHES.
    const tradieView = readAffinePatchesUnderHat(
      u.tradieBrain.marginNotePatches,
      TRADIE_MARGIN_HAT_CONTEXT_TAG,
    );
    expect(tradieView).toHaveLength(2);

    // PM hat (contextTag 0x20) reading the same patches: SEES NONE.
    // BKDS-derived key for contextTag 0x20 cannot decrypt patches
    // encrypted to contextTag 0x11; the K3 cryptographic gate
    // structurally rejects the decryption attempt.
    const pmView = readAffinePatchesUnderHat(
      u.tradieBrain.marginNotePatches,
      PM_HAT_CONTEXT_TAG,
    );
    expect(pmView).toHaveLength(0);

    // PM-OWNER hat (contextTag 0x21) — also blocked.
    const pmOwnerView = readAffinePatchesUnderHat(
      u.tradieBrain.marginNotePatches,
      PM_OWNER_HAT_CONTEXT_TAG,
    );
    expect(pmOwnerView).toHaveLength(0);
  });

  test('[§O11 acceptance #4] tradie hat cannot read PM\'s owner-financial AFFINE patches', async () => {
    const u = buildFederationUniverse();
    const dispatch = await pmDispatchAndRequireDelivery(u.pmBrain, {
      requestId: REQ_ID,
      customer: 'Tenant 4B',
      description: 'HVAC failure',
      tradieRef: `${u.tradieBrain.tenantDomain}#${u.tradieBrain.hat.hatId}`,
      nowIso: NOW,
    });
    expect(dispatch.delivered).toBe(true);

    // PM authors owner-financial AFFINE patches under PM-OWNER hat
    // (contextTag 0x21).
    pmWriteOwnerFinancialPatch(u.pmBrain, {
      requestId: REQ_ID,
      note: 'Owner cost ceiling: $2000 — auto-approve below this',
    });
    pmWriteOwnerFinancialPatch(u.pmBrain, {
      requestId: REQ_ID,
      note: 'Lease SLA: 4-hour HVAC response; insurance covers above $1500',
    });

    expect(u.pmBrain.ownerFinancialPatches).toHaveLength(2);
    expect(u.pmBrain.ownerFinancialPatches.every(
      (p) => p.contextTag === PM_OWNER_HAT_CONTEXT_TAG,
    )).toBe(true);

    // PM-OWNER hat reading: SEES BOTH PATCHES.
    const ownerView = readAffinePatchesUnderHat(
      u.pmBrain.ownerFinancialPatches,
      PM_OWNER_HAT_CONTEXT_TAG,
    );
    expect(ownerView).toHaveLength(2);

    // Tradie hat (contextTag 0x10) reading: SEES NONE.
    const tradieView = readAffinePatchesUnderHat(
      u.pmBrain.ownerFinancialPatches,
      TRADIE_HAT_CONTEXT_TAG,
    );
    expect(tradieView).toHaveLength(0);

    // Tradie-MARGIN sub-hat (contextTag 0x11) — also blocked. The
    // chapter-29 worked example has the tradie's compliance ledger
    // AND margin notes both AFFINE — neither can read PM owner.
    const tradieMarginView = readAffinePatchesUnderHat(
      u.pmBrain.ownerFinancialPatches,
      TRADIE_MARGIN_HAT_CONTEXT_TAG,
    );
    expect(tradieMarginView).toHaveLength(0);
  });

  test('every AFFINE patch is hat-keyed; reader-key mismatch ⇒ empty result', async () => {
    // Per the BRAIN-DISPATCHER-UNIFICATION.md §2.5 carpenter+musician
    // property: a patch under contextTag X is read-visible only to a
    // reader under contextTag X. The cross-vertical case is no
    // different — that's the architectural claim D-O11 establishes.
    const u = buildFederationUniverse();
    await pmDispatchAndRequireDelivery(u.pmBrain, {
      requestId: REQ_ID,
      customer: 'Tenant 4B',
      description: 'HVAC failure',
      tradieRef: `${u.tradieBrain.tenantDomain}#${u.tradieBrain.hat.hatId}`,
      nowIso: NOW,
    });
    pmWriteOwnerFinancialPatch(u.pmBrain, {
      requestId: REQ_ID,
      note: 'one PM owner patch',
    });
    tradieWriteMarginNotePatch(u.tradieBrain, {
      jobId: REQ_ID,
      note: 'one tradie margin patch',
    });

    // Test every cross-pair: reader key ≠ writer key ⇒ 0 patches.
    const ALL_TAGS = [
      PM_HAT_CONTEXT_TAG,
      PM_OWNER_HAT_CONTEXT_TAG,
      TRADIE_HAT_CONTEXT_TAG,
      TRADIE_MARGIN_HAT_CONTEXT_TAG,
    ];
    for (const readerTag of ALL_TAGS) {
      const pmPatches = readAffinePatchesUnderHat(
        u.pmBrain.ownerFinancialPatches,
        readerTag,
      );
      const tradiePatches = readAffinePatchesUnderHat(
        u.tradieBrain.marginNotePatches,
        readerTag,
      );
      const expectedPm = readerTag === PM_OWNER_HAT_CONTEXT_TAG ? 1 : 0;
      const expectedTradie = readerTag === TRADIE_MARGIN_HAT_CONTEXT_TAG ? 1 : 0;
      expect(pmPatches).toHaveLength(expectedPm);
      expect(tradiePatches).toHaveLength(expectedTradie);
    }
  });
});

```
