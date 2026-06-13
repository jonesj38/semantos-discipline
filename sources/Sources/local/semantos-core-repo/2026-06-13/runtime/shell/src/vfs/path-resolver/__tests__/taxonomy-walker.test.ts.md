---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/__tests__/taxonomy-walker.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.393271+00:00
---

# runtime/shell/src/vfs/path-resolver/__tests__/taxonomy-walker.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { readTaxonomyNode, walkTaxonomyDir } from '../taxonomy-walker';
import type { TaxonomyNode } from '@semantos/protocol-types';

const tree: TaxonomyNode[] = [
  {
    path: 'create',
    name: 'create',
    axis: 'how',
    children: [
      {
        path: 'create.job',
        name: 'job',
        axis: 'how',
        children: [{ path: 'create.job.plumbing', name: 'plumbing', axis: 'how' }],
      },
      { path: 'create.standalone', name: 'standalone', axis: 'how' },
    ],
  },
  { path: 'discover', name: 'discover', axis: 'how' },
];

describe('walkTaxonomyDir', () => {
  test('1. lists each node + .json sibling at the root', () => {
    const out = walkTaxonomyDir(tree, []);
    expect(out).toContain('create');
    expect(out).toContain('create.json');
    expect(out).toContain('discover.json');
    // No `discover` directory because that node has no children
    expect(out?.filter((n) => n === 'discover').length).toBe(0);
  });

  test('2. walks into a child node', () => {
    const out = walkTaxonomyDir(tree, ['create']);
    expect(out).toContain('job');
    expect(out).toContain('job.json');
    expect(out).toContain('standalone.json');
  });

  test('3. accepts ".json" suffix on the path segment', () => {
    expect(walkTaxonomyDir(tree, ['create.json'])).toEqual(walkTaxonomyDir(tree, ['create']));
  });

  test('4. unknown segment yields null', () => {
    expect(walkTaxonomyDir(tree, ['nope'])).toBeNull();
  });
});

describe('readTaxonomyNode', () => {
  test('5. reads the leaf JSON', () => {
    const out = readTaxonomyNode(tree, ['discover.json']);
    expect(out).not.toBeNull();
    expect(JSON.parse(out!.data.toString('utf-8')).path).toBe('discover');
  });

  test('6. recurses into a child', () => {
    const out = readTaxonomyNode(tree, ['create', 'job.json']);
    expect(out).not.toBeNull();
    expect(JSON.parse(out!.data.toString('utf-8')).path).toBe('create.job');
  });

  test('7. non-.json filename is rejected', () => {
    expect(readTaxonomyNode(tree, ['discover'])).toBeNull();
  });

  test('8. unknown node returns null', () => {
    expect(readTaxonomyNode(tree, ['nope.json'])).toBeNull();
  });
});

```
