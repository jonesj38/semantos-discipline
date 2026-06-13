---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/__tests__/bootstrap-coverage.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.387839+00:00
---

# runtime/shell/src/router/__tests__/bootstrap-coverage.test.ts

```ts
/**
 * Bootstrap coverage — pins which verbs each bootstrap registers and
 * confirms the browser bootstrap cleanly stubs the node-only verbs.
 *
 * This is the contract test the prompt asks for: every verb that
 * existed pre-refactor resolves under both bootstraps; the node-safe
 * subset shares identical handlers between them.
 */

import { describe, expect, test } from 'bun:test';
import { buildBrowserRegistry } from '../bootstrap-browser';
import { buildNodeRegistry } from '../bootstrap-node';

const ALL_NODE_VERBS = [
  'new',
  'patch',
  'transition',
  'inspect',
  'trace',
  'verify',
  'sign',
  'publish',
  'revoke',
  'stake',
  'vote',
  'dispute',
  'transfer',
  'flow',
  'list',
  'identity',
  'whoami',
  'capabilities',
  'eval',
  'compile',
  'bind',
  'taxonomy',
  'cdm',
  'extract',
  'infer',
  'extension',
  'game',
  'grammar',
  'govern',
  'settle',
  'share',
  'export',
  'merge',
  'diff',
  'host.exec',
  'host.audit',
  'transfer.share',
  'transfer.fetch',
  'transfer.list',
  // Conversations persist through ctx.adapter (browser-safe storage seam),
  // so they register under both bootstraps — node-only set excludes them.
  'conversation.create',
  'conversations.find',
] as const;

const NODE_ONLY = new Set([
  'taxonomy',
  'grammar',
  'cdm',
  'extract',
  'infer',
  'extension',
  'game',
  'host.exec',
  'host.audit',
  'transfer.share',
  'transfer.fetch',
  'transfer.list',
]);

describe('bootstrap-node', () => {
  test('1. registers every shell verb', () => {
    const reg = buildNodeRegistry();
    for (const verb of ALL_NODE_VERBS) {
      expect(reg.has(verb)).toBe(true);
    }
  });

  test('2. exposes the same set of keys as the legacy switch (no extras)', () => {
    const reg = buildNodeRegistry();
    expect(reg.keys().sort()).toEqual([...ALL_NODE_VERBS].sort());
  });
});

describe('bootstrap-browser', () => {
  test('3. registers every verb the node bootstrap registers', () => {
    const browser = buildBrowserRegistry();
    for (const verb of ALL_NODE_VERBS) {
      expect(browser.has(verb)).toBe(true);
    }
  });

  test('4. node-only verbs return the NOT_IN_BROWSER envelope', async () => {
    const browser = buildBrowserRegistry();
    for (const verb of NODE_ONLY) {
      const handler = browser.get(verb)!;
      const out = (await handler({ verb } as never, {} as never)) as Record<string, unknown>;
      expect(out.code).toBe('NOT_IN_BROWSER');
      expect(out.verb).toBe(verb);
    }
  });

  test('5. browser-safe verbs share the *same handler reference* as node', () => {
    const node = buildNodeRegistry();
    const browser = buildBrowserRegistry();
    for (const verb of ALL_NODE_VERBS) {
      if (NODE_ONLY.has(verb)) continue;
      expect(browser.get(verb)).toBe(node.get(verb));
    }
  });

  test('6. unknown verb returns undefined from get() (not a stub)', () => {
    const browser = buildBrowserRegistry();
    expect(browser.get('does-not-exist')).toBeUndefined();
  });
});

describe('runtime registration', () => {
  test('7. extension can append a verb post-bootstrap and route to it', async () => {
    const reg = buildBrowserRegistry();
    expect(reg.has('plugin.foo')).toBe(false);
    reg.register('plugin.foo', async () => ({ from: 'plugin' }));
    expect(reg.has('plugin.foo')).toBe(true);
    const handler = reg.get('plugin.foo')!;
    expect(await handler({} as never, {} as never)).toEqual({ from: 'plugin' });
  });
});

```
