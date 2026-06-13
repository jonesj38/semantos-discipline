---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/__tests__/wallet-client-integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.911713+00:00
---

# core/protocol-types/src/wallet-client/__tests__/wallet-client-integration.test.ts

```ts
/**
 * Integration test — drives the public WalletClient class against a
 * recorded-style stub transport. Pins per-method dispatch
 * (path / method / body / parser) and the BRC-100 error envelope path.
 *
 * Mirrors the contract test the prompt asks for: stub transport
 * returns canned responses; we assert byte-identical method results.
 */

import { describe, expect, test } from 'bun:test';
import { WalletClient } from '../wallet-client-facade';
import { WalletClientError } from '../wallet-error';
import { makeStubTransport, type RecordedRequest } from './stub-transport';

function makeClient(responder: (req: RecordedRequest) => unknown) {
  const transport = makeStubTransport(responder as Parameters<typeof makeStubTransport>[0]);
  const client = new WalletClient({ baseUrl: 'http://localhost:3321/' }, transport);
  return { client, transport };
}

describe('WalletClient integration', () => {
  test('1. trims trailing slash from baseUrl', async () => {
    const { client, transport } = makeClient(() => 800000);
    await client.getHeight();
    expect(transport.recorded[0]?.ctx.baseUrl).toBe('http://localhost:3321');
  });

  test('2. defaults timeout / origin / originator', async () => {
    const { client, transport } = makeClient(() => 0);
    await client.getHeight();
    const ctx = transport.recorded[0]!.ctx;
    expect(ctx.timeoutMs).toBe(120_000);
    expect(ctx.origin).toBe('http://localhost');
    expect(ctx.originator).toBe('semantos');
  });

  test('3. getHeight unwraps {height: …}', async () => {
    const { client } = makeClient(() => ({ height: 1234 }));
    expect(await client.getHeight()).toBe(1234);
  });

  test('4. getNetwork falls back to mainnet', async () => {
    const { client } = makeClient(() => ({}));
    expect(await client.getNetwork()).toBe('mainnet');
  });

  test('5. getPublicKey forwards args + returns the key', async () => {
    const { client, transport } = makeClient((req) => {
      expect(req.path).toBe('/v1/getPublicKey');
      expect(req.body).toMatchObject({
        originator: 'semantos',
        identityKey: true,
      });
      return { publicKey: '02deadbeef' };
    });
    expect(await client.getPublicKey()).toBe('02deadbeef');
    expect(transport.recorded).toHaveLength(1);
  });

  test('6. listOutputs unwraps array body', async () => {
    const { client } = makeClient(() => [{ outpoint: 'tx.0', satoshis: 5 }]);
    const out = await client.listOutputs('inbox');
    expect(out).toEqual([{ outpoint: 'tx.0', satoshis: 5 }]);
  });

  test('7. createAction surfaces wallet error envelopes as WalletClientError', async () => {
    const { client } = makeClient(() => ({
      status: 'error',
      code: 'NOPERM',
      description: 'denied',
    }));
    let err: unknown;
    try {
      await client.createAction({ description: 'd', outputs: [] });
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(WalletClientError);
    expect((err as WalletClientError).code).toBe('NOPERM');
    expect((err as WalletClientError).message).toBe('denied');
  });

  test('8. createAction returns parsed result on success', async () => {
    const { client } = makeClient(() => ({
      txid: 'abc',
      tx: 'beef',
      proof: 'p',
    }));
    expect(await client.createAction({ description: 'd', outputs: [] })).toEqual({
      txid: 'abc',
      tx: 'beef',
      proof: 'p',
    });
  });

  test('9. signAction passes spends through to body', async () => {
    const { client, transport } = makeClient(() => ({ txid: 'tx-1' }));
    const out = await client.signAction({
      reference: 'r1',
      spends: { 0: { unlockingScript: 'aa' } },
    });
    expect(out.txid).toBe('tx-1');
    expect(transport.recorded[0]?.body).toMatchObject({
      reference: 'r1',
      spends: { 0: { unlockingScript: 'aa' } },
    });
  });

  test('10. createSignature returns a signature array', async () => {
    const { client } = makeClient(() => ({ signature: [9, 8, 7] }));
    const out = await client.createSignature({
      protocolID: [1, 'sig'],
      keyID: 'k',
      counterparty: 'self',
      data: [1, 2],
    });
    expect(out.signature).toEqual([9, 8, 7]);
  });

  test('11. internalizeAction defaults accepted=true on bare {} responses', async () => {
    const { client } = makeClient(() => ({}));
    const out = await client.internalizeAction({
      tx: [1, 2],
      outputs: [{ outputIndex: 0, protocol: 'wallet payment' }],
      description: 'ingest',
    });
    expect(out).toEqual({ accepted: true });
  });

  test('12. isAuthenticated returns false on transport failure rather than throwing', async () => {
    const { client } = makeClient(() => {
      throw new WalletClientError('HTTP_500', 'down');
    });
    expect(await client.isAuthenticated()).toBe(false);
  });

  test('13. isAuthenticated unwraps {authenticated: true}', async () => {
    const { client } = makeClient(() => ({ authenticated: true }));
    expect(await client.isAuthenticated()).toBe(true);
  });
});

```
