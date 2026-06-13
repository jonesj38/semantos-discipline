---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/__tests__/persistence-hook.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.531654+00:00
---

# packages/game-sdk/src/engine/__tests__/persistence-hook.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  cellStorePort,
  noopCellStore,
  resolveCellStore,
  type CellStoreFacade,
} from '../persistence-hook';

afterEach(() => cellStorePort.unbind());

describe('persistence-hook', () => {
  test('1. resolveCellStore returns noop when nothing bound', async () => {
    expect(await resolveCellStore().read('x')).toBeNull();
  });

  test('2. noopCellStore.write returns void without side effect', async () => {
    await noopCellStore.write('p', new Uint8Array([1, 2, 3]));
    expect(await noopCellStore.list('p')).toEqual([]);
  });

  test('3. resolveCellStore returns the bound facade', async () => {
    const writes: { path: string; bytes: Uint8Array }[] = [];
    const stub: CellStoreFacade = {
      write: (path, bytes) => {
        writes.push({ path, bytes });
      },
      read: () => null,
      delete: () => {},
      list: () => [],
    };
    cellStorePort.bind(stub);
    await resolveCellStore().write('a', new Uint8Array([7]));
    expect(writes).toEqual([{ path: 'a', bytes: new Uint8Array([7]) }]);
  });
});

```
