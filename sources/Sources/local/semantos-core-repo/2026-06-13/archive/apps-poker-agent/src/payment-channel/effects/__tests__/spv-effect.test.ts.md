---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/__tests__/spv-effect.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.796817+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/__tests__/spv-effect.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import { spvPort } from '@semantos/protocol-types/ports';
import { effectBus, makeSpvEffect } from '../index';

let dispose: (() => void) | null = null;

afterEach(() => {
  dispose?.();
  dispose = null;
  spvPort.unbind();
});

function silent() {
  return {
    info: () => {},
    warn: () => {},
    debug: () => {},
    error: () => {},
  };
}

describe('spv-effect', () => {
  test('1. resolves true once the proofSource produces an entry at min depth', async () => {
    let polls = 0;
    spvPort.bind({
      verifyBeef: async () => true,
      verifyBump: async () => true,
    });
    let resolved: boolean | null = null;
    const eff = makeSpvEffect({
      pollMs: 1,
      maxPolls: 5,
      logger: silent(),
      proofSource: async () => {
        polls++;
        return polls >= 2 ? { beef: 'beef-bytes', depth: 6 } : null;
      },
      onResolved: (_, ok) => {
        resolved = ok;
      },
    });
    dispose = eff.dispose;
    effectBus.emit({
      type: 'await-spv',
      channelId: 'c1',
      txid: 'tx-1',
      minConfirmations: 6,
    });
    await new Promise((r) => setTimeout(r, 30));
    expect(resolved).toBe(true);
  });

  test('2. times out (resolves false) after maxPolls when proof never appears', async () => {
    spvPort.bind({
      verifyBeef: async () => true,
      verifyBump: async () => true,
    });
    let resolved: boolean | null = null;
    const eff = makeSpvEffect({
      pollMs: 1,
      maxPolls: 3,
      logger: silent(),
      proofSource: async () => null,
      onResolved: (_, ok) => {
        resolved = ok;
      },
    });
    dispose = eff.dispose;
    effectBus.emit({
      type: 'await-spv',
      channelId: 'c1',
      txid: 'tx-2',
      minConfirmations: 1,
    });
    await new Promise((r) => setTimeout(r, 30));
    expect(resolved).toBe(false);
  });

  test('3. rejects depth below minConfirmations', async () => {
    spvPort.bind({
      verifyBeef: async () => true,
      verifyBump: async () => true,
    });
    let resolved: boolean | null = null;
    const eff = makeSpvEffect({
      pollMs: 1,
      maxPolls: 2,
      logger: silent(),
      proofSource: async () => ({ beef: 'b', depth: 1 }),
      onResolved: (_, ok) => {
        resolved = ok;
      },
    });
    dispose = eff.dispose;
    effectBus.emit({
      type: 'await-spv',
      channelId: 'c1',
      txid: 'tx-3',
      minConfirmations: 6,
    });
    await new Promise((r) => setTimeout(r, 30));
    expect(resolved).toBe(false);
  });

  test('4. resolves false when neither verifier nor proofSource bound', async () => {
    let resolved: boolean | null = null;
    const eff = makeSpvEffect({
      logger: silent(),
      onResolved: (_, ok) => {
        resolved = ok;
      },
    });
    dispose = eff.dispose;
    effectBus.emit({
      type: 'await-spv',
      channelId: 'c1',
      txid: 'tx-4',
      minConfirmations: 1,
    });
    await new Promise((r) => setTimeout(r, 5));
    expect(resolved).toBe(false);
  });

  test('5. dispose stops polling new commands', async () => {
    let calls = 0;
    const eff = makeSpvEffect({
      pollMs: 1,
      maxPolls: 1,
      logger: silent(),
      proofSource: async () => {
        calls++;
        return null;
      },
    });
    eff.dispose();
    dispose = null;
    effectBus.emit({
      type: 'await-spv',
      channelId: 'c1',
      txid: 'tx-5',
      minConfirmations: 1,
    });
    await new Promise((r) => setTimeout(r, 10));
    expect(calls).toBe(0);
  });
});

```
