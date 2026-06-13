---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/__tests__/semantic-queries.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.907470+00:00
---

# core/protocol-types/src/semantic-fs/__tests__/semantic-queries.test.ts

```ts
/**
 * semantic-queries tests — drives queryByParent / queryByType /
 * queryByOwner against a CellStore-backed in-memory adapter.
 */

import { describe, expect, test } from 'bun:test';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import { CellStore } from '../../cell-store/cell-store-facade';
import { Linearity } from '../../constants';
import { computeTypeHash } from '../type-hasher';
import {
  queryByOwner,
  queryByParent,
  queryByType,
} from '../semantic-queries';
import { hexToBytes } from '../../cell-store/content-hasher';

function makeOwner(seed: number): Uint8Array {
  const bytes = new Uint8Array(16);
  bytes[0] = seed;
  return bytes;
}

async function seedTwoTypes(): Promise<{ adapter: MemoryAdapter; store: CellStore }> {
  const adapter = new MemoryAdapter();
  const store = new CellStore(adapter);
  const plumbing = await computeTypeHash(['create', 'job', 'plumbing']);
  const electric = await computeTypeHash(['create', 'job', 'electric']);
  await store.put('objects/create/job/plumbing/job-1', new TextEncoder().encode('a'), {
    linearity: Linearity.LINEAR,
    typeHash: plumbing,
    ownerId: makeOwner(1),
  });
  await store.put('objects/create/job/plumbing/job-2', new TextEncoder().encode('b'), {
    linearity: Linearity.LINEAR,
    typeHash: plumbing,
    ownerId: makeOwner(2),
  });
  await store.put('objects/create/job/electric/job-3', new TextEncoder().encode('c'), {
    linearity: Linearity.LINEAR,
    typeHash: electric,
    ownerId: makeOwner(1),
  });
  return { adapter, store };
}

describe('queryByType', () => {
  test('1. returns every object under the named taxonomy', async () => {
    const { adapter } = await seedTwoTypes();
    const refs = await queryByType(adapter, 'create.job.plumbing');
    expect(refs.map((r) => r.key).sort()).toEqual([
      'objects/create/job/plumbing/job-1',
      'objects/create/job/plumbing/job-2',
    ]);
  });

  test('2. filters out other taxonomies', async () => {
    const { adapter } = await seedTwoTypes();
    const refs = await queryByType(adapter, 'create.job.electric');
    expect(refs.map((r) => r.key)).toEqual(['objects/create/job/electric/job-3']);
  });

  test('3. unknown taxonomy yields []', async () => {
    const { adapter } = await seedTwoTypes();
    const refs = await queryByType(adapter, 'never.heard.of');
    expect(refs).toEqual([]);
  });
});

describe('queryByOwner', () => {
  test('4. matches objects by ownerId', async () => {
    const { adapter } = await seedTwoTypes();
    const refs = await queryByOwner(adapter, makeOwner(1));
    expect(refs.map((r) => r.key).sort()).toEqual([
      'objects/create/job/electric/job-3',
      'objects/create/job/plumbing/job-1',
    ]);
  });

  test('5. unknown owner yields []', async () => {
    const { adapter } = await seedTwoTypes();
    const refs = await queryByOwner(adapter, makeOwner(99));
    expect(refs).toEqual([]);
  });

  test('6. distinguishes adjacent ownerIds', async () => {
    const { adapter } = await seedTwoTypes();
    const refs = await queryByOwner(adapter, makeOwner(2));
    expect(refs.map((r) => r.key)).toEqual(['objects/create/job/plumbing/job-2']);
  });
});

describe('queryByParent', () => {
  test('7. zero-parent objects: query for the all-zero parent matches every object that uses the default', async () => {
    const { adapter } = await seedTwoTypes();
    const allZero = '00'.repeat(32);
    const refs = await queryByParent(adapter, allZero);
    expect(refs.length).toBe(3); // every test object defaults to a zero parentHash
  });

  test('8. matches a specific parent hash', async () => {
    const adapter = new MemoryAdapter();
    const store = new CellStore(adapter);
    const parent = hexToBytes('aa'.repeat(32));
    await store.put('objects/create/job/plumbing/job-A', new TextEncoder().encode('x'), {
      typeHash: await computeTypeHash(['create', 'job', 'plumbing']),
      parentHash: parent,
    });
    await store.put('objects/create/job/plumbing/job-B', new TextEncoder().encode('y'), {
      typeHash: await computeTypeHash(['create', 'job', 'plumbing']),
    });
    const refs = await queryByParent(adapter, 'aa'.repeat(32));
    expect(refs.map((r) => r.key)).toEqual(['objects/create/job/plumbing/job-A']);
  });
});

```
