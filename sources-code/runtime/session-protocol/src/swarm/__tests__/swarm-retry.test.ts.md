---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/swarm-retry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.080081+00:00
---

# runtime/session-protocol/src/swarm/__tests__/swarm-retry.test.ts

```ts
/**
 * Request timeout + retry — packet loss recovery.
 *
 * Real networks drop datagrams; without retry a single dropped REQUEST or CELL
 * strands a cell in-flight forever and the download hangs. (This is exactly
 * what stalled 3 of 4 Pi leechers under multicast contention until retry was
 * added.) Here a lossy bus drops the first N frames; the download must still
 * complete via re-request.
 */
import { describe, expect, test } from 'bun:test';
import { publishFile, bytesEqual, sha256 } from '@semantos/protocol-types';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmSession } from '../swarm-session';

/** Drops the first `drop` unicast frames (REQUEST/CELL), then passes everything. */
class LossyBus extends SwarmBus {
  private dropsLeft: number;
  constructor(drop: number) {
    super();
    this.dropsLeft = drop;
  }
  override sendTo(from: string, to: string, frame: Uint8Array): void {
    if (this.dropsLeft > 0) {
      this.dropsLeft--;
      return; // simulate a dropped datagram
    }
    super.sendTo(from, to, frame);
  }
}

describe('swarm session — request retry', () => {
  test('download completes despite dropped REQUEST/CELL datagrams', async () => {
    const file = Uint8Array.from({ length: 12 * 1016 }, (_, i) => (i * 13 + 1) & 0xff);
    const published = publishFile(file, 'lossy/file');
    const brain = new FakeBrainClient();
    const bus = new LossyBus(6); // drop the first 6 unicast frames

    const opts = { brain, requestTimeoutMs: 40 };
    const seeder = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'seed'), ...opts });
    const leecher = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'leech'), ...opts });

    await seeder.seed(published);
    const got = await Promise.race([
      leecher.download(published.infohash),
      new Promise<never>((_, r) => setTimeout(() => r(new Error('timeout: retry')), 4000)),
    ]);

    expect(bytesEqual(got, file)).toBe(true);
    expect(bytesEqual(sha256(got), published.manifest.contentHash)).toBe(true);

    await seeder.stop();
    await leecher.stop();
  });
});

```
