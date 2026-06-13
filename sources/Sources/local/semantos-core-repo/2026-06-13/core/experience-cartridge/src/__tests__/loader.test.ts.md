---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/__tests__/loader.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.954054+00:00
---

# core/experience-cartridge/src/__tests__/loader.test.ts

```ts
/**
 * RM-011 loader tests — `loadCartridge(input) → LoadedCartridge`.
 */
import { describe, expect, test } from 'bun:test';
import { loadCartridge } from '../loader.js';
import type { CartridgeInput, FsmEdge } from '../types.js';

const minimal: CartridgeInput = {
  manifest: { id: 'test.minimal', version: '0.1.0', description: 'minimal cartridge' },
};

describe('loadCartridge', () => {
  test('L1 manifest-only input passes through', () => {
    const c = loadCartridge(minimal);
    expect(c.manifest.id).toBe('test.minimal');
    expect(c.grammar).toBeUndefined();
    expect(c.lexicons).toBeUndefined();
    expect(c.fsmEdges).toBeUndefined();
    expect(c.reducerPasses).toBeUndefined();
    expect(c.conversationHooks).toBeUndefined();
  });

  test('L2 optional surfaces are preserved (defensive-copied)', () => {
    const fsm: FsmEdge[] = [{ transition: 'go', from: 'a', to: 'b' }];
    const lexicons = [
      { name: 'fake', categories: ['x'] as ReadonlyArray<'x'>, header: (c: 'x') => c },
    ];
    const passes = [() => undefined];

    const c = loadCartridge({
      manifest: minimal.manifest,
      grammar: { grammarId: 'g.test', grammarVersion: '1.0.0' },
      fsmEdges: fsm,
      lexicons,
      reducerPasses: passes,
      conversationHooks: { runTurn: () => undefined },
    });

    expect(c.grammar?.grammarId).toBe('g.test');
    expect(c.fsmEdges).toEqual(fsm);
    expect(c.lexicons?.[0]?.name).toBe('fake');
    expect(c.reducerPasses?.length).toBe(1);
    expect(c.conversationHooks).toBeDefined();

    // Defensive-copy: mutating the input array does NOT mutate the cartridge.
    fsm.push({ transition: 'extra', from: 'c', to: 'd' });
    expect(c.fsmEdges?.length).toBe(1);
  });
});

```
