---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/__tests__/verb-registry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.388807+00:00
---

# runtime/shell/src/router/__tests__/verb-registry.test.ts

```ts
/**
 * Verb-registry tests — covers the registration / dispatch contract
 * the new router relies on.
 */

import { describe, expect, test } from 'bun:test';
import { makeVerbRegistry, registerHandlers } from '../verb-registry';
import type { VerbHandler } from '../types';

const ok: VerbHandler = async () => ({ ok: true });
const err: VerbHandler = async () => ({ error: 'fail', code: 'BOOM' });

describe('verb-registry', () => {
  test('1. fresh registry has no verbs', () => {
    const reg = makeVerbRegistry();
    expect(reg.keys()).toEqual([]);
  });

  test('2. register exposes the handler via get()', () => {
    const reg = makeVerbRegistry();
    reg.register('foo', ok);
    expect(reg.get('foo')).toBe(ok);
    expect(reg.has('foo')).toBe(true);
  });

  test('3. registerHandlers bulk-installs from a record', () => {
    const reg = makeVerbRegistry();
    registerHandlers(reg, { foo: ok, bar: err });
    expect(reg.keys().sort()).toEqual(['bar', 'foo']);
  });

  test('4. get() returns undefined for unknown verbs', () => {
    const reg = makeVerbRegistry();
    expect(reg.get('nope')).toBeUndefined();
  });

  test('5. require() throws for unknown verbs (used by other call sites)', () => {
    const reg = makeVerbRegistry();
    expect(() => reg.require('nope')).toThrow(/Registry has no handler/);
  });

  test('6. re-registering a verb overwrites the prior handler', () => {
    const reg = makeVerbRegistry();
    reg.register('x', ok);
    reg.register('x', err);
    expect(reg.get('x')).toBe(err);
  });

  test('7. handlers can be added at runtime (extension pattern)', async () => {
    const reg = makeVerbRegistry();
    expect(reg.has('plugin')).toBe(false);
    reg.register('plugin', async () => ({ from: 'plugin' }));
    const handler = reg.get('plugin')!;
    const out = await handler({} as never, {} as never);
    expect(out).toEqual({ from: 'plugin' });
  });
});

```
