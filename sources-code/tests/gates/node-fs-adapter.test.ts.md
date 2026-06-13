---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/node-fs-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.575238+00:00
---

# tests/gates/node-fs-adapter.test.ts

```ts
/**
 * Phase 25A — NodeFsAdapter tests (T8–T15).
 */

import { describe, test, expect, afterAll } from 'bun:test';
import { mkdtemp, rm } from 'fs/promises';
import { join } from 'path';
import { tmpdir } from 'os';
import { createHash } from 'crypto';
import { NodeFsAdapter } from '../../core/protocol-types/src/adapters/node-fs-adapter';

function sha256(data: Uint8Array): string {
  return createHash('sha256').update(data).digest('hex');
}

let testRoot: string;
let adapter: NodeFsAdapter;

// Create a fresh temp directory for each test run
const setup = (async () => {
  testRoot = await mkdtemp(join(tmpdir(), 'semantos-test-'));
  adapter = new NodeFsAdapter(testRoot);
})();

afterAll(async () => {
  await setup;
  await rm(testRoot, { recursive: true, force: true });
});

describe('Phase 25A — NodeFsAdapter', () => {
  // T8: write creates directories and file, read retrieves correct bytes
  test('T8: write creates directories and file, read retrieves', async () => {
    await setup;
    const data = new Uint8Array([1, 2, 3, 4, 5]);
    await adapter.write('deep/nested/dir/file.bin', data);
    const result = await adapter.read('deep/nested/dir/file.bin');
    expect(result).toEqual(data);
  });

  // T9: write overwrites existing file
  test('T9: write overwrites existing file', async () => {
    await setup;
    await adapter.write('overwrite.bin', new Uint8Array([1]));
    await adapter.write('overwrite.bin', new Uint8Array([2, 3]));
    const result = await adapter.read('overwrite.bin');
    expect(result).toEqual(new Uint8Array([2, 3]));
  });

  // T10: read non-existent key returns null
  test('T10: read non-existent key returns null', async () => {
    await setup;
    const result = await adapter.read('does/not/exist.bin');
    expect(result).toBeNull();
  });

  // T11: list returns directory contents recursively
  test('T11: list returns directory contents recursively', async () => {
    await setup;
    await adapter.write('listdir/a.bin', new Uint8Array([1]));
    await adapter.write('listdir/sub/b.bin', new Uint8Array([2]));
    await adapter.write('listdir/sub/deep/c.bin', new Uint8Array([3]));

    const results = await adapter.list('listdir');
    expect(results.sort()).toEqual(['a.bin', 'sub/b.bin', 'sub/deep/c.bin']);
  });

  // T12: delete removes file, returns true
  test('T12: delete removes file, returns true', async () => {
    await setup;
    await adapter.write('todelete.bin', new Uint8Array([1]));
    expect(await adapter.delete('todelete.bin')).toBe(true);
    expect(await adapter.delete('todelete.bin')).toBe(false);
    expect(await adapter.exists('todelete.bin')).toBe(false);
  });

  // T13: stat returns correct size and hash
  test('T13: stat returns correct size and hash', async () => {
    await setup;
    const data = new Uint8Array([10, 20, 30, 40]);
    await adapter.write('statfile.bin', data);
    const info = await adapter.stat('statfile.bin');
    expect(info).not.toBeNull();
    expect(info!.size).toBe(4);
    expect(info!.contentHash).toBe(sha256(data));
    expect(info!.modifiedAt).toBeGreaterThan(0);

    expect(await adapter.stat('nope.bin')).toBeNull();
  });

  // T14: path traversal attack throws
  test('T14: path traversal attack throws', async () => {
    await setup;
    expect(adapter.read('../../../etc/passwd')).rejects.toThrow(/path traversal/);
    expect(adapter.write('../../etc/evil', new Uint8Array([1]))).rejects.toThrow(/path traversal/);
    expect(adapter.read('foo/../../bar')).rejects.toThrow(/path traversal/);
  });

  // T15: null byte in key throws
  test('T15: null byte in key throws', async () => {
    await setup;
    expect(adapter.read('foo\0bar')).rejects.toThrow(/null byte/);
    expect(adapter.write('foo\0bar', new Uint8Array([1]))).rejects.toThrow(/null byte/);
  });
});

```
