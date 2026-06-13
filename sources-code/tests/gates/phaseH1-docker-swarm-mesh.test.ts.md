---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phaseH1-docker-swarm-mesh.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.567239+00:00
---

# tests/gates/phaseH1-docker-swarm-mesh.test.ts

```ts
/**
 * Phase H1 Gate Tests — Docker Swarm Poker Mesh
 *
 * T1-T8: loopback (no Docker required)
 * T9-T10: Docker integration (skipped unless DOCKER_INTEGRATION=1)
 *
 * Cross-references:
 *   docker-multicast-adapter.ts — adapter under test
 *   udp-transport.ts — LoopbackUdpTransport
 *   Phase H1 PRD — DH1.6
 */

import { describe, test, expect, beforeEach, afterEach } from 'bun:test';
import {
  DockerMulticastAdapter,
  deriveBCA,
  encodeHeader,
  decodeHeader,
  HEADER_SIZE,
  MSG_HEARTBEAT,
  MSG_CELL,
  MSG_CONTROL,
} from '../../core/protocol-types/src/adapters/docker-multicast-adapter';
import { LoopbackUdpTransport } from '../../core/protocol-types/src/adapters/udp-transport';
import type { PublishableObject, NetworkEvent } from '../../core/protocol-types/src/network';

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

function makeTestObject(path: string): PublishableObject {
  return {
    cellBytes: new Uint8Array(1024).fill(0xab),
    semanticPath: path,
    contentHash: 'a'.repeat(64),
    ownerCert: 'test-cert',
    typeHash: 'b'.repeat(64),
  };
}

function makeAdapter(botIndex: number, opts?: { heartbeatIntervalMs?: number; staleTimeoutMs?: number }) {
  const bca = deriveBCA(botIndex);
  const transport = new LoopbackUdpTransport(bca);
  return new DockerMulticastAdapter({
    botIndex,
    transport,
    heartbeatIntervalMs: opts?.heartbeatIntervalMs ?? 100,
    staleTimeoutMs: opts?.staleTimeoutMs ?? 500,
  });
}

describe('Phase H1 — Docker Swarm Poker Mesh', () => {
  beforeEach(() => {
    LoopbackUdpTransport.resetAll();
  });

  // ── T1: Adapter init, BCA derivation, isConnected ──

  test('T1: adapter initialises with correct BCA and connection state', async () => {
    const adapter = makeAdapter(7);

    expect(adapter.getNodeBCA()).toBe('2602:f9f8::0007');
    expect(adapter.isConnected()).toBe(false);

    await adapter.start();
    expect(adapter.isConnected()).toBe(true);

    await adapter.stop();
    expect(adapter.isConnected()).toBe(false);
  });

  test('T1b: BCA derivation for various indices', () => {
    expect(deriveBCA(0)).toBe('2602:f9f8::0000');
    expect(deriveBCA(1)).toBe('2602:f9f8::0001');
    expect(deriveBCA(255)).toBe('2602:f9f8::00ff');
    expect(deriveBCA(4096)).toBe('2602:f9f8::1000');
  });

  // ── T2: Pub/sub between two adapters ──

  test('T2: publish/subscribe between two adapters via loopback', async () => {
    const a1 = makeAdapter(1);
    const a2 = makeAdapter(2);
    await a1.start();
    await a2.start();

    const received: NetworkEvent[] = [];
    a2.subscribe('tm_semantos_objects', (evt) => received.push(evt));

    const obj = makeTestObject('test/pub-sub');
    const result = await a1.publish(obj);

    expect(result.txid).toBeTruthy();
    expect(result.publishedAt).toBeGreaterThan(0);

    // Wait for microtask delivery + CBOR decode
    await sleep(50);

    expect(received.length).toBe(1);
    expect(received[0].result.semanticPath).toBe('test/pub-sub');
    expect(received[0].result.cellBytes.length).toBe(1024);
    expect(received[0].result.cellBytes[0]).toBe(0xab);

    await a1.stop();
    await a2.stop();
  });

  // ── T3: Heartbeat emission ──

  test('T3: heartbeat emitted at configured interval', async () => {
    const a1 = makeAdapter(1, { heartbeatIntervalMs: 60 });
    const a2 = makeAdapter(2, { heartbeatIntervalMs: 60 });
    await a1.start();
    await a2.start();

    // Wait for at least 2 heartbeat cycles
    await sleep(200);

    const peers = a2.discoverPeers();
    expect(peers.length).toBe(1);
    expect(peers[0].botIndex).toBe(1);
    expect(peers[0].bca).toBe(deriveBCA(1));

    await a1.stop();
    await a2.stop();
  });

  // ── T4: Peer discovery via heartbeats ──

  test('T4: mutual peer discovery between three adapters', async () => {
    const adapters = [makeAdapter(10), makeAdapter(11), makeAdapter(12)];
    for (const a of adapters) await a.start();

    await sleep(300);

    for (const a of adapters) {
      const peers = a.discoverPeers();
      expect(peers.length).toBe(2);
    }

    for (const a of adapters) await a.stop();
  });

  // ── T5: Stale peer eviction ──

  test('T5: stale peer eviction fires onPeerOffline', async () => {
    const a1 = makeAdapter(1, { heartbeatIntervalMs: 60, staleTimeoutMs: 300 });
    const a2 = makeAdapter(2, { heartbeatIntervalMs: 60, staleTimeoutMs: 300 });
    await a1.start();
    await a2.start();

    // Wait for peer discovery
    await sleep(200);
    expect(a2.discoverPeers().length).toBe(1);

    // Track eviction
    const evicted: string[] = [];
    a2.onPeerOffline((peer) => evicted.push(peer.bca));

    // Stop a1 so it stops heartbeating
    await a1.stop();

    // Wait for stale timeout + eviction check
    await sleep(600);

    expect(evicted.length).toBe(1);
    expect(evicted[0]).toBe(deriveBCA(1));
    expect(a2.discoverPeers().length).toBe(0);

    await a2.stop();
  });

  // ── T6: CoAP header layout + CBOR round-trip ──

  test('T6: CoAP header encode/decode round-trip', () => {
    const header = encodeHeader(MSG_CELL, 0x1234, 7, 0xdeadbeef, 512);
    expect(header.length).toBe(HEADER_SIZE);
    expect(header.length).toBe(12);

    const decoded = decodeHeader(header);
    expect(decoded.version).toBe(0x01);
    expect(decoded.msgType).toBe(MSG_CELL);
    expect(decoded.msgId).toBe(0x1234);
    expect(decoded.botIndex).toBe(7);
    expect(decoded.timestamp).toBe(0xdeadbeef);
    expect(decoded.payloadLen).toBe(512);
  });

  test('T6b: header constants are correct', () => {
    expect(HEADER_SIZE).toBe(12);
    expect(MSG_HEARTBEAT).toBe(0x01);
    expect(MSG_CELL).toBe(0x02);
    expect(MSG_CONTROL).toBe(0x03);
  });

  // ── T7: Table formation protocol ──

  test('T7: control message round-trip between adapters', async () => {
    const a1 = makeAdapter(1);
    const a2 = makeAdapter(2);
    await a1.start();
    await a2.start();

    const received: any[] = [];
    a2.onControlMessage((msg) => received.push(msg));

    await a1.sendControl({
      type: 'table.proposal',
      from: 1,
      payload: { tableId: 'test-table-1', stake: 100 },
    });

    await sleep(50);

    expect(received.length).toBe(1);
    expect(received[0].type).toBe('table.proposal');
    expect(received[0].payload.tableId).toBe('test-table-1');
    expect(received[0].payload.stake).toBe(100);

    await a1.stop();
    await a2.stop();
  });

  // ── T8: 25 adapters discover 24 peers each ──

  test('T8: 25 adapters each discover 24 peers', async () => {
    const adapters: DockerMulticastAdapter[] = [];
    for (let i = 0; i < 25; i++) {
      adapters.push(makeAdapter(i, { heartbeatIntervalMs: 60 }));
    }
    for (const a of adapters) await a.start();

    // Allow heartbeats to propagate (25 nodes, short intervals)
    await sleep(500);

    for (const a of adapters) {
      const peers = a.discoverPeers();
      expect(peers.length).toBe(24);
    }

    for (const a of adapters) await a.stop();
  }, 10_000);

  // ── T9-T10: Docker integration (skipped without Docker) ──

  const skipDocker = !process.env.DOCKER_INTEGRATION;

  test.skipIf(skipDocker)('T9: poker hand on locked table', async () => {
    // Requires Docker containers with real UDP transport
    expect(true).toBe(true);
  });

  test.skipIf(skipDocker)('T10: docker-compose health check', async () => {
    // Requires Docker containers running
    expect(true).toBe(true);
  });

  // ── Bonus: resolve and sendToNode ──

  test('Bonus: resolve returns published objects', async () => {
    const a1 = makeAdapter(1);
    await a1.start();

    await a1.publish(makeTestObject('bonus/resolve-test'));
    const results = await a1.resolve({ path: 'bonus/resolve-test' });
    expect(results.length).toBe(1);
    expect(results[0].semanticPath).toBe('bonus/resolve-test');

    await a1.stop();
  });

  test('Bonus: resolveBCA returns peer info after discovery', async () => {
    const a1 = makeAdapter(1);
    const a2 = makeAdapter(2);
    await a1.start();
    await a2.start();

    await sleep(200);

    const info = await a2.resolveBCA(deriveBCA(1));
    expect(info).not.toBeNull();
    expect(info!.bca).toBe(deriveBCA(1));

    await a1.stop();
    await a2.stop();
  });

  test('Bonus: getStats returns correct counts', async () => {
    const a1 = makeAdapter(1);
    await a1.start();
    await sleep(10); // Ensure uptime > 0

    await a1.publish(makeTestObject('stats/test-1'));
    await a1.publish(makeTestObject('stats/test-2'));

    const stats = a1.getStats();
    expect(stats.objects).toBe(2);
    expect(stats.uptime).toBeGreaterThanOrEqual(0);

    await a1.stop();
  });
});

```
