---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/__tests__/persist-effect.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.796215+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/__tests__/persist-effect.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import { effectBus, makePersistEffect, type PersistStore } from '../index';
import type { ChannelArtifacts, SpvProof } from '../../fsm';
import { validArtifacts, validSpv } from '../../fsm/__tests__/fixtures';

interface Captured {
  artifacts: Map<string, ChannelArtifacts>;
  spv: Map<string, SpvProof>;
  errors: string[];
}

function makeStore(): { store: PersistStore; cap: Captured } {
  const cap: Captured = {
    artifacts: new Map(),
    spv: new Map(),
    errors: [],
  };
  const store: PersistStore = {
    putArtifacts: async (id, a) => {
      cap.artifacts.set(id, a);
    },
    putSpv: async (id, p) => {
      cap.spv.set(id, p);
    },
    getArtifacts: async (id) => cap.artifacts.get(id) ?? null,
  };
  return { store, cap };
}

function silentLogger(errors: string[]) {
  return {
    info: () => {},
    warn: () => {},
    debug: () => {},
    error: (msg: string) => errors.push(msg),
  };
}

let dispose: (() => void) | null = null;
afterEach(() => {
  dispose?.();
  dispose = null;
});

describe('persist-effect', () => {
  test('1. persists artifacts on the first persist-artifacts cmd', async () => {
    const { store, cap } = makeStore();
    const eff = makePersistEffect({ store, logger: silentLogger(cap.errors) });
    dispose = eff.dispose;
    effectBus.emit({ type: 'persist-artifacts', channelId: 'c1', artifacts: validArtifacts });
    await new Promise((r) => setTimeout(r, 5));
    expect(cap.artifacts.get('c1')).toEqual(validArtifacts);
  });

  test('2. byte-freeze: rejects a second persist-artifacts with different bytes', async () => {
    const { store, cap } = makeStore();
    const eff = makePersistEffect({ store, logger: silentLogger(cap.errors) });
    dispose = eff.dispose;
    effectBus.emit({ type: 'persist-artifacts', channelId: 'c1', artifacts: validArtifacts });
    await new Promise((r) => setTimeout(r, 5));
    const tamperedArtifacts: ChannelArtifacts = {
      ...validArtifacts,
      simpleRawTx: 'ff'.repeat(16),
      simpleHash: 'fe'.repeat(32),
    };
    effectBus.emit({ type: 'persist-artifacts', channelId: 'c1', artifacts: tamperedArtifacts });
    await new Promise((r) => setTimeout(r, 5));
    // Still the original bytes.
    expect(cap.artifacts.get('c1')!.simpleRawTx).toEqual(validArtifacts.simpleRawTx);
    expect(cap.errors.some((e) => e.includes('byte-freeze'))).toBe(true);
  });

  test('3. idempotent: persisting the same artifacts twice is a no-op', async () => {
    const { store, cap } = makeStore();
    let putCount = 0;
    const counted: PersistStore = {
      ...store,
      putArtifacts: async (id, a) => {
        putCount++;
        cap.artifacts.set(id, a);
      },
    };
    const eff = makePersistEffect({ store: counted, logger: silentLogger(cap.errors) });
    dispose = eff.dispose;
    effectBus.emit({ type: 'persist-artifacts', channelId: 'c1', artifacts: validArtifacts });
    await new Promise((r) => setTimeout(r, 5));
    effectBus.emit({ type: 'persist-artifacts', channelId: 'c1', artifacts: validArtifacts });
    await new Promise((r) => setTimeout(r, 5));
    expect(putCount).toBe(1);
    expect(cap.errors.length).toBe(0);
  });

  test('4. persists spv proof on persist-spv', async () => {
    const { store, cap } = makeStore();
    const eff = makePersistEffect({ store, logger: silentLogger(cap.errors) });
    dispose = eff.dispose;
    effectBus.emit({ type: 'persist-spv', channelId: 'c1', proof: validSpv });
    await new Promise((r) => setTimeout(r, 5));
    expect(cap.spv.get('c1')).toEqual(validSpv);
  });

  test('5. dispose stops further persists', async () => {
    const { store, cap } = makeStore();
    const eff = makePersistEffect({ store, logger: silentLogger(cap.errors) });
    eff.dispose();
    dispose = null;
    effectBus.emit({ type: 'persist-artifacts', channelId: 'c1', artifacts: validArtifacts });
    await new Promise((r) => setTimeout(r, 5));
    expect(cap.artifacts.size).toBe(0);
  });
});

```
