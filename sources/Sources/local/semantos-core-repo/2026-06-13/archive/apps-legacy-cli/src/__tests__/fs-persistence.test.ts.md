---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/__tests__/fs-persistence.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.701344+00:00
---

# archive/apps-legacy-cli/src/__tests__/fs-persistence.test.ts

```ts
import { describe, expect, test, beforeEach, afterEach } from 'bun:test';
import { FsPersistence } from '../fs-persistence';
import { mkdtempSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

describe('FsPersistence', () => {
  let root: string;
  let store: FsPersistence;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), 'semantos-fs-test-'));
    store = new FsPersistence({ root });
  });

  afterEach(() => {
    rmSync(root, { recursive: true, force: true });
  });

  test('write then read round-trips the same bytes', async () => {
    const data = new Uint8Array([1, 2, 3, 4, 5]);
    await store.write('legacy-grants/gmail/g-1.enc', data);
    const got = await store.read('legacy-grants/gmail/g-1.enc');
    expect(Array.from(got!)).toEqual([1, 2, 3, 4, 5]);
  });

  test('read returns null for non-existent key', async () => {
    expect(await store.read('legacy-grants/gmail/no-such.enc')).toBeNull();
  });

  test('delete removes the file', async () => {
    await store.write('legacy-grants/gmail/g-1.enc', new Uint8Array([0xff]));
    await store.delete('legacy-grants/gmail/g-1.enc');
    expect(await store.read('legacy-grants/gmail/g-1.enc')).toBeNull();
  });

  test('list returns keys under a prefix', async () => {
    await store.write('legacy-grants/gmail/a.enc', new Uint8Array([1]));
    await store.write('legacy-grants/gmail/b.enc', new Uint8Array([2]));
    await store.write('legacy-grants/meta/c.enc', new Uint8Array([3]));
    const got = await store.list('legacy-grants/gmail/');
    expect(got.sort()).toEqual([
      'legacy-grants/gmail/a.enc',
      'legacy-grants/gmail/b.enc',
    ]);
  });

  test('list returns empty array when prefix dir does not exist', async () => {
    expect(await store.list('legacy-grants/no-such-provider/')).toEqual([]);
  });

  test('files are written with mode 0600', async () => {
    await store.write('legacy-grants/gmail/g-1.enc', new Uint8Array([1]));
    const path = join(root, 'legacy-grants/gmail/g-1.enc');
    const mode = statSync(path).mode & 0o777;
    expect(mode).toBe(0o600);
  });

  test('directories are created with mode 0700', async () => {
    await store.write('legacy-grants/gmail/g-1.enc', new Uint8Array([1]));
    const dirMode = statSync(join(root, 'legacy-grants/gmail')).mode & 0o777;
    expect(dirMode).toBe(0o700);
  });

  test('list under a deeper prefix walks recursively', async () => {
    await store.write('legacy-grants/gmail/g-1.enc', new Uint8Array([1]));
    await store.write('legacy-grants/meta/m-1.enc', new Uint8Array([2]));
    const got = await store.list('legacy-grants/');
    expect(got.sort()).toEqual([
      'legacy-grants/gmail/g-1.enc',
      'legacy-grants/meta/m-1.enc',
    ]);
  });
});

```
