---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/__tests__/lifecycle.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.794520+00:00
---

# archive/apps-poker-agent/src/payment-channel/__tests__/lifecycle.test.ts

```ts
/**
 * Full payment-channel lifecycle integration test.
 *
 * Drives a single channel from UNFUNDED → CLOSED through the facade,
 * with every effect atom wired against in-memory test doubles. Asserts:
 *
 *   - Final reducer state is CLOSED
 *   - Frozen artifacts match the bytes we passed in
 *   - Persist effect captured those exact bytes
 *   - Broadcast effect saw funding + settlement rawTx
 *   - Fee-credit effect tallied the expected sats
 *   - Log effect produced the golden command sequence
 */

import { afterEach, describe, expect, test } from 'bun:test';
import {
  broadcasterPort,
  type BroadcastResult,
} from '@semantos/protocol-types/ports';
import {
  bindConsumer,
  bootEffects,
  close,
  effectBus,
  fund,
  getState,
  internalizeConsumer,
  internalizeProvider,
  resetChannelAtoms,
  settle,
  shutdownEffects,
  type EffectHandles,
  type PersistStore,
} from '../index';
import { GOLDEN_LIFECYCLE_LOG } from './golden-log';
import {
  consumerKeyIds,
  validArtifacts,
  validSpv,
} from '../fsm/__tests__/fixtures';

afterEach(() => {
  shutdownEffects();
  resetChannelAtoms();
  broadcasterPort.unbind();
});

function makePersistStore(cap: {
  artifacts: Map<string, unknown>;
  spv: Map<string, unknown>;
}): PersistStore {
  return {
    putArtifacts: async (id, a) => {
      cap.artifacts.set(id, a);
    },
    putSpv: async (id, p) => {
      cap.spv.set(id, p);
    },
    getArtifacts: async (id) => (cap.artifacts.get(id) as never) ?? null,
  };
}

describe('payment-channel lifecycle', () => {
  test('1. UNFUNDED → FUNDED → FLOW_READY → SETTLING → CLOSED', async () => {
    const cap = { artifacts: new Map(), spv: new Map() };
    const broadcasts: { label: string; raw: string }[] = [];
    broadcasterPort.bind({
      broadcast: async (raw): Promise<BroadcastResult> => {
        broadcasts.push({ label: 'unknown', raw: typeof raw === 'string' ? raw : '' });
        return { ok: true, txid: 'broadcast-txid' };
      },
    });
    const handles: EffectHandles = bootEffects({
      persistStore: makePersistStore(cap),
      skipPortBinding: true,
    });

    fund({
      channelId: 'lc-1',
      role: 'consumer',
      artifacts: validArtifacts,
      isNativeMultisig: true,
      keyIds: consumerKeyIds,
    });

    // Wait for async effects (persist + broadcast).
    await new Promise((r) => setTimeout(r, 10));

    bindConsumer({ channelId: 'lc-1', proof: validSpv });
    internalizeConsumer('lc-1');
    internalizeProvider('lc-1');
    settle({
      channelId: 'lc-1',
      spvProof: validSpv,
      settlementRawTx: 'beef'.repeat(8),
    });
    await new Promise((r) => setTimeout(r, 10));

    const closed = close({ channelId: 'lc-1' });
    expect(closed.state).toBe('CLOSED');

    // Final state.
    expect(getState('lc-1').state).toBe('CLOSED');

    // Persist captured the frozen artifacts.
    expect(cap.artifacts.get('lc-1')).toEqual(validArtifacts);
    expect(cap.spv.get('lc-1')).toEqual(validSpv);

    // Broadcast saw funding rawTx + settlement rawTx.
    expect(broadcasts.length).toBeGreaterThanOrEqual(2);
    expect(broadcasts.some((b) => b.raw === validArtifacts.simpleRawTx)).toBe(true);
    expect(broadcasts.some((b) => b.raw === 'beef'.repeat(8))).toBe(true);

    // Fee-credit accounting: 1 fund + 2 ticks + 1 settle = 4.
    expect(handles.feeCredit.totalForChannel('lc-1')).toBe(4);
  });

  test('2. log effect emits the golden command sequence', async () => {
    const entries: { cmd: string; state?: string; label?: string; reason?: string; event?: string }[] = [];
    const persist = {
      putArtifacts: async () => {},
      putSpv: async () => {},
      getArtifacts: async () => null,
    };
    broadcasterPort.bind({
      broadcast: async () => ({ ok: true, txid: 't' }) as BroadcastResult,
    });

    bootEffects({
      persistStore: persist,
      skipPortBinding: true,
      swap: {
        log: {
          dispose: effectBus.on((cmd) => {
            const entry: { cmd: string; state?: string; label?: string; reason?: string; event?: string } = {
              cmd: cmd.type,
            };
            if (cmd.type === 'mark-state') entry.state = cmd.state;
            if (cmd.type === 'broadcast') entry.label = cmd.label;
            if (cmd.type === 'fee-credit') entry.reason = cmd.reason;
            if (cmd.type === 'emit-event') entry.event = cmd.event.type;
            entries.push(entry);
          }),
        },
      },
    });

    fund({
      channelId: 'lc-2',
      role: 'consumer',
      artifacts: validArtifacts,
      isNativeMultisig: true,
      keyIds: consumerKeyIds,
    });
    await new Promise((r) => setTimeout(r, 5));
    bindConsumer({ channelId: 'lc-2', proof: validSpv });
    internalizeConsumer('lc-2');
    internalizeProvider('lc-2');
    settle({
      channelId: 'lc-2',
      spvProof: validSpv,
      settlementRawTx: 'cafebabe',
    });
    close({ channelId: 'lc-2' });
    await new Promise((r) => setTimeout(r, 10));

    expect(entries).toEqual(GOLDEN_LIFECYCLE_LOG);
  });

  test('3. effects can be swapped — persist swap captures via custom hook', async () => {
    const seen: string[] = [];
    const cap = { artifacts: new Map(), spv: new Map() };
    bootEffects({
      persistStore: makePersistStore(cap),
      skipPortBinding: true,
      swap: {
        persist: {
          dispose: effectBus.on((cmd) => {
            if (cmd.type === 'persist-artifacts') seen.push(cmd.artifacts.txid);
          }),
        },
      },
    });
    broadcasterPort.bind({
      broadcast: async () => ({ ok: true, txid: 't' }) as BroadcastResult,
    });
    fund({
      channelId: 'lc-3',
      role: 'consumer',
      artifacts: validArtifacts,
      isNativeMultisig: true,
      keyIds: consumerKeyIds,
    });
    await new Promise((r) => setTimeout(r, 5));
    expect(seen).toEqual([validArtifacts.txid]);
    // Default persist store stayed empty because we swapped it.
    expect(cap.artifacts.size).toBe(0);
  });
});

```
