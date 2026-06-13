---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/__tests__/type-hasher.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.904774+00:00
---

# core/protocol-types/src/semantic-fs/__tests__/type-hasher.test.ts

```ts
/**
 * type-hasher tests — pinning the SHA-256-of-dotted-path contract.
 */

import { describe, expect, test } from 'bun:test';
import { computeTypeHash } from '../type-hasher';
import { defaultSha256, hexFromBuffer, hexToBytes } from '../../cell-store/content-hasher';

describe('computeTypeHash', () => {
  test('1. returns a 32-byte buffer', async () => {
    const out = await computeTypeHash(['create', 'job', 'plumbing']);
    expect(out.length).toBe(32);
  });

  test('2. matches sha256(dotted-path)', async () => {
    const segs = ['create', 'job', 'plumbing'];
    const direct = await defaultSha256(new TextEncoder().encode(segs.join('.')));
    const out = await computeTypeHash(segs);
    expect(hexFromBuffer(out)).toBe(direct);
  });

  test('3. is deterministic for fixed inputs', async () => {
    const a = await computeTypeHash(['discover', 'asset']);
    const b = await computeTypeHash(['discover', 'asset']);
    expect(hexFromBuffer(a)).toBe(hexFromBuffer(b));
  });

  test('4. different segment ordering yields different hashes', async () => {
    const a = await computeTypeHash(['create', 'job']);
    const b = await computeTypeHash(['job', 'create']);
    expect(hexFromBuffer(a)).not.toBe(hexFromBuffer(b));
  });

  test('5. empty path hashes the empty string', async () => {
    const out = await computeTypeHash([]);
    const direct = await defaultSha256(new Uint8Array(0));
    expect(hexFromBuffer(out)).toBe(direct);
  });

  test('6. round-trips through hexToBytes', async () => {
    const out = await computeTypeHash(['x', 'y']);
    const round = hexToBytes(hexFromBuffer(out));
    expect(round).toEqual(out);
  });
});

```
