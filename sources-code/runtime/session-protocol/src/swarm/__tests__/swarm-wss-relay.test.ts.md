---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/swarm-wss-relay.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.077345+00:00
---

# runtime/session-protocol/src/swarm/__tests__/swarm-wss-relay.test.ts

```ts
/**
 * Cross-internet WSS transport — a real relay + WSS clients run the SAME engine
 * the LAN multicast path does. Proves: a full transfer over WebSocket (peers
 * dial OUT to a relay, no inbound/NAT rules), rendezvous-room isolation, and
 * unicast routing. This is the ceiling-lift: the swarm now works off-LAN.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { bytesEqual, publishFile, toHex } from '@semantos/protocol-types';
import { FakeBrainClient } from '../brain-client';
import { createMeteredTransfer } from '../metered-transfer';
import { serveSwarmRelay, wssSwarmTransport } from '../swarm-wss-relay';
import { multicastGroupForInfohash } from '../transfer-rendezvous';

function fileOf(n: number, seed: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 13 + seed) & 0xff;
  return b;
}

const cleanups: Array<() => Promise<void> | void> = [];
afterEach(async () => { for (const c of cleanups.splice(0)) await c(); });

describe('WSS swarm transport (cross-internet)', () => {
  test('a full transfer flows over a WSS relay room', async () => {
    const relay = serveSwarmRelay(0);
    cleanups.push(() => relay.stop());
    const url = `ws://localhost:${relay.port}`;
    const discovery = new FakeBrainClient();

    const seeder = await createMeteredTransfer({
      transport: wssSwarmTransport({ url, room: 'swarm', id: 'seeder' }),
      brain: discovery,
    });
    const leecher = await createMeteredTransfer({
      transport: wssSwarmTransport({ url, room: 'swarm', id: 'leecher' }),
      brain: discovery,
    });
    cleanups.push(() => seeder.stop(), () => leecher.stop());

    const file = fileOf(10 * 1016 + 21, 4);
    const magnet = await seeder.share(file, 'over-wss.bin');
    const got = await leecher.fetch(magnet, { timeoutMs: 12000 });
    expect(bytesEqual(got, file)).toBe(true);
  });

  test('the rendezvous group can be the relay room (on-chain ref → room)', async () => {
    const relay = serveSwarmRelay(0);
    cleanups.push(() => relay.stop());
    const url = `ws://localhost:${relay.port}`;
    const discovery = new FakeBrainClient();

    const file = fileOf(6 * 1016, 7);
    // The infohash is known up front → both peers join its rendezvous room
    // (no tracker round-trip needed to agree on where to meet).
    const magnet = toHex(publishFile(file, 'r.bin').infohash);
    const room = multicastGroupForInfohash(magnet).group;
    expect(room.startsWith('ff02:')).toBe(true);

    const seeder = await createMeteredTransfer({ transport: wssSwarmTransport({ url, room, id: 'seeder' }), brain: discovery });
    const leecher = await createMeteredTransfer({ transport: wssSwarmTransport({ url, room, id: 'leecher' }), brain: discovery });
    cleanups.push(() => seeder.stop(), () => leecher.stop());
    await seeder.share(file, 'r.bin');

    const got = await leecher.fetch(magnet, { timeoutMs: 12000 });
    expect(bytesEqual(got, file)).toBe(true);
  }, 15000);

  test('rooms are isolated: a peer in another room receives nothing', async () => {
    const relay = serveSwarmRelay(0);
    cleanups.push(() => relay.stop());
    const url = `ws://localhost:${relay.port}`;

    const a = wssSwarmTransport({ url, room: 'room-A', id: 'a' });
    const outsider = wssSwarmTransport({ url, room: 'room-B', id: 'b' });
    await a.start();
    await outsider.start();
    cleanups.push(() => a.stop(), () => outsider.stop());

    let outsiderGot = 0;
    outsider.onFrame(() => { outsiderGot++; });
    await a.broadcast(new Uint8Array([1, 2, 3]));
    await new Promise(r => setTimeout(r, 150));
    expect(outsiderGot).toBe(0);
    expect(relay.rooms()['room-A']).toBe(1);
    expect(relay.rooms()['room-B']).toBe(1);
  });

  test('unicast sendTo routes to one peer by address', async () => {
    const relay = serveSwarmRelay(0);
    cleanups.push(() => relay.stop());
    const url = `ws://localhost:${relay.port}`;

    const a = wssSwarmTransport({ url, room: 'r', id: 'a' });
    const b = wssSwarmTransport({ url, room: 'r', id: 'b' });
    const c = wssSwarmTransport({ url, room: 'r', id: 'c' });
    await Promise.all([a.start(), b.start(), c.start()]);
    cleanups.push(() => a.stop(), () => b.stop(), () => c.stop());

    let bGot = 0, cGot = 0;
    let bFrom = '';
    b.onFrame((_f, from) => { bGot++; bFrom = from; });
    c.onFrame(() => { cGot++; });
    await a.sendTo('b', new Uint8Array([9]));
    await new Promise(r => setTimeout(r, 150));
    expect(bGot).toBe(1);
    expect(bFrom).toBe('a'); // recipient learns the sender's address → can reply
    expect(cGot).toBe(0);    // not the target
  });
});

```
