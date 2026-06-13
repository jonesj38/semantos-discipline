---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/wss-rpc-channel.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.080383+00:00
---

# runtime/session-protocol/src/swarm/__tests__/wss-rpc-channel.test.ts

```ts
/**
 * WssRpcChannel + RpcSwarmBrainClient over a real WebSocket — the production
 * brain seam. A brain-shaped mock server (JSON-RPC verb.dispatch routed to a
 * FakeBrainClient) stands in for the deployed brain; the channel + client are
 * exercised end-to-end over an actual socket, including a full swarm download
 * whose cold path (publish/locate/announce) goes over WSS while the hot path
 * stays on the in-memory data-plane transport.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { publishFile, bytesEqual, fromHex, toHex } from '@semantos/protocol-types';
import { WssRpcChannel } from '../wss-rpc-channel';
import { RpcSwarmBrainClient } from '../rpc-brain-client';
import { FakeBrainClient } from '../brain-client';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { SwarmSession } from '../swarm-session';

// ── brain-shaped mock WS server ────────────────────────────────────────────────

async function handleSwarm(brain: FakeBrainClient, verb: string, p: any): Promise<unknown> {
  switch (verb) {
    case 'publish': {
      const r = await brain.publish({ infohash: fromHex(p.infohash), manifestCell: fromHex(p.manifestCellHex), semanticPath: p.semanticPath });
      return { infohash: r.infohash, stored: true, anchorStatus: 'pending' };
    }
    case 'locate': {
      const loc = await brain.locate(fromHex(p.infohash));
      return loc.manifestCell
        ? { manifestKnown: true, manifestCellHex: toHex(loc.manifestCell), anchorStatus: 'none', seeders: loc.seeders.map(s => ({ address: s.address, bitfield: s.bitfield ? toHex(s.bitfield) : '', lastSeen: s.lastSeen })) }
        : { manifestKnown: false, seeders: [] };
    }
    case 'announce': {
      await brain.announce({ infohash: fromHex(p.infohash), address: p.address, bitfield: fromHex(p.bitfieldHex) });
      return { ok: true };
    }
    case 'settle': {
      const r = await brain.settle({ infohash: fromHex(p.infohash), receipts: p.receipts });
      return { recorded: r.recorded };
    }
    default:
      return {};
  }
}

interface MockBrain {
  url: string;
  brain: FakeBrainClient;
  lastBearer: () => string | null;
  stop: () => void;
}

function startMockBrain(opts: { silent?: boolean } = {}): MockBrain {
  const brain = new FakeBrainClient();
  let bearer: string | null = null;
  const server = Bun.serve({
    port: 0,
    fetch(req, srv) {
      bearer = new URL(req.url).searchParams.get('bearer');
      if (srv.upgrade(req)) return undefined;
      return new Response('expected websocket', { status: 426 });
    },
    websocket: {
      async message(ws, raw) {
        if (opts.silent) return; // never respond → exercise client timeout
        let req: any;
        try { req = JSON.parse(String(raw)); } catch { return; }
        const { id, method, params } = req;
        if (method !== 'verb.dispatch' || params?.extensionId !== 'swarm') {
          ws.send(JSON.stringify({ jsonrpc: '2.0', id, error: { code: -32601, message: 'method not found' } }));
          return;
        }
        try {
          const result = await handleSwarm(brain, params.verb, params.params);
          ws.send(JSON.stringify({ jsonrpc: '2.0', id, result }));
        } catch (e) {
          ws.send(JSON.stringify({ jsonrpc: '2.0', id, error: { code: -32000, message: String(e) } }));
        }
      },
    },
  });
  return { url: `ws://localhost:${server.port}/api/v1/rpc`, brain, lastBearer: () => bearer, stop: () => server.stop(true) };
}

const cleanups: Array<() => void> = [];
afterEach(() => { for (const c of cleanups.splice(0)) c(); });

// ── tests ──────────────────────────────────────────────────────────────────────

describe('WssRpcChannel', () => {
  test('publish + locate round-trip over a real WebSocket (+ bearer in URL)', async () => {
    const mock = startMockBrain();
    cleanups.push(mock.stop);
    const channel = new WssRpcChannel(mock.url, { bearer: 'tok-123' });
    cleanups.push(() => channel.close());
    const client = new RpcSwarmBrainClient(channel);

    const pub = publishFile(new Uint8Array(3000).fill(9), 'wss/a');
    await client.publish({ infohash: pub.infohash, manifestCell: pub.manifestCell, semanticPath: 'wss/a' });
    await client.announce({ infohash: pub.infohash, address: 'fe80::5', bitfield: new Uint8Array([0xff]) });

    const loc = await client.locate(pub.infohash);
    expect(loc.manifestCell && bytesEqual(loc.manifestCell, pub.manifestCell)).toBe(true);
    expect(loc.seeders[0]?.address).toBe('fe80::5');
    expect(mock.lastBearer()).toBe('tok-123');
  });

  test('rpc error responses reject the call', async () => {
    const mock = startMockBrain();
    cleanups.push(mock.stop);
    const channel = new WssRpcChannel(mock.url);
    cleanups.push(() => channel.close());
    // Unknown method → the mock replies with a JSON-RPC error.
    await expect(channel.call('verb.dispatch', { extensionId: 'nope', verb: 'x', params: {} })).rejects.toThrow('rpc error');
  });

  test('a silent server trips the per-request timeout', async () => {
    const mock = startMockBrain({ silent: true });
    cleanups.push(mock.stop);
    const channel = new WssRpcChannel(mock.url, { timeoutMs: 150 });
    cleanups.push(() => channel.close());
    await expect(channel.call('verb.dispatch', { extensionId: 'swarm', verb: 'locate', params: { infohash: '00' } })).rejects.toThrow('timeout');
  });

  test('full swarm download with the brain over WSS (cold path on the socket)', async () => {
    const mock = startMockBrain();
    cleanups.push(mock.stop);
    const file = Uint8Array.from({ length: 16 * 1016 }, (_, i) => (i * 7 + 3) & 0xff);
    const published = publishFile(file, 'wss/file');

    const bus = new SwarmBus();
    const seeder = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'seed'), brain: new RpcSwarmBrainClient(new WssRpcChannel(mock.url)) });
    const leecher = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'leech'), brain: new RpcSwarmBrainClient(new WssRpcChannel(mock.url)) });

    await seeder.seed(published);                 // publish + announce → WSS → brain
    const got = await Promise.race([
      leecher.download(published.infohash),        // locate → WSS → brain; cells → bus
      new Promise<never>((_, r) => setTimeout(() => r(new Error('timeout')), 5000)),
    ]);
    expect(bytesEqual(got, file)).toBe(true);
    // The brain (server-side FakeBrainClient) actually holds the published manifest.
    expect((await mock.brain.locate(published.infohash)).manifestCell).not.toBeNull();

    await seeder.stop();
    await leecher.stop();
  });
});

```
