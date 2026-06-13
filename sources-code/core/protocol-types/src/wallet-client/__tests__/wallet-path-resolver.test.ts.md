---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/__tests__/wallet-path-resolver.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.912298+00:00
---

# core/protocol-types/src/wallet-client/__tests__/wallet-path-resolver.test.ts

```ts
/**
 * tryPaths fallback walker tests.
 */

import { describe, expect, test } from 'bun:test';
import { tryPaths } from '../wallet-path-resolver';
import { WalletClientError } from '../wallet-error';
import { makeStubTransport, type RecordedRequest } from './stub-transport';

const ctx = {
  baseUrl: 'http://localhost:3321',
  origin: 'http://localhost',
  originator: 'test',
  timeoutMs: 1000,
};

function notFound(req: RecordedRequest): never {
  throw new WalletClientError('HTTP_404', `not found: ${req.path}`);
}

describe('tryPaths', () => {
  test('1. returns the first successful response', async () => {
    const transport = makeStubTransport(async (req) =>
      req.path === '/v1/getHeight' ? { height: 800000 } : notFound(req),
    );
    const out = await tryPaths(transport, ctx, 'GET', ['/v1/getHeight', '/getHeight']);
    expect(out).toEqual({ height: 800000 });
    expect(transport.recorded).toHaveLength(1);
  });

  test('2. falls through 404s to the next path', async () => {
    const transport = makeStubTransport(async (req) =>
      req.path === '/getHeight' ? { height: 1 } : notFound(req),
    );
    const out = await tryPaths(transport, ctx, 'GET', ['/v1/getHeight', '/getHeight']);
    expect(out).toEqual({ height: 1 });
    expect(transport.recorded.map((r) => r.path)).toEqual(['/v1/getHeight', '/getHeight']);
  });

  test('3. surfaces non-404 errors immediately', async () => {
    const transport = makeStubTransport(() => {
      throw new WalletClientError('HTTP_500', 'down');
    });
    await expect(
      tryPaths(transport, ctx, 'GET', ['/v1/x', '/x']),
    ).rejects.toBeInstanceOf(WalletClientError);
    expect(transport.recorded).toHaveLength(1);
  });

  test('4. surfaces non-WalletClientError exceptions and stops walking', async () => {
    const transport = makeStubTransport(() => {
      throw new TypeError('boom');
    });
    await expect(tryPaths(transport, ctx, 'GET', ['/a', '/b'])).rejects.toThrow(/boom/);
  });

  test('5. throws NO_PATH when every path is a 404', async () => {
    const transport = makeStubTransport(notFound);
    await expect(
      tryPaths(transport, ctx, 'GET', ['/a', '/b']),
    ).rejects.toBeInstanceOf(WalletClientError);
    expect(transport.recorded).toHaveLength(2);
  });

  test('6. forwards method + body to the transport', async () => {
    let capturedBody: unknown = null;
    const transport = makeStubTransport((req) => {
      capturedBody = req.body;
      return { ok: true };
    });
    await tryPaths(transport, ctx, 'POST', ['/v1/foo'], { hello: 'world' });
    expect(capturedBody).toEqual({ hello: 'world' });
  });
});

```
