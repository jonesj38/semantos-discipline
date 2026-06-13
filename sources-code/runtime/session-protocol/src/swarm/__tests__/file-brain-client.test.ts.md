---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/file-brain-client.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.079442+00:00
---

# runtime/session-protocol/src/swarm/__tests__/file-brain-client.test.ts

```ts
/**
 * FileBrainClient — shared-directory tracker used for cross-process real-UDP
 * runs. A second instance (≈ a second process) must see what the first wrote.
 */
import { describe, expect, test } from 'bun:test';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { publishFile, bytesEqual } from '@semantos/protocol-types';
import { FileBrainClient } from '../file-brain-client';

function tmp(): string {
  return mkdtempSync(join(tmpdir(), 'swarm-fbc-'));
}

describe('FileBrainClient', () => {
  test('publish/announce in one instance are visible to another (shared dir)', async () => {
    const dir = tmp();
    const pub = publishFile(new Uint8Array(2000).fill(7), 'f');
    const a = new FileBrainClient(dir);
    await a.publish({ infohash: pub.infohash, manifestCell: pub.manifestCell, semanticPath: 'f' });
    await a.announce({ infohash: pub.infohash, address: 'node-1', bitfield: new Uint8Array([0xff]) });

    const b = new FileBrainClient(dir); // separate instance == separate process
    const loc = await b.locate(pub.infohash);
    expect(loc.manifestCell && bytesEqual(loc.manifestCell, pub.manifestCell)).toBe(true);
    expect(loc.seeders[0]!.address).toBe('node-1');
    expect([...loc.seeders[0]!.bitfield!]).toEqual([0xff]);

    const r = await b.settle({ infohash: pub.infohash, receipts: [{ cellIndex: 0, payerCertId: 'p', txAnchor: 'ab', amount: 1, currency: 'sat' }] });
    expect(r.recorded).toBe(1);
    rmSync(dir, { recursive: true, force: true });
  });

  test('locate of an unknown infohash returns a null manifest', async () => {
    const dir = tmp();
    const loc = await new FileBrainClient(dir).locate(new Uint8Array(32));
    expect(loc.manifestCell).toBeNull();
    expect(loc.seeders).toEqual([]);
    rmSync(dir, { recursive: true, force: true });
  });
});

```
