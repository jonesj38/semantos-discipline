---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/swarm-session.loopback.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.080987+00:00
---

# runtime/session-protocol/src/swarm/__tests__/swarm-session.loopback.test.ts

```ts
/**
 * End-to-end swarm download over LoopbackUdpTransport — M3 (keystone).
 *
 * Two real swarm nodes over the in-process UDP transport: a seeder ingests a
 * multi-cell file and serves it; a leecher discovers it, runs rarest-first,
 * verifies every delivered cell against the manifest root, reassembles, and we
 * assert the bytes + content hash match. No real socket, no real brain.
 *
 * Covers: tracker-assisted discovery, pure-HAVE-gossip discovery, and
 * robustness against a malicious seeder that corrupts every cell it serves.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { LoopbackUdpTransport } from '@semantos/protocol-types/adapters/udp-transport';
import { publishFile, bytesEqual, sha256, toHex } from '@semantos/protocol-types';
import { udpSwarmTransport } from '../swarm-transport';
import { FakeBrainClient, type SwarmBrainClient } from '../brain-client';
import { SwarmSession } from '../swarm-session';
import { bitfieldFor } from '../have-bitfield';
import {
  MSG_SWARM_REQUEST,
  MSG_SWARM_CELL,
  MSG_SWARM_HAVE,
  parseSwarm,
  decodeRequest,
  encodeCell,
  encodeHave,
  frameSwarm,
} from '../swarm-wire';

const PORT = 41234;
const GROUP = 'ff02::swarm';

function makeTransport(addr: string) {
  const udp = new LoopbackUdpTransport(addr);
  return { udp, transport: udpSwarmTransport({ udp, address: addr, port: PORT, group: GROUP }) };
}

function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`timeout: ${label}`)), ms)),
  ]);
}

function fileOf(n: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 37 + 13) & 0xff;
  return b;
}

afterEach(() => {
  LoopbackUdpTransport.resetAll();
});

describe('swarm session — loopback end-to-end', () => {
  test('leecher downloads a multi-cell file from a seeder (tracker-assisted)', async () => {
    const file = fileOf(30 * 1016 + 511); // 31 cells
    const published = publishFile(file, 'media/clip.bin');
    const brain = new FakeBrainClient();

    const seeder = new SwarmSession({ transport: makeTransport('fe80::1').transport, brain });
    const leecher = new SwarmSession({ transport: makeTransport('fe80::2').transport, brain });

    await seeder.seed(published);
    const got = await withTimeout(leecher.download(published.infohash), 5000, 'download');

    expect(got.length).toBe(file.length);
    expect(bytesEqual(got, file)).toBe(true);
    expect(bytesEqual(sha256(got), published.manifest.contentHash)).toBe(true);

    await seeder.stop();
    await leecher.stop();
  });

  test('leecher discovers the seeder purely via HAVE gossip (no tracker seeders)', async () => {
    const file = fileOf(12 * 1016);
    const published = publishFile(file, 'gossip/file');
    const real = new FakeBrainClient();
    // Brain knows the manifest but reports NO seeders — discovery must happen on the wire.
    const gossipBrain: SwarmBrainClient = {
      publish: real.publish.bind(real),
      announce: real.announce.bind(real),
      settle: real.settle.bind(real),
      locate: async ih => ({ manifestCell: (await real.locate(ih)).manifestCell, seeders: [] }),
    };

    const seeder = new SwarmSession({ transport: makeTransport('fe80::1').transport, brain: gossipBrain });
    const leecher = new SwarmSession({ transport: makeTransport('fe80::2').transport, brain: gossipBrain });

    await seeder.seed(published);
    const got = await withTimeout(leecher.download(published.infohash), 5000, 'gossip-download');

    expect(bytesEqual(got, file)).toBe(true);
    await seeder.stop();
    await leecher.stop();
  });

  test('a malicious seeder that corrupts cells cannot poison the download', async () => {
    const file = fileOf(8 * 1016);
    const published = publishFile(file, 'evil/file');
    const real = new FakeBrainClient();
    await real.publish({ infohash: published.infohash, manifestCell: published.manifestCell, semanticPath: 'evil/file' });

    // Tracker points ONLY at the evil seeder, so the leecher tries it first.
    const evilAddr = 'fe80::e';
    const fullBf = bitfieldFor(
      Array.from({ length: published.manifest.totalCells }, (_, i) => i),
      published.manifest.totalCells,
    );
    const leecherBrain: SwarmBrainClient = {
      publish: real.publish.bind(real),
      announce: real.announce.bind(real),
      settle: real.settle.bind(real),
      locate: async ih => ({
        manifestCell: (await real.locate(ih)).manifestCell,
        seeders: [{ address: evilAddr, bitfield: fullBf }],
      }),
    };

    // Evil responder: replies to every REQUEST with a corrupt cell + bogus proof.
    const evil = makeTransport(evilAddr);
    evil.transport.onFrame((frame, from) => {
      const { header, payload } = parseSwarm(frame);
      if (header.msgType !== MSG_SWARM_REQUEST) return;
      const req = decodeRequest(payload);
      const corrupt = new Uint8Array(1024).fill(0xee);
      const cell = encodeCell({
        infohash: published.infohash,
        cellIndex: req.cellIndex,
        proof: { leafIndex: req.cellIndex, siblings: [] },
        cellBytes: corrupt,
      });
      void evil.transport.sendTo(from, frameSwarm(MSG_SWARM_CELL, cell, { msgId: 0, nodeIdShort: 0, timestamp: 0 }));
    });
    await evil.transport.start();
    void evil.transport.broadcast(
      frameSwarm(MSG_SWARM_HAVE, encodeHave(published.infohash, published.manifest.totalCells, fullBf), {
        msgId: 0, nodeIdShort: 0, timestamp: 0,
      }),
    );

    // Honest seeder, discovered via gossip after the leecher bans evil.
    const honest = new SwarmSession({ transport: makeTransport('fe80::3').transport, brain: leecherBrain });
    const leecher = new SwarmSession({ transport: makeTransport('fe80::4').transport, brain: leecherBrain });

    await honest.seed(published);
    const got = await withTimeout(leecher.download(published.infohash), 5000, 'evil-download');

    // Despite the evil seeder being tried first, the result is exactly correct.
    expect(bytesEqual(got, file)).toBe(true);
    expect(bytesEqual(sha256(got), published.manifest.contentHash)).toBe(true);

    await honest.stop();
    await leecher.stop();
    await evil.transport.stop();
  });
});

describe('swarm session — M7 anchor verification', () => {
  test('a matching anchor proof lets the download proceed', async () => {
    const file = fileOf(6 * 1016);
    const published = publishFile(file, 'anchor/ok');
    const brain = new FakeBrainClient();
    const seeder = new SwarmSession({ transport: makeTransport('fe80::1').transport, brain });
    const leecher = new SwarmSession({ transport: makeTransport('fe80::2').transport, brain });

    await seeder.seed(published);
    brain.setAnchorProof(published.infohash, { stateHash: toHex(published.infohash), txid: 'ab'.repeat(32) });
    const got = await withTimeout(leecher.download(published.infohash), 5000, 'anchor-ok');
    expect(bytesEqual(got, file)).toBe(true);

    await seeder.stop();
    await leecher.stop();
  });

  test('a mismatched anchor proof rejects the download (trustless binding)', async () => {
    const file = fileOf(6 * 1016);
    const published = publishFile(file, 'anchor/bad');
    const brain = new FakeBrainClient();
    const seeder = new SwarmSession({ transport: makeTransport('fe80::1').transport, brain });
    const leecher = new SwarmSession({ transport: makeTransport('fe80::2').transport, brain });

    await seeder.seed(published);
    brain.setAnchorProof(published.infohash, { stateHash: '00'.repeat(32) }); // wrong commitment
    await expect(leecher.download(published.infohash)).rejects.toThrow('anchor proof');

    await seeder.stop();
    await leecher.stop();
  });
});

```
