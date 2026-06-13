---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/__tests__/verb-stub.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.389104+00:00
---

# runtime/shell/src/router/__tests__/verb-stub.test.ts

```ts
/**
 * Browser-stub factory tests.
 */

import { describe, expect, test } from 'bun:test';
import {
  NOT_IN_BROWSER,
  makeNotInBrowserStub,
  makeStubsFor,
} from '../verb-stub';

describe('verb-stub', () => {
  test('1. NOT_IN_BROWSER carries the canonical envelope', () => {
    expect(NOT_IN_BROWSER.code).toBe('NOT_IN_BROWSER');
    expect(NOT_IN_BROWSER.error).toMatch(/Node\.js/);
  });

  test('2. makeNotInBrowserStub returns the verb name in the envelope', async () => {
    const stub = makeNotInBrowserStub('cdm');
    const out = (await stub({} as never, {} as never)) as Record<string, unknown>;
    expect(out.code).toBe('NOT_IN_BROWSER');
    expect(out.verb).toBe('cdm');
  });

  test('3. makeStubsFor produces one entry per verb', async () => {
    const stubs = makeStubsFor(['cdm', 'extract', 'infer']);
    expect(Object.keys(stubs).sort()).toEqual(['cdm', 'extract', 'infer']);
    const out = (await stubs.extract!({} as never, {} as never)) as { verb: string };
    expect(out.verb).toBe('extract');
  });

  test('4. each stub yields a fresh response object', async () => {
    const stub = makeNotInBrowserStub('foo');
    const a = await stub({} as never, {} as never);
    const b = await stub({} as never, {} as never);
    expect(a).not.toBe(b);
    expect(a).toEqual(b as object);
  });

  test('5. empty list yields empty object', () => {
    expect(makeStubsFor([])).toEqual({});
  });
});

```
