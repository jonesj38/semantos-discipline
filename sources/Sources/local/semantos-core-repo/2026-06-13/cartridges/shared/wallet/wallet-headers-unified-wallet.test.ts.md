---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/wallet/wallet-headers-unified-wallet.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.434513+00:00
---

# cartridges/shared/wallet/wallet-headers-unified-wallet.test.ts

```ts
/**
 * wallet-headers-unified-wallet.test.ts — adapter conformance.
 *
 * Per C6a tick 4 design split (2026-05-28): the wallet-headers adapter
 * passes `runBrc100InterfaceConformance` (shape + round-trip checks),
 * NOT `runBrc100CryptoEquivalence` (the delegate's key is operator-
 * owned, not the deterministic test key).
 *
 * To make round-trip assertions meaningful without an actual Metanet
 * Desktop process, the test injects a mock fetch that ROUTES requests
 * to an in-process ProtoWallet (one with its own test key — separate
 * from the conformance suite's TEST_PRIVKEY, intentionally, so byte-
 * equivalence assertions don't accidentally hold).
 *
 * Production callers construct WalletHeadersUnifiedWallet with no
 * config (uses default base http://localhost:3321 + globalThis.fetch)
 * and talk to a real Metanet Desktop.
 */

import { describe, expect, it, beforeAll } from 'bun:test';
import { ProtoWallet, PrivateKey } from '@bsv/sdk';

import { _resetWalletRegistryForTests } from './unified-wallet';
import {
  WalletHeadersUnifiedWallet,
  registerWalletHeadersWallet,
  walletHeadersFactory,
} from './wallet-headers-unified-wallet';
import {
  runBrc100InterfaceConformance,
} from './unified-wallet.conformance.test';

/**
 * Build a mock fetch that simulates Metanet Desktop by routing POSTs
 * to a private ProtoWallet instance.  Distinct key from TEST_PRIVKEY —
 * intentional, so anyone tempted to also run runBrc100CryptoEquivalence
 * against this adapter gets a loud failure rather than a coincidental
 * pass.
 */
function makeMetanetMockFetch(): typeof globalThis.fetch {
  const MOCK_PRIVKEY = new Uint8Array(32);
  for (let i = 0; i < 32; i++) MOCK_PRIVKEY[i] = (0x80 + i) & 0xff;
  const hex = Array.from(MOCK_PRIVKEY)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  const delegate = new ProtoWallet(PrivateKey.fromHex(hex));

  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input.toString();
    const method = url.split('/').pop() ?? '';
    const args = init?.body ? JSON.parse(init.body as string) : {};

    // Method-dispatch table — only the ones runBrc100InterfaceConformance
    // exercises need real handling; others can return canned shapes for
    // the method-presence smoke. The conformance suite never CALLS the
    // tx methods (createAction etc), it only checks they exist.
    const handlers: Record<string, () => Promise<unknown>> = {
      getPublicKey: () => delegate.getPublicKey(args),
      createSignature: () => delegate.createSignature(args),
      verifySignature: () => delegate.verifySignature(args),
      createHmac: () => delegate.createHmac(args),
      verifyHmac: () => delegate.verifyHmac(args),
      encrypt: () => delegate.encrypt(args),
      decrypt: () => delegate.decrypt(args),
      // Network info — canned shapes matching @bsv/sdk's documented
      // return types.  A real Metanet Desktop would return its own
      // values; the conformance suite only checks shape.
      getNetwork: () => Promise.resolve({ network: 'mainnet' as const }),
      getVersion: () => Promise.resolve({ version: 'wallet-headers-mock/0.1.0' }),
      isAuthenticated: () => Promise.resolve({ authenticated: true }),
      waitForAuthentication: () => Promise.resolve({ authenticated: true }),
      getHeight: () => Promise.resolve({ height: 800_000 }),
      // Tx methods — never called by interface-conformance but
      // present so the method-existence smoke passes shape-wise if
      // anything ever does call them.
      createAction: () => Promise.resolve({ noSendChange: [], sendWithResults: [] }),
      signAction: () => Promise.resolve({ txid: '00'.repeat(32) }),
    };

    const handler = handlers[method];
    if (!handler) {
      return new Response(
        JSON.stringify({ error: 'method_not_implemented_in_mock', method }),
        { status: 501, headers: { 'Content-Type': 'application/json' } },
      );
    }
    const result = await handler();
    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }) as typeof globalThis.fetch;
}

describe('wallet-headers-unified-wallet — registration + smoke', () => {
  beforeAll(() => {
    _resetWalletRegistryForTests();
    registerWalletHeadersWallet();
  });

  it('factory descriptor has id=wallet-headers and canTransact=true', () => {
    expect(walletHeadersFactory.id).toBe('wallet-headers');
    expect(walletHeadersFactory.canTransact).toBe(true);
  });

  it('build() returns a WalletInterface implementation', async () => {
    const w = await walletHeadersFactory.build({ fetch: makeMetanetMockFetch() });
    expect(w).toBeDefined();
    expect(typeof w.getPublicKey).toBe('function');
    expect(typeof w.createSignature).toBe('function');
    expect(typeof w.createAction).toBe('function');
  });

  it('uses default base http://localhost:3321 when none provided', () => {
    const w = new WalletHeadersUnifiedWallet();
    expect(w).toBeDefined();
    // No assertion on internal — the smoke is that construction succeeds.
  });

  it('honours custom base config', () => {
    const w = new WalletHeadersUnifiedWallet({ base: 'http://other.local:9999' });
    expect(w).toBeDefined();
  });

  it('surfaces HTTP errors with method name in the message', async () => {
    const errorFetch = (async () =>
      new Response('boom', { status: 500 })) as typeof globalThis.fetch;
    const w = new WalletHeadersUnifiedWallet({ fetch: errorFetch });
    await expect(
      w.getPublicKey({ identityKey: true }),
    ).rejects.toThrow(/wallet-headers getPublicKey HTTP 500/);
  });
});

// ── Run the BRC-100 INTERFACE-CONFORMANCE suite ──────────────────────
// This adapter does NOT pass runBrc100CryptoEquivalence — its delegate's
// key is operator-owned, not the deterministic test key.  Interface
// conformance is the appropriate tier per C6a tick 4 design split.
runBrc100InterfaceConformance('wallet-headers', {
  buildConfig: {
    fetch: makeMetanetMockFetch(),
  },
});

```
