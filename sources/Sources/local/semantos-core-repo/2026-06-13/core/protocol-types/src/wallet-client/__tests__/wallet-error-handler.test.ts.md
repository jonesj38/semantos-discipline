---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/__tests__/wallet-error-handler.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.912581+00:00
---

# core/protocol-types/src/wallet-client/__tests__/wallet-error-handler.test.ts

```ts
/**
 * Tests for the {status:'error'} → throw decoder.
 */

import { describe, expect, test } from 'bun:test';
import {
  throwIfError,
  toWalletClientError,
} from '../wallet-error-handler';
import { WalletClientError } from '../wallet-error';

describe('throwIfError', () => {
  test('1. is a no-op for non-error responses', () => {
    expect(() => throwIfError({ txid: 'abc' }, 'createAction')).not.toThrow();
    expect(() => throwIfError(null, 'op')).not.toThrow();
    expect(() => throwIfError(undefined, 'op')).not.toThrow();
  });

  test('2. throws WalletClientError on {status:"error", code, description}', () => {
    let err: unknown;
    try {
      throwIfError({ status: 'error', code: 'NO_KEY', description: 'no key' }, 'createAction');
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(WalletClientError);
    expect((err as WalletClientError).code).toBe('NO_KEY');
    expect((err as WalletClientError).message).toBe('no key');
  });

  test('3. defaults code to UNKNOWN when missing', () => {
    let err: unknown;
    try {
      throwIfError({ status: 'error' }, 'createAction');
    } catch (e) {
      err = e;
    }
    expect((err as WalletClientError).code).toBe('UNKNOWN');
  });

  test('4. defaults message to "<op> failed" when description is missing', () => {
    let err: unknown;
    try {
      throwIfError({ status: 'error' }, 'createAction');
    } catch (e) {
      err = e;
    }
    expect((err as WalletClientError).message).toBe('createAction failed');
  });

  test('5. ignores objects without status:"error"', () => {
    expect(() => throwIfError({ status: 'ok', txid: 'abc' }, 'op')).not.toThrow();
  });
});

describe('toWalletClientError', () => {
  test('6. constructs a WalletClientError with code + message', () => {
    const err = toWalletClientError('HTTP_500', 'down');
    expect(err).toBeInstanceOf(WalletClientError);
    expect(err.code).toBe('HTTP_500');
    expect(err.message).toBe('down');
  });
});

```
