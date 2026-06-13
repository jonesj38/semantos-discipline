---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/__tests__/taxonomy-seed-applicator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.125337+00:00
---

# runtime/services/src/services/config-store/__tests__/taxonomy-seed-applicator.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  applyTaxonomySeed,
  flattenNodePaths,
  seedToTaxonomyNodes,
} from '../taxonomy-seed-applicator';
import { makeConfig, sampleSeed } from './fixtures';

describe('seedToTaxonomyNodes', () => {
  test('1. carries the axis + metadata + nested children verbatim', () => {
    const out = seedToTaxonomyNodes([
      {
        path: 'what.thing',
        name: 'thing',
        axis: 'what',
        metadata: { foo: 'bar' },
        children: [{ path: 'what.thing.box', name: 'box', axis: 'what' }],
      },
    ]);
    expect(out[0]!.path).toBe('what.thing');
    expect(out[0]!.metadata).toEqual({ foo: 'bar' });
    expect(out[0]!.children?.[0]!.path).toBe('what.thing.box');
  });
});

describe('applyTaxonomySeed', () => {
  test('2. null seed leaves config untouched', () => {
    const config = makeConfig();
    expect(applyTaxonomySeed(config, null)).toBe(config);
  });

  test('3. empty domain config gets pure seed dimensions', () => {
    const config = makeConfig();
    const out = applyTaxonomySeed(config, sampleSeed);
    expect(out.taxonomy?.dimensions).toHaveLength(1);
    expect(out.taxonomy?.dimensions[0]!.id).toBe('what');
  });

  test('4. existing domain dimension with matching id is merged into the seed', () => {
    const config = makeConfig({
      taxonomy: {
        dimensions: [
          {
            id: 'what',
            name: 'what',
            rootPath: 'what',
            nodes: [{ path: 'what.custom', name: 'custom', axis: 'what' }],
          } as never,
        ],
      },
    });
    const out = applyTaxonomySeed(config, sampleSeed);
    const paths = flattenNodePaths(out.taxonomy!.dimensions[0]!.nodes);
    expect(paths.has('what.service')).toBe(true);
    expect(paths.has('what.thing')).toBe(true);
    expect(paths.has('what.custom')).toBe(true);
  });

  test('5. dedupes by node path during merge', () => {
    const config = makeConfig({
      taxonomy: {
        dimensions: [
          {
            id: 'what',
            name: 'what',
            rootPath: 'what',
            nodes: [{ path: 'what.thing', name: 'thing', axis: 'what' }],
          } as never,
        ],
      },
    });
    const out = applyTaxonomySeed(config, sampleSeed);
    const dim = out.taxonomy!.dimensions[0]!;
    const thingCount = dim.nodes.filter((n) => n.path === 'what.thing').length;
    expect(thingCount).toBe(1);
  });

  test('6. non-seed domain dimensions pass through unchanged', () => {
    const config = makeConfig({
      taxonomy: {
        dimensions: [
          {
            id: 'instrument',
            name: 'instrument',
            rootPath: 'instrument',
            nodes: [{ path: 'instrument.guitar', name: 'guitar', axis: 'how' }],
          } as never,
        ],
      },
    });
    const out = applyTaxonomySeed(config, sampleSeed);
    const ids = out.taxonomy!.dimensions.map((d) => d.id).sort();
    expect(ids).toEqual(['instrument', 'what']);
  });
});

describe('flattenNodePaths', () => {
  test('7. collects every node path (incl. children) into a Set', () => {
    const paths = flattenNodePaths([
      {
        path: 'a',
        name: 'a',
        axis: 'what',
        children: [{ path: 'a.b', name: 'b', axis: 'what' }],
      },
    ]);
    expect([...paths].sort()).toEqual(['a', 'a.b']);
  });

  test('8. empty input → empty set', () => {
    expect(flattenNodePaths([])).toEqual(new Set());
  });
});

```
