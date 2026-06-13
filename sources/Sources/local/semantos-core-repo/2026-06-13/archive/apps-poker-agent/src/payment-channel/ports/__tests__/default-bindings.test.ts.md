---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/ports/__tests__/default-bindings.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.798771+00:00
---

# archive/apps-poker-agent/src/payment-channel/ports/__tests__/default-bindings.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  bindDefaultPaymentChannelPorts,
  makeArcBroadcaster,
} from '../default-bindings';
import {
  broadcasterPort,
  channelIdGeneratorPort,
  createWalletPort,
  loggerPort,
  walletPort,
} from '../index';

afterEach(() => {
  broadcasterPort.unbind();
  walletPort.unbind();
  createWalletPort('provider').unbind();
  createWalletPort('consumer').unbind();
  channelIdGeneratorPort.unbind();
  loggerPort.unbind();
});

describe('bindDefaultPaymentChannelPorts', () => {
  test('1. binds the broadcaster port to a real ARC wrapper', () => {
    bindDefaultPaymentChannelPorts();
    expect(broadcasterPort.isBound()).toBe(true);
  });

  test('2. binds the logger port', () => {
    bindDefaultPaymentChannelPorts();
    expect(loggerPort.isBound()).toBe(true);
  });

  test('3. is idempotent — does not overwrite a pre-bound broadcaster', () => {
    const first = makeArcBroadcaster('http://first.example');
    broadcasterPort.bind(first);
    bindDefaultPaymentChannelPorts({ arcUrl: 'http://second.example' });
    expect(broadcasterPort.get()).toBe(first);
  });

  test('4. role-scoped wallets bind to distinct ports', () => {
    const provider = {
      isAuthenticated: async () => true,
      createAction: async () => ({ txid: 'p' }),
      getPublicKey: async () => 'p',
      listOutputs: async () => [],
      signAction: async () => ({ txid: 'p' }),
      internalizeAction: async () => ({ accepted: true }),
    };
    const consumer = {
      ...provider,
      createAction: async () => ({ txid: 'c' }),
      getPublicKey: async () => 'c',
    };
    bindDefaultPaymentChannelPorts({ wallet: { provider, consumer } });
    expect(createWalletPort('provider').get()).toBe(provider);
    expect(createWalletPort('consumer').get()).toBe(consumer);
  });

  test('5. single-wallet form binds the role-agnostic walletPort', () => {
    const w = {
      isAuthenticated: async () => true,
      createAction: async () => ({ txid: 'w' }),
      getPublicKey: async () => 'w',
      listOutputs: async () => [],
      signAction: async () => ({ txid: 'w' }),
      internalizeAction: async () => ({ accepted: true }),
    };
    bindDefaultPaymentChannelPorts({ wallet: w });
    expect(walletPort.get()).toBe(w);
  });

  test('6. binds a custom channel-id generator when supplied', () => {
    bindDefaultPaymentChannelPorts({
      channelIdGenerator: { next: () => 'fixed-id' },
    });
    expect(channelIdGeneratorPort.get().next()).toBe('fixed-id');
  });
});

describe('makeArcBroadcaster', () => {
  test('7. returns an object with a broadcast method', () => {
    const b = makeArcBroadcaster();
    expect(typeof b.broadcast).toBe('function');
  });

  test('8. surfaces ARC errors as { ok: false, error }', async () => {
    const b = makeArcBroadcaster('http://localhost:1');
    const result = await b.broadcast('00');
    // Either parsing fails or the localhost:1 broadcast fails; both
    // collapse to ok: false with a stringified error.
    expect(result.ok).toBe(false);
    expect(typeof result.error === 'string' || typeof result.status === 'string').toBe(true);
  });
});

```
