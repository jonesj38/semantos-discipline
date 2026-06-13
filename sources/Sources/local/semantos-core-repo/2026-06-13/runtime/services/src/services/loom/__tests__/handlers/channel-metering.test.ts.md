---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/__tests__/handlers/channel-metering.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.121888+00:00
---

# runtime/services/src/services/loom/__tests__/handlers/channel-metering.test.ts

```ts
/**
 * channel-metering handler tests.
 *
 * The handler family takes ports as arguments; tests pass stub
 * implementations so we can verify dispatch ordering, witness-hash
 * chaining, balance/cumulative bookkeeping, and dispute/settlement
 * cascades without touching the live PlexusService / CashLanesService.
 */

import { describe, expect, test } from 'bun:test';
import { atom, get, type Atom } from '@semantos/state';

import {
  advanceChannelPhase,
  createPaymentChannel,
  recordChannelTransaction,
  recordSettlement,
  type ChannelMeteringPorts,
} from '../../handlers/channel-metering';
import { freshInitialState } from '../../loom-atoms';
import type { LoomState } from '../../loom-types';
import type {
  ChannelLifecycleFlow,
  GuardContext,
  PhaseTransitionResult,
} from '../../FlowRunner';
import { makeTypeDef } from '../fixtures';

function freshAtom(): Atom<LoomState> {
  return atom<LoomState>(freshInitialState());
}

function stubPlexus(currentCertId?: string): ChannelMeteringPorts['plexus'] {
  return {
    getSnapshot: () => ({
      currentIdentity: currentCertId ? { certId: currentCertId } : undefined,
    }),
    deriveChild: async (_p, _r, _d) => ({ certId: `cert-derived` }),
    createEdge: async (_a, _b) => ({ edgeId: 'edge-1', sharedSecret: new Uint8Array([1, 2]) }),
  };
}

function stubCashLanes(): ChannelMeteringPorts['cashLanes'] {
  return {
    prepareCashLanesSettlement: async (id, owner, _c, _f) => ({
      unsignedTx: `unsigned:${id}:${owner}`,
      channelId: id,
      ownerAmount: owner,
      counterpartyAmount: 0,
    }),
    collectCashLanesSignatures: async (_id, _cert, _tx) => ({
      ownerSig: 'owner-sig',
      counterpartySig: 'counterparty-sig',
    }),
    broadcastCashLanesSettlement: async (_id, _tx, _sigs) => ({
      txid: 'tx-deadbeef',
      broadcastTime: 1,
      status: 'broadcast',
    }),
    awaitCashLanesConfirmation: async (_id) => ({ confirmed: true }),
  };
}

function stubFlowRunner(transitionResult: PhaseTransitionResult): ChannelMeteringPorts['flowRunner'] {
  return { transitionPhase: () => transitionResult };
}

const stubHash: ChannelMeteringPorts['hash'] = {
  sha256hex: async (input) => `hash:${input.length}`,
};

function makePorts(over: Partial<ChannelMeteringPorts> = {}): ChannelMeteringPorts {
  return {
    plexus: over.plexus ?? stubPlexus(),
    cashLanes: over.cashLanes ?? stubCashLanes(),
    flowRunner: over.flowRunner ?? stubFlowRunner({ ok: true }),
    hash: over.hash ?? stubHash,
  };
}

describe('createPaymentChannel', () => {
  test('1. seeds payload fields and dispatches the new object', async () => {
    const a = freshAtom();
    const id = await createPaymentChannel(a, makePorts(), {
      typeDef: makeTypeDef({ name: 'Channel' }),
      counterpartyCertId: 'cp-1',
      fundingSatoshis: 1000,
      policyObjectId: 'pol-1',
      meterUnit: 'msg',
      hatId: 'hat-1',
    });
    const obj = get(a).objects.get(id);
    expect(obj?.payload.status).toBe('prefunding');
    expect(obj?.payload.counterpartyCertId).toBe('cp-1');
    expect(obj?.payload.fundingSatoshis).toBe(1000);
    expect(obj?.payload.cumulativeSatoshis).toBe(0);
  });

  test('2. when plexus has a current identity, derives channel cert and creates an edge', async () => {
    const a = freshAtom();
    const id = await createPaymentChannel(a, makePorts({ plexus: stubPlexus('cert-me') }), {
      typeDef: makeTypeDef(),
      counterpartyCertId: 'cp-2',
      fundingSatoshis: 500,
      policyObjectId: 'pol-2',
      meterUnit: 'tick',
      hatId: 'hat-2',
    });
    const obj = get(a).objects.get(id);
    expect(obj?.payload.channelCertId).toBe('cert-derived');
    expect(obj?.payload.counterpartyEdgeId).toBe('edge-1');
    expect(obj?.payload.sharedSecret).toEqual(new Uint8Array([1, 2]));
  });

  test('3. plexus failure does not block the channel from being created', async () => {
    const a = freshAtom();
    const failing: ChannelMeteringPorts['plexus'] = {
      getSnapshot: () => ({ currentIdentity: { certId: 'me' } }),
      deriveChild: async () => { throw new Error('plexus down'); },
      createEdge: async () => { throw new Error('unreachable'); },
    };
    const id = await createPaymentChannel(a, makePorts({ plexus: failing }), {
      typeDef: makeTypeDef(),
      counterpartyCertId: 'cp-3',
      fundingSatoshis: 1,
      policyObjectId: 'pol-3',
      meterUnit: 'tick',
      hatId: 'hat-3',
    });
    expect(get(a).objects.get(id)?.payload.channelCertId).toBeUndefined();
  });

  test('4. attaches a creation patch with channel_opened action', async () => {
    const a = freshAtom();
    const id = await createPaymentChannel(a, makePorts(), {
      typeDef: makeTypeDef(),
      counterpartyCertId: 'cp-4',
      fundingSatoshis: 0,
      policyObjectId: 'pol-4',
      meterUnit: 'msg',
      hatId: 'hat-4',
      hatCapabilities: [10],
    });
    const last = get(a).objects.get(id)?.patches[0];
    expect(last?.delta.action).toBe('channel_opened');
    expect(last?.delta.counterpartyCertId).toBe('cp-4');
    expect(last?.hatCapabilities).toEqual([10]);
  });
});

describe('advanceChannelPhase', () => {
  function emptyLifecycle(): ChannelLifecycleFlow {
    return { phases: [] } as unknown as ChannelLifecycleFlow;
  }
  const emptyContext = {} as unknown as GuardContext;

  test('5. returns a not-found result when the object is missing', async () => {
    const a = freshAtom();
    const result = await advanceChannelPhase(a, makePorts(), {
      objectId: 'missing',
      lifecycle: emptyLifecycle(),
      targetPhase: 'metered',
      context: emptyContext,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/Object not found/);
  });

  test('6. happy path updates payload.status, appends a transition patch, returns ok', async () => {
    const a = freshAtom();
    const id = await createPaymentChannel(a, makePorts(), {
      typeDef: makeTypeDef(),
      counterpartyCertId: 'cp',
      fundingSatoshis: 0,
      policyObjectId: 'pol',
      meterUnit: 'msg',
      hatId: 'hat-x',
    });
    const result = await advanceChannelPhase(
      a,
      makePorts({ flowRunner: stubFlowRunner({ ok: true }) }),
      {
        objectId: id,
        lifecycle: emptyLifecycle(),
        targetPhase: 'metered',
        context: emptyContext,
      },
    );
    expect(result.ok).toBe(true);
    const obj = get(a).objects.get(id);
    expect(obj?.payload.status).toBe('metered');
    const last = obj?.patches.slice(-1)[0];
    expect(last?.kind).toBe('state_transition');
    expect(last?.delta.toPhase).toBe('metered');
  });

  test('7. flowRunner failure short-circuits — no payload mutation, no patch appended', async () => {
    const a = freshAtom();
    const id = await createPaymentChannel(a, makePorts(), {
      typeDef: makeTypeDef(),
      counterpartyCertId: 'cp',
      fundingSatoshis: 0,
      policyObjectId: 'pol',
      meterUnit: 'msg',
      hatId: 'hat-x',
    });
    const patchesBefore = get(a).objects.get(id)?.patches.length ?? 0;
    const result = await advanceChannelPhase(
      a,
      makePorts({ flowRunner: stubFlowRunner({ ok: false, reason: 'guard fail' }) }),
      {
        objectId: id,
        lifecycle: emptyLifecycle(),
        targetPhase: 'metered',
        context: emptyContext,
      },
    );
    expect(result.ok).toBe(false);
    expect(get(a).objects.get(id)?.payload.status).toBe('prefunding');
    expect(get(a).objects.get(id)?.patches.length).toBe(patchesBefore);
  });
});

describe('recordChannelTransaction', () => {
  test('8. throws when the channel object is missing', async () => {
    const a = freshAtom();
    await expect(
      recordChannelTransaction(a, { hash: stubHash }, {
        objectId: 'missing',
        from: 'a',
        to: 'b',
        amount: 1,
        meterUnit: 'msg',
      }),
    ).rejects.toThrow(/Object not found/);
  });

  test('9. appends a channel_transaction patch and increments balance + cumulative + tick', async () => {
    const a = freshAtom();
    const id = await createPaymentChannel(a, makePorts(), {
      typeDef: makeTypeDef(),
      counterpartyCertId: 'cp',
      fundingSatoshis: 0,
      policyObjectId: 'pol',
      meterUnit: 'msg',
      hatId: 'hat-x',
    });
    await recordChannelTransaction(a, { hash: stubHash }, {
      objectId: id,
      from: 'me',
      to: 'cp',
      amount: 25,
      meterUnit: 'msg',
    });
    const obj = get(a).objects.get(id);
    const tx = obj?.patches.slice(-1)[0];
    expect(tx?.kind).toBe('channel_transaction');
    expect(tx?.delta.amount).toBe(25);
    expect(obj?.payload.cumulativeSatoshis).toBe(25);
    expect((obj?.payload.balanceTracking as Record<string, number>).cp).toBe(25);
    expect(obj?.payload.currentTick).toBe(1);
  });

  test('10. multiple recordings accumulate balance + tick monotonically', async () => {
    const a = freshAtom();
    const id = await createPaymentChannel(a, makePorts(), {
      typeDef: makeTypeDef(),
      counterpartyCertId: 'cp',
      fundingSatoshis: 0,
      policyObjectId: 'pol',
      meterUnit: 'msg',
      hatId: 'hat-x',
    });
    for (const amount of [10, 20, 30]) {
      await recordChannelTransaction(a, { hash: stubHash }, {
        objectId: id,
        from: 'me',
        to: 'cp',
        amount,
        meterUnit: 'msg',
      });
    }
    const obj = get(a).objects.get(id)!;
    expect(obj.payload.cumulativeSatoshis).toBe(60);
    expect((obj.payload.balanceTracking as Record<string, number>).cp).toBe(60);
    expect(obj.payload.currentTick).toBe(3);
  });
});

describe('recordSettlement', () => {
  test('11. confirmed settlement sets settlementConfirmed=true', async () => {
    const a = freshAtom();
    const id = await createPaymentChannel(a, makePorts(), {
      typeDef: makeTypeDef(),
      counterpartyCertId: 'cp',
      fundingSatoshis: 0,
      policyObjectId: 'pol',
      meterUnit: 'msg',
      hatId: 'hat-x',
    });
    await recordSettlement(a, { cashLanes: stubCashLanes() }, { objectId: id });
    const obj = get(a).objects.get(id);
    expect(obj?.payload.settlementConfirmed).toBe(true);
    expect(obj?.payload.settlementTxId).toBe('tx-deadbeef');
  });

  test('12. unconfirmed settlement leaves settlementConfirmed undefined', async () => {
    const a = freshAtom();
    const id = await createPaymentChannel(a, makePorts(), {
      typeDef: makeTypeDef(),
      counterpartyCertId: 'cp',
      fundingSatoshis: 0,
      policyObjectId: 'pol',
      meterUnit: 'msg',
      hatId: 'hat-x',
    });
    const cashLanes = {
      ...stubCashLanes(),
      awaitCashLanesConfirmation: async () => ({ confirmed: false }),
    };
    await recordSettlement(a, { cashLanes }, { objectId: id });
    expect(get(a).objects.get(id)?.payload.settlementConfirmed).toBe(false);
  });
});

```
