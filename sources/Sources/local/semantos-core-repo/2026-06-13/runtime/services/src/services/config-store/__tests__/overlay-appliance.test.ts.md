---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/__tests__/overlay-appliance.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.125642+00:00
---

# runtime/services/src/services/config-store/__tests__/overlay-appliance.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { applyAllOverlays, insertNodeAtParent } from '../overlay-appliance';
import type { ConfigOverlay, TaxonomyNode } from '../../../config/extensionConfig';
import { makeConfig } from './fixtures';

const node = (path: string, axis: 'what' | 'how' | 'why' = 'what'): TaxonomyNode => ({
  path,
  name: path.split('.').slice(-1)[0]!,
  axis,
});

const overlay = (nodes: TaxonomyNode[], id = 'o-1'): ConfigOverlay => ({
  id,
  source: 'ballot',
  appliedAt: 0,
  taxonomyNodes: nodes,
});

const baseConfig = () =>
  makeConfig({
    taxonomy: {
      dimensions: [
        {
          id: 'what',
          name: 'what',
          rootPath: 'what',
          nodes: [
            {
              path: 'what.thing',
              name: 'thing',
              axis: 'what',
              children: [],
            },
          ],
        } as never,
      ],
    },
  });

describe('applyAllOverlays', () => {
  test('1. zero overlays is a no-op', () => {
    const cfg = baseConfig();
    expect(applyAllOverlays(cfg, [])).toBe(cfg);
  });

  test('2. inserts a child node under the matching parent path', () => {
    const cfg = baseConfig();
    const out = applyAllOverlays(cfg, [overlay([node('what.thing.box')])]);
    const dim = out.taxonomy!.dimensions[0]! as { nodes: TaxonomyNode[] };
    expect(dim.nodes[0]!.children?.[0]!.path).toBe('what.thing.box');
  });

  test('3. appends a top-level node when no parent matches', () => {
    const cfg = baseConfig();
    const out = applyAllOverlays(cfg, [overlay([node('what.standalone')])]);
    const dim = out.taxonomy!.dimensions[0]! as { nodes: TaxonomyNode[] };
    expect(dim.nodes.find((n) => n.path === 'what.standalone')).toBeDefined();
  });

  test('4. dedupes existing paths', () => {
    const cfg = baseConfig();
    const out = applyAllOverlays(cfg, [overlay([node('what.thing')])]);
    const dim = out.taxonomy!.dimensions[0]! as { nodes: TaxonomyNode[] };
    expect(dim.nodes.filter((n) => n.path === 'what.thing')).toHaveLength(1);
  });

  test('5. ignores overlays whose axis has no matching dimension', () => {
    const cfg = baseConfig();
    const out = applyAllOverlays(cfg, [overlay([node('how.tool', 'how')])]);
    expect(out.taxonomy!.dimensions).toHaveLength(1);
  });

  test('6. attaches the overlays array to the result for downstream introspection', () => {
    const cfg = baseConfig();
    const list: ConfigOverlay[] = [overlay([node('what.thing.x')])];
    const out = applyAllOverlays(cfg, list);
    expect(out.overlays).toBe(list);
  });
});

describe('insertNodeAtParent', () => {
  test('7. inserts under a top-level parent', () => {
    const updated = insertNodeAtParent(
      [{ ...node('a') }],
      'a',
      node('a.b'),
    );
    expect(updated?.[0]!.children).toEqual([node('a.b')]);
  });

  test('8. recurses into nested children', () => {
    const root: TaxonomyNode[] = [
      { ...node('a'), children: [{ ...node('a.b'), children: [] }] },
    ];
    const updated = insertNodeAtParent(root, 'a.b', node('a.b.c'));
    expect(updated?.[0]!.children?.[0]!.children?.[0]!.path).toBe('a.b.c');
  });

  test('9. returns null when parent missing', () => {
    expect(insertNodeAtParent([{ ...node('a') }], 'never', node('x'))).toBeNull();
  });
});

```
