---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/swarm-transport-seam.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.077630+00:00
---

# runtime/session-protocol/src/swarm/__tests__/swarm-transport-seam.test.ts

```ts
/**
 * Transport-agnosticism seam check — M9.
 *
 * Re-runs the M3 end-to-end download over a completely different SwarmTransport
 * implementation — an in-process bus with no UdpTransport, no sockets at all.
 * The SwarmSession is unchanged: it only ever sees the SwarmTransport interface.
 * This proves a future WSS transport (35B) drops in with zero engine changes.
 */
import { describe, expect, test } from 'bun:test';
import { publishFile, bytesEqual, sha256 } from '@semantos/protocol-types';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmSession } from '../swarm-session';

function fileOf(n: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 53 + 29) & 0xff;
  return b;
}
function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([p, new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`timeout: ${label}`)), ms))]);
}

describe('swarm session — transport seam (M9)', () => {
  test('downloads end-to-end over a non-UDP in-memory transport', async () => {
    const file = fileOf(20 * 1016 + 7);
    const published = publishFile(file, 'seam/file');
    const brain = new FakeBrainClient();
    const bus = new SwarmBus();

    const seeder = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'node-seed'), brain });
    const leecher = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'node-leech'), brain });

    await seeder.seed(published);
    const got = await withTimeout(leecher.download(published.infohash), 5000, 'seam-download');

    expect(bytesEqual(got, file)).toBe(true);
    expect(bytesEqual(sha256(got), published.manifest.contentHash)).toBe(true);

    await seeder.stop();
    await leecher.stop();
  });
});

```
