---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/__tests__/wallet-request-builder.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.913162+00:00
---

# core/protocol-types/src/wallet-client/__tests__/wallet-request-builder.test.ts

```ts
/**
 * Per-method request-builder tests. Pure functions — no transport.
 */

import { describe, expect, test } from 'bun:test';
import {
  buildCreateAction,
  buildCreateSignature,
  buildGetHeight,
  buildGetNetwork,
  buildGetPublicKey,
  buildInternalizeAction,
  buildIsAuthenticated,
  buildListOutputs,
  buildSignAction,
} from '../wallet-request-builder';

describe('GET-style builders', () => {
  test('1. buildIsAuthenticated lists both /v1 and bare paths', () => {
    expect(buildIsAuthenticated()).toEqual({
      method: 'GET',
      paths: ['/v1/isAuthenticated', '/isAuthenticated'],
    });
  });

  test('2. buildGetHeight lists both /v1 and bare paths', () => {
    expect(buildGetHeight()).toEqual({
      method: 'GET',
      paths: ['/v1/getHeight', '/getHeight'],
    });
  });

  test('3. buildGetNetwork lists both /v1 and bare paths', () => {
    expect(buildGetNetwork()).toEqual({
      method: 'GET',
      paths: ['/v1/getNetwork', '/getNetwork'],
    });
  });
});

describe('buildGetPublicKey', () => {
  test('4. defaults to identityKey:true with the supplied originator', () => {
    const spec = buildGetPublicKey('myapp');
    expect(spec.method).toBe('POST');
    expect(spec.body).toEqual({ originator: 'myapp', identityKey: true });
  });

  test('5. forwards explicit args verbatim', () => {
    const spec = buildGetPublicKey('myapp', {
      protocolID: [1, 'cell-anchor'],
      keyID: 'k1',
      counterparty: 'self',
    });
    expect(spec.body).toEqual({
      originator: 'myapp',
      protocolID: [1, 'cell-anchor'],
      keyID: 'k1',
      counterparty: 'self',
    });
  });
});

describe('buildListOutputs', () => {
  test('6. omits tags + include when not supplied', () => {
    const spec = buildListOutputs('myapp', 'inbox');
    expect(spec.body).toEqual({ originator: 'myapp', basket: 'inbox' });
  });

  test('7. includes tags + include header when supplied', () => {
    const spec = buildListOutputs('myapp', 'inbox', ['t1', 't2'], 'locking scripts');
    expect(spec.body).toEqual({
      originator: 'myapp',
      basket: 'inbox',
      tags: ['t1', 't2'],
      include: 'locking scripts',
    });
  });

  test('8. empty tags array is omitted (not sent as [])', () => {
    const spec = buildListOutputs('myapp', 'inbox', []);
    expect((spec.body as Record<string, unknown>).tags).toBeUndefined();
  });
});

describe('buildCreateAction', () => {
  test('9. preserves outputs and originator', () => {
    const spec = buildCreateAction('myapp', {
      description: 'hi',
      outputs: [{ lockingScript: 'aa', satoshis: 0 }],
    });
    const body = spec.body as Record<string, unknown>;
    expect(body.originator).toBe('myapp');
    expect(body.description).toBe('hi');
    expect(body.outputs).toEqual([
      {
        lockingScript: 'aa',
        satoshis: 0,
        outputDescription: undefined,
        basket: undefined,
        tags: undefined,
      },
    ]);
  });

  test('10. includes inputs array only when non-empty', () => {
    const spec = buildCreateAction('myapp', {
      description: 'hi',
      outputs: [],
      inputs: [
        {
          outpoint: 'tx.0',
          inputDescription: 'spend',
          unlockingScriptLength: 73,
        },
      ],
    });
    const body = spec.body as Record<string, unknown>;
    expect(Array.isArray(body.inputs)).toBe(true);
    expect((body.inputs as unknown[])[0]).toMatchObject({
      outpoint: 'tx.0',
      inputDescription: 'spend',
      unlockingScriptLength: 73,
    });
  });

  test('11. omits inputs array when empty', () => {
    const spec = buildCreateAction('myapp', {
      description: 'hi',
      outputs: [],
      inputs: [],
    });
    expect((spec.body as Record<string, unknown>).inputs).toBeUndefined();
  });

  test('12. forwards inputBEEF when supplied', () => {
    const spec = buildCreateAction('myapp', {
      description: 'hi',
      outputs: [],
      inputBEEF: [1, 2, 3],
    });
    expect((spec.body as Record<string, unknown>).inputBEEF).toEqual([1, 2, 3]);
  });
});

describe('buildSignAction / buildCreateSignature / buildInternalizeAction', () => {
  test('13. buildSignAction merges originator + args', () => {
    const spec = buildSignAction('myapp', {
      reference: 'ref-1',
      spends: { 0: { unlockingScript: 'aa' } },
    });
    expect(spec.body).toEqual({
      originator: 'myapp',
      reference: 'ref-1',
      spends: { 0: { unlockingScript: 'aa' } },
    });
  });

  test('14. buildCreateSignature merges originator + args', () => {
    const spec = buildCreateSignature('myapp', {
      protocolID: [1, 'sig'],
      keyID: 'k',
      counterparty: 'self',
      data: [1, 2, 3],
    });
    const body = spec.body as Record<string, unknown>;
    expect(body.originator).toBe('myapp');
    expect(body.data).toEqual([1, 2, 3]);
  });

  test('15. buildInternalizeAction sets all four required fields', () => {
    const spec = buildInternalizeAction('myapp', {
      tx: [1, 2, 3],
      outputs: [{ outputIndex: 0, protocol: 'wallet payment' }],
      description: 'ingest',
      labels: ['foo'],
    });
    expect(spec.body).toEqual({
      originator: 'myapp',
      tx: [1, 2, 3],
      outputs: [{ outputIndex: 0, protocol: 'wallet payment' }],
      description: 'ingest',
      labels: ['foo'],
    });
  });
});

```
