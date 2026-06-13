---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/state-machines/lead-authorized-edge.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.492882+00:00
---

# cartridges/oddjobz/brain/tests/state-machines/lead-authorized-edge.test.ts

```ts
/**
 * SD2 incr.2 — focused conformance for the new `lead → authorized`
 * Job-FSM edge (ingested work-order / maintenance-order skips straight
 * to approved; the WO IS the authorisation).
 *
 * Deliberately NARROW: it asserts ONLY the new edge + that the
 * existing `lead → qualified` edge is undisturbed, and that
 * `findJobTransition` resolves the new edge. It does NOT assert the
 * total table shape — the pre-existing `§O4 Job FSM table shape`
 * block in job-fsm.test.ts is a STALE relic of the superseded 7-row
 * §O4 FSM (4 fails on pristine origin, the TS twin of the
 * JobFSM.lean drift) whose realign-vs-accept is a separate surfaced
 * operator ruling — incr.2 neither caused nor fixes it, so this test
 * stays orthogonal to it.
 *
 * Mirrors the Zig `job_fsm.zig` row-1 assertions (Zig is the canon;
 * declaration order = row order; this guards the TS mirror stays in
 * lockstep for the new row).
 */

import { describe, expect, test } from 'bun:test';
import { JOB_TRANSITIONS, findJobTransition } from '../../src/state-machines/job-fsm.js';

describe('SD2 incr.2 — lead→authorized edge (TS mirror, lockstep w/ Zig)', () => {
  test('the lead→authorized row exists, ungated/operator (mirror of qualified→authorized)', () => {
    const row = JOB_TRANSITIONS.find(
      (r) => r.from === 'lead' && r.to === 'authorized',
    );
    expect(row).toBeDefined();
    expect(row!.capRequired).toBeNull();
    expect(row!.principalKinds).toEqual(['operator']);
  });

  test('it is declared at row 1, right after the row-0 lead→qualified edge (Zig declaration-order parity)', () => {
    expect(JOB_TRANSITIONS[0]!.from).toBe('lead');
    expect(JOB_TRANSITIONS[0]!.to).toBe('qualified');
    expect(JOB_TRANSITIONS[1]!.from).toBe('lead');
    expect(JOB_TRANSITIONS[1]!.to).toBe('authorized');
  });

  test('lead→qualified (the ROM-accept edge) is undisturbed', () => {
    const q = JOB_TRANSITIONS.find(
      (r) => r.from === 'lead' && r.to === 'qualified',
    );
    expect(q).toBeDefined();
    expect(q!.capRequired).toBeNull();
    expect(q!.principalKinds).toEqual(['operator']);
  });

  test('findJobTransition resolves the new edge (router eligibility gate)', () => {
    const t = findJobTransition('lead', 'authorized');
    expect(t).toBeDefined();
    expect(t!.to).toBe('authorized');
  });
});

```
