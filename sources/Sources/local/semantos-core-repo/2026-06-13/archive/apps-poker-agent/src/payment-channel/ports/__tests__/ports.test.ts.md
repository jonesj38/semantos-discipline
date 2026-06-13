---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/ports/__tests__/ports.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.799080+00:00
---

# archive/apps-poker-agent/src/payment-channel/ports/__tests__/ports.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  broadcasterPort,
  channelIdGeneratorPort,
  createWalletPort,
  getChannelIdGenerator,
  getLogger,
  loggerPort,
  signerPort,
  silentLogger,
  spvPort,
  utxoProviderPort,
  walletPort,
} from '../index';

afterEach(() => {
  walletPort.unbind();
  createWalletPort('provider').unbind();
  createWalletPort('consumer').unbind();
  utxoProviderPort.unbind();
  broadcasterPort.unbind();
  signerPort.unbind();
  spvPort.unbind();
  loggerPort.unbind();
  channelIdGeneratorPort.unbind();
});

describe('payment-channel ports', () => {
  test('1. every port throws when unbound', () => {
    for (const p of [walletPort, utxoProviderPort, broadcasterPort, signerPort, spvPort]) {
      expect(() => p.get()).toThrow();
    }
  });

  test('2. logger falls back to silentLogger when unbound', () => {
    expect(getLogger()).toBe(silentLogger);
  });

  test('3. channel-id generator returns null when unbound', () => {
    expect(getChannelIdGenerator()).toBeNull();
  });

  test('4. createWalletPort returns the same instance for repeated role lookups', () => {
    const a = createWalletPort('provider');
    const b = createWalletPort('provider');
    expect(a).toBe(b);
  });

  test('5. createWalletPort isolates provider and consumer', () => {
    const provider = createWalletPort('provider');
    const consumer = createWalletPort('consumer');
    expect(provider).not.toBe(consumer);
  });

  test('6. role-scoped wallet ports do not leak across roles', () => {
    const provider = createWalletPort('provider');
    const consumer = createWalletPort('consumer');
    provider.bind({
      isAuthenticated: async () => true,
      createAction: async () => ({ txid: 'p' }),
      getPublicKey: async () => 'p',
      listOutputs: async () => [],
      signAction: async () => ({ txid: 'p' }),
      internalizeAction: async () => ({ accepted: true }),
    });
    expect(consumer.isBound()).toBe(false);
  });
});

```
