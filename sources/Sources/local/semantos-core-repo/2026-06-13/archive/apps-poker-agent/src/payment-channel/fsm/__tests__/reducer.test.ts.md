---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/fsm/__tests__/reducer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.798379+00:00
---

# archive/apps-poker-agent/src/payment-channel/fsm/__tests__/reducer.test.ts

```ts
/**
 * channelReducer — 40+ transition cases covering the happy path
 * (UNFUNDED → … → CLOSED) plus every invariant rejection.
 */

import { describe, expect, test } from 'bun:test';
import { channelReducer } from '../reducer';
import type {
  ChannelEvent,
  ChannelStateValue,
} from '../types';
import {
  consumerKeyIds,
  freshState,
  fundedAndReady,
  validArtifacts,
  validSpv,
} from './fixtures';

function expectAdvanced(state: ChannelStateValue, target: ChannelStateValue['state']): void {
  expect(state.state).toBe(target);
  expect(state.lastError).toBeUndefined();
}

function expectRejected(state: ChannelStateValue, prior: ChannelStateValue['state']): void {
  expect(state.state).toBe(prior);
  expect(state.lastError).toBeDefined();
}

const fundEvent: Extract<ChannelEvent, { type: 'fund' }> = {
  type: 'fund',
  artifacts: validArtifacts,
  isNativeMultisig: true,
  keyIds: consumerKeyIds,
};

describe('happy path', () => {
  test('1. UNFUNDED → FUNDED on a clean fund event', () => {
    const out = channelReducer(freshState(), fundEvent);
    expectAdvanced(out.next, 'FUNDED');
    expect(out.next.artifacts).toEqual(validArtifacts);
    expect(out.next.isNativeMultisig).toBe(true);
    expect(out.emitted.map((c) => c.type)).toEqual(['persist-artifacts', 'mark-state']);
  });

  test('2. FUNDING_PENDING → FUNDED is allowed (idempotent)', () => {
    const start: ChannelStateValue = { ...freshState(), state: 'FUNDING_PENDING' };
    const out = channelReducer(start, fundEvent);
    expectAdvanced(out.next, 'FUNDED');
  });

  test('3. extract from FUNDED is a confirmation step (no state change)', () => {
    const start = channelReducer(freshState(), fundEvent).next;
    const out = channelReducer(start, { type: 'extract', vout: 0 });
    expectAdvanced(out.next, 'FUNDED');
  });

  test('4. attach-spv from FUNDED stores the proof without advancing state', () => {
    const start = channelReducer(freshState(), fundEvent).next;
    const out = channelReducer(start, { type: 'attach-spv', proof: validSpv });
    expect(out.next.state).toBe('FUNDED');
    expect(out.next.spvProof).toEqual(validSpv);
    expect(out.emitted.map((c) => c.type)).toEqual(['persist-spv']);
  });

  test('5. flow-ready promotes FUNDED → FLOW_READY when SPV is attached', () => {
    let s = channelReducer(freshState(), fundEvent).next;
    s = channelReducer(s, { type: 'attach-spv', proof: validSpv }).next;
    const out = channelReducer(s, { type: 'flow-ready' });
    expectAdvanced(out.next, 'FLOW_READY');
  });

  test('6. flow-activate / flow-deactivate toggle between FLOW_READY ↔ FLOW_ACTIVE', () => {
    let s = fundedAndReady();
    s = channelReducer(s, { type: 'flow-activate' }).next;
    expect(s.state).toBe('FLOW_ACTIVE');
    s = channelReducer(s, { type: 'flow-deactivate' }).next;
    expect(s.state).toBe('FLOW_READY');
  });

  test('7. settle-begin from FLOW_READY advances to SETTLING', () => {
    const out = channelReducer(fundedAndReady(), { type: 'settle-begin', spvProof: validSpv });
    expectAdvanced(out.next, 'SETTLING');
  });

  test('8. settle-begin from FLOW_ACTIVE also advances to SETTLING', () => {
    const start = channelReducer(fundedAndReady(), { type: 'flow-activate' }).next;
    const out = channelReducer(start, { type: 'settle-begin', spvProof: validSpv });
    expectAdvanced(out.next, 'SETTLING');
  });

  test('9. close from SETTLING advances to CLOSED', () => {
    let s = channelReducer(fundedAndReady(), { type: 'settle-begin', spvProof: validSpv }).next;
    s = channelReducer(s, { type: 'close' }).next;
    expect(s.state).toBe('CLOSED');
  });

  test('10. full UNFUNDED → CLOSED replay', () => {
    let s = freshState();
    s = channelReducer(s, fundEvent).next;
    s = channelReducer(s, { type: 'attach-spv', proof: validSpv }).next;
    s = channelReducer(s, { type: 'flow-ready' }).next;
    s = channelReducer(s, { type: 'flow-activate' }).next;
    s = channelReducer(s, { type: 'settle-begin', spvProof: validSpv }).next;
    s = channelReducer(s, { type: 'close' }).next;
    expect(s.state).toBe('CLOSED');
  });
});

describe('fund — invariant rejections', () => {
  test('11. rejected when current state is FUNDED already', () => {
    const out = channelReducer({ ...fundedAndReady(), state: 'CLOSED' }, fundEvent);
    expectRejected(out.next, 'CLOSED');
    expect(out.next.lastError).toMatch(/cannot fund/);
  });

  test('12. invariant 3 rejected when isNativeMultisig=false', () => {
    const out = channelReducer(freshState(), { ...fundEvent, isNativeMultisig: false });
    expectRejected(out.next, 'UNFUNDED');
    expect(out.next.lastError).toMatch(/invariant 3/);
  });

  test('13. invariant 4 rejected when keyID format is malformed', () => {
    const out = channelReducer(freshState(), {
      ...fundEvent,
      keyIds: [{ role: 'consumer', keyId: 'bogus' }],
    });
    expect(out.next.lastError).toMatch(/invariant 4/);
  });

  test('14. invariant 4 rejected when role prefix mismatches channel role', () => {
    const out = channelReducer(freshState('provider'), {
      ...fundEvent,
      keyIds: consumerKeyIds, // consumer prefix on a provider channel
    });
    expect(out.next.lastError).toMatch(/keyID role.*does not match channel role/);
  });

  test('15. re-fund attempts from FUNDED are gated by the state machine', () => {
    const after = channelReducer(freshState(), fundEvent).next;
    const out = channelReducer(after, {
      ...fundEvent,
      artifacts: { ...validArtifacts, envelopeHex: 'aabbcc' },
    });
    expect(out.next.lastError).toMatch(/cannot fund from FUNDED/);
    // Frozen bytes are still untouched on the prior state.
    expect(out.next.artifacts).toEqual(validArtifacts);
  });
});

describe('extract — gating', () => {
  test('16. rejected from UNFUNDED', () => {
    const out = channelReducer(freshState(), { type: 'extract', vout: 0 });
    expectRejected(out.next, 'UNFUNDED');
  });

  test('17. rejected when artifacts are missing (state corruption)', () => {
    const out = channelReducer(
      { ...freshState(), state: 'FUNDED' },
      { type: 'extract', vout: 0 },
    );
    expectRejected(out.next, 'FUNDED');
  });

  test('18. rejected on vout mismatch', () => {
    const after = channelReducer(freshState(), fundEvent).next;
    const out = channelReducer(after, { type: 'extract', vout: 1 });
    expect(out.next.lastError).toMatch(/vout mismatch/);
  });
});

describe('attach-spv — gating', () => {
  test('19. rejected from UNFUNDED', () => {
    const out = channelReducer(freshState(), { type: 'attach-spv', proof: validSpv });
    expectRejected(out.next, 'UNFUNDED');
  });

  test('20. rejected when SPV bumpHash is empty (invariant 2)', () => {
    const after = channelReducer(freshState(), fundEvent).next;
    const out = channelReducer(after, {
      type: 'attach-spv',
      proof: { ...validSpv, bumpHash: '' },
    });
    expect(out.next.lastError).toMatch(/invariant 2/);
  });
});

describe('flow-ready — gating', () => {
  test('21. rejected from UNFUNDED', () => {
    const out = channelReducer(freshState(), { type: 'flow-ready' });
    expectRejected(out.next, 'UNFUNDED');
  });

  test('22. rejected from FUNDED without SPV', () => {
    const after = channelReducer(freshState(), fundEvent).next;
    const out = channelReducer(after, { type: 'flow-ready' });
    expect(out.next.lastError).toMatch(/invariant 2/);
  });

  test('23. accepted from FUNDED with SPV', () => {
    let s = channelReducer(freshState(), fundEvent).next;
    s = channelReducer(s, { type: 'attach-spv', proof: validSpv }).next;
    const out = channelReducer(s, { type: 'flow-ready' });
    expectAdvanced(out.next, 'FLOW_READY');
  });

  test('24. rejected from FLOW_ACTIVE (already past FLOW_READY)', () => {
    const start = channelReducer(fundedAndReady(), { type: 'flow-activate' }).next;
    const out = channelReducer(start, { type: 'flow-ready' });
    expect(out.next.lastError).toMatch(/cannot enter FLOW_READY/);
  });
});

describe('flow-activate / flow-deactivate', () => {
  test('25. flow-activate rejected from FUNDED', () => {
    const out = channelReducer(
      { ...freshState(), state: 'FUNDED' },
      { type: 'flow-activate' },
    );
    expect(out.next.lastError).toMatch(/cannot activate flow/);
  });

  test('26. flow-deactivate rejected from FLOW_READY', () => {
    const out = channelReducer(fundedAndReady(), { type: 'flow-deactivate' });
    expect(out.next.lastError).toMatch(/cannot deactivate flow/);
  });

  test('27. flow-deactivate from FLOW_ACTIVE returns to FLOW_READY', () => {
    const start = channelReducer(fundedAndReady(), { type: 'flow-activate' }).next;
    const out = channelReducer(start, { type: 'flow-deactivate' });
    expectAdvanced(out.next, 'FLOW_READY');
  });
});

describe('settle-begin — gating', () => {
  test('28. rejected from FUNDED', () => {
    const after = channelReducer(freshState(), fundEvent).next;
    const out = channelReducer(after, { type: 'settle-begin', spvProof: validSpv });
    expect(out.next.lastError).toMatch(/cannot settle/);
  });

  test('29. rejected from UNFUNDED', () => {
    const out = channelReducer(freshState(), { type: 'settle-begin', spvProof: validSpv });
    expectRejected(out.next, 'UNFUNDED');
  });

  test('30. rejected without SPV proof (invariant 2)', () => {
    const out = channelReducer(fundedAndReady(), {
      type: 'settle-begin',
      spvProof: { ...validSpv, bumpHash: '' },
    });
    expect(out.next.lastError).toMatch(/invariant 2/);
  });
});

describe('close — gating', () => {
  test('31. rejected from UNFUNDED', () => {
    const out = channelReducer(freshState(), { type: 'close' });
    expectRejected(out.next, 'UNFUNDED');
  });
  test('32. rejected from FLOW_READY', () => {
    const out = channelReducer(fundedAndReady(), { type: 'close' });
    expect(out.next.lastError).toMatch(/cannot close/);
  });
  test('33. accepted from SETTLING', () => {
    let s = channelReducer(fundedAndReady(), { type: 'settle-begin', spvProof: validSpv }).next;
    s = channelReducer(s, { type: 'close' }).next;
    expect(s.state).toBe('CLOSED');
  });
});

describe('emitted commands', () => {
  test('34. fund emits persist-artifacts + mark-state in order', () => {
    const out = channelReducer(freshState(), fundEvent);
    expect(out.emitted).toEqual([
      { type: 'persist-artifacts', artifacts: validArtifacts },
      { type: 'mark-state', state: 'FUNDED' },
    ]);
  });

  test('35. attach-spv emits persist-spv only', () => {
    const after = channelReducer(freshState(), fundEvent).next;
    const out = channelReducer(after, { type: 'attach-spv', proof: validSpv });
    expect(out.emitted).toEqual([{ type: 'persist-spv', proof: validSpv }]);
  });

  test('36. settle-begin emits persist-spv + mark-state', () => {
    const out = channelReducer(fundedAndReady(), { type: 'settle-begin', spvProof: validSpv });
    expect(out.emitted.map((c) => c.type)).toEqual(['persist-spv', 'mark-state']);
  });

  test('37. close emits a single mark-state', () => {
    let s = channelReducer(fundedAndReady(), { type: 'settle-begin', spvProof: validSpv }).next;
    const out = channelReducer(s, { type: 'close' });
    expect(out.emitted).toEqual([{ type: 'mark-state', state: 'CLOSED' }]);
  });

  test('38. rejected events emit no commands', () => {
    const out = channelReducer(freshState(), { type: 'flow-ready' });
    expect(out.emitted).toEqual([]);
  });
});

describe('reducer purity', () => {
  test('39. reducer never mutates the input state', () => {
    const before = freshState();
    const snapshot = JSON.stringify(before);
    channelReducer(before, fundEvent);
    expect(JSON.stringify(before)).toBe(snapshot);
  });

  test('40. lastError is cleared on a successful subsequent transition', () => {
    let s = freshState();
    s = channelReducer(s, { type: 'flow-ready' }).next; // rejected — populates lastError
    expect(s.lastError).toBeDefined();
    s = channelReducer(s, fundEvent).next;
    expect(s.lastError).toBeUndefined();
  });

  test('41. unknown event yields lastError without state change', () => {
    const before = freshState();
    const out = channelReducer(before, { type: 'mystery' as never });
    expect(out.next.state).toBe(before.state);
    expect(out.next.lastError).toMatch(/unknown event/);
    expect(out.emitted).toEqual([]);
  });

  test('42. fund stores merged keyIds dedup-ed by keyId string', () => {
    const after = channelReducer(freshState(), fundEvent).next;
    const merged = channelReducer(after, fundEvent);
    expect(merged.next.keyIds.length).toBe(consumerKeyIds.length);
  });
});

```
